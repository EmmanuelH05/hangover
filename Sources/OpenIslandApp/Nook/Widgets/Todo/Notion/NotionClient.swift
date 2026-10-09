import Foundation

/// Every way a Notion request can fail, already sorted into the cases the
/// widget shows differently. Carries no token and no response text.
enum NotionAPIError: Error, Equatable, Sendable {
    /// 401: the token is wrong or was revoked.
    case unauthorized
    /// 403: the integration lacks a capability.
    case forbidden
    /// 404: the database is gone or not shared with the integration.
    case notFound
    /// 429 or 529, with the server's requested wait when it sent one.
    case rateLimited(retryAfter: TimeInterval?)
    /// 400: Notion rejected the request shape, usually a changed schema.
    case badRequest(code: String?)
    case server(status: Int)
    /// No connection, DNS failure or timeout.
    case offline
    case invalidResponse
    case cancelled
}

/// Thin typed wrapper over the REST endpoints the todo widget needs.
///
/// Auth is an internal integration token pasted by the user. OAuth is out of
/// scope: public integrations need a client secret held on a server, and this
/// app has no backend.
struct NotionClient: Sendable {
    /// Pinned API version. From 2025-09-03 on, a database's rows and schema
    /// live on its data source, which is why queries, schema reads and page
    /// parents below use `/v1/data_sources` and `data_source_id`.
    static let apiVersion = "2026-03-11"
    static let maxPageSize = 100
    /// Upper bound on pagination round trips for one logical call.
    static let maxPagesPerCall = 5
    static let maxRetryAfter: TimeInterval = 3600

    private static let host = "api.notion.com"
    private static let pathPrefix = "/v1/"

    let token: String
    let transport: any NookTodoTransport

    // MARK: Endpoints

    /// `GET /v1/users/me`. Used to validate a token.
    func currentUser() async throws -> NotionUser {
        try await send(method: "GET", path: ["users", "me"], body: nil)
    }

    /// `POST /v1/search` filtered to data sources, following pagination.
    func searchDataSources(limit: Int) async throws -> [NotionDataSource] {
        try await paginate(limit: limit) { cursor, pageSize in
            var body: [String: NotionJSONValue] = [
                "filter": ["property": "object", "value": "data_source"],
                "page_size": .int(pageSize),
            ]
            if let cursor { body["start_cursor"] = .string(cursor) }
            return try await send(method: "POST", path: ["search"], body: .object(body))
        }
    }

    /// `GET /v1/data_sources/{id}`. Returns the schema.
    func dataSource(id: String) async throws -> NotionDataSource {
        try await send(method: "GET", path: ["data_sources", id], body: nil)
    }

    /// `POST /v1/data_sources/{id}/query`, following pagination up to `limit`.
    func queryPages(
        dataSourceID: String,
        filter: NotionJSONValue?,
        sorts: [NotionJSONValue],
        limit: Int
    ) async throws -> [NotionPage] {
        try await paginate(limit: limit) { cursor, pageSize in
            var body: [String: NotionJSONValue] = ["page_size": .int(pageSize)]
            if let filter { body["filter"] = filter }
            if !sorts.isEmpty { body["sorts"] = .array(sorts) }
            if let cursor { body["start_cursor"] = .string(cursor) }
            return try await send(method: "POST", path: ["data_sources", dataSourceID, "query"], body: .object(body))
        }
    }

    /// `PATCH /v1/pages/{id}` with property values.
    func updatePage(id: String, properties: NotionJSONValue) async throws {
        let _: NotionPage = try await send(method: "PATCH", path: ["pages", id], body: ["properties": properties])
    }

    /// `POST /v1/pages` under a data source.
    func createPage(dataSourceID: String, properties: NotionJSONValue) async throws -> NotionPage {
        try await send(method: "POST", path: ["pages"], body: [
            "parent": ["type": "data_source_id", "data_source_id": .string(dataSourceID)],
            "properties": properties,
        ])
    }

    // MARK: Plumbing

    private func paginate<Element: Decodable & Sendable>(
        limit: Int,
        fetch: (_ cursor: String?, _ pageSize: Int) async throws -> NotionList<Element>
    ) async throws -> [Element] {
        var collected: [Element] = []
        var cursor: String?
        for _ in 0..<Self.maxPagesPerCall {
            let remaining = limit - collected.count
            guard remaining > 0 else { break }
            let page = try await fetch(cursor, min(Self.maxPageSize, remaining))
            collected.append(contentsOf: page.results)
            guard page.hasMore, let next = page.nextCursor, !next.isEmpty else { break }
            cursor = next
        }
        return Array(collected.prefix(limit))
    }

    private func send<Response: Decodable>(
        method: String,
        path: [String],
        body: NotionJSONValue?
    ) async throws -> Response {
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
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw NotionAPIError.invalidResponse
        }
    }

    private func makeRequest(method: String, path: [String], body: NotionJSONValue?) throws -> URLRequest {
        // IDs come from the network and from settings. Keep them inside one
        // path segment each.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        var encoded: [String] = []
        for segment in path {
            guard !segment.isEmpty,
                  let escaped = segment.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw NotionAPIError.invalidResponse
            }
            encoded.append(escaped)
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = Self.host
        components.percentEncodedPath = Self.pathPrefix + encoded.joined(separator: "/")
        guard let url = components.url else { throw NotionAPIError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = NookTodoURLSessionTransport.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            do {
                request.httpBody = try JSONEncoder().encode(body)
            } catch {
                throw NotionAPIError.invalidResponse
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    static func classify(_ error: Error) -> NotionAPIError {
        if let known = error as? NotionAPIError { return known }
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

    static func failure(status: Int, response: HTTPURLResponse, data: Data) -> NotionAPIError? {
        switch status {
        case 200..<300:
            return nil
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 429, 529:
            return .rateLimited(retryAfter: retryAfter(from: response))
        case 400..<500:
            return .badRequest(code: (try? JSONDecoder().decode(NotionErrorBody.self, from: data))?.code)
        default:
            return .server(status: status)
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
