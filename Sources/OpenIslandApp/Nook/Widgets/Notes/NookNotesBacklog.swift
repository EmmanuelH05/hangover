import Foundation

/// The sends to Apple Notes that failed (N4), kept between launches. A send
/// that Notes refused or did not answer used to be dropped: the note stayed
/// as Hangover had it and Apple Notes never heard of the edit. These are
/// tried again at the next launch and after the next send that works.
///
/// An entry is the scope (the folder, or Hangover's own record), as the
/// Apple note mapping keeps them, and the note's id.
struct NookNotesBacklog {
    static let notesKey = "nook.notes.appleNeedsSync"
    static let erasuresKey = "nook.notes.appleNeedsErase"

    let defaults: UserDefaults

    // MARK: Notes to send

    func noteIDs(scope: String) -> [String] {
        strings(Self.notesKey).compactMap { entry -> String? in
            let parts = entry.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == scope else { return nil }
            return String(parts[1])
        }
    }

    func add(noteID: String, scope: String) {
        let entry = "\(scope)\n\(noteID)"
        var all = strings(Self.notesKey)
        guard !all.contains(entry) else { return }
        all.append(entry)
        defaults.set(all, forKey: Self.notesKey)
    }

    func remove(noteID: String, scope: String) {
        let entry = "\(scope)\n\(noteID)"
        let all = strings(Self.notesKey)
        guard all.contains(entry) else { return }
        defaults.set(all.filter { $0 != entry }, forKey: Self.notesKey)
    }

    /// The note was renamed: what waited under the old name waits under the new.
    func move(noteID: String, to newID: String, scope: String) {
        guard noteIDs(scope: scope).contains(noteID) else { return }
        remove(noteID: noteID, scope: scope)
        add(noteID: newID, scope: scope)
    }

    // MARK: Notes to delete

    /// An entry is the scope, the note's id and the seconds it was created
    /// at, and after them, from the day the text was kept (N14), the text of
    /// its `created:` line. An entry without the text is read as it always was.
    func erasures(scope: String) -> [NookNoteErasure] {
        strings(Self.erasuresKey).compactMap { entry -> NookNoteErasure? in
            let parts = entry.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false)
            guard (3...4).contains(parts.count), parts[0] == scope else { return nil }
            let created = Int(parts[2]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            return NookNoteErasure(
                noteID: String(parts[1]), created: created, createdText: parts.count == 4 ? String(parts[3]) : nil
            )
        }
    }

    func add(_ erasure: NookNoteErasure, scope: String) {
        let entry = Self.entry(erasure, scope: scope)
        var all = strings(Self.erasuresKey)
        guard !all.contains(entry) else { return }
        all.append(entry)
        defaults.set(all, forKey: Self.erasuresKey)
    }

    func remove(_ erasure: NookNoteErasure, scope: String) {
        let entry = Self.entry(erasure, scope: scope)
        let all = strings(Self.erasuresKey)
        guard all.contains(entry) else { return }
        defaults.set(all.filter { $0 != entry }, forKey: Self.erasuresKey)
    }

    // MARK: Parts

    private static func entry(_ erasure: NookNoteErasure, scope: String) -> String {
        let created = erasure.created.map { String(NookNoteFiles.seconds($0)) } ?? ""
        let entry = "\(scope)\n\(erasure.noteID)\n\(created)"
        return erasure.createdText.map { "\(entry)\n\($0)" } ?? entry
    }

    private func strings(_ key: String) -> [String] {
        defaults.stringArray(forKey: key) ?? []
    }
}
