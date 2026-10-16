import Foundation

/// A Notes app that is not there (D70). It takes every note and makes up an
/// id, and nothing leaves the process. A model on a store of its own (a
/// test, the demo) gets this one, so it can never reach the real Notes app.
struct NookInertAppleNotesBridge: NookAppleNotesBridge {
    func create(bodyHTML: String) async throws -> String { UUID().uuidString }
    func update(id: String, bodyHTML: String) async throws -> Bool { true }
    func delete(id: String) async throws {}
}

/// A watcher that watches nothing.
@MainActor
final class NookInertFolderWatcher: NookNoteFolderWatching {
    func watch(_ folder: URL, onChange: @escaping @MainActor () -> Void) -> Bool { true }
    func stop() {}
}

extension NookNotesStore {
    /// The store the Nook makes for itself. On the app's own settings it
    /// keeps notes where the user chose. On a store of its own, which is a
    /// test or a demo run, it keeps them under a folder of its own that
    /// nothing else reads, with no Notes app and no watching (D53).
    static func make(defaults: UserDefaults) -> NookNotesStore {
        if defaults === UserDefaults.standard { return NookNotesStore(defaults: defaults) }
        return isolated(defaults: defaults)
    }

    /// A store whose folder, record and old file are all under a new
    /// temporary folder.
    static func isolated(defaults: UserDefaults) -> NookNotesStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookNotes-\(UUID().uuidString)", isDirectory: true)
        return NookNotesStore(
            defaults: defaults,
            home: root,
            appleNotes: NookInertAppleNotesBridge(),
            watcher: NookInertFolderWatcher(),
            trash: { try FileManager.default.removeItem(at: $0) }
        )
    }
}
