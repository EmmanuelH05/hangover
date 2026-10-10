import Foundation
import OpenIslandCore

/// The three parts of the tour. Every page says which one it belongs to,
/// which tells a newcomer how far along they are.
enum OnboardingChapter: String, CaseIterable, Sendable {
    /// What the island is and how it opens.
    case basics
    /// The choices: what it shows and how it looks.
    case yours
    /// What it may ask for, a few tricks and the recap.
    case know

    var titleKey: String { "onboarding.chapter.\(rawValue)" }
}

/// The pages of the welcome tour, in the order they are shown. A page asks
/// one thing only (D43).
enum OnboardingPage: Int, CaseIterable, Identifiable, Sendable {
    /// What Hangover is. Nothing to choose.
    case welcome
    /// With coding agents or without: the agents switch, asked as a question.
    case purpose
    case opening
    /// What the right of the closed island shows.
    case closed
    case agents
    /// Which widgets are switched on.
    case widgets
    /// Each switched-on widget in action on the real island, one at a time
    /// (D47). Shown with the other live pages.
    case features
    /// A starting layout for those widgets.
    case layout
    /// Moving and resizing the widgets, done for real on the real island.
    case arrange
    /// Where the to-do widget gets its tasks, and how to connect that
    /// place. Shown only while the to-do widget is on the page.
    case todos
    /// Where quick notes go, and a note saved to try it. Shown only while
    /// the notes widget is on the page.
    case notes
    /// Where the user is, for the weather card and the closed island's
    /// temperature. Shown only while the weather widget is on the page.
    case weather
    /// How the opened island looks: its width and its corners.
    case opened
    /// The glow: its strength and its colors.
    case look
    case permissions
    /// The outside things the app works with, and where each is set up.
    case integrations
    /// Small things that are easy to miss.
    case tips
    case done

    var id: Int { rawValue }

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }

    var chapter: OnboardingChapter {
        switch self {
        case .welcome, .purpose, .opening: .basics
        case .closed, .agents, .widgets, .features, .layout, .arrange, .todos, .notes, .weather, .opened, .look: .yours
        case .permissions, .integrations, .tips, .done: .know
        }
    }

    /// True for a page that uses the opened island at the top of the screen
    /// as its preview (D44). While one is up, the tour holds the island
    /// open and its window steps aside, narrow, at the left of the screen.
    var isLive: Bool {
        switch self {
        case .widgets, .features, .layout, .arrange, .todos, .notes, .weather, .opened: true
        default: false
        }
    }

    /// True for a page that is only about agents.
    var isAgentsOnly: Bool { self == .agents }

    /// True for the page that carries the agents switch. No run of the tour
    /// leaves it out.
    var offersAgentsSwitch: Bool { self == .purpose }

    /// True for the page that is only about the to-do widget.
    var needsTodoWidget: Bool { self == .todos }

    /// True for the page that is only about the notes widget.
    var needsNotesWidget: Bool { self == .notes }

    /// True for the page that is only about the weather widget.
    var needsWeatherWidget: Bool { self == .weather }

    /// The pages a tour walks, in order. With the agents switched off the
    /// agents page is left out (D41), and with the to-do, the notes or the
    /// weather widget off its page is.
    static func shown(
        agentsEnabled: Bool,
        hasTodoWidget: Bool = true,
        hasNotesWidget: Bool = true,
        hasWeatherWidget: Bool = true
    ) -> [OnboardingPage] {
        allCases.filter { page in
            (agentsEnabled || !page.isAgentsOnly)
                && (hasTodoWidget || !page.needsTodoWidget)
                && (hasNotesWidget || !page.needsNotesWidget)
                && (hasWeatherWidget || !page.needsWeatherWidget)
        }
    }

    /// The page to show for `page`: itself, or the nearest page before it
    /// when `pages` leaves it out.
    static func landing(_ page: OnboardingPage, in pages: [OnboardingPage]) -> OnboardingPage {
        if pages.contains(page) { return page }
        return pages.last { $0.rawValue < page.rawValue } ?? pages.first ?? page
    }

    /// File name of this page's picture in the render snapshots.
    var snapshotName: String {
        let name = switch self {
        case .welcome: "welcome"
        case .purpose: "purpose"
        case .opening: "opening"
        case .closed: "closed"
        case .agents: "agents"
        case .widgets: "widgets"
        case .features: "features"
        case .todos: "todos"
        case .notes: "notes"
        case .weather: "weather"
        case .layout: "layout"
        case .arrange: "arrange"
        case .opened: "opened"
        case .look: "look"
        case .permissions: "permissions"
        case .integrations: "integrations"
        case .tips: "tips"
        case .done: "done"
        }
        return String(format: "%02d-%@", rawValue + 1, name)
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
    /// The pages this run walks, in tour order. A page that is taken out
    /// while it is up gives way to the one before it.
    var pages: [OnboardingPage] {
        didSet { page = OnboardingPage.landing(page, in: pages) }
    }

    init(startingAt page: OnboardingPage = .welcome, pages: [OnboardingPage] = OnboardingPage.allCases) {
        self.pages = pages
        self.page = OnboardingPage.landing(page, in: pages)
    }

    var isFirstPage: Bool { page == pages.first }
    var isLastPage: Bool { page == pages.last }
    var hasEnded: Bool { outcome != nil }

    /// Finishing and skipping both count as having seen the tour. Either
    /// one is recorded, and the tour never shows by itself again.
    var recordsCompletion: Bool { hasEnded }

    /// One page on. On the last page this finishes the tour.
    mutating func next() {
        guard !hasEnded else { return }
        if let index = pages.firstIndex(of: page), index + 1 < pages.count {
            page = pages[index + 1]
        } else {
            outcome = .finished
        }
    }

    /// One page back. Nothing on the first page.
    mutating func back() {
        guard !hasEnded, let index = pages.firstIndex(of: page), index > 0 else { return }
        page = pages[index - 1]
    }

    /// Straight to a page, from a progress dot. A page this run leaves out
    /// is not gone to.
    mutating func go(to page: OnboardingPage) {
        guard !hasEnded, pages.contains(page) else { return }
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
