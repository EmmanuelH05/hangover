import Foundation

/// The launch animation: the island opens for a moment and closes again.
/// These are its rules, kept apart from the timers that run it.
enum IslandBootAnimation {
    /// How long after launch the island opens.
    static let openDelay: TimeInterval = 0.5
    /// How long it stays open.
    static let openDuration: TimeInterval = 1.5

    /// The animation opens a closed island only. An island that a link or
    /// a card already opened is in use, and the animation would take it
    /// over and then close it.
    static func shouldOpen(status: NotchStatus) -> Bool {
        status == .closed
    }

    /// The animation closes only what it opened. Anything that opened or
    /// pinned the island since has changed the reason.
    static func shouldClose(reason: NotchOpenReason?) -> Bool {
        reason == .boot
    }
}
