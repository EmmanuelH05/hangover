import AppKit
import Foundation

/// The demo mode (D51): sample content and a timed script, for a screen
/// recording of the app. Only the environment turns it on. Nothing in
/// Settings and no string a user can see mentions it, and with the variable
/// absent no code in this folder runs.
@MainActor
enum DemoMode {
    /// `OPEN_ISLAND_DEMO=1` switches the mode on.
    nonisolated static let switchKey = "OPEN_ISLAND_DEMO"
    /// An absolute path to the picture the backdrop shows.
    nonisolated static let backdropKey = "OPEN_ISLAND_DEMO_BACKDROP"
    /// The name of the script to run after launch.
    nonisolated static let scriptKey = "OPEN_ISLAND_DEMO_SCRIPT"

    /// True once a demo model was built. Windows read it to raise their
    /// level. It is set in one place, `DemoLaunch`, and nowhere else.
    private(set) static var isActive = false

    static func activate() {
        isActive = true
    }

    nonisolated static func isRequested(environment: [String: String]) -> Bool {
        environment[switchKey] == "1"
    }

    /// The level the tour, Settings and the ring light take in the demo
    /// mode: one step above the island and the backdrop under it. Any other
    /// time the level they asked for.
    static func raised(_ level: NSWindow.Level) -> NSWindow.Level {
        DemoWindowLevels.level(forWindowAt: level, isDemo: isActive)
    }

    /// Whether the tour should count Hangover as the active app. In the demo
    /// mode it always does: nobody is at the Mac to bring the app forward, and
    /// a tour that thinks it lost focus lets go of the island.
    static func countsAsActive(_ appIsActive: Bool) -> Bool {
        DemoPresence.appIsActive(real: appIsActive, isDemo: isActive)
    }
}

/// Whether the app counts as active, as a plain value.
enum DemoPresence {
    static func appIsActive(real: Bool, isDemo: Bool) -> Bool {
        isDemo || real
    }
}

/// The window levels of the demo mode, as plain values.
enum DemoWindowLevels {
    /// The island's panel, and the backdrop beside it.
    static let island = NSWindow.Level.statusBar
    /// The tour, Settings and the ring light.
    static let raised = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

    static func level(forWindowAt base: NSWindow.Level, isDemo: Bool) -> NSWindow.Level {
        isDemo ? raised : base
    }
}
