import Foundation

/// The last task list that loaded, kept on disk for offline starts.
struct NotionTodoSnapshot: Codable, Equatable, Sendable {
    struct Task: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let dueDate: Date?
        /// Absent in files written before notes existed.
        var notes: String? = nil
    }

    let dataSourceID: String
    let databaseTitle: String
    let savedAt: Date
    let tasks: [Task]

    init(dataSourceID: String, databaseTitle: String, savedAt: Date, items: [NookTodoItem]) {
        self.dataSourceID = dataSourceID
        self.databaseTitle = databaseTitle
        self.savedAt = savedAt
        tasks = items.map { Task(id: $0.id, title: $0.title, dueDate: $0.dueDate, notes: $0.notes) }
    }

    var items: [NookTodoItem] {
        tasks.map {
            NookTodoItem(
                id: $0.id, title: $0.title, dueDate: $0.dueDate, isCompleted: false,
                listName: databaseTitle, notes: $0.notes
            )
        }
    }
}

/// File-backed store under `Application Support/OpenIsland/Todo/`. An actor,
/// which keeps the disk work off the main thread and serialized.
actor NotionTodoCache {
    static let fileName = "notion-tasks.json"

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
    func load() -> NotionTodoSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(NotionTodoSnapshot.self, from: data)
    }

    func save(_ snapshot: NotionTodoSnapshot) throws {
        guard let directory, let fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
