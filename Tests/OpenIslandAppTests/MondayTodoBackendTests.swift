import Foundation
import Testing
@testable import OpenIslandApp

@Suite struct MondayTodoBackendTests {
    private static let columns = """
    {"data":{"me":{"id":"42"},"boards":[{"name":"Sprint","columns":[
      {"id":"name","title":"Name","type":"name"},
      {"id":"person","title":"Owner","type":"people"},
      {"id":"status","title":"Status","type":"status"},
      {"id":"date4","title":"Due","type":"date"},
      {"id":"date9","title":"Created","type":"date"}]}]}}
    """

    private static let noPeople = """
    {"data":{"me":{"id":"42"},"boards":[{"name":"Sprint","columns":[
      {"id":"status","title":"Status","type":"status"}]}]}}
    """

    private static let items = """
    {"data":{"boards":[{"items_page":{"items":[
      {"id":"3","name":"Zeta","column_values":[
        {"id":"status","type":"status","text":"Working on it"},{"id":"date4","type":"date","text":"2026-10-22"}]},
      {"id":"1","name":"Old thing","column_values":[
        {"id":"status","type":"status","text":"done"},{"id":"date4","type":"date","text":"2026-10-01"}]},
      {"id":"2","name":"Alpha","column_values":[
        {"id":"status","type":"status","text":"Stuck"},{"id":"date4","type":"date","text":"2026-10-20 09:30"}]},
      {"id":"4","name":"Undated","column_values":[
        {"id":"status","type":"status","text":null},{"id":"date4","type":"date","text":null}]}
    ]}}]}}
    """

    private static func session(_ transport: StubTodoTransport) -> NookTodoRemoteSession {
        NookTodoRemoteSession(token: "mon_secret", host: nil, transport: transport)
    }

    private static func loadTransport(columns: String = columns) -> StubTodoTransport {
        StubTodoTransport { _, index in .json(index == 0 ? columns : items) }
    }

    private static let loadContext = [
        "peopleColumn": "person", "statusColumn": "status", "dateColumn": "date4",
        "meID": "42", "boardName": "Sprint",
    ]

    private func query(_ request: URLRequest) -> String {
        request.jsonBody["query"] as? String ?? ""
    }

    private func variables(_ request: URLRequest) -> [String: Any] {
        request.jsonBody["variables"] as? [String: Any] ?? [:]
    }

    // MARK: Check

    @Test func checkListsBoardsAndSendsTheBareToken() async throws {
        let transport = StubTodoTransport { _, _ in
            .json(#"{"data":{"me":{"id":"42","name":"Mannie"},"boards":[{"id":"7","name":"Sprint"},{"id":"8","name":"Home"}]}}"#)
        }
        let result = try await MondayTodoBackend.check(Self.session(transport))
        #expect(result.accountName == "Mannie")
        #expect(result.places == [
            NookTodoPlaceChoice(id: "7", name: "Sprint"), NookTodoPlaceChoice(id: "8", name: "Home"),
        ])
        let request = try #require(transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.monday.com/v2")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "mon_secret")
        #expect(request.value(forHTTPHeaderField: "API-Version") == "2025-01")
        #expect(query(request).contains("boards(limit: 100, state: active)"))
    }

    // MARK: Load

    @Test func loadKeepsOpenItemsSortedWithPrefixedIds() async throws {
        let transport = Self.loadTransport()
        let load = try await MondayTodoBackend.load(Self.session(transport), placeID: "7", placeName: nil)
        #expect(load.items.map(\.id) == ["monday:2", "monday:3", "monday:4"])
        #expect(load.items.map(\.title) == ["Alpha", "Zeta", "Undated"])
        #expect(load.items.allSatisfy { $0.listName == "Sprint" && !$0.isCompleted })
        #expect(load.items[0].dueDate == NookTodoRemoteHTTP.day("2026-10-20"))
        #expect(load.items[1].dueDate == NookTodoRemoteHTTP.day("2026-10-22"))
        #expect(load.items[2].dueDate == nil)
        #expect(load.placeName == "Sprint")
        #expect(load.context == Self.loadContext)

        let requests = transport.requests
        #expect(requests.count == 2)
        #expect(query(requests[0]).contains("columns { id title type }"))
        #expect(query(requests[0]).contains("me { id }"))
        #expect(variables(requests[0])["ids"] as? [String] == ["7"])
        let second = query(requests[1])
        #expect(second.contains("items_page"))
        #expect(second.contains("column_id: \"person\""))
        #expect(second.contains("assigned_to_me"))
        #expect(variables(requests[1])["ids"] as? [String] == ["7"])
    }

    @Test func loadWithoutAPeopleColumnSendsNoRules() async throws {
        let transport = Self.loadTransport(columns: Self.noPeople)
        let load = try await MondayTodoBackend.load(Self.session(transport), placeID: "7", placeName: nil)
        let last = try #require(transport.requests.last)
        let second = query(last)
        #expect(second.contains("items_page"))
        #expect(!second.contains("rules"))
        #expect(!second.contains("assigned_to_me"))
        #expect(load.context["peopleColumn"] == nil)
        #expect(load.context["dateColumn"] == nil)
        #expect(load.context["statusColumn"] == "status")
    }

    // MARK: Writes

    @Test func addSendsCreateItemWithThePersonAndTheDate() async throws {
        let transport = StubTodoTransport { _, _ in .json(#"{"data":{"create_item":{"id":"9"}}}"#) }
        try await MondayTodoBackend.add(
            "Write essay", due: DateComponents(year: 2026, month: 10, day: 25),
            session: Self.session(transport), placeID: "7", context: Self.loadContext
        )
        let request = try #require(transport.requests.first)
        #expect(query(request).contains("create_item"))
        let vars = variables(request)
        #expect(vars["board"] as? String == "7")
        #expect(vars["name"] as? String == "Write essay")
        let text = try #require(vars["values"] as? String)
        let values = try #require(
            try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        let people = try #require(values["person"] as? [String: Any])
        let persons = try #require(people["personsAndTeams"] as? [[String: Any]])
        #expect(persons.first?["id"] as? Int == 42)
        #expect(persons.first?["kind"] as? String == "person")
        #expect((values["date4"] as? [String: Any])?["date"] as? String == "2026-10-25")
    }

    @Test func addLeavesOutColumnsThatDoNotExist() async throws {
        let transport = StubTodoTransport { _, _ in .json(#"{"data":{"create_item":{"id":"9"}}}"#) }
        try await MondayTodoBackend.add(
            "Plain", due: nil, session: Self.session(transport), placeID: "7", context: ["statusColumn": "status"]
        )
        let request = try #require(transport.requests.first)
        #expect(variables(request)["values"] as? String == "{}")
    }

    @Test func completeSendsChangeSimpleColumnValueWithDone() async throws {
        let transport = StubTodoTransport { _, _ in .json(#"{"data":{"change_simple_column_value":{"id":"3"}}}"#) }
        try await MondayTodoBackend.complete(
            "monday:3", session: Self.session(transport), placeID: "7", context: Self.loadContext
        )
        let request = try #require(transport.requests.first)
        #expect(query(request).contains("change_simple_column_value"))
        let vars = variables(request)
        #expect(vars["board"] as? String == "7")
        #expect(vars["item"] as? String == "3")
        #expect(vars["column"] as? String == "status")
        #expect(vars["value"] as? String == "Done")
    }

    @Test func completeWithoutAStatusColumnIsABadRequest() async {
        let transport = StubTodoTransport()
        await #expect(throws: NookTodoRemoteError.badRequest) {
            try await MondayTodoBackend.complete(
                "monday:3", session: Self.session(transport), placeID: "7", context: ["peopleColumn": "person"]
            )
        }
        #expect(transport.requests.isEmpty)
    }

    // MARK: Errors

    @Test func anErrorsBodyIsClassifiedEvenAtStatus200() async {
        let cases: [(String, NookTodoRemoteError)] = [
            ("Not Authenticated", .unauthorized),
            ("Unauthorized: bad token", .unauthorized),
            ("ComplexityException: too costly", .rateLimited(retryAfter: nil)),
            ("Something else broke", .badRequest),
        ]
        for (message, expected) in cases {
            let transport = StubTodoTransport { _, _ in
                .json(#"{"errors":[{"message":"\#(message)"}],"data":null}"#)
            }
            await #expect(throws: expected) {
                _ = try await MondayTodoBackend.check(Self.session(transport))
            }
        }
    }

    @Test func aBodyThatIsNotTheExpectedShapeIsInvalid() async {
        let transport = StubTodoTransport { _, _ in .json(#"{"data":{"boards":"nope"}}"#) }
        await #expect(throws: NookTodoRemoteError.invalidResponse) {
            _ = try await MondayTodoBackend.check(Self.session(transport))
        }
    }
}
