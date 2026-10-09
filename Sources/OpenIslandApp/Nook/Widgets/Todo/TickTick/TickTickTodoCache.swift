import Foundation

/// The last task list that loaded, kept on disk for offline starts.
struct TickTickTodoSnapshot: Codable, Equatable, Sendable {
    struct Task: Codable, Equatable, Sendable {
        let id: String
        let projectID: String
        let title: String
        let dueDate: Date?
        let notes: String?
        let notesField: TickTickNotesField
    }

    let listID: String
    let listName: String
    let savedAt: Date
    let tasks: [Task]

    init(listID: String, listName: String, savedAt: Date, rows: [TickTickRow]) {
        self.listID = listID
        self.listName = listName
        self.savedAt = savedAt
        tasks = rows.map {
            Task(
                id: $0.item.id, projectID: $0.projectID, title: $0.item.title,
                dueDate: $0.item.dueDate, notes: $0.item.notes, notesField: $0.notesField
            )
        }
    }

    var rows: [TickTickRow] {
        tasks.map {
            TickTickRow(
                item: NookTodoItem(
                    id: $0.id, title: $0.title, dueDate: $0.dueDate, isCompleted: false,
                    listName: listName, notes: $0.notes
                ),
                projectID: $0.projectID,
                notesField: $0.notesField
            )
        }
    }
}

/// File-backed store under `Application Support/OpenIsland/Todo/`. An actor,
/// which keeps the disk work off the main thread and serialized.
actor TickTickTodoCache {
    static let fileName = "ticktick-tasks.json"

    private let directory: URL?

    /// Pass a directory in tests. The default is the app's own folder.
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("OpenIsland", isDirectory: true)
            .appendingPathComponent("Todo", isDirectory: true)
    }

    private var fileURL: URL? { directory?.appendingPathComponent(Self.fileName) }

    /// Nil when nothing was cached yet. A corrupt file also reads as nil and
    /// is replaced by the next successful refresh.
    func load() -> TickTickTodoSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(TickTickTodoSnapshot.self, from: data)
    }

    func save(_ snapshot: TickTickTodoSnapshot) throws {
        guard let directory, let fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
