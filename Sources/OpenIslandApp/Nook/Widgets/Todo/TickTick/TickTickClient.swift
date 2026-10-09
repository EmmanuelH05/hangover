import Foundation

/// Every way a TickTick request can fail, already sorted into the cases the
/// widget shows differently. Carries no token and no response text.
enum TickTickAPIError: Error, Equatable, Sendable {
    /// 401: the token is wrong or was revoked.
    case unauthorized
    /// 403: the token may not do this to the list.
    case forbidden
    /// 404: the list or the task is gone.
    case notFound
    /// 429, or TickTick's own "too many requests" error code.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other 4xx: TickTick rejected the request.
    case badRequest
    case server(status: Int)
    /// No connection, DNS failure or timeout.
    case offline
    case invalidResponse
    case cancelled
}

/// Which field of a task holds its note. TickTick shows `content` on a plain
/// task and `desc` on one that has a checklist.
enum TickTickNotesField: String, Codable, Equatable, Sendable {
    case content
    case desc
}

/// Thin typed wrapper over the Open API endpoints the todo widget needs.
///
/// Auth is a personal API token pasted by the user (TickTick web app,
/// Settings, Account, API Token). OAuth is out of scope: it needs a client
/// secret held on a server, and this app has no backend.
struct TickTickClient: Sendable {
    /// Stands for the inbox in a path. The inbox has a real ID of its own
    /// (`inbox` plus digits) and is not in the list of projects.
    static let inboxID = "inbox"
    static let maxRetryAfter: TimeInterval = 3600
    /// The error code TickTick sends when requests come too fast.
    static let rateLimitErrorCode = "exceed_query_limit"

    private static let host = "api.ticktick.com"
    private static let pathPrefix = "/open/v1/"

    let token: String
    let transport: any NookTodoTransport

    // MARK: Endpoints

    /// `GET /open/v1/project`. Every list but the inbox. Also used to check
    /// a token, because the API has no "who am I" request.
    func projects() async throws -> [TickTickProject] {
        let data = try await send(method: "GET", path: ["project"], body: nil)
        do {
            return try JSONDecoder().decode([TickTickLossy<TickTickProject>].self, from: data).compactMap(\.value)
        } catch {
            throw TickTickAPIError.invalidResponse
        }
    }

    /// `GET /open/v1/project/{id}/data`. The list and its open tasks. Pass
    /// `inboxID` for the inbox.
    func projectData(id: String) async throws -> TickTickProjectData {
        let data = try await send(method: "GET", path: ["project", id, "data"], body: nil)
        do {
            return try JSONDecoder().decode(TickTickProjectData.self, from: data)
        } catch {
            throw TickTickAPIError.invalidResponse
        }
    }

    /// `POST /open/v1/task`. Without a project the task lands in the inbox.
    /// Returns nil when TickTick took the task but its answer could not be
    /// read, which is still a task that exists.
    func createTask(title: String, projectID: String?) async throws -> TickTickTask? {
        var fields = ["title": title]
        if let projectID { fields["projectId"] = projectID }
        guard let body = try? JSONEncoder().encode(fields) else { throw TickTickAPIError.invalidResponse }
        let data = try await send(method: "POST", path: ["task"], body: body)
        return try? JSONDecoder().decode(TickTickTask.self, from: data)
    }

    /// `POST /open/v1/project/{projectId}/task/{taskId}/complete`.
    func completeTask(id: String, projectID: String) async throws {
        _ = try await send(method: "POST", path: ["project", projectID, "task", id, "complete"], body: nil)
    }

    /// Reads the task, changes the one field that holds its note and sends
    /// the whole task back: `GET /open/v1/project/{projectId}/task/{taskId}`,
    /// then `POST /open/v1/task/{taskId}`.
    ///
    /// The whole task goes back because TickTick's docs do not say what
    /// happens to a field an update leaves out, and a title or a due date
    /// must never be lost to a note. Nothing is written when the read fails.
    func setNotes(_ text: String, taskID: String, projectID: String, field: TickTickNotesField) async throws {
        let current = try await send(method: "GET", path: ["project", projectID, "task", taskID], body: nil)
        let body = try Self.taskBody(current, taskID: taskID, field: field, text: text)
        _ = try await send(method: "POST", path: ["task", taskID], body: body)
    }

    /// The task as TickTick sent it, fields this app does not know included,
    /// with the note changed. Throws when the answer is not that task.
    static func taskBody(_ current: Data, taskID: String, field: TickTickNotesField, text: String) throws -> Data {
        guard var task = (try? JSONSerialization.jsonObject(with: current)) as? [String: Any],
              task["id"] as? String == taskID else {
            throw TickTickAPIError.invalidResponse
        }
        task[field.rawValue] = text
        guard let body = try? JSONSerialization.data(withJSONObject: task) else {
            throw TickTickAPIError.invalidResponse
        }
        return body
    }

    // MARK: Plumbing

    private func send(method: String, path: [String], body: Data?) async throws -> Data {
        let request = try makeRequest(method: method, path: path, body: body)
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw Self.classify(error)
        }
        if let failure = Self.failure(status: response.statusCode, response: response, data: data) {
            throw failure
        }
        return data
    }

    private func makeRequest(method: String, path: [String], body: Data?) throws -> URLRequest {
        // IDs come from the network and from settings. Keep them inside one
        // path segment each.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var encoded: [String] = []
        for segment in path {
            guard !segment.isEmpty,
                  let escaped = segment.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw TickTickAPIError.invalidResponse
            }
            encoded.append(escaped)
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.percentEncodedPath = Self.pathPrefix + encoded.joined(separator: "/")
        guard let url = components.url else { throw TickTickAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = NookTodoURLSessionTransport.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func classify(_ error: Error) -> TickTickAPIError {
        if let known = error as? TickTickAPIError { return known }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return .cancelled
            // The transport's word for an answer that is not HTTP.
            case .badServerResponse: return .invalidResponse
            default: return .offline
            }
        }
        return .offline
    }

    static func failure(status: Int, response: HTTPURLResponse, data: Data) -> TickTickAPIError? {
        // An answer that carries an error code is a failure under any
        // status, 200 included. The "too many requests" code is a rate limit.
        let code = (try? JSONDecoder().decode(TickTickErrorBody.self, from: data))?.errorCode
        if status == 429 || code == rateLimitErrorCode {
            return .rateLimited(retryAfter: retryAfter(from: response))
        }
        if (200..<300).contains(status) {
            return code == nil ? nil : .invalidResponse
        }
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 400..<500: return .badRequest
        default: return .server(status: status)
        }
    }

    /// `Retry-After` is an integer number of seconds.
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return min(seconds, maxRetryAfter)
    }
}
