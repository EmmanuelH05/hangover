import Foundation

/// Whether a person could see a notice put on the closed notch right now.
/// The due-day reminder records a notice as shown only once this held for
/// its whole time on screen. A notice that nobody saw is said again.
///
/// Four things hide a closed-notch notice:
/// - the screen is off, locked, asleep or another user's session is in front
/// - the island is open, which draws the open island and not the notice
/// - the display has notices turned off
/// - a recording is running, whose timer takes the closed notch over
struct NookTodoDueSight: Equatable, Sendable {
    /// `IslandScreenPresence.isOn`: awake, screens on, unlocked, this session in front.
    var isScreenOn: Bool
    var isIslandOpen: Bool
    /// The "notices on the closed island" setting of the display in use.
    var showsNotices: Bool
    var isRecording: Bool

    var canSee: Bool {
        isScreenOn && !isIslandOpen && showsNotices && !isRecording
    }

    /// Why a notice would not be seen, for the log. Nil while it would be.
    var reasonHidden: String? {
        if !isScreenOn { return "the screen is off or locked" }
        if isIslandOpen { return "the island is open" }
        if !showsNotices { return "notices are off on this display" }
        if isRecording { return "a recording is running" }
        return nil
    }
}
