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

    /// True for text with something in it besides blanks.
    static func isUnsaved(_ text: String?) -> Bool {
        guard let text else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
