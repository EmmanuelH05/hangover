import Foundation

/// A line the user has typed in a widget of the open island and not saved.
/// While one is held the island does not close when the pointer leaves it
/// (D20): a half-typed note, to-do or timer length must not vanish. The
/// widget that holds the line reports it; a field that only has the keys,
/// or one that shows saved text, holds nothing.
enum NookDraft: Hashable, Sendable {
    /// The notes card's field.
    case note
    /// The to-do card's "add" field.
    case todo
    /// The timer card's typed length.
    case timerEntry
    /// The design kit's field for a color being typed.
    case designColor
    /// The design kit's field for a picture's name, when it holds a name
    /// the shelf does not have yet.
    case designName
    /// The design kit's Links tab: a link typed in the field and not added.
    case designLink
    /// The design kit's Links tab: a name for a link or a collection that
    /// differs from the saved one and is not kept.
    case designLinkName
    /// The Link to MP3 card's field: a link typed and not yet saved.
    case linkAudio

    /// True for text with something in it besides blanks.
    static func isUnsaved(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
