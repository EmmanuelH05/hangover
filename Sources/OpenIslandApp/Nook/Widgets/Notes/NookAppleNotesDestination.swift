import Foundation

/// Which Apple note belongs to which note (D70). Kept in the app's
/// preferences. A key holds a scope (the folder, or Hangover's own record)
/// and the note's id, so two folders with a note of the same name do not
/// share an Apple note. With each Apple note goes what its note was created
/// as (N14): a file deleted or renamed by another program leaves its
/// mapping behind, and a later note with the same file name is another note.
@MainActor
final class NookAppleNoteIDs {
    static let defaultsKey = "nook.notes.appleNoteIDs"

    private struct Mapping {
        var appleID: String
        /// The note's `created:` text, as the file has it. The same at every
        /// read, in every time zone, and after every save, which seconds are
        /// not. Nil for a mapping stored before the text was kept.
        var createdText: String?
        /// Whole seconds. Kept by a mapping stored before the text was, which
        /// is matched the way it always was and rewritten with the text at
        /// its next push. Nil for a mapping stored without one, which is taken
        /// as it stands.
        var created: Int?

        func belongs(toCreated date: Date?, text: String?) -> Bool {
            if let createdText {
                guard let text else { return true }
                return createdText == text
            }
            guard let created, let date else { return true }
            return created == NookNoteFiles.seconds(date)
        }
    }

    private let defaults: UserDefaults
    let scope: String

    init(defaults: UserDefaults, scope: String) {
        self.defaults = defaults
        self.scope = scope
    }

    /// True when what is stored cannot be read. The Apple notes made so far
    /// cannot be told then, and sending a note on would make a second Apple
    /// note for each one that has one. The stored value is left as it is, and
    /// nothing is written over it.
    var isUnreadable: Bool { stored == nil }

    /// The Apple note of a note created as `createdText`. Nil when there is
    /// none, and nil when the one stored belongs to an earlier note of the
    /// same name. Leave both out to take whatever is stored, which is what a
    /// note with no readable `created:` line does. `created` is read against a
    /// mapping that has no text yet, and only then.
    func appleID(for noteID: String, created: Date? = nil, createdText: String? = nil) -> String? {
        guard let mapping = stored?[key(noteID)], mapping.belongs(toCreated: created, text: createdText) else { return nil }
        return mapping.appleID
    }

    func set(_ appleID: String?, for noteID: String, created: Date? = nil, createdText: String? = nil) {
        guard var next = readableForWriting() else { return }
        next[key(noteID)] = appleID.map { id in
            // The text, or when the note has none, the seconds a mapping always held.
            Mapping(appleID: id, createdText: createdText, created: createdText == nil ? created.map(NookNoteFiles.seconds) : nil)
        }
        save(next)
    }

    /// A mapping stored with seconds is written again with the text, after a
    /// push that found it. Nothing changes for one that has the text already,
    /// and for a note with none to give.
    func rewriteWithText(for noteID: String, createdText: String?) {
        guard let createdText, var next = readableForWriting(),
              var mapping = next[key(noteID)], mapping.createdText == nil else { return }
        mapping.createdText = createdText
        mapping.created = nil
        next[key(noteID)] = mapping
        save(next)
    }

    // MARK: A create that may have landed

    /// Notes made by a create whose answer Hangover may not have heard, with
    /// the title each was made with: scope and note id to title. The retry
    /// looks for a note with that title in Hangover's folder in Notes before
    /// it makes another. Kept through a quit, which can end a create as well.
    static let uncertainKey = "nook.notes.appleCreateUncertain"

    private var uncertain: [String: String] {
        defaults.dictionary(forKey: Self.uncertainKey) as? [String: String] ?? [:]
    }

    /// A create is about to be made, and may land without being heard of.
    func markUncertainCreate(_ noteID: String, title: String) {
        var next = uncertain
        next[key(noteID)] = title
        defaults.set(next, forKey: Self.uncertainKey)
    }

    /// The title the note was made with, when a create of it may have landed.
    func uncertainCreateTitle(for noteID: String) -> String? {
        uncertain[key(noteID)]
    }

    /// The create was answered, refused, or its note was found.
    func clearUncertainCreate(_ noteID: String) {
        var next = uncertain
        guard next.removeValue(forKey: key(noteID)) != nil else { return }
        defaults.set(next, forKey: Self.uncertainKey)
    }

    /// True when this Apple note is the Apple note of a note, in any folder. A
    /// note found by its title is only adopted when it is not.
    func isMapped(_ appleID: String) -> Bool {
        stored?.values.contains { $0.appleID == appleID } ?? true
    }

    /// The Apple note follows its note to a new id.
    func move(from oldID: String, to newID: String) {
        if oldID != newID, let title = uncertainCreateTitle(for: oldID) {
            clearUncertainCreate(oldID)
            markUncertainCreate(newID, title: title)
        }
        guard oldID != newID, var next = readableForWriting(), let mapping = next[key(oldID)] else { return }
        next[key(oldID)] = nil
        next[key(newID)] = mapping
        save(next)
    }

    /// Nil when the stored value cannot be read, which is logged: a write
    /// then would replace it with a list holding one note.
    private func readableForWriting() -> [String: Mapping]? {
        guard let current = stored else {
            NookNotesLog.warning("The list of Apple notes made cannot be read, so it is left as it is")
            return nil
        }
        return current
    }

    /// Nil when something is stored that is not a list of Apple notes made.
    private var stored: [String: Mapping]? {
        guard let object = defaults.object(forKey: Self.defaultsKey) else { return [:] }
        guard let raw = object as? [String: Any] else { return nil }
        var mappings: [String: Mapping] = [:]
        for (key, value) in raw {
            if let appleID = value as? String {
                mappings[key] = Mapping(appleID: appleID)
            } else if let entry = value as? [String: Any], let appleID = entry["apple"] as? String {
                mappings[key] = Mapping(
                    appleID: appleID,
                    createdText: entry["createdText"] as? String,
                    created: (entry["created"] as? NSNumber)?.intValue
                )
            } else {
                return nil
            }
        }
        return mappings
    }

    private func save(_ mappings: [String: Mapping]) {
        defaults.set(mappings.mapValues { mapping -> [String: Any] in
            var entry: [String: Any] = ["apple": mapping.appleID]
            if let createdText = mapping.createdText { entry["createdText"] = createdText }
            if let created = mapping.created { entry["created"] = created }
            return entry
        }, forKey: Self.defaultsKey)
    }

    private func key(_ noteID: String) -> String {
        "\(scope)\n\(noteID)"
    }
}

/// The Apple Notes side of a destination: makes the Apple note on the first
/// save, then updates it. One way: nothing is read back.
@MainActor
final class NookAppleNotesLink {
    private let bridge: any NookAppleNotesBridge
    private let ids: NookAppleNoteIDs

    init(bridge: any NookAppleNotesBridge, ids: NookAppleNoteIDs) {
        self.bridge = bridge
        self.ids = ids
    }

    /// The Apple note follows its note to the file's new name, at once and
    /// not when the send's turn comes: a note made in between with the old
    /// name is another note.
    func moved(from oldID: String, to newID: String) {
        ids.move(from: oldID, to: newID)
    }

    func push(_ note: NookNote, replacing previousID: String?) async throws {
        // Without the list of Apple notes made, a note that has one would get a second.
        guard !ids.isUnreadable else { throw NookAppleNotesError.listUnreadable }
        // Still needed for a rename made before the first send was done.
        if let previousID { ids.move(from: previousID, to: note.id) }
        let html = NookAppleNotesBody.html(from: note.text)
        // The date goes with the text and not without it: a note with no
        // `created:` line has only its file's birth date, which moves with
        // every save: the lookup takes whatever is stored (N14).
        let date = note.createdText == nil ? nil : note.created
        if let appleID = ids.appleID(for: note.id, created: date, createdText: note.createdText),
           try await bridge.update(id: appleID, bodyHTML: html) {
            ids.rewriteWithText(for: note.id, createdText: note.createdText)
            return
        }
        // An earlier create may have landed without a word: its note is this note's.
        if let adopted = try await landedCreate(for: note.id) {
            ids.set(adopted, for: note.id, created: date, createdText: note.createdText)
            ids.clearUncertainCreate(note.id)
            if try await bridge.update(id: adopted, bodyHTML: html) { return }
        }
        // No Apple note yet, the one stored was another note's, or the user
        // deleted it in Notes: make one.
        let made = try await create(note.id, title: NookAppleNotesBody.title(of: note.text), html: html)
        ids.set(made, for: note.id, created: date, createdText: note.createdText)
    }

    /// Makes the Apple note. A create that did not answer in time may have
    /// made it all the same, because the event Hangover sent still lands when
    /// the script is ended, and the quit can end one just as well. It is
    /// marked before it starts and the mark is taken off when an answer
    /// says nothing was made. A refusal does: macOS stopped it before any
    /// event was sent. Any other failure leaves the mark.
    private func create(_ noteID: String, title: String, html: String) async throws -> String {
        ids.markUncertainCreate(noteID, title: title)
        do {
            let made = try await bridge.create(bodyHTML: html)
            ids.clearUncertainCreate(noteID)
            return made
        } catch NookAppleNotesError.notPermitted {
            ids.clearUncertainCreate(noteID)
            throw NookAppleNotesError.notPermitted
        }
    }

    /// The Apple note an earlier create made without being heard of: a note
    /// in Hangover's folder in Notes with the title it was made with, and not
    /// the Apple note of any note. Nil when there was no such create.
    private func landedCreate(for noteID: String) async throws -> String? {
        guard let title = ids.uncertainCreateTitle(for: noteID) else { return nil }
        return try await bridge.find(title: title).first { !ids.isMapped($0) }
    }

    func remove(_ erasure: NookNoteErasure) async throws {
        guard !ids.isUnreadable else { throw NookAppleNotesError.listUnreadable }
        guard let appleID = ids.appleID(for: erasure.noteID, created: erasure.created, createdText: erasure.createdText) else {
            // A create that landed without a word left an Apple note nothing maps to.
            if let landed = try await landedCreate(for: erasure.noteID) {
                try await bridge.delete(id: landed)
            }
            ids.clearUncertainCreate(erasure.noteID)
            return
        }
        try await bridge.delete(id: appleID)
        ids.set(nil, for: erasure.noteID)
    }
}

/// Hangover's own list of the notes it made in Apple Notes (D70). The Notes
/// app has no way to be listened to, and edits made there do not come
/// back, so the list the card shows is this one.
@MainActor
final class NookAppleNotesRecord {
    private struct Entry: Codable {
        let id: String
        var text: String
        var created: Date
        var updated: Date
    }

    /// How the record stands after its file was read.
    enum Standing: Equatable {
        case ready
        /// The file could not be read. It was moved next to where it was,
        /// under this name, and the record started again. Nothing was
        /// written over it.
        case setAside(String)
        /// The file could not be read and could not be moved either. Nothing
        /// is written until it can be, because a write would replace it.
        case blocked
    }

    private let fileURL: URL
    private let now: () -> Date
    private var entries: [Entry] = []
    private(set) var standing: Standing = .ready

    init(fileURL: URL, now: @escaping () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.now = now
        resolve()
    }

    var notes: [NookNote] {
        entries.map {
            NookNote(
                id: $0.id, text: $0.text, created: $0.created, updated: $0.updated,
                createdText: NookNoteFiles.absoluteText($0.created)
            )
        }
    }

    func upsert(_ note: NookNote) throws {
        try resolveIfBlocked()
        let entry = Entry(id: note.id, text: note.text, created: note.created, updated: note.updated)
        var next = entries
        if let index = next.firstIndex(where: { $0.id == note.id }) {
            next[index] = entry
        } else {
            next.append(entry)
        }
        try write(next)
        entries = next
    }

    func remove(id: String) throws {
        try resolveIfBlocked()
        let next = entries.filter { $0.id != id }
        try write(next)
        entries = next
    }

    // MARK: Reading

    /// Reads the file. A file that is not there is an empty record. A file
    /// that is there and cannot be read is moved aside, never written over:
    /// the next save would otherwise leave a file holding that one note and
    /// nothing else.
    private func resolve() {
        do {
            entries = try Self.read(fileURL)
            standing = .ready
        } catch {
            NookNotesLog.failure("read the list of Apple notes", path: fileURL.path, error: error)
            entries = []
            standing = setAside()
        }
    }

    private func resolveIfBlocked() throws {
        guard standing == .blocked else { return }
        resolve()
        if standing == .blocked { throw NookNoteStorageError.recordUnreadable }
    }

    private func setAside() -> Standing {
        let directory = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        let stamp = Self.stamp(now())
        var name = "\(stem).unreadable-\(stamp).json"
        var copy = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "\(stem).unreadable-\(stamp)-\(copy).json"
            copy += 1
        }
        do {
            try FileManager.default.moveItem(at: fileURL, to: directory.appendingPathComponent(name))
            return .setAside(name)
        } catch {
            NookNotesLog.failure("set the unreadable list of Apple notes aside", path: fileURL.path, error: error)
            return .blocked
        }
    }

    private static func read(_ url: URL) throws -> [Entry] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Entry].self, from: data)
    }

    /// 20261015-093000, in UTC, for a file name.
    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    // MARK: Writing

    private func write(_ entries: [Entry]) throws {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NookNotesLog.failure("write the list of Apple notes", path: fileURL.path, error: error)
            throw NookNoteStorageError.cannotWrite
        }
    }
}

/// Notes kept in Hangover's own record and sent to the Notes app (D70).
@MainActor
final class NookAppleNotesDestination: NookNoteDestination {
    let saveTo: NookNotesSaveTo = .appleNotes

    private let record: NookAppleNotesRecord
    private let link: NookAppleNotesLink
    private let makeID: () -> String

    init(record: NookAppleNotesRecord, link: NookAppleNotesLink, makeID: @escaping () -> String = { UUID().uuidString }) {
        self.record = record
        self.link = link
        self.makeID = makeID
    }

    func load() throws -> [NookNote] {
        if record.standing == .blocked { throw NookNoteStorageError.recordUnreadable }
        return record.notes
    }

    var standingProblem: NookNotesNotice? {
        switch record.standing {
        case .ready: nil
        case let .setAside(name): .appleNotesListSetAside(name)
        case .blocked: .appleNotesListUnreadable
        }
    }

    func read(id: String) throws -> NookNote? {
        record.notes.first { $0.id == id }
    }

    /// The record is Hangover's own, so nothing else changes it: `base` is not looked at,
    /// and a note never has a file to rename.
    func save(text: String, id: String?, base: String?, created: Date, now: Date, renaming: Bool) throws -> NookNoteWrite {
        let note = NookNote(
            id: id ?? makeID(), text: text,
            created: NookNoteFiles.wholeSeconds(created), updated: NookNoteFiles.wholeSeconds(now),
            createdText: NookNoteFiles.absoluteText(created)
        )
        try record.upsert(note)
        return NookNoteWrite(note: note)
    }

    func erase(id: String) throws -> NookNoteErasure {
        try record.remove(id: id)
        return NookNoteErasure(noteID: id)
    }

    func sync(_ note: NookNote, replacing previousID: String?) async throws {
        try await link.push(note, replacing: previousID)
    }

    func sync(_ erasure: NookNoteErasure) async throws {
        try await link.remove(erasure)
    }
}

/// Markdown files that are also kept in Apple Notes (D70). The file is the
/// source of truth: the list comes from it, and a save the Notes app
/// refuses is still saved.
@MainActor
final class NookBothDestination: NookNoteDestination {
    let saveTo: NookNotesSaveTo = .both

    private let folder: NookFolderDestination
    private let link: NookAppleNotesLink

    init(folder: NookFolderDestination, link: NookAppleNotesLink) {
        self.folder = folder
        self.link = link
    }

    func load() throws -> [NookNote] {
        try folder.load()
    }

    func read(id: String) throws -> NookNote? {
        try folder.read(id: id)
    }

    func save(text: String, id: String?, base: String?, created: Date, now: Date, renaming: Bool) throws -> NookNoteWrite {
        try folder.save(text: text, id: id, base: base, created: created, now: now, renaming: renaming)
    }

    func moved(from oldID: String, to newID: String) {
        link.moved(from: oldID, to: newID)
    }

    func erase(id: String) throws -> NookNoteErasure {
        try folder.erase(id: id)
    }

    func sync(_ note: NookNote, replacing previousID: String?) async throws {
        try await link.push(note, replacing: previousID)
    }

    func sync(_ erasure: NookNoteErasure) async throws {
        try await link.remove(erasure)
    }
}
