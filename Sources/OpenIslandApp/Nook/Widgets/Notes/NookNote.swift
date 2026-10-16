import Foundation

/// One note (D70): free text of any length. Its title is its first line.
struct NookNote: Identifiable, Equatable, Sendable {
    /// What the list and the editor know the note by. In a folder it is the
    /// file's name, which changes when the title does. Kept in Hangover's own
    /// record it is a made-up id that never changes.
    let id: String
    var text: String
    var created: Date
    /// The last edit, by Hangover or by another program.
    var updated: Date
    /// Whether the note could be read. A file that cannot be read stays in
    /// the list as a row marked so, with no text, and is never written over.
    var state: State = .readable
    /// What tells this note from an earlier one of the same name when its
    /// Apple note is looked up (N14): the `created:` line as the file has it,
    /// whether or not Hangover can read it as a date, or for a note in
    /// Hangover's own record, its creation moment as text. The text is the
    /// same at every read and in every time zone; the seconds `created` holds
    /// are not, because a line with no zone reads differently once the clock's
    /// zone changes, and a file with no readable line gets its birth date,
    /// which every atomic save moves. Nil when the file has no `created:` line.
    var createdText: String?

    enum State: Equatable, Sendable {
        case readable
        /// The file is there and cannot be read.
        case unreadable
        /// The file is in iCloud and is not on this Mac yet (N17). Reading it
        /// would wait for the download, so it is not read: iCloud is asked
        /// for it, and the row says so until it is here.
        case downloading
    }

    var title: String { NookNoteFiles.title(from: text) }
}

/// Where notes are saved, which Settings and the welcome tour choose between.
enum NookNotesSaveTo: String, CaseIterable, Identifiable, Sendable {
    /// Each note is a Markdown file in a folder, which is usually inside an
    /// Obsidian vault.
    case folder
    /// Each note is a note in a Hangover folder in the Notes app. One way:
    /// Hangover keeps its own record to list them from.
    case appleNotes
    /// The Markdown file is the note, and each save also updates its Apple
    /// note.
    case both

    var id: String { rawValue }

    var usesFolder: Bool { self != .appleNotes }
    var usesAppleNotes: Bool { self != .folder }
}

/// Sizes in the notes widget and its editor. Plain numbers in a plain enum,
/// not statics of a View, which a test off the main actor cannot read.
enum NookNoteSizes {
    /// One row of the list.
    static let rowHeight: CGFloat = 16
    static let rowSpacing: CGFloat = 2
    /// How far a row's highlight reaches past its text.
    static let rowInset: CGFloat = 4
    /// The editor pinned above the grid, when the Notes widget is not on the
    /// page: the same height as the event editor's room, a little shorter.
    static let pinnedEditorHeight: CGFloat = 170
    /// Height the pinned editor adds above the grid: itself and one row gap.
    static var pinnedEditorPageHeight: CGFloat { pinnedEditorHeight + NookWidgetLayout.rowSpacing }
    /// Quiet time after the last key before a note is saved.
    static let saveDelay: Duration = .seconds(1)
    /// How long the first line must stay as it is before the file is renamed
    /// to match it (N16). The editor closing renames at once.
    static let renameDelay: Duration = .seconds(5)
    /// How long a list with a note still downloading from iCloud waits before
    /// it is read again, and how many times it does (N17).
    static let downloadCheckDelay: Duration = .seconds(5)
    static let downloadChecks = 12
}

/// Where an open note is edited (D70). With the Notes widget on the page
/// the editor takes the card's place; with it off the page the editor is
/// pinned above the grid, the way the event editor is, so the shortcut
/// works from anywhere.
enum NookNoteEditorPlacement: Equatable, Sendable {
    case hidden
    case inCard
    case pinned

    static func resolve(isOpen: Bool, notesWidgetOnPage: Bool) -> NookNoteEditorPlacement {
        guard isOpen else { return .hidden }
        return notesWidgetOnPage ? .inCard : .pinned
    }
}

/// Waits `delay`, then runs `action` once, and gives back what cancels the
/// wait (D70). The store's wait before a save.
typealias NookNoteSaveSchedule = @MainActor (_ delay: Duration, _ action: @escaping @MainActor () -> Void) -> (@MainActor () -> Void)
