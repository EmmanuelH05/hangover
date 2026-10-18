import Foundation

/// Asana's requests for the todo card (D83): my open tasks in one
/// workspace. The shape is fixed by `NookTodoBackend` and ruling B4.
enum AsanaTodoBackend: NookTodoBackend {
    static let kind = NookTodoSourceKind.asana
    static let needsPlace = true
    static let canAdd = true
    static let canComplete = true
    static let canEditNotes = true
    static let canSetDue = true

    private static let host = "app.asana.com"
    private static let idPrefix = "asana:"

    private struct Envelope<Payload: Decodable>: Decodable {
        let data: Payload
    }

    private struct Named: Decodable {
        let gid: String
        let name: String
    }

    private struct Me: Decodable {
        let name: String?
        let workspaces: [Named]?
    }

    private struct Task: Decodable {
        let gid: String
        let name: String?
        let due_on: String?
        let due_at: String?
        let notes: String?
        let completed: Bool?
    }

    static func check(_ session: NookTodoRemoteSession) async throws -> NookTodoRemoteCheck {
        let url = try NookTodoRemoteHTTP.url(
            host: host, path: ["api", "1.0", "users", "me"],
            query: [URLQueryItem(name: "opt_fields", value: "name,workspaces.name")]
        )
        let data = try await send(url, method: "GET", session: session)
        let me = try NookTodoRemoteHTTP.decode(Envelope<Me>.self, from: data).data
        let places = (me.workspaces ?? []).map { NookTodoPlaceChoice(id: $0.gid, name: $0.name) }
        return NookTodoRemoteCheck(places: places, accountName: me.name)
    }

    static func load(
        _ session: NookTodoRemoteSession, placeID: String?, placeName: String?
    ) async throws -> NookTodoRemoteLoad {
        guard let placeID, !placeID.isEmpty else { throw NookTodoRemoteError.notFound }
        let url = try NookTodoRemoteHTTP.url(
            host: host, path: ["api", "1.0", "tasks"],
            query: [
                URLQueryItem(name: "assignee", value: "me"),
                URLQueryItem(name: "workspace", value: placeID),
                URLQueryItem(name: "completed_since", value: "now"),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(
                    name: "opt_fields",
                    value: "name,due_on,due_at,notes,completed,projects.name"
                ),
            ]
        )
        let data = try await send(url, method: "GET", session: session)
        let tasks = try NookTodoRemoteHTTP.decode(Envelope<[Task]>.self, from: data).data
        let list = placeName ?? ""
        let items = tasks
            .filter { $0.completed != true }
            .map { task in
                NookTodoItem(
                    id: idPrefix + task.gid,
                    title: task.name ?? "",
                    dueDate: NookTodoRemoteHTTP.day(task.due_on) ?? NookTodoRemoteHTTP.moment(task.due_at),
                    isCompleted: false,
                    listName: list,
                    notes: task.notes
                )
            }
            .sorted(by: dueThenTitle)
        return NookTodoRemoteLoad(items: items, placeName: placeName)
    }

    static func add(
        _ title: String, due: DateComponents?, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        guard let placeID, !placeID.isEmpty else { throw NookTodoRemoteError.notFound }
        var fields: [String: Any] = ["name": title, "workspace": placeID, "assignee": "me"]
        if let day = NookTodoRemoteHTTP.dayText(due) { fields["due_on"] = day }
        let url = try NookTodoRemoteHTTP.url(host: host, path: ["api", "1.0", "tasks"])
        _ = try await send(url, method: "POST", session: session, body: try body(fields))
    }

    static func complete(
        _ id: String, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        try await update(id, fields: ["completed": true], session: session)
    }

    static func setNotes(
        _ notes: String, for id: String, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        try await update(id, fields: ["notes": notes], session: session)
    }

    private static func update(_ id: String, fields: [String: Any], session: NookTodoRemoteSession) async throws {
        let url = try NookTodoRemoteHTTP.url(host: host, path: ["api", "1.0", "tasks", gid(from: id)])
        _ = try await send(url, method: "PUT", session: session, body: try body(fields))
    }

    /// The id Asana knows: a row id without the app's prefix.
    private static func gid(from id: String) -> String {
        id.hasPrefix(idPrefix) ? String(id.dropFirst(idPrefix.count)) : id
    }

    private static func body(_ fields: [String: Any]) throws -> Data {
        do {
            return try JSONSerialization.data(withJSONObject: ["data": fields])
        } catch {
            throw NookTodoRemoteError.badRequest
        }
    }

    private static func send(
        _ url: URL, method: String, session: NookTodoRemoteSession, body: Data? = nil
    ) async throws -> Data {
        let request = NookTodoRemoteHTTP.request(url: url, method: method, token: session.token, body: body)
        return try await NookTodoRemoteHTTP.send(request, transport: session.transport)
    }

    /// Undated rows go last; the rest by day, then by title.
    private static func dueThenTitle(_ a: NookTodoItem, _ b: NookTodoItem) -> Bool {
        switch (a.dueDate, b.dueDate) {
        case let (x?, y?) where x != y: return x < y
        case (nil, _?): return false
        case (_?, nil): return true
        default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }
}
