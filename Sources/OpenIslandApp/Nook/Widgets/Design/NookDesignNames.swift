import Foundation

/// How the kit keeps a name that someone typed. One rule for every kind of
/// name, with the length each kind allows: palettes and colors 60,
/// pictures and links 80.
enum NookDesignNames {
    /// Whether a name field holds a name that is not kept: one with
    /// something in it that differs from the saved name once cleaned. A
    /// field that starts with the saved name, or holds only blanks, holds
    /// nothing, which is the rule every widget's draft follows (D20).
    static func isUnsaved(_ typed: String, saved: String, limit: Int) -> Bool {
        NookDraft.isUnsaved(typed) && clean(typed, limit: limit) != saved
    }

    /// A name on one line (a line break of any kind, a CRLF included, is
    /// one space), cut to `limit` characters, and trimmed after the cut.
    /// Trimming only before it would leave a space at the end when the cut
    /// falls inside a run of spaces.
    static func clean(_ name: String, limit: Int) -> String {
        let oneLine = name.components(separatedBy: .newlines).filter { !$0.isEmpty }.joined(separator: " ")
        return String(oneLine.trimmingCharacters(in: .whitespaces).prefix(limit))
            .trimmingCharacters(in: .whitespaces)
    }
}
