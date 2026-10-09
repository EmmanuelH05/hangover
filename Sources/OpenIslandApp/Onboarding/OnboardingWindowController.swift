import AppKit
import SwiftUI

/// Owns the welcome tour's window: an ordinary centered window, not the
/// island. One tour is up at a time. Closing the window by its red button
/// skips the tour, the same as the Skip button.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var tour: OnboardingTour?

    var isShowing: Bool { window?.isVisible == true }

    /// Brings the tour up. While one is already on screen it is kept, turned
    /// to `page` and brought forward, and `makeTour` is not called.
    ///
    /// `makeTour` gets the closure that puts the window away, to call when
    /// its tour ends.
    func show(
        startingAt page: OnboardingPage,
        title: String,
        lang: LanguageManager,
        makeTour: (_ close: @escaping @MainActor () -> Void) -> OnboardingTour
    ) {
        if let window, let tour, window.isVisible {
            if page != .welcome { tour.go(to: page) }
            bringForward(window)
            return
        }

        let tour = makeTour { [weak self] in self?.close() }
        let window = makeWindow(title: title)
        window.contentView = NSHostingView(rootView: OnboardingView(tour: tour, lang: lang))
        window.center()
        self.tour = tour
        self.window = window
        bringForward(window)
    }

    /// Puts the window away. Safe to call when none is up.
    func close() {
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
        endingTour?.skip()
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
        return window
    }

    private func bringForward(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
