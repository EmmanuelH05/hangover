import Foundation
@testable import OpenIslandApp

enum TickTickFixtures {
    static let token = "tt_test_token_value"
    /// What the inbox is called in task payloads: `inbox` plus digits.
    static let inboxRealID = "inbox1234567"
    static let workID = "6226ff9877acee87727f6bca"

    static func task(
        id: String,
        title: String,
        projectID: String? = inboxRealID,
        due: String? = nil,
        allDay: Bool = false,
        timeZone: String? = nil,
        status: Int = 0,
        sortOrder: Int = 0,
        kind: String? = "TEXT",
        content: String? = nil,
        desc: String? = nil
    ) -> String {
        var fields = ["\"id\":\"\(id)\"", "\"title\":\"\(title)\"", "\"status\":\(status)",
                      "\"sortOrder\":\(sortOrder)", "\"isAllDay\":\(allDay)", "\"etag\":\"abc\"",
                      "\"some_future_field\":{\"a\":[1,2,3]}"]
        if let projectID { fields.append("\"projectId\":\"\(projectID)\"") }
        if let due { fields.append("\"dueDate\":\"\(due)\"") }
        if let timeZone { fields.append("\"timeZone\":\"\(timeZone)\"") }
        if let kind { fields.append("\"kind\":\"\(kind)\"") }
        if let content { fields.append("\"content\":\"\(content)\"") }
        if let desc { fields.append("\"desc\":\"\(desc)\"") }
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// One task as `GET /project/{id}/task/{id}` returns it, with fields the
    /// app never reads. A notes save must send every one of them back.
    static func storedTask(id: String, projectID: String = inboxRealID) -> String {
        """
        {"id":"\(id)","projectId":"\(projectID)","title":"Kept title","content":"old note","desc":"old desc",
         "dueDate":"2026-10-10T17:00:00+0000","repeatFlag":"RRULE:FREQ=MONTHLY;INTERVAL=1","priority":5,
         "tags":["work","urgent"],"reminders":["TRIGGER:PT0S"],"sortOrder":-2199023255552,"status":0,"etag":"abc"}
        """
    }

    static func project(
        id: String,
        name: String,
        closed: Bool = false,
        kind: String = "TASK",
        permission: String? = nil
    ) -> String {
        var fields = ["\"id\":\"\(id)\"", "\"name\":\"\(name)\"", "\"closed\":\(closed)",
                      "\"kind\":\"\(kind)\"", "\"viewMode\":\"list\"", "\"color\":\"#F18181\""]
        if let permission { fields.append("\"permission\":\"\(permission)\"") }
        return "{" + fields.joined(separator: ",") + "}"
    }

    static func projectData(project: String? = nil, tasks: [String]) -> String {
        let projectJSON = project.map { "\"project\":\($0)," } ?? ""
        return "{\(projectJSON)\"tasks\":[\(tasks.joined(separator: ","))],\"columns\":[]}"
    }

    static func list(_ entries: [String]) -> String {
        "[" + entries.joined(separator: ",") + "]"
    }

    static func decodeTask(_ json: String) throws -> TickTickTask {
        try JSONDecoder().decode(TickTickTask.self, from: Data(json.utf8))
    }

    static func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("TickTickTodoTests-\(UUID().uuidString)", isDirectory: true)
    }

    /// A calendar pinned to one zone, which keeps date tests the same on
    /// every machine.
    static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        return calendar
    }
}

/// Everything one TickTick service needs, with nothing shared between tests.
@MainActor
final class TickTickHarness {
    let transport = StubTodoTransport()
    let tokens: InMemoryTodoTokenStore
    let defaults: UserDefaults = MemoryDefaults()
    let directory = TickTickFixtures.makeTempDirectory()
    let clock = TestClock()
    let cache: TickTickTodoCache
    let service: NookTickTickTodoService

    init(token: String? = TickTickFixtures.token, listID: String? = nil) {
        tokens = InMemoryTodoTokenStore(token: token)
        cache = TickTickTodoCache(directory: directory)
        if let listID {
            defaults.set(listID, forKey: NookTickTickTodoService.Keys.listID)
        }
        let clock = clock
        service = NookTickTickTodoService(
            defaults: defaults, transport: transport, tokenStore: tokens, cache: cache, now: { clock.now }
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Serves an account: the inbox, the list of lists, and one more list.
    func serve(
        inbox: [String] = [],
        projects: [String] = [],
        work: String? = nil,
        written: String = TickTickFixtures.task(id: "new", title: "Written")
    ) {
        transport.setResponder { request, _ in
            switch request.route {
            case "GET /open/v1/project/inbox/data": .json(TickTickFixtures.projectData(tasks: inbox))
            case "GET /open/v1/project": .json(TickTickFixtures.list(projects))
            case "GET /open/v1/project/\(TickTickFixtures.workID)/data":
                work.map { .json($0) } ?? StubTodoResponse(status: 404)
            case "POST /open/v1/task": .json(written)
            default:
                if request.httpMethod == "GET", let id = request.url?.lastPathComponent,
                   request.url?.path.contains("/task/") == true {
                    .json(TickTickFixtures.storedTask(id: id))
                } else {
                    StubTodoResponse(status: 200, body: "")
                }
            }
        }
    }

    func activate() async {
        service.setActive(true)
        await service.setupTask?.value
    }

    /// Waits for the reload a write starts, and for cache writes to land.
    func settle() async {
        await service.refreshTask?.value
        for _ in 0..<20 { await Task.yield() }
        _ = await cache.load()
    }

    var routes: [String] { transport.requests.map(\.route) }

    /// The bodies of the notes updates sent for one task.
    func noteUpdates(for id: String) -> [[String: Any]] {
        transport.requests.filter { $0.route == "POST /open/v1/task/\(id)" }.map(\.jsonBody)
    }
}
