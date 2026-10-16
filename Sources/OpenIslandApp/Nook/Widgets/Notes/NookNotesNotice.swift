import Foundation

/// What the notes widget has to say when something goes wrong (D70). A notice
/// has two texts: a few words for the closed island (`textKey`, about 18
/// characters fit in the wing) and the whole sentence for the place the user
/// can read while the island is open (`problemKey`), which is the editor's
/// header and the card.
enum NookNotesNotice: Equatable, Sendable {
    /// A note could not be written.
    case notSaved
    /// A note could not be written to the folder, which is the likely cause.
    case notSavedInFolder(String)
    /// A note could not be deleted.
    case notDeleted
    /// The old Quick Notes file could not be moved in.
    case notImported
    /// Notes that could not be saved before the app quit were put back.
    case restored
    /// The file was changed by another program while the note was open, and
    /// the text went to a copy with this file name.
    case savedAsCopy(String)
    /// A note's file cannot be read, so it cannot be opened. Holds its name.
    case noteUnreadable(String)
    /// A note's file is in iCloud and not on this Mac yet (N17). Holds its name.
    case noteDownloading(String)
    /// The folder cannot be read, which is not the same as it holding no
    /// notes. Holds its name.
    case cantReadFolder(String)
    /// The folder was there before and is not now. Holds its name.
    case folderGone(String)
    /// macOS has not let Hangover control Notes.
    case appleNotesOff(keptIn: Place)
    /// Notes refused for another reason.
    case appleNotesFailed(keptIn: Place)
    /// Hangover's list of Apple notes could not be read. The old file was
    /// set aside under this name and a new list was started.
    case appleNotesListSetAside(String)
    /// The same, and the old file could not be set aside: nothing is saved.
    case appleNotesListUnreadable

    /// Where the note is, when Apple Notes did not take it.
    enum Place: Equatable, Sendable {
        case folder
        case hangover
    }

    /// A button a notice offers.
    enum Action: Hashable, CaseIterable, Sendable {
        case chooseFolder
        case createFolder
        /// System Settings, Privacy and Security, Automation: where macOS
        /// lets Hangover control Notes.
        case openAutomationSettings

        var titleKey: String {
            switch self {
            case .chooseFolder: "nook.notes.action.chooseFolder"
            case .createFolder: "nook.notes.action.createFolder"
            case .openAutomationSettings: "nook.notes.action.openAutomation"
            }
        }
    }

    // MARK: Words

    /// A few words, for the closed island.
    var textKey: String {
        switch self {
        case .notSaved, .notSavedInFolder: "nook.notes.notice.notSaved"
        case .notDeleted: "nook.notes.notice.notDeleted"
        case .notImported: "nook.notes.notice.notImported"
        case .restored: "nook.notes.notice.restored"
        case .savedAsCopy: "nook.notes.notice.savedCopy"
        case .noteUnreadable: "nook.notes.notice.noteUnreadable"
        case .noteDownloading: "nook.notes.notice.noteDownloading"
        case .cantReadFolder: "nook.notes.notice.cantReadFolder"
        case .folderGone: "nook.notes.notice.folderGone"
        case .appleNotesOff(.folder): "nook.notes.notice.appleOff.folder"
        case .appleNotesOff(.hangover): "nook.notes.notice.appleOff.hangover"
        case .appleNotesFailed(.folder): "nook.notes.notice.appleFailed.folder"
        case .appleNotesFailed(.hangover): "nook.notes.notice.appleFailed.hangover"
        case .appleNotesListSetAside, .appleNotesListUnreadable: "nook.notes.notice.listUnreadable"
        }
    }

    /// The whole sentence, for the editor's header and the card.
    var problemKey: String {
        switch self {
        case .notSaved: "nook.notes.problem.notSaved"
        case .notSavedInFolder: "nook.notes.problem.notSavedInFolder"
        case .notDeleted: "nook.notes.problem.notDeleted"
        case .notImported: "nook.notes.problem.notImported"
        case .restored: "nook.notes.problem.restored"
        case .savedAsCopy: "nook.notes.problem.savedCopy"
        case .noteUnreadable: "nook.notes.problem.noteUnreadable"
        case .noteDownloading: "nook.notes.problem.noteDownloading"
        case .cantReadFolder: "nook.notes.problem.cantReadFolder"
        case .folderGone: "nook.notes.problem.folderGone"
        case .appleNotesOff(.folder): "nook.notes.problem.appleOff.folder"
        case .appleNotesOff(.hangover): "nook.notes.problem.appleOff.hangover"
        case .appleNotesFailed(.folder): "nook.notes.problem.appleFailed.folder"
        case .appleNotesFailed(.hangover): "nook.notes.problem.appleFailed.hangover"
        case .appleNotesListSetAside: "nook.notes.problem.listSetAside"
        case .appleNotesListUnreadable: "nook.notes.problem.listUnreadable"
        }
    }

    /// What the sentence is about, for the `%@` in it.
    var subject: String? {
        switch self {
        case let .notSavedInFolder(name), let .savedAsCopy(name), let .noteUnreadable(name),
             let .noteDownloading(name),
             let .cantReadFolder(name), let .folderGone(name), let .appleNotesListSetAside(name):
            name
        default:
            nil
        }
    }

    /// The buttons the sentence comes with.
    var actions: [Action] {
        switch self {
        case .notSavedInFolder, .cantReadFolder: [.chooseFolder]
        case .folderGone: [.chooseFolder, .createFolder]
        case .appleNotesOff: [.openAutomationSettings]
        default: []
        }
    }

    /// True when a note could not be written, which an emptied note ends.
    var isAboutSaving: Bool {
        switch self {
        case .notSaved, .notSavedInFolder: true
        default: false
        }
    }

    /// True when the folder could not be listed, which the next list that
    /// works ends. The card says so in place of "No notes yet".
    var isAboutFolder: Bool {
        switch self {
        case .cantReadFolder, .folderGone: true
        default: false
        }
    }

    /// True for a notice about something that happened and was dealt with,
    /// which a later save does not take away. It goes when the next note is
    /// opened.
    var isInformation: Bool {
        switch self {
        case .restored, .savedAsCopy, .appleNotesListSetAside: true
        default: false
        }
    }

    var symbol: String { "exclamationmark.triangle" }
}
