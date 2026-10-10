import AppKit
import SwiftUI

/// Owns the welcome tour's window. One tour is up at a time. Closing the
/// window by its red button skips the tour, the same as the Skip button.
///
/// On a live page (`OnboardingPage.isLive`) the real island is the preview
/// (D44): the window goes narrow and docks at the left of the screen the
/// island is on, and the tour holds the island open. On the others it is the
/// full window, centered on that screen. Every way the window can go away
/// lets the island go.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var tour: OnboardingTour?
    private var islandFootprint: () -> OnboardingIslandFootprint? = { nil }

    var isShowing: Bool { window?.isVisible == true }

    /// The tour that is up, for the demo script to press its buttons (D51).
    var currentTour: OnboardingTour? { tour }

    private override init() {
        super.init()
        // The hold follows app activation (`OnboardingIslandHold`). A click
        // inside the island does not change it: the island's panel is a
        // non-activating panel of this app.
        let names: [Notification.Name] = [
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification,
            NSApplication.didHideNotification,
            NSApplication.didUnhideNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(
                self, selector: #selector(presenceDidChange), name: name, object: nil
            )
        }
    }

    @objc private func presenceDidChange() {
        refreshPresence()
    }

    /// Reads whether Hangover is active and the window can be seen, and
    /// tells the tour, which holds or lets go of the island.
    private func refreshPresence() {
        guard let window, let tour else { return }
        let isVisible = window.isVisible && !window.isMiniaturized && !NSApp.isHidden
        tour.setPresence(appIsActive: DemoMode.countsAsActive(NSApp.isActive), windowIsVisible: isVisible)
    }

    /// Brings the tour up. While one is already on screen it is kept, turned
    /// to `page` and brought forward, and `makeTour` is not called.
    ///
    /// `makeTour` gets the closure that puts the window away, to call when
    /// its tour ends. `islandFootprint` says where the opened island sits.
    func show(
        startingAt page: OnboardingPage,
        title: String,
        lang: LanguageManager,
        islandFootprint: @escaping () -> OnboardingIslandFootprint?,
        makeTour: (_ close: @escaping @MainActor () -> Void) -> OnboardingTour
    ) {
        if let window, let tour, window.isVisible {
            if page != .welcome { tour.go(to: page) }
            bringForward(window)
            return
        }
        discardStaleWindow()

        self.islandFootprint = islandFootprint
        let tour = makeTour { [weak self] in self?.close() }
        let window = makeWindow(title: title)
        let host = NSHostingView(
            rootView: OnboardingView(
                tour: tour,
                lang: lang,
                onPageChange: { [weak self] in self?.pageDidChange() },
                onFootprintChange: { [weak self] in self?.footprintDidChange() }
            )
        )
        // The window's size is the controller's to set, not the page's.
        host.sizingOptions = []
        window.contentView = host
        self.tour = tour
        self.window = window
        place(window, for: tour.page, animated: false)
        bringForward(window)
        // After activation, which lets the hold see the app as it is.
        refreshPresence()
    }

    /// Puts the window away. Safe to call when none is up.
    func close() {
        tour?.releaseIsland()
        guard let window else { return }
        // The tour has ended by the time this runs, which keeps
        // `windowWillClose` from skipping it a second time.
        self.window = nil
        tour = nil
        window.delegate = nil
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        // The red button. The window is already on its way out: let go of
        // it first, which keeps the tour's end from closing it again.
        let endingTour = tour
        window?.delegate = nil
        window = nil
        tour = nil
        endingTour?.releaseIsland()
        endingTour?.skip()
    }

    /// A window that is not on screen but was never put away. Its tour is
    /// let go before a new one starts. The island cannot stay held.
    private func discardStaleWindow() {
        tour?.releaseIsland()
        window?.delegate = nil
        window?.close()
        window = nil
        tour = nil
    }

    /// The page changed: hold or let go of the island, and move the window.
    private func pageDidChange() {
        guard let window, let tour else { return }
        refreshPresence()
        place(window, for: tour.page, animated: true)
    }

    /// The island's footprint may have changed (a wider look on the opened
    /// page): on a live page, move the window back out from under it.
    private func footprintDidChange() {
        guard let window, let tour, window.isVisible else { return }
        let footprint = islandFootprint() ?? Self.fallbackFootprint()
        guard let footprint,
              let target = OnboardingIslandHold.redock(
                  current: window.frame, isLivePage: tour.page.isLive, footprint: footprint
              )
        else { return }
        window.setFrame(target, display: true, animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    func windowDidMiniaturize(_ notification: Notification) { refreshPresence() }
    func windowDidDeminiaturize(_ notification: Notification) { refreshPresence() }

    // MARK: Placement

    private func place(_ window: NSWindow, for page: OnboardingPage, animated: Bool) {
        guard let target = targetFrame(for: page) else {
            window.center()
            return
        }
        guard !Self.isSameFrame(target, window.frame) else { return }
        let animates = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(target, display: true, animate: animates)
    }

    private func targetFrame(for page: OnboardingPage) -> NSRect? {
        let footprint = islandFootprint() ?? Self.fallbackFootprint()
        guard let footprint else { return nil }
        return OnboardingWindowFrame.frame(
            isLive: page.isLive,
            screen: footprint.screen,
            island: footprint.island
        )
    }

    /// With no answer from the island, the main screen and an island of the
    /// widest look in its middle.
    private static func fallbackFootprint() -> OnboardingIslandFootprint? {
        guard let screen = NSScreen.main?.visibleFrame else { return nil }
        let width = min(screen.width, 760)
        let island = CGRect(x: screen.midX - width / 2, y: screen.maxY - 320, width: width, height: 320)
        return OnboardingIslandFootprint(screen: screen, island: island)
    }

    private static func isSameFrame(_ a: NSRect, _ b: NSRect) -> Bool {
        OnboardingWindowFrame.isSame(a, b)
    }

    private func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: OnboardingStyle.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(OnboardingStyle.ink)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        window.level = DemoMode.raised(window.level)
        return window
    }

    private func bringForward(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
