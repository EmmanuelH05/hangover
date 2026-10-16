import Foundation

/// The sample notes (D51, D70). The notes widget reads Markdown files; the
/// sample is a folder of them in the demo's own temporary folder, written in
/// the format the widget writes. Saving a note writes a file there and
/// nothing else: the Notes app is not reached.
@MainActor
enum DemoNotes {
    /// Plain notes of an ordinary day, oldest first, with how many minutes
    /// before the launch each was last edited.
    static let samples: [(minutesAgo: Int, text: String)] = [
        (300, "Try the new cache key\nCheck the hit rate after the deploy."),
        (230, "Ask about the midterm room\nEmail the TA before Friday."),
        (150, "Idea: widget presets\nOne for studying, one for coding."),
        (70, "Send the slides tonight"),
        (25, "Read chapter 6"),
    ]

    /// Writes the sample notes as files in `folder`.
    static func write(in folder: URL, now: Date, calendar: Calendar = .current) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var taken: Set<String> = []
        for sample in samples {
            let edited = now.addingTimeInterval(-TimeInterval(sample.minutesAgo) * 60)
            let name = NookNoteFiles.fileName(forTitle: NookNoteFiles.title(from: sample.text), taken: taken)
            taken.insert(name)
            let content = NookNoteFiles.render(body: sample.text, created: edited, updated: edited, calendar: calendar)
            let url = folder.appendingPathComponent(name)
            try content.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: edited], ofItemAtPath: url.path)
        }
    }

    /// The store the demo's Nook uses: notes in the demo's own folder, a
    /// Notes app that is not there, and no watching. Its clock starts at the
    /// launch time the samples are dated from, so a note saved in a recording
    /// is the newest.
    static func makeStore(defaults: UserDefaults, root: URL, notesFolder: URL, now launch: Date) -> NookNotesStore {
        defaults.set(notesFolder.path, forKey: NookNotesStore.folderKey)
        defaults.set(NookNotesSaveTo.folder.rawValue, forKey: NookNotesStore.saveToKey)
        // No old Quick Notes file is moved in during a recording.
        defaults.set(true, forKey: NookNotesStore.importedKey)
        return NookNotesStore(
            defaults: defaults,
            home: root,
            appleNotes: NookInertAppleNotesBridge(),
            watcher: NookInertFolderWatcher(),
            now: { [started = Date()] in launch.addingTimeInterval(Date().timeIntervalSince(started)) },
            trash: { try FileManager.default.removeItem(at: $0) }
        )
    }
}
