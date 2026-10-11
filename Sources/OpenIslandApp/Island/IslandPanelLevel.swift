import AppKit

/// The window level of the island's panel. It sits with the menu bar's
/// status items, above every app window.
///
/// A macOS permission prompt is a window on the modal panel level, which is
/// lower, and it comes up in the middle of the open island's frame. Under
/// the island it can be neither seen nor clicked, and the welcome tour
/// holds the island open. While the app has such a request up, an open
/// island steps below the prompt. A closed island stays where it is: it
/// covers nothing and lets the mouse through.
enum IslandPanelLevel {
    static let standard = NSWindow.Level.statusBar
    /// Above app windows, below a system alert.
    static let underSystemPrompt = NSWindow.Level.floating

    static func level(isOpen: Bool, isSystemPromptUp: Bool) -> NSWindow.Level {
        isOpen && isSystemPromptUp ? underSystemPrompt : standard
    }
}
