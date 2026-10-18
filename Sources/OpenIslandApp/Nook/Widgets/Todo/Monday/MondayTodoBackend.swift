import Foundation

/// monday's requests for the todo card (D83): items assigned to me, not
/// Done, on one board. Everything goes to one GraphQL endpoint; the shape of
/// the calls is settled in the decisions log (B5).
enum MondayTodoBackend: NookTodoBackend {
    static let kind = NookTodoSourceKind.monday
    static let needsPlace = true
    static let canAdd = true
    static let canComplete = true
    static let canEditNotes = false
    static let canSetDue = true

    private static let host = "api.monday.com"
    private static let apiVersion = "2025-01"
    private static let idPrefix = "monday:"

    // MARK: Answers

    private struct Empty: Decodable {}

    private struct Failure: Decodable {
        let message: String?
        let extensions: Extensions?

        struct Extensions: Decodable {
            let code: String?
        }
    }

    /// The codes monday puts in `errors[].extensions.code` when requests
    /// come too fast or cost too much.
    private static let rateLimitCodes: Set<String> = [
        "complexityexception", "complexity_budget_exhausted", "rate_limit_exceeded",
    ]

    private struct ErrorsOnly: Decodable {
        let errors: [Failure]?
    }

    private struct Envelope<T: Decodable>: Decodable {
        let data: T?
    }

    private struct CheckData: Decodable {
        struct Me: Decodable {
            let id: String
            let name: String?
        }
        struct Board: Decodable {
            let id: String
            let name: String
        }
        let me: Me?
        let boards: [Board]?
    }

    private struct ColumnsData: Decodable {
        struct Me: Decodable {
            let id: String
        }
        struct Column: Decodable {
            let id: String
            let type: String
        }
        struct Board: Decodable {
            let name: String?
            let columns: [Column]?
        }
        let me: Me?
        let boards: [Board]?
    }

    private struct ItemsData: Decodable {
        struct Value: Decodable {
            let id: String
            let text: String?
        }
        struct Item: Decodable {
            let id: String
            let name: String
            let column_values: [Value]?
        }
        struct Page: Decodable {
            let items: [Item]?
        }
        struct Board: Decodable {
            let items_page: Page?
        }
        let boards: [Board]?
    }

    // MARK: The one request

    /// Posts a query with its variables and answers the `data` object. An
    /// `errors` array is a failure even when the status is 200, which is how
    /// monday reports a bad token or a query that costs too much.
    private static func post<T: Decodable>(
        _ query: String, variables: [String: any Sendable] = [:], as type: T.Type, session: NookTodoRemoteSession
    ) async throws -> T {
        let url = try NookTodoRemoteHTTP.url(host: host, path: ["v2"])
        guard let body = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": variables]) else {
            throw NookTodoRemoteError.badRequest
        }
        let request = NookTodoRemoteHTTP.request(
            url: url, method: "POST", token: session.token, bearer: false,
            headers: ["API-Version": apiVersion], body: body
        )
        let data = try await NookTodoRemoteHTTP.send(request, transport: session.transport)
        if let errors = try? JSONDecoder().decode(ErrorsOnly.self, from: data).errors, !errors.isEmpty {
            throw classify(errors)
        }
        guard let payload = try NookTodoRemoteHTTP.decode(Envelope<T>.self, from: data).data else {
            throw NookTodoRemoteError.invalidResponse
        }
        return payload
    }

    /// The message's words and the extension's code both count: monday has
    /// moved between the two across API versions.
    private static func classify(_ failures: [Failure]) -> NookTodoRemoteError {
        let text = failures.compactMap(\.message).joined(separator: " ").lowercased()
        let codes = Set(failures.compactMap { $0.extensions?.code?.lowercased() })
        if text.contains("not authenticated") || text.contains("unauthorized") || codes.contains("unauthorized") {
            return .unauthorized
        }
        if text.contains("complexity") || text.contains("rate limit") || !codes.isDisjoint(with: rateLimitCodes) {
            return .rateLimited(retryAfter: nil)
        }
        return .badRequest
    }

    // MARK: Backend

    static func check(_ session: NookTodoRemoteSession) async throws -> NookTodoRemoteCheck {
        let data = try await post(
            "query { me { id name } boards(limit: 100, state: active) { id name } }",
            as: CheckData.self, session: session
        )
        let places = (data.boards ?? []).map { NookTodoPlaceChoice(id: $0.id, name: $0.name) }
        return NookTodoRemoteCheck(places: places, accountName: data.me?.name)
    }

    static func load(
        _ session: NookTodoRemoteSession, placeID: String?, placeName: String?
    ) async throws -> NookTodoRemoteLoad {
        guard let placeID else { throw NookTodoRemoteError.notFound }
        let ids: [String: any Sendable] = ["ids": [placeID]]
        let first = try await post(
            "query ($ids: [ID!]) { me { id } boards(ids: $ids) { name columns { id title type } } }",
            variables: ids, as: ColumnsData.self, session: session
        )
        guard let board = first.boards?.first else { throw NookTodoRemoteError.notFound }
        let columns = board.columns ?? []
        let peopleColumn = columns.first { $0.type == "people" }?.id
        let statusColumn = columns.first { $0.type == "status" }?.id
        let dateColumn = columns.first { $0.type == "date" }?.id
        let boardName = board.name ?? placeName

        var rules = ""
        if let peopleColumn {
            rules = ", query_params: { rules: [{ column_id: \(quoted(peopleColumn)), "
                + "compare_value: [\"assigned_to_me\"], operator: any_of }] }"
        }
        let second = try await post(
            "query ($ids: [ID!]) { boards(ids: $ids) { items_page(limit: 100\(rules)) "
                + "{ items { id name column_values { id type text } } } } }",
            variables: ids, as: ItemsData.self, session: session
        )

        var rows: [NookTodoItem] = []
        for item in second.boards?.first?.items_page?.items ?? [] {
            let values = item.column_values ?? []
            if let statusColumn,
               let status = values.first(where: { $0.id == statusColumn })?.text,
               status.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Done") == .orderedSame {
                continue
            }
            var due: Date?
            if let dateColumn, let text = values.first(where: { $0.id == dateColumn })?.text {
                due = NookTodoRemoteHTTP.day(String(text.prefix(10)))
            }
            rows.append(NookTodoItem(
                id: idPrefix + item.id, title: item.name, dueDate: due, isCompleted: false,
                listName: boardName ?? ""
            ))
        }
        rows.sort { left, right in
            switch (left.dueDate, right.dueDate) {
            case let (a?, b?) where a != b: return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
            }
        }

        var context: [String: String] = [:]
        context["meID"] = first.me?.id
        context["peopleColumn"] = peopleColumn
        context["statusColumn"] = statusColumn
        context["dateColumn"] = dateColumn
        context["boardName"] = boardName
        return NookTodoRemoteLoad(items: rows, placeName: boardName, context: context)
    }

    static func add(
        _ title: String, due: DateComponents?, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        guard let placeID else { throw NookTodoRemoteError.notFound }
        var values: [String: Any] = [:]
        if let people = context["peopleColumn"], let me = context["meID"].flatMap({ Int($0) }) {
            values[people] = ["personsAndTeams": [["id": me, "kind": "person"]]]
        }
        if let dateColumn = context["dateColumn"], let day = NookTodoRemoteHTTP.dayText(due) {
            values[dateColumn] = ["date": day]
        }
        guard let encoded = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let valuesText = String(data: encoded, encoding: .utf8) else {
            throw NookTodoRemoteError.badRequest
        }
        _ = try await post(
            "mutation ($board: ID!, $name: String!, $values: JSON) "
                + "{ create_item(board_id: $board, item_name: $name, column_values: $values) { id } }",
            variables: ["board": placeID, "name": title, "values": valuesText],
            as: Empty.self, session: session
        )
    }

    static func complete(
        _ id: String, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        guard let placeID else { throw NookTodoRemoteError.notFound }
        guard let statusColumn = context["statusColumn"] else { throw NookTodoRemoteError.badRequest }
        let itemID = id.hasPrefix(idPrefix) ? String(id.dropFirst(idPrefix.count)) : id
        _ = try await post(
            "mutation ($board: ID!, $item: ID!, $column: String!, $value: String!) "
                + "{ change_simple_column_value(board_id: $board, item_id: $item, column_id: $column, "
                + "value: $value) { id } }",
            variables: ["board": placeID, "item": itemID, "column": statusColumn, "value": "Done"],
            as: Empty.self, session: session
        )
    }

    /// A string as a GraphQL literal. A column id is plain, but it comes from
    /// the network, so quotes and backslashes are escaped all the same.
    private static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }
}
