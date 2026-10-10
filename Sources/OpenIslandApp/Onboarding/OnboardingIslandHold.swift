import CoreGraphics

/// Whether the tour holds the real island open (D44). A pure function of
/// three facts, which keeps the rule testable without a window.
///
/// The hold is on only while a live page is up, Hangover is the active app
/// and the tour window can be seen. The moment the user clicks another app
/// the hold goes off and an island it opened closes; when Hangover is active
/// again with a live page still up, the hold comes back.
///
/// The signal is app activation, not which window is key. The island's panel
/// is a non-activating panel of this same app (`OverlayPanelController`).
/// A click inside the island leaves Hangover the active app and changes
/// nothing here, even though the panel becomes the key window.
enum OnboardingIslandHold {
    static func holds(isLivePage: Bool, appIsActive: Bool, windowIsVisible: Bool) -> Bool {
        isLivePage && appIsActive && windowIsVisible
    }

    /// The new frame for the tour's window when the island's footprint
    /// changed under a live page, or nil when the window is where it
    /// belongs. A wider look chosen on the opened page can reach under a
    /// docked window; this is what moves it back out of the way.
    static func redock(current: CGRect, isLivePage: Bool, footprint: OnboardingIslandFootprint) -> CGRect? {
        guard isLivePage else { return nil }
        let target = OnboardingWindowFrame.narrow(screen: footprint.screen, island: footprint.island)
        return OnboardingWindowFrame.isSame(target, current) ? nil : target
    }
}

extension OnboardingWindowFrame {
    /// True when two frames differ by less than half a point everywhere.
    static func isSame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }
}
