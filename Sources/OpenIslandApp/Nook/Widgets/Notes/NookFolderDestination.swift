import Foundation

/// Notes as Markdown files in one folder (D70): each note is a `.md` file
/// with `created:` and `updated:` in its front matter. Only the folder's own
/// files count, not those in folders inside it.
@MainActor
final class NookFolderDestination: NookNoteDestination {
    let saveTo: NookNotesSaveTo = .folder
    let folder: URL

    private let calendar: Calendar
    private let fileManager: FileManager
    private let trash: (URL) throws -> Void
    private let isFolderExpected: () -> Bool
    private let iCloud: NookNoteICloud
    /// The files iCloud was asked for and has not brought yet, so a list read
    /// again and again asks once (N17).
    private var askedForDownload: Set<String> = []

    /// `trash` moves a file to the Trash. Tests pass one that moves it to a
    /// folder of their own, which keeps them out of the real Trash.
    /// `isFolderExpected` says whether the folder was there before. One that
    /// was and is not now is gone, and is not made again without the user
    /// knowing: the notes in it may be in the Trash, or the folder on a disk
    /// that is not connected. A folder never seen is made at the first save.
    init(
        folder: URL,
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
        isFolderExpected: @escaping () -> Bool = { false },
        iCloud: NookNoteICloud = .live,
        trash: @escaping (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }
    ) {
        self.iCloud = iCloud
        self.folder = folder
        self.calendar = calendar
        self.fileManager = fileManager
        self.isFolderExpected = isFolderExpected
        self.trash = trash
    }

    // MARK: Reading

    /// Every note in the folder. A file that cannot be read is a row marked
    /// so, not a file that is not there. A folder that cannot be listed is
    /// an error, never an empty list.
    func load() throws -> [NookNote] {
        guard fileManager.fileExists(atPath: folder.path) else {
            if isFolderExpected() { throw NookNoteStorageError.folderGone }
            return []
        }
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .creationDateKey],
                // Hidden files include the stand-ins iCloud leaves for notes it
                // has not downloaded yet.
                options: [.skipsHiddenFiles]
            )
        } catch {
            NookNotesLog.failure("list the notes folder", path: folder.path, error: error)
            throw NookNoteStorageError.cannotRead
        }
        let notes = urls.compactMap(note(at:))
        // A file that is gone leaves the cache.
        let names = Set(notes.map(\.id))
        readCache = readCache.filter { names.contains($0.key) }
        return notes
    }

    /// A file as it was read: the next read of the same file, with the same
    /// date and size, takes the note from here and not from the disk. A
    /// folder with a whole vault in it is not read again at every change.
    private struct Read {
        let modified: Date?
        let size: Int?
        let note: NookNote
    }

    private var readCache: [String: Read] = [:]

    private func note(at url: URL) -> NookNote? {
        guard url.pathExtension.lowercased() == NookNoteFiles.fileExtension else { return nil }
        let values = fileValues(of: url, [
            .isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey,
        ])
        guard values?.isRegularFile == true else { return nil }
        let modified = values?.contentModificationDate
        let size = values?.fileSize
        let name = url.lastPathComponent
        if let cached = readCache[name], cached.modified == modified, cached.size == size, modified != nil {
            return cached.note
        }
        // A file iCloud keeps and has not brought here is not read: reading
        // waits for the download, and this runs on the main actor (N17).
        if iCloud.isNotDownloaded(url) {
            requestDownload(of: url)
            let when = modified ?? values?.creationDate ?? .distantPast
            return NookNote(
                id: name, text: "", created: values?.creationDate ?? when, updated: when, state: .downloading
            )
        }
        askedForDownload.remove(name)
        let raw: String
        do {
            raw = try String(contentsOf: url, encoding: .utf8)
        } catch {
            NookNotesLog.failure("read a note", path: url.path, error: error)
            // Not cached: it is read again at the next look.
            let when = modified ?? values?.creationDate ?? .distantPast
            return NookNote(
                id: name, text: "", created: values?.creationDate ?? when, updated: when, state: .unreadable
            )
        }
        let note = makeNote(named: name, raw: raw, modified: modified, birth: values?.creationDate)
        readCache[name] = Read(modified: modified, size: size, note: note)
        return note
    }

    /// A file's dates and size. A file whose values cannot be read is read as
    /// one with none, and the failure is logged.
    private func fileValues(of url: URL, _ keys: Set<URLResourceKey>) -> URLResourceValues? {
        do {
            return try url.resourceValues(forKeys: keys)
        } catch {
            NookNotesLog.failure("read the dates of a note", path: url.path, error: error)
            return nil
        }
    }

    /// A file's text as a note.
    private func makeNote(named name: String, raw: String, modified: Date?, birth: Date?) -> NookNote {
        let parsed = NookNoteFiles.parse(raw, calendar: calendar)
        let created = parsed.created ?? birth ?? modified ?? .distantPast
        let updated = NookNoteFiles.lastEdit(frontMatterUpdated: parsed.updated, fileModified: modified, created: created)
        return NookNote(id: name, text: parsed.body, created: created, updated: updated, createdText: parsed.createdText)
    }

    // MARK: Writing

    /// One note read again from its file, not from what was read before.
    func read(id: String) throws -> NookNote? {
        let url = folder.appendingPathComponent(id)
        guard let raw = try readFile(at: url) else { return nil }
        let values = fileValues(of: url, [.contentModificationDateKey, .creationDateKey])
        return makeNote(named: id, raw: raw, modified: values?.contentModificationDate, birth: values?.creationDate)
    }

    func save(text: String, id: String?, base: String?, created: Date, now: Date, renaming: Bool) throws -> NookNoteWrite {
        // A folder that was there and is gone is not made again silently.
        if !fileManager.fileExists(atPath: folder.path), isFolderExpected() {
            throw NookNoteStorageError.folderGone
        }
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            NookNotesLog.failure("make the notes folder", path: folder.path, error: error)
            throw NookNoteStorageError.cannotWrite
        }
        let stamp = NookNoteFiles.wholeSeconds(now)
        var fileCreated = NookNoteFiles.wholeSeconds(created)
        var keptFrontMatter: [String] = []

        // The names in the folder. A folder that cannot be listed is an
        // error: with no names to check against, a new "Plan" would be
        // written over the "Plan.md" that is there.
        let names = try fileNames()
        let current = id.flatMap { names.contains($0) ? $0 : nil }

        // What another program put in the file stays: the front matter it
        // has, line for line, with its tags and its own creation date. And
        // if it changed the text since Hangover read it, Hangover does not
        // write over that.
        if let current, let raw = try readFile(at: folder.appendingPathComponent(current)) {
            let parsed = NookNoteFiles.parse(raw, calendar: calendar)
            if let base, parsed.body != base {
                return try saveCopy(text: text, created: fileCreated, stamp: stamp, names: names, changed: current)
            }
            keptFrontMatter = parsed.frontMatter
            fileCreated = parsed.created ?? fileCreated
        }

        // A file keeps its name while the user is still typing: the name is
        // chosen when the note is first made, and again when `renaming`.
        let name: String
        if let current, !renaming {
            name = current
        } else {
            name = targetName(for: text, current: current, names: names)
        }
        let createdText = try writeFile(
            at: folder.appendingPathComponent(name), body: text, created: fileCreated, stamp: stamp, keeping: keptFrontMatter
        )
        // A new title is a new file. The old one goes to the Trash only
        // after the new one is written: a rename that failed half way would
        // otherwise leave a note with no file, or a file with another
        // note's name.
        if let current, name != current { trashRenamed(current) }
        let isRenamePending = !NookNoteFiles.fileName(name, stillFits: NookNoteFiles.title(from: text))
        return NookNoteWrite(
            note: NookNote(id: name, text: text, created: fileCreated, updated: stamp, createdText: createdText),
            isRenamePending: isRenamePending
        )
    }

    /// The text goes to a file of its own, "Title (Hangover).md", and the
    /// file another program changed is left as that program wrote it.
    private func saveCopy(
        text: String, created: Date, stamp: Date, names: [String], changed id: String
    ) throws -> NookNoteWrite {
        let title = NookNoteFiles.title(from: text)
        let name = NookNoteFiles.fileName(forTitle: NookNoteFiles.copyTitle(for: title), taken: Set(names))
        NookNotesLog.warning("A note was changed by another program while it was open, so it was saved as a copy", path: folder.appendingPathComponent(id).path)
        let createdText = try writeFile(at: folder.appendingPathComponent(name), body: text, created: created, stamp: stamp, keeping: [])
        return NookNoteWrite(
            note: NookNote(id: name, text: text, created: created, updated: stamp, createdText: createdText), isCopy: true
        )
    }

    /// Writes the file and answers the `created:` text it now has (N14), which is the kept
    /// line as it was, or the one written when there was none.
    private func writeFile(
        at url: URL, body: String, created: Date, stamp: Date, keeping frontMatter: [String]
    ) throws -> String? {
        let content = NookNoteFiles.render(
            body: body, created: created, updated: stamp, keeping: frontMatter, calendar: calendar
        )
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NookNotesLog.failure("write a note", path: url.path, error: error)
            throw NookNoteStorageError.cannotWrite
        }
        // The file's own date is the one the list orders by when a program
        // other than Hangover edits the note, so Hangover's edit carries the
        // same time as the front matter.
        do {
            try fileManager.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)
        } catch {
            NookNotesLog.failure("set the date of a note", path: url.path, error: error)
        }
        return NookNoteFiles.parse(content, calendar: calendar).createdText
    }

    /// A file's text. Nil when there is no such file. A file that is there
    /// and cannot be read is an error, so it is not written over blind.
    private func readFile(at url: URL) throws -> String? {
        if iCloud.isNotDownloaded(url) {
            requestDownload(of: url)
            throw NookNoteStorageError.notDownloaded
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            NookNotesLog.failure("read a note", path: url.path, error: error)
            throw NookNoteStorageError.cannotRead
        }
    }

    /// Asks iCloud to bring a file here, once until it has.
    private func requestDownload(of url: URL) {
        guard askedForDownload.insert(url.lastPathComponent).inserted else { return }
        do {
            try iCloud.startDownload(url)
        } catch {
            NookNotesLog.failure("ask iCloud for a note", path: url.path, error: error)
        }
    }

    private func fileNames() throws -> [String] {
        do {
            return try fileManager.contentsOfDirectory(atPath: folder.path)
        } catch {
            NookNotesLog.failure("list the notes folder", path: folder.path, error: error)
            throw NookNoteStorageError.cannotRead
        }
    }

    /// The file a note is written to. A note keeps its file's name unless
    /// its title changed; a new name is found among the names in the folder,
    /// so it is never one that is taken.
    private func targetName(for text: String, current: String?, names: [String]) -> String {
        let title = NookNoteFiles.title(from: text)
        if let current, NookNoteFiles.fileName(current, stillFits: title) { return current }
        return NookNoteFiles.fileName(forTitle: title, taken: Set(names.filter { $0 != current }))
    }

    /// The file a note had before its title changed goes to the Trash. If
    /// it cannot, it stays as an older version, which loses nothing.
    private func trashRenamed(_ name: String) {
        let url = folder.appendingPathComponent(name)
        do {
            try trash(url)
        } catch {
            NookNotesLog.failure("trash the file a note was renamed from", path: url.path, error: error)
        }
    }

    // MARK: Removing

    func erase(id: String) throws -> NookNoteErasure {
        let url = folder.appendingPathComponent(id)
        guard fileManager.fileExists(atPath: url.path) else { return NookNoteErasure(noteID: id) }
        do {
            try trash(url)
        } catch {
            throw NookNoteStorageError.cannotRemove
        }
        return NookNoteErasure(noteID: id)
    }
}
