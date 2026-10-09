import Foundation
@testable import OpenIslandApp

/// What the stub answers for one request.
struct StubNotionResponse: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = "{}"

    static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> StubNotionResponse {
        StubNotionResponse(status: status, headers: headers, body: body)
    }
}

/// A transport that never touches the network. Records every request.
final class StubNotionTransport: NotionTransport, @unchecked Sendable {
    typealias Responder = @Sendable (_ request: URLRequest, _ callIndex: Int) throws -> StubNotionResponse

    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var responder: Responder
    private var hold: (@Sendable (URLRequest) async -> Void)?

    init(_ responder: @escaping Responder = { _, _ in StubNotionResponse() }) {
        self.responder = responder
    }

    var requests: [URLRequest] {
        lock.withLock { recorded }
    }

    func setResponder(_ responder: @escaping Responder) {
        lock.withLock { self.responder = responder }
    }

    /// Runs after a request is recorded and before it is answered. Lets a
    /// test keep one request in flight while other work happens.
    func setHold(_ hold: (@Sendable (URLRequest) async -> Void)?) {
        lock.withLock { self.hold = hold }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (index, current, wait): (Int, Responder, (@Sendable (URLRequest) async -> Void)?) = lock.withLock {
            recorded.append(request)
            return (recorded.count - 1, responder, hold)
        }
        if let wait { await wait(request) }
        let reply = try current(request, index)
        let url = request.url ?? URL(fileURLWithPath: "/")
        guard let response = HTTPURLResponse(
            url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers
        ) else {
            throw NotionAPIError.invalidResponse
        }
        return (Data(reply.body.utf8), response)
    }

    /// Requests whose path ends with the given suffix.
    func requests(endingWith suffix: String) -> [URLRequest] {
        requests.filter { $0.url?.path.hasSuffix(suffix) ?? false }
    }
}

extension URLRequest {
    /// The JSON body as a dictionary, for assertions.
    var jsonBody: [String: Any] {
        guard let httpBody, let object = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any] else {
            return [:]
        }
        return object
    }

    var route: String { "\(httpMethod ?? "") \(url?.path ?? "")" }
}

final class InMemoryNotionTokenStore: NotionTokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    private var reads = 0
    var failure: NotionKeychainError?

    init(token: String? = nil) { stored = token }

    var token: String? { lock.withLock { stored } }
    var readCount: Int { lock.withLock { reads } }

    func read() throws -> String? {
        try lock.withLock {
            reads += 1
            if let failure { throw failure }
            return stored
        }
    }

    func save(_ token: String) throws {
        try lock.withLock {
            if let failure { throw failure }
            stored = token
        }
    }

    func delete() throws {
        try lock.withLock {
            if let failure { throw failure }
            stored = nil
        }
    }
}

/// A clock the test moves by hand.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

enum NotionFixtures {
    static let token = "ntn_test_token_value"
    static let dataSourceID = "11111111-2222-3333-4444-555555555555"

    /// The reference "To-Do" database: a select Status with a Done option.
    static let selectSchema = """
    {"object":"data_source","id":"\(dataSourceID)","title":[{"type":"text","plain_text":"To-Do"}],
     "some_future_field":{"a":[1,2,3]},
     "properties":{
      "Task":{"id":"title","name":"Task","type":"title","title":{}},
      "Status":{"id":"st%3A1","name":"Status","type":"select","select":{"options":[
        {"id":"a","name":"To Do","color":"gray"},{"id":"b","name":"In Progress"},
        {"id":"c","name":"Waiting"},{"id":"d","name":"Done"}]}},
      "Due":{"id":"due1","name":"Due","type":"date","date":{}},
      "Priority":{"id":"pri1","name":"Priority","type":"select","select":{"options":[
        {"id":"l","name":"Low"},{"id":"h","name":"High"},{"id":"m","name":"Medium"}]}},
      "Category":{"id":"cat1","name":"Category","type":"select","select":{"options":[
        {"id":"w","name":"Work"},{"id":"s","name":"School"}]}},
      "Extra":{"id":"ex1","name":"Extra","type":"rich_text","rich_text":{}},
      "Notes":{"id":"nt1","name":"Notes","type":"rich_text","rich_text":{}},
      "Mystery":{"id":"my1","name":"Mystery","type":"hologram","hologram":[1,{"x":null}]},
      "Broken":"not an object",
      "Total":{"id":"f1","name":"Total","type":"formula","formula":{"expression":"1"}}
     }}
    """

    static let statusSchema = """
    {"object":"data_source","id":"\(dataSourceID)","title":[{"plain_text":"Projects"}],
     "properties":{
      "Name":{"id":"title","name":"Name","type":"title","title":{}},
      "Status":{"id":"st1","name":"Status","type":"status","status":{
        "options":[{"id":"o1","name":"Not started"},{"id":"o2","name":"In progress"},
                   {"id":"o3","name":"Done"},{"id":"o4","name":"Archived"}],
        "groups":[{"id":"g1","name":"To-do","option_ids":["o1"]},
                  {"id":"g2","name":"In progress","option_ids":["o2"]},
                  {"id":"g3","name":"Complete","option_ids":["o3","o4"]}]}},
      "Deadline":{"id":"dl1","name":"Deadline","type":"date","date":{}},
      "Created":{"id":"cr1","name":"Created","type":"date","date":{}},
      "Tags":{"id":"tg1","name":"Tags","type":"multi_select","multi_select":{"options":[
        {"id":"t1","name":"Home"},{"id":"t2","name":"Errand"}]}}
     }}
    """

    static let checkboxSchema = """
    {"object":"data_source","id":"\(dataSourceID)","title":[{"plain_text":"Groceries"}],
     "properties":{
      "Item":{"id":"title","name":"Item","type":"title","title":{}},
      "Bought":{"id":"cb1","name":"Bought","type":"checkbox","checkbox":{}},
      "Aisle":{"id":"ai1","name":"Aisle","type":"select","select":{"options":[{"id":"x","name":"Produce"}]}}
     }}
    """

    static func page(
        id: String,
        title: String,
        status: String? = "To Do",
        due: String? = nil,
        priority: String? = nil,
        notes: [String] = []
    ) -> String {
        let notesJSON = notes
            .map { "{\"type\":\"text\",\"text\":{\"content\":\"\($0)\"},\"plain_text\":\"\($0)\",\"href\":null}" }
            .joined(separator: ",")
        let statusJSON = status.map { "{\"id\":\"x\",\"name\":\"\($0)\",\"color\":\"gray\"}" } ?? "null"
        let dueJSON = due.map { "{\"start\":\"\($0)\",\"end\":null,\"time_zone\":null}" } ?? "null"
        let priorityJSON = priority.map { "{\"id\":\"p\",\"name\":\"\($0)\"}" } ?? "null"
        return """
        {"object":"page","id":"\(id)","in_trash":false,"properties":{
          "Task":{"id":"title","type":"title","title":[{"type":"text","plain_text":"\(title)","href":null}]},
          "Status":{"id":"st%3A1","type":"select","select":\(statusJSON)},
          "Due":{"id":"due1","type":"date","date":\(dueJSON)},
          "Priority":{"id":"pri1","type":"select","select":\(priorityJSON)},
          "Notes":{"id":"nt1","type":"rich_text","rich_text":[\(notesJSON)]},
          "Mystery":{"id":"my1","type":"hologram","hologram":{"deep":[1,2]}},
          "Total":{"id":"f1","type":"formula","formula":{"type":"number","number":3}}
        }}
        """
    }

    static func list(_ results: [String], hasMore: Bool = false, nextCursor: String? = nil) -> String {
        let cursor = nextCursor.map { "\"\($0)\"" } ?? "null"
        return "{\"object\":\"list\",\"results\":[\(results.joined(separator: ","))],\"has_more\":\(hasMore),\"next_cursor\":\(cursor)}"
    }

    static func decodeSchema(_ json: String) throws -> NotionDataSource {
        try JSONDecoder().decode(NotionDataSource.self, from: Data(json.utf8))
    }

    static func decodePage(_ json: String) throws -> NotionPage {
        try JSONDecoder().decode(NotionPage.self, from: Data(json.utf8))
    }

    /// A settings store for one test, held in memory.
    static func makeDefaults() -> UserDefaults { MemoryDefaults() }

    static func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NotionTodoTests-\(UUID().uuidString)", isDirectory: true)
    }
}
