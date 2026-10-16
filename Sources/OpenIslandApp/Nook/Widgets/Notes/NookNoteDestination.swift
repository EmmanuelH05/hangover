import Foundation

/// A note that was deleted, for Apple Notes to clear away in its turn. It
/// names the note and not the Apple note: the Apple note may still be on
/// its way to being made, and is looked up when the erasure is its turn.
struct NookNoteErasure: Equatable, Sendable {
    var noteID: String
    /// When the note was created. A mapping stored before the text was kept
    /// is the note's only if it was made for a note created at this time (N14).
    /// Nil when the note's `created:` line could not be read.
    var created: Date?
    /// The note's `created:` text (`NookNote.createdText`). The Apple note
    /// stored under this name is the note's only if it was made for a note
    /// with this text.
    var createdText: String?
}

/// What a save came to (N13).
struct NookNoteWrite: Equatable, Sendable {
    var note: NookNote
    /// True when the file's name no longer fits the note's title, because the
    /// save was asked not to rename it (N16). The store renames it later.
    var isRenamePending = false
    /// True when the file had been changed by another program since Hangover
    /// last read it, and what was typed went to a copy beside it instead.
    /// The other program's version is untouched.
    var isCopy = false
}

/// Where notes are kept (D70). A write has two parts: the one that happens
/// at once (a file, or Hangover's own record) and the one that follows for
/// Apple Notes, which is slow and may be refused. The store runs the first
/// in place and queues the second, one at a time.
@MainActor
protocol NookNoteDestination: AnyObject {
    var saveTo: NookNotesSaveTo { get }

    /// Every note this destination holds, in no particular order.
    func load() throws -> [NookNote]

    /// One note read again from where it is kept, not from what was read
    /// before. Nil when it is not there any more.
    func read(id: String) throws -> NookNote?

    /// Saves a note. `id` is the id it had when it was saved before, nil for
    /// a new note. `base` is the text the note had when it was loaded or
    /// last saved; a file that holds something else by now was changed by
    /// another program, and is not written over. The note comes back with
    /// the id it has now: a title that changed gives a file a new name, but
    /// only when `renaming` is true. An autosave while the user types is not
    /// asked to (N16): a file named "Gro" and then "Groceries" while the first
    /// line was still being typed would be two files, and a link to each.
    func save(text: String, id: String?, base: String?, created: Date, now: Date, renaming: Bool) throws -> NookNoteWrite

    /// Removes a note: a file goes to the Trash.
    func erase(id: String) throws -> NookNoteErasure

    /// Brings the Apple note in line with a note just written. `previousID`
    /// is the id the note had before, when the write changed it. Does
    /// nothing for a destination with no Apple side.
    func sync(_ note: NookNote, replacing previousID: String?) async throws

    /// Deletes the Apple note a deleted note had.
    func sync(_ erasure: NookNoteErasure) async throws

    /// Hangover renamed a note's file. The Apple note follows it at once, and
    /// not when its send comes, so that a note made in between with the old
    /// name is not taken for it (N14).
    func moved(from oldID: String, to newID: String)

    /// Something the destination found wrong with what it keeps, which the
    /// user is told while the island is open. Nil when all is well.
    var standingProblem: NookNotesNotice? { get }
}

extension NookNoteDestination {
    /// A save that renames the file when the title changed.
    func save(text: String, id: String?, base: String?, created: Date, now: Date) throws -> NookNoteWrite {
        try save(text: text, id: id, base: base, created: created, now: now, renaming: true)
    }

    func sync(_ note: NookNote, replacing previousID: String?) async throws {}
    func sync(_ erasure: NookNoteErasure) async throws {}
    var standingProblem: NookNotesNotice? { nil }
    func moved(from oldID: String, to newID: String) {}

    /// A save with nothing to compare the file with.
    func write(text: String, id: String?, created: Date, now: Date) throws -> NookNote {
        try save(text: text, id: id, base: nil, created: created, now: now).note
    }
}

/// Why a note could not be written or removed.
enum NookNoteStorageError: Error, Equatable, Sendable {
    case cannotWrite
    case cannotRemove
    /// The folder, or a file in it that is there, could not be read. A file
    /// is not written over, and a folder is not taken for an empty one.
    case cannotRead
    /// The folder was there before and is not now.
    case folderGone
    /// The record of Apple notes cannot be read, and cannot be set aside.
    case recordUnreadable
    /// The file is in iCloud and not on this Mac yet (N17). It was not read,
    /// because that would hold the app up until the download ends.
    case notDownloaded
}
