import SwiftUI

/// The keys the tour window answers, one for each of its buttons.
enum OnboardingKey: CaseIterable, Sendable {
    /// Escape: Skip.
    case escape
    /// Return: Next, or Finish on the last page.
    case returnKey
    case leftArrow
    case rightArrow

    var shortcut: KeyboardShortcut {
        switch self {
        case .escape: .cancelAction
        case .returnKey: .defaultAction
        case .leftArrow: KeyboardShortcut(.leftArrow, modifiers: [])
        case .rightArrow: KeyboardShortcut(.rightArrow, modifiers: [])
        }
    }
}

/// When the tour window takes a key. The design kit's loupe answers Escape
/// (it cancels the pick) and the arrows and Return itself, and the same key
/// must never also skip or turn the tour. The window takes none while the
/// loupe is up, nor for `settle` after it goes away, which covers a key whose
/// answer to the loupe came a moment before the loupe was gone. A pure rule,
/// which keeps it testable without a window.
enum OnboardingKeyRule {
    /// How long the window keeps taking no key after the loupe is gone.
    static let settle: Duration = .milliseconds(500)

    static func takesKeys(isSampling: Bool, isSettling: Bool) -> Bool {
        !isSampling && !isSettling
    }

    /// The shortcut a button gets for a key: its own, or none while the
    /// window takes no key. A button with no shortcut still answers a click.
    static func shortcut(for key: OnboardingKey, takesKeys: Bool) -> KeyboardShortcut? {
        takesKeys ? key.shortcut : nil
    }
}
