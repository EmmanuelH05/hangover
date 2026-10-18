import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct AsanaTodoBackendTests {
    private static let token = "asana_test_token"

    private static func session(_ transport: StubTodoTransport) -> NookTodoRemoteSession {
        NookTodoRemoteSession(token: token, host: nil, transport: transport)
    }

    private static let tasks = """
    {"data":[
      {"gid":"30","name":"Undated","due_on":null,"due_at":null,"notes":"","completed":false},
      {"gid":"20","name":"Timed","due_on":null,"due_at":"2026-10-21T17:00:00.000Z","notes":"bring ID","completed":false,
       "projects":[{"gid":"p1","name":"Move"}]},
      {"gid":"10","name":"Dated","due_on":"2026-10-20","due_at":null,"notes":null,"completed":false},
      {"gid":"40","name":"Finished","due_on":"2026-10-19","due_at":null,"notes":"","completed":true},
      {"gid":"15","name":"Alpha","due_on":"2026-10-20","due_at":null,"notes":"","completed":false}
    ]}
    """

    @Test func checkListsWorkspacesAndTheAccountName() async throws {
        let transport = StubTodoTransport { _, _ in
            .json("""
            {"data":{"gid":"1","name":"Mannie","workspaces":[{"gid":"w1","name":"UCLA"},{"gid":"w2","name":"Home"}]}}
            """)
        }

        let check = try await AsanaTodoBackend.check(Self.session(transport))

        #expect(check.accountName == "Mannie")
        #expect(check.places == [
            NookTodoPlaceChoice(id: "w1", name: "UCLA"),
            NookTodoPlaceChoice(id: "w2", name: "Home"),
        ])
        let request = try #require(transport.requests.first)
        #expect(request.route == "GET /api/1.0/users/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token)")
        #expect(request.url?.host == "app.asana.com")
    }

    @Test func loadBuildsRowsDropsDoneAndSorts() async throws {
        let transport = StubTodoTransport { _, _ in .json(Self.tasks) }

        let load = try await AsanaTodoBackend.load(Self.session(transport), placeID: "w1", placeName: "UCLA")

        #expect(load.items.map(\.id) == ["asana:15", "asana:10", "asana:20", "asana:30"])
        #expect(load.items.allSatisfy { $0.listName == "UCLA" && !$0.isCompleted })
        #expect(load.placeName == "UCLA")
        let dated = try #require(load.items.first { $0.id == "asana:10" })
        #expect(dated.dueDate == NookTodoRemoteHTTP.day("2026-10-20"))
        let timed = try #require(load.items.first { $0.id == "asana:20" })
        #expect(timed.dueDate == NookTodoRemoteHTTP.moment("2026-10-21T17:00:00.000Z"))
        #expect(timed.notes == "bring ID")
        let undated = try #require(load.items.first { $0.id == "asana:30" })
        #expect(undated.dueDate == nil)

        let request = try #require(transport.requests.first)
        #expect(request.route == "GET /api/1.0/tasks")
        let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(query.first { $0.name == "workspace" }?.value == "w1")
        #expect(query.first { $0.name == "assignee" }?.value == "me")
        #expect(query.first { $0.name == "completed_since" }?.value == "now")
    }

    @Test func loadThrowsInvalidResponseOnBadJSON() async {
        let transport = StubTodoTransport { _, _ in .json("{\"data\":\"nope\"}") }

        await #expect(throws: NookTodoRemoteError.invalidResponse) {
            _ = try await AsanaTodoBackend.load(Self.session(transport), placeID: "w1", placeName: nil)
        }
    }

    @Test func addSendsNameWorkspaceAssigneeAndDay() async throws {
        let transport = StubTodoTransport()
        let due = DateComponents(year: 2026, month: 10, day: 22)

        try await AsanaTodoBackend.add(
            "Buy milk", due: due, session: Self.session(transport), placeID: "w1", context: [:]
        )

        let request = try #require(transport.requests.first)
        #expect(request.route == "POST /api/1.0/tasks")
        let data = request.jsonBody["data"] as? [String: Any]
        #expect(data?["name"] as? String == "Buy milk")
        #expect(data?["workspace"] as? String == "w1")
        #expect(data?["assignee"] as? String == "me")
        #expect(data?["due_on"] as? String == "2026-10-22")
    }

    @Test func addWithoutADayLeavesDueOut() async throws {
        let transport = StubTodoTransport()

        try await AsanaTodoBackend.add(
            "Call mom", due: nil, session: Self.session(transport), placeID: "w1", context: [:]
        )

        let data = transport.requests.first?.jsonBody["data"] as? [String: Any]
        #expect(data?["due_on"] == nil)
    }

    @Test func completeSendsCompletedToTheRightGid() async throws {
        let transport = StubTodoTransport()

        try await AsanaTodoBackend.complete(
            "asana:123", session: Self.session(transport), placeID: "w1", context: [:]
        )

        let request = try #require(transport.requests.first)
        #expect(request.route == "PUT /api/1.0/tasks/123")
        let data = request.jsonBody["data"] as? [String: Any]
        #expect(data?["completed"] as? Bool == true)
    }

    @Test func setNotesSendsTheNotes() async throws {
        let transport = StubTodoTransport()

        try await AsanaTodoBackend.setNotes(
            "five pages", for: "asana:77", session: Self.session(transport), placeID: "w1", context: [:]
        )

        let request = try #require(transport.requests.first)
        #expect(request.route == "PUT /api/1.0/tasks/77")
        let data = request.jsonBody["data"] as? [String: Any]
        #expect(data?["notes"] as? String == "five pages")
    }

    @Test func a401IsUnauthorized() async {
        let transport = StubTodoTransport { _, _ in .json("{}", status: 401) }

        await #expect(throws: NookTodoRemoteError.unauthorized) {
            _ = try await AsanaTodoBackend.check(Self.session(transport))
        }
    }

    @Test func a429CarriesRetryAfter() async {
        let transport = StubTodoTransport { _, _ in
            .json("{}", status: 429, headers: ["Retry-After": "30"])
        }

        await #expect(throws: NookTodoRemoteError.rateLimited(retryAfter: 30)) {
            _ = try await AsanaTodoBackend.load(Self.session(transport), placeID: "w1", placeName: nil)
        }
    }
}
