import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct CanvasTodoBackendTests {
    static let host = "school.example.edu"
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// A moment in days from `now`, written the way Canvas writes it.
    static func due(inDays days: Double) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(days * 86_400))
    }

    static func session(_ transport: StubTodoTransport) -> NookTodoRemoteSession {
        NookTodoRemoteSession(token: "canvas-token", host: host, transport: transport, now: now)
    }

    static let courses = """
    [{"id":11,"name":"Intro to Linguistics","course_code":"LING 1"},
     {"id":12,"name":"Operating Systems","course_code":"CS 111"}]
    """

    static func item(
        id: Int, title: String, due: String?, course: Int = 12, context: String = "Operating Systems",
        submissions: String = "false", override: String = "null", type: String = "assignment"
    ) -> String {
        let dueJSON = due.map { "\"\($0)\"" } ?? "null"
        return """
        {"plannable_type":"\(type)","plannable_id":\(id),"course_id":\(course),"context_name":"\(context)",
         "plannable":{"id":\(id),"title":"\(title)","due_at":\(dueJSON)},
         "submissions":\(submissions),"planner_override":\(override)}
        """
    }

    static func serve(_ transport: StubTodoTransport, planner: [String]) {
        transport.setResponder { request, _ in
            switch request.url?.path ?? "" {
            case "/api/v1/courses": return .json(courses)
            case "/api/v1/planner/items": return .json("[" + planner.joined(separator: ",") + "]")
            default: return .json("{}", status: 404)
            }
        }
    }

    @Test func checkListsActiveCoursesWithBearerHeaderOnTheHost() async throws {
        let transport = StubTodoTransport { _, _ in .json(Self.courses) }
        let result = try await CanvasTodoBackend.check(Self.session(transport))
        #expect(result.places.map(\.id) == ["11", "12"])
        #expect(result.places.map(\.name) == ["Intro to Linguistics", "Operating Systems"])
        let request = try #require(transport.requests.first)
        #expect(request.url?.host == Self.host)
        #expect(request.url?.path == "/api/v1/courses")
        #expect(request.url?.query?.contains("enrollment_state=active") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer canvas-token")
    }

    @Test func loadKeepsOnlyOpenAssignmentsInTheWindowAndFillsTheRows() async throws {
        let transport = StubTodoTransport()
        Self.serve(transport, planner: [
            Self.item(id: 3, title: "Zebra essay", due: Self.due(inDays: 2)),
            Self.item(id: 1, title: "Alpha lab", due: Self.due(inDays: 2), course: 11, context: "Intro"),
            Self.item(id: 2, title: "Early quiz", due: Self.due(inDays: 1), override: "{\"id\":900,\"marked_complete\":false}"),
            Self.item(id: 4, title: "Turned in", due: Self.due(inDays: 1), submissions: "{\"submitted\":true}"),
            Self.item(id: 5, title: "Open submission", due: Self.due(inDays: 3), submissions: "{\"submitted\":false}"),
            Self.item(id: 6, title: "Marked done", due: Self.due(inDays: 1), override: "{\"id\":901,\"marked_complete\":true}"),
            Self.item(id: 7, title: "Too far", due: Self.due(inDays: 30)),
            Self.item(id: 8, title: "A quiz page", due: Self.due(inDays: 1), type: "wiki_page"),
            Self.item(id: 9, title: "Unknown course", due: Self.due(inDays: 4), course: 99, context: "Mystery 5")
        ])
        let load = try await CanvasTodoBackend.load(Self.session(transport), placeID: nil, placeName: nil)

        #expect(load.items.map(\.title) == ["Early quiz", "Alpha lab", "Zebra essay", "Open submission", "Unknown course"])
        #expect(load.items.map(\.id) == [
            "canvas:assignment:2", "canvas:assignment:1", "canvas:assignment:3",
            "canvas:assignment:5", "canvas:assignment:9"
        ])
        #expect(load.items.map(\.listName) == ["CS 111", "LING 1", "CS 111", "CS 111", "Mystery 5"])
        #expect(load.items.allSatisfy { !$0.isCompleted && $0.notes == nil })
        #expect(load.context == ["override:canvas:assignment:2": "900"])

        let planner = try #require(transport.requests(endingWith: "/planner/items").first)
        let query = planner.url?.query ?? ""
        #expect(query.contains("per_page=100"))
        #expect(query.contains("start_date=" + ISO8601DateFormatter().string(from: Self.now)))
        #expect(query.contains("end_date=" + ISO8601DateFormatter().string(from: Self.now.addingTimeInterval(14 * 86_400))))
    }

    @Test func completePutsToAnExistingOverride() async throws {
        let transport = StubTodoTransport { _, _ in .json("{}") }
        try await CanvasTodoBackend.complete(
            "canvas:assignment:2", session: Self.session(transport), placeID: nil,
            context: ["override:canvas:assignment:2": "900"]
        )
        let request = try #require(transport.requests.first)
        #expect(request.route == "PUT /api/v1/planner/overrides/900")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer canvas-token")
        #expect(request.jsonBody["marked_complete"] as? Bool == true)
    }

    @Test func completePostsANewOverrideWhenThereIsNone() async throws {
        let transport = StubTodoTransport { _, _ in .json("{}") }
        try await CanvasTodoBackend.complete(
            "canvas:assignment:77", session: Self.session(transport), placeID: nil, context: [:]
        )
        let request = try #require(transport.requests.first)
        #expect(request.route == "POST /api/v1/planner/overrides")
        let body = request.jsonBody
        #expect(body["plannable_type"] as? String == "assignment")
        #expect(body["plannable_id"] as? Int == 77)
        #expect(body["marked_complete"] as? Bool == true)
    }

    @Test func aWrongHostClassifiesAsNotFound() async {
        let transport = StubTodoTransport { _, _ in .json("{}", status: 404) }
        await #expect(throws: NookTodoRemoteError.notFound) {
            _ = try await CanvasTodoBackend.check(Self.session(transport))
        }
    }

    @Test func aRejectedTokenClassifiesAsUnauthorized() async {
        let transport = StubTodoTransport { _, _ in .json("{}", status: 401) }
        await #expect(throws: NookTodoRemoteError.unauthorized) {
            _ = try await CanvasTodoBackend.load(Self.session(transport), placeID: nil, placeName: nil)
        }
    }
}
