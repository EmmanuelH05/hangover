import Foundation

/// Canvas's requests for the todo card (T14): assignments due in the next
/// two weeks, not yet turned in, checked off through the planner. The shape
/// is fixed by `NookTodoBackend` and the decisions log (B6).
enum CanvasTodoBackend: NookTodoBackend {
    static let kind = NookTodoSourceKind.canvas
    static let needsPlace = false
    static let needsHost = true
    static let canAdd = false
    static let canComplete = true
    static let canEditNotes = false
    static let canSetDue = false

    /// Days ahead of now the planner is asked about.
    private static let windowDays = 14
    private static let idPrefix = "canvas:assignment:"
    private static let overrideKeyPrefix = "override:"

    static func check(_ session: NookTodoRemoteSession) async throws -> NookTodoRemoteCheck {
        let courses = try await fetchCourses(session)
        let places = courses.map { NookTodoPlaceChoice(id: $0.id.text, name: $0.name ?? $0.courseCode ?? $0.id.text) }
        return NookTodoRemoteCheck(places: places, accountName: nil)
    }

    static func load(
        _ session: NookTodoRemoteSession, placeID: String?, placeName: String?
    ) async throws -> NookTodoRemoteLoad {
        let courses = try await fetchCourses(session)
        var codeByCourse: [String: String] = [:]
        for course in courses {
            if let code = course.courseCode, !code.isEmpty { codeByCourse[course.id.text] = code }
        }

        let end = session.now.addingTimeInterval(TimeInterval(windowDays * 24 * 60 * 60))
        let formatter = ISO8601DateFormatter()
        let host = try requireHost(session)
        let url = try NookTodoRemoteHTTP.url(
            host: host,
            path: ["api", "v1", "planner", "items"],
            query: [
                URLQueryItem(name: "start_date", value: formatter.string(from: session.now)),
                URLQueryItem(name: "end_date", value: formatter.string(from: end)),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        let request = NookTodoRemoteHTTP.request(url: url, method: "GET", token: session.token)
        let data = try await NookTodoRemoteHTTP.send(request, transport: session.transport)
        let planned = try NookTodoRemoteHTTP.decode([PlannerItem].self, from: data)

        var rows: [NookTodoItem] = []
        var context: [String: String] = [:]
        var seen = Set<String>()
        for item in planned {
            guard item.plannableType == "assignment", let plannable = item.plannable,
                  let title = plannable.title,
                  !(item.submissions?.isSubmitted ?? false),
                  !(item.plannerOverride?.markedComplete ?? false),
                  let due = NookTodoRemoteHTTP.moment(plannable.dueAt),
                  due >= session.now, due <= end else { continue }
            let rowID = idPrefix + item.plannableID.text
            guard seen.insert(rowID).inserted else { continue }
            let course = item.courseID.map(\.text).flatMap { codeByCourse[$0] }
            let list = course ?? item.contextName ?? ""
            rows.append(NookTodoItem(id: rowID, title: title, dueDate: due, isCompleted: false, listName: list))
            if let override = item.plannerOverride { context[overrideKeyPrefix + rowID] = override.id.text }
        }
        rows.sort { left, right in
            if left.dueDate != right.dueDate { return (left.dueDate ?? .distantFuture) < (right.dueDate ?? .distantFuture) }
            return left.title < right.title
        }
        return NookTodoRemoteLoad(items: rows, placeName: nil, context: context)
    }

    static func complete(
        _ id: String, session: NookTodoRemoteSession, placeID: String?, context: [String: String]
    ) async throws {
        guard id.hasPrefix(idPrefix), id.count > idPrefix.count else { throw NookTodoRemoteError.badRequest }
        let plannableID = String(id.dropFirst(idPrefix.count))
        let host = try requireHost(session)
        let request: URLRequest
        if let overrideID = context[overrideKeyPrefix + id] {
            let url = try NookTodoRemoteHTTP.url(host: host, path: ["api", "v1", "planner", "overrides", overrideID])
            let body = try JSONSerialization.data(withJSONObject: ["marked_complete": true])
            request = NookTodoRemoteHTTP.request(url: url, method: "PUT", token: session.token, body: body)
        } else {
            let url = try NookTodoRemoteHTTP.url(host: host, path: ["api", "v1", "planner", "overrides"])
            // Canvas ids are numbers; one that is not stays a string.
            let plannable: Any = Int(plannableID) ?? plannableID
            let body = try JSONSerialization.data(withJSONObject: [
                "plannable_type": "assignment",
                "plannable_id": plannable,
                "marked_complete": true
            ])
            request = NookTodoRemoteHTTP.request(url: url, method: "POST", token: session.token, body: body)
        }
        _ = try await NookTodoRemoteHTTP.send(request, transport: session.transport)
    }

    // MARK: Requests

    private static func requireHost(_ session: NookTodoRemoteSession) throws -> String {
        guard let host = session.host, !host.isEmpty else { throw NookTodoRemoteError.badRequest }
        return host
    }

    private static func fetchCourses(_ session: NookTodoRemoteSession) async throws -> [Course] {
        let url = try NookTodoRemoteHTTP.url(
            host: try requireHost(session),
            path: ["api", "v1", "courses"],
            query: [
                URLQueryItem(name: "enrollment_state", value: "active"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        let request = NookTodoRemoteHTTP.request(url: url, method: "GET", token: session.token)
        let data = try await NookTodoRemoteHTTP.send(request, transport: session.transport)
        return try NookTodoRemoteHTTP.decode([Course].self, from: data)
    }

    // MARK: Wire types

    /// Canvas writes ids as numbers; a string id is read the same way.
    private struct FlexibleID: Decodable {
        let text: String

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                text = String(number)
            } else {
                text = try container.decode(String.self)
            }
        }
    }

    private struct Course: Decodable {
        let id: FlexibleID
        let name: String?
        let courseCode: String?

        enum CodingKeys: String, CodingKey {
            case id, name
            case courseCode = "course_code"
        }
    }

    /// `submissions` is the JSON value `false` when Canvas has nothing to
    /// say, else an object. Bool is tried first, then the object.
    private enum Submissions: Decodable {
        case none
        case object(submitted: Bool)

        private struct Body: Decodable { let submitted: Bool? }

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if (try? container.decode(Bool.self)) != nil {
                self = .none
            } else {
                self = .object(submitted: try container.decode(Body.self).submitted ?? false)
            }
        }

        var isSubmitted: Bool {
            if case .object(let submitted) = self { return submitted }
            return false
        }
    }

    private struct PlannerItem: Decodable {
        let plannableType: String
        let plannableID: FlexibleID
        let courseID: FlexibleID?
        let contextName: String?
        let plannable: Plannable?
        let submissions: Submissions?
        let plannerOverride: Override?

        struct Plannable: Decodable {
            let title: String?
            let dueAt: String?

            enum CodingKeys: String, CodingKey {
                case title
                case dueAt = "due_at"
            }
        }

        struct Override: Decodable {
            let id: FlexibleID
            let markedComplete: Bool?

            enum CodingKeys: String, CodingKey {
                case id
                case markedComplete = "marked_complete"
            }
        }

        enum CodingKeys: String, CodingKey {
            case plannable, submissions
            case plannableType = "plannable_type"
            case plannableID = "plannable_id"
            case courseID = "course_id"
            case contextName = "context_name"
            case plannerOverride = "planner_override"
        }
    }
}
