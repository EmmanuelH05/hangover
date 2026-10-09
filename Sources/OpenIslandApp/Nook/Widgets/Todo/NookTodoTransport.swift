import Foundation

/// Sends one HTTP request for a task source that lives on the network. The
/// app uses `URLSession`; tests use a stub.
protocol NookTodoTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct NookTodoURLSessionTransport: NookTodoTransport {
    static let requestTimeout: TimeInterval = 15
    static let resourceTimeout: TimeInterval = 30

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = Self.requestTimeout
        configuration.timeoutIntervalForResource = Self.resourceTimeout
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    /// Throws `URLError(.badServerResponse)` for an answer that is not HTTP.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
