import Foundation
import OpenIslandCore

/// The pages of the welcome tour, in the order they are shown.
enum OnboardingPage: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case opening
    case agents
    case nook
    /// How the opened island looks: its width and its corners.
    case opened
    /// The glow: its strength and its colors.
    case look
    case permissions
    case done

    var id: Int { rawValue }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }

    /// File name of this page's picture in the render snapshots.
    var snapshotName: String {
        switch self {
        case .welcome: "1-welcome"
        case .opening: "2-opening"
        case .agents: "3-agents"
        case .nook: "4-nook"
        case .opened: "5-opened"
        case .look: "6-look"
        case .permissions: "7-permissions"
        case .done: "8-done"
        }
    }
}

/// How a tour ended.
enum OnboardingOutcome: Equatable, Sendable {
    /// The last page's button was pressed.
    case finished
    /// Skip, Escape or the window's close button.
    case skipped
}

/// The welcome tour as a plain state machine: the page that is up and
/// whether the tour has ended. It holds no view and no app state, which
/// keeps every move testable without a window.
struct OnboardingFlow: Equatable, Sendable {
    private(set) var page: OnboardingPage
    private(set) var outcome: OnboardingOutcome?

    init(startingAt page: OnboardingPage = .welcome) {
        self.page = page
    }

    var isFirstPage: Bool { page.previous == nil }
    var isLastPage: Bool { page.next == nil }
    var hasEnded: Bool { outcome != nil }

    /// Finishing and skipping both count as having seen the tour. Either
    /// one is recorded, and the tour never shows by itself again.
    var recordsCompletion: Bool { hasEnded }

    /// One page on. On the last page this finishes the tour.
    mutating func next() {
        guard !hasEnded else { return }
        if let next = page.next {
            page = next
        } else {
            outcome = .finished
        }
    }

    /// One page back. Nothing on the first page.
    mutating func back() {
        guard !hasEnded, let previous = page.previous else { return }
        page = previous
    }

    /// Straight to a page, from a progress dot.
    mutating func go(to page: OnboardingPage) {
        guard !hasEnded else { return }
        self.page = page
    }

    /// Ends the tour from any page.
    mutating func skip() {
        guard !hasEnded else { return }
        outcome = .skipped
    }
}

/// Decides whether the welcome tour may come up without being asked for.
enum OnboardingGate {
    struct Facts: Equatable, Sendable {
        /// The tour was finished, skipped or closed on this install.
        var isCompleted: Bool
        /// A harness run is driving the app for screenshots.
        var isHarness: Bool
    }

    /// Every install gets the tour by itself once: a new one on its first
    /// launch, and one that ran before the tour existed, with or without
    /// agents connected, on its first launch of a build that has it.
    static func showsByItself(_ facts: Facts) -> Bool {
        !facts.isCompleted && !facts.isHarness
    }

    /// A name in the app's environment that starts this way belongs to a
    /// harness, a scenario or a debugging switch, unless it is one of the
    /// ordinary names below.
    static let harnessPrefix = "OPEN_ISLAND_"

    /// Names an ordinary launch can carry: paths the app reads, and the
    /// mark the Pi and OpenCode plugins export into their own shells.
    static let ordinaryNames: Set<String> = [
        "OPEN_ISLAND_SOCKET_PATH",
        "OPEN_ISLAND_HOOKS_BINARY",
        "OPEN_ISLAND_MEDIAREMOTE_DIR",
        "OPEN_ISLAND_ACTIVE",
    ]

    /// True when the launch was set up through the environment: a harness
    /// scenario, a forced glow or page, or any other `OPEN_ISLAND_` switch.
    /// Such a launch is someone driving the app for a picture or a test, on
    /// what may be a clean settings domain, and it never gets the tour.
    static func isHarnessLaunch(environment: [String: String]) -> Bool {
        environment.keys.contains { $0.hasPrefix(harnessPrefix) && !ordinaryNames.contains($0) }
    }
}
