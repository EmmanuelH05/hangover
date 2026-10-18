import AppKit

/// How the tour's window sits among other windows. A pure rule, which a test
/// can check without a window.
///
/// The island's panel joins every Space and shows over a full-screen app
/// (`OverlayPanelController`). A plain window does neither: over a full-screen
/// app it could not be seen, and on a live page that left the island held open
/// beside a tour that had gone. The window follows the user to the active
/// Space and may show over a full-screen app. On a live page it floats, which
/// keeps it beside the island while the island is used; on the other pages it
/// is an ordinary window.
enum OnboardingWindowTraits {
    static let collectionBehavior: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

    static func level(isLivePage: Bool) -> NSWindow.Level {
        isLivePage ? .floating : .normal
    }
}
