import Foundation

/// A task app reached over the network with a personal token (D83): Asana,
/// monday and Canvas. Each one is a `NookTodoBackend`, the few requests
/// that differ, and `NookRemoteTodoService` is the one service around
/// them: the token file, the refresh gate, the states, the writes. TickTick
/// and Notion came before this and keep their own services.
protocol NookTodoBackend: Sendable {
    static var kind: NookTodoSourceKind { get }
    /// Whether a workspace or board must be picked before tasks load.
    static var needsPlace: Bool { get }
    /// Whether the app lives at an address the user names (a school's
    /// Canvas), which the token is no good without.
    static var needsHost: Bool { get }
    static var canAdd: Bool { get }
    static var canComplete: Bool { get }
    static var canEditNotes: Bool { get }
    static var canSetDue: Bool { get }

    /// Checks the token and lists the places it can read. The check is a
    /// request the app answers for any good token.
    static func check(_ session: NookTodoRemoteSession) async throws -> NookTodoRemoteCheck
    /// The open tasks, with whatever a later write needs to know.
    /// `placeName` is the saved name of the place, for rows that carry it.
    static func load(
        _ session: NookTodoRemoteSession, placeID: String?, placeName: String?
    ) async throws -> NookTodoRemoteLoad
    static func add(
        _ title: String, due: DateComponents?, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws
    static func complete(
        _ id: String, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws
    static func setNotes(
        _ notes: String, for id: String, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws
}

extension NookTodoBackend {
    static var needsHost: Bool { false }

    /// An app that offers no adding or no notes is never asked. The default
    /// refuses, which keeps a wrong call from going out as a request.
    static func add(
        _ title: String, due: DateComponents?, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        throw NookTodoRemoteError.badRequest
    }

    static func setNotes(
        _ notes: String, for id: String, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        throw NookTodoRemoteError.badRequest
    }
}

/// What a request needs: the token, the host for an app that has one, the
/// way out, and the moment it is made (a window of days starts there).
struct NookTodoRemoteSession: Sendable {
    let token: String
    let host: String?
    let transport: any NookTodoTransport
    var now: Date = Date()
}

/// One entry of the workspace or board picker.
struct NookTodoPlaceChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// The answer to a token check.
struct NookTodoRemoteCheck: Equatable, Sendable {
    var places: [NookTodoPlaceChoice]
    /// The account's name, when the app says it.
    var accountName: String?
}

/// One full read of the tasks.
struct NookTodoRemoteLoad: Equatable, Sendable {
    var items: [NookTodoItem]
    /// The place's name as the app has it.
    var placeName: String?
    /// Whatever a write needs that the rows do not carry: column ids, the
    /// account's id, an override's id. The backend fills it and reads it.
    var context: [String: String] = [:]
}

/// Every way a request can fail, sorted into what the widget shows
/// differently. Carries no token and no response text.
enum NookTodoRemoteError: Error, Equatable, Sendable {
    /// 401: the token is wrong or was revoked.
    case unauthorized
    /// 403: the token may not do this.
    case forbidden
    /// 404: the place or the task is gone.
    case notFound
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other 4xx: the app rejected the request.
    case badRequest
    case server(status: Int)
    /// No connection, DNS failure or timeout.
    case offline
    case invalidResponse
    case cancelled

    static let maxRetryAfter: TimeInterval = 3600

    static func classify(_ error: any Error) -> NookTodoRemoteError {
        if let known = error as? NookTodoRemoteError { return known }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return .cancelled
            case .badServerResponse: return .invalidResponse
            default: return .offline
            }
        }
        return .offline
    }

    /// The failure a status stands for, nil for a good answer.
    static func failure(status: Int, response: HTTPURLResponse) -> NookTodoRemoteError? {
        if (200..<300).contains(status) { return nil }
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 404: return .notFound
        case 429: return .rateLimited(retryAfter: retryAfter(from: response))
        case 400..<500: return .badRequest
        default: return .server(status: status)
        }
    }

    /// `Retry-After` as a number of seconds.
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(raw.trimmingCharacters(in: .whitespaces)),
              seconds.isFinite, seconds >= 0 else { return nil }
        return min(seconds, maxRetryAfter)
    }
}

/// The one way a backend sends a request.
enum NookTodoRemoteHTTP {
    /// A JSON request with the token in the `Authorization` header. `bearer`
    /// false sends the token bare, which is how monday wants it.
    static func request(
        url: URL,
        method: String,
        token: String,
        bearer: Bool = true,
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = NookTodoURLSessionTransport.requestTimeout
        request.setValue(bearer ? "Bearer \(token)" : token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Sends and answers the body, or throws a `NookTodoRemoteError`.
    static func send(_ request: URLRequest, transport: any NookTodoTransport) async throws -> Data {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw NookTodoRemoteError.classify(error)
        }
        if let failure = NookTodoRemoteError.failure(status: response.statusCode, response: response) {
            throw failure
        }
        return data
    }

    /// A URL from parts, with every path segment escaped on its own. IDs
    /// come from the network and from settings and never make a path of
    /// their own.
    static func url(host: String, path: [String], query: [URLQueryItem] = []) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        var encoded: [String] = []
        for segment in path {
            guard !segment.isEmpty, let escaped = segment.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw NookTodoRemoteError.invalidResponse
            }
            encoded.append(escaped)
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.percentEncodedPath = "/" + encoded.joined(separator: "/")
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw NookTodoRemoteError.invalidResponse }
        return url
    }

    /// Decodes, or throws `invalidResponse` with no words from the body.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw NookTodoRemoteError.invalidResponse
        }
    }

    /// A date such as "2026-10-20" as midnight of that day on the Mac's
    /// calendar, which is how the card's due days are kept (D69).
    static func day(_ text: String?, calendar: Calendar = .current) -> Date? {
        guard let text, text.count == 10 else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// An ISO 8601 moment, with or without fractions of a second.
    static func moment(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFractions = ISO8601DateFormatter()
        withFractions.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractions.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }

    /// A due day as the apps write one: "2026-10-20".
    static func dayText(_ due: DateComponents?, calendar: Calendar = .current) -> String? {
        guard let due, let date = NookTodoDay.date(from: due, calendar: calendar) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

/// What a remote source is doing, or why it cannot show live tasks. Each
/// case has one sentence, worded with the app's name.
enum NookTodoRemoteState: Equatable, Sendable {
    case inactive
    case connecting
    case noToken
    /// The app's address has not been given (Canvas).
    case noHost
    /// The token file could not be read, saved or deleted.
    case tokenFileProblem
    /// 401: the token is wrong or was revoked.
    case invalidToken
    /// A new token could not be checked: the app was reached and did not
    /// answer the question. Nothing retries a connect.
    case connectFailed
    /// No workspace or board picked yet.
    case noPlace
    /// 404: the workspace or board is gone.
    case placeUnavailable
    /// Another 4xx: the app would not take the request.
    case rejected
    /// 403 on a read.
    case forbidden
    case rateLimited
    case offline
    case serverError
    case ready

    /// Failures that pass on their own. The rows stay on screen.
    var isTransientFailure: Bool {
        switch self {
        case .rateLimited, .offline, .serverError: true
        default: false
        }
    }

    var messageKey: String {
        switch self {
        case .inactive: "nook.todo.remote.state.inactive"
        case .connecting: "nook.todo.remote.state.connecting"
        case .noToken: "nook.todo.remote.state.noToken"
        case .noHost: "nook.todo.remote.state.noHost"
        case .tokenFileProblem: "nook.todo.remote.state.tokenFile"
        case .invalidToken: "nook.todo.remote.state.invalidToken"
        case .connectFailed: "nook.todo.remote.state.connectFailed"
        case .noPlace: "nook.todo.remote.state.noPlace"
        case .placeUnavailable: "nook.todo.remote.state.placeUnavailable"
        case .rejected: "nook.todo.remote.state.rejected"
        case .forbidden: "nook.todo.remote.state.forbidden"
        case .rateLimited: "nook.todo.remote.state.rateLimited"
        case .offline: "nook.todo.remote.state.offline"
        case .serverError: "nook.todo.remote.state.serverError"
        case .ready: "nook.todo.remote.state.ready"
        }
    }

    /// The sentence, with the app's name in it.
    func message(app: String, lang: LanguageManager = .shared) -> String {
        lang.t(messageKey, app)
    }
}

/// A write that failed for a reason that may not repeat.
enum NookTodoRemoteActionError: Equatable, Sendable {
    case addFailed
    case completeFailed
    case notesFailed
    case rateLimited

    var concernsNotes: Bool { self == .notesFailed }

    var messageKey: String {
        switch self {
        case .addFailed: "nook.todo.remote.error.addFailed"
        case .completeFailed: "nook.todo.remote.error.completeFailed"
        case .notesFailed: "nook.todo.remote.error.notesFailed"
        case .rateLimited: "nook.todo.remote.state.rateLimited"
        }
    }
}

/// A host name the user typed for an app that lives at a school's address.
enum NookTodoRemoteHost {
    /// "bruinlearn.ucla.edu" from whatever was pasted: a scheme, a path and
    /// blank space are dropped; anything that is not a host name is nil.
    static func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        guard !text.isEmpty, text.count <= 253, !text.hasPrefix("."), !text.hasSuffix("."),
              text.contains(".") else { return nil }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        for label in labels {
            guard !label.isEmpty, label.count <= 63,
                  label.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
                  !label.hasPrefix("-"), !label.hasSuffix("-") else { return nil }
        }
        return text
    }
}
