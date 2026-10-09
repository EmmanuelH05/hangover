import Foundation

// Response models for the parts of the TickTick Open API the todo widget
// reads. Every type decodes leniently: unknown fields are ignored, and one
// malformed entry in a list is dropped instead of failing the whole response.

/// Decodes to nil instead of throwing when the payload has an unexpected shape.
struct TickTickLossy<Wrapped: Decodable & Sendable>: Decodable, Sendable {
    let value: Wrapped?

    init(from decoder: Decoder) throws {
        value = try? Wrapped(from: decoder)
    }
}

private struct TickTickKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension KeyedDecodingContainer where Key == TickTickKey {
    func lenient<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        try? decodeIfPresent(T.self, forKey: TickTickKey(key))
    }

    /// A string that is present and not empty.
    func text(_ key: String) -> String? {
        lenient(String.self, key).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Decodes from any JSON value and keeps nothing. Counts entries of a list
/// whose content does not matter.
private struct TickTickIgnored: Decodable, Sendable {
    init(from decoder: Decoder) throws {}
}

/// A list. TickTick's API calls it a project.
struct TickTickProject: Decodable, Equatable, Sendable {
    let id: String
    let name: String
    /// True for an archived list.
    let isClosed: Bool
    /// "TASK" or "NOTE". Nil when TickTick did not say.
    let kind: String?
    /// "read", "write" or "comment". Nil for a list the user owns.
    let permission: String?

    init(id: String, name: String, isClosed: Bool = false, kind: String? = nil, permission: String? = nil) {
        self.id = id
        self.name = name
        self.isClosed = isClosed
        self.kind = kind
        self.permission = permission
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TickTickKey.self)
        id = try container.decode(String.self, forKey: TickTickKey("id"))
        name = container.lenient(String.self, "name") ?? ""
        isClosed = container.lenient(Bool.self, "closed") ?? false
        kind = container.text("kind")
        permission = container.text("permission")
    }

    /// A list of notes holds no tasks to check off.
    var holdsTasks: Bool { kind?.uppercased() != "NOTE" }

    /// A shared list the user may read or comment on, and not change.
    var isReadOnly: Bool { permission.map { $0.lowercased() != "write" } ?? false }
}

struct TickTickTask: Decodable, Equatable, Sendable {
    static let statusOpen = 0

    let id: String
    /// Nil when TickTick left it out. The list that was asked for stands in.
    let projectID: String?
    let title: String
    /// The note of a plain task.
    let content: String?
    /// The note of a task that has a checklist.
    let desc: String?
    /// As sent: `yyyy-MM-dd'T'HH:mm:ssZ`, with or without milliseconds.
    let startDate: String?
    let dueDate: String?
    let isAllDay: Bool
    /// The IANA zone the dates were set in.
    let timeZone: String?
    /// 0 is open, 2 is completed, -1 is abandoned.
    let status: Int
    /// TickTick's own order inside a list. Smaller comes first.
    let sortOrder: Int64
    /// "TEXT", "NOTE" or "CHECKLIST".
    let kind: String?
    /// The task carries checklist items of its own.
    let hasChecklistItems: Bool

    init(
        id: String,
        projectID: String? = nil,
        title: String,
        content: String? = nil,
        desc: String? = nil,
        startDate: String? = nil,
        dueDate: String? = nil,
        isAllDay: Bool = false,
        timeZone: String? = nil,
        status: Int = TickTickTask.statusOpen,
        sortOrder: Int64 = 0,
        kind: String? = nil,
        hasChecklistItems: Bool = false
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.content = content
        self.desc = desc
        self.startDate = startDate
        self.dueDate = dueDate
        self.isAllDay = isAllDay
        self.timeZone = timeZone
        self.status = status
        self.sortOrder = sortOrder
        self.kind = kind
        self.hasChecklistItems = hasChecklistItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TickTickKey.self)
        id = try container.decode(String.self, forKey: TickTickKey("id"))
        projectID = container.text("projectId")
        title = container.lenient(String.self, "title") ?? ""
        content = container.text("content")
        desc = container.text("desc")
        startDate = container.text("startDate")
        dueDate = container.text("dueDate")
        isAllDay = container.lenient(Bool.self, "isAllDay") ?? false
        timeZone = container.text("timeZone")
        status = container.lenient(Int.self, "status") ?? Self.statusOpen
        sortOrder = container.lenient(Int64.self, "sortOrder") ?? 0
        kind = container.text("kind")
        hasChecklistItems = !(container.lenient([TickTickIgnored].self, "items") ?? []).isEmpty
    }
}

/// `GET /project/{id}/data`: a list and its open tasks.
struct TickTickProjectData: Decodable, Equatable, Sendable {
    /// Missing for the inbox on some accounts.
    let project: TickTickProject?
    let tasks: [TickTickTask]

    init(project: TickTickProject?, tasks: [TickTickTask]) {
        self.project = project
        self.tasks = tasks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TickTickKey.self)
        project = container.lenient(TickTickLossy<TickTickProject>.self, "project")?.value
        tasks = (container.lenient([TickTickLossy<TickTickTask>].self, "tasks") ?? []).compactMap(\.value)
    }
}

/// The body TickTick sends with a failed request.
struct TickTickErrorBody: Decodable, Sendable {
    let errorCode: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TickTickKey.self)
        errorCode = container.text("errorCode")
    }
}
