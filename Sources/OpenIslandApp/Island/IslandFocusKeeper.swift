import AppKit

/// Remembers which app the user was in, and gives the keyboard back to it.
///
/// A link from Shortcuts or Raycast brings this app to the front to deliver
/// it. For an action that shows nothing ("start a timer") that would leave
/// the keyboard with an app that has no window, and the user's typing would
/// go nowhere until they clicked back into their own app.
@MainActor
final class IslandFocusKeeper {
    /// How long to let the activation that came with the link settle before
    /// handing the keyboard back.
    nonisolated static let settleDelay: TimeInterval = 0.15
    /// An activation older than this was the user's own and not the link's:
    /// they were typing in the island or in Settings.
    nonisolated static let linkActivationWindow: TimeInterval = 2

    private var lastOtherApp: pid_t?
    private var becameActiveAt: Date?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        noteFrontmostApp()
        if NSApp.isActive { becameActiveAt = .distantPast }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.noteFrontmostApp() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.becameActiveAt = Date() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.becameActiveAt = nil }
        })
    }

    /// Hands the keyboard back to the app the user was in, when it was the
    /// link that took it.
    func giveBack() {
        let askedAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self,
                  Self.shouldGiveBack(
                      isActive: NSApp.isActive,
                      becameActiveAt: self.becameActiveAt,
                      askedAt: askedAt,
                      hasOwnWindowUp: Self.hasOwnWindowUp
                  ),
                  let pid = self.lastOtherApp,
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
            NSApp.yieldActivation(to: app)
            app.activate()
        }
    }

    /// Only an activation that arrived with the link is handed back. With
    /// Settings up, or with the app in front since before the link, the
    /// user is in this app and keeps the keyboard.
    nonisolated static func shouldGiveBack(
        isActive: Bool,
        becameActiveAt: Date?,
        askedAt: Date,
        hasOwnWindowUp: Bool
    ) -> Bool {
        guard isActive, !hasOwnWindowUp, let becameActiveAt else { return false }
        return askedAt.timeIntervalSince(becameActiveAt) < linkActivationWindow
    }

    private func noteFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        lastOtherApp = app.processIdentifier
    }

    /// The Settings window. The island's own panel never becomes main.
    private static var hasOwnWindowUp: Bool {
        NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
    }
}
