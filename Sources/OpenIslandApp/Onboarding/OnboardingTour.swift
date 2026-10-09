import Foundation
import Observation
import OpenIslandCore

/// The agents the tour offers to connect. The Setup tab lists every agent
/// the app knows; the tour keeps to the common ones and links there.
enum OnboardingAgent: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case codex
    case cursor
    case gemini
    case openCode

    var id: String { rawValue }

    /// Product names, which are not translated.
    var name: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .gemini: "Gemini CLI"
        case .openCode: "OpenCode"
        }
    }
}

/// Where one agent stands, as the agents page draws it.
struct OnboardingAgentStatus: Equatable, Sendable {
    var isConnected = false
    var isBusy = false
    /// False while the app cannot install for this agent yet, which is the
    /// case until its hooks helper has been found.
    var canConnect = true
    /// True when Connect was pressed in this tour and the install ended
    /// without the agent being connected.
    var didFail = false
}

/// Everything the pages show that comes from the app. A plain value: the
/// live window reads it from the app model on every draw, and a test or a
/// snapshot hands in a fixed one.
struct OnboardingState: Equatable, Sendable {
    var openTrigger: IslandOpenTrigger = .hover
    /// True while the real island is open, which is how the tour knows the
    /// user tried it.
    var isIslandOpen = false
    var agents: [OnboardingAgent: OnboardingAgentStatus] = [:]
    /// True when an agent the tour does not list is connected, from the
    /// Setup tab.
    var hasAgentOutsideTour = false
    /// The Nook widgets that are switched on.
    var enabledWidgets: Set<NookWidgetKind> = Set(NookWidgetKind.defaultEnabled)
    /// The layout template the display in use is on, if any.
    var appliedTemplate: PersonalizationTemplate.ID?
    /// The template picked in this tour. It stays the user's pick after a
    /// glow of their own is chosen, which Settings would call a setup of
    /// their own.
    var pickedTemplate: PersonalizationTemplate.ID?
    var glowStyle: IslandHaloStyle = .subtle
    /// The glow theme the display's colors equal, nil for colors of the
    /// user's own or one color for everything.
    var glowThemeID: String?
    /// How the opened island looks on the display in use.
    var openedLook = IslandOpenedLook.standard
    /// The kind of display the island is on, which the look's pictures
    /// are drawn for.
    var displayProfile: IslandAppearanceDisplayProfile = .notch
    /// True once the real island was open while this tour was up. It stays
    /// true after the island closes.
    var hasOpenedIsland = false
    /// The approve shortcut as key caps, such as control, option, Y. Nil
    /// while that shortcut is switched off.
    var approveKeys: [String]?
    var denyKeys: [String]?

    func status(of agent: OnboardingAgent) -> OnboardingAgentStatus {
        agents[agent] ?? OnboardingAgentStatus()
    }

    /// The template the pages show as chosen: the one the display is on
    /// right now, or the one picked in this tour when a later choice, such
    /// as a glow, made the display match none.
    var shownTemplate: PersonalizationTemplate.ID? { appliedTemplate ?? pickedTemplate }

    /// The agents that are connected, in the order the tour lists them.
    var connectedAgents: [OnboardingAgent] {
        OnboardingAgent.allCases.filter { status(of: $0).isConnected }
    }
}

/// What a click in the tour can do to the app. Each one runs only from a
/// button the user pressed. None of them asks macOS for a permission: the
/// tour has no such action to give.
@MainActor
struct OnboardingActions {
    var setOpenTrigger: (IslandOpenTrigger) -> Void = { _ in }
    var connect: (OnboardingAgent) -> Void = { _ in }
    /// Opens Settings on the Setup tab, where every agent is listed.
    var showAllAgents: () -> Void = {}
    var setWidget: (_ kind: NookWidgetKind, _ isEnabled: Bool) -> Void = { _, _ in }
    var applyTemplate: (PersonalizationTemplate) -> Void = { _ in }
    var setGlowStyle: (IslandHaloStyle) -> Void = { _ in }
    var setGlowTheme: (IslandHaloTheme) -> Void = { _ in }
    var setOpenedWidth: (IslandOpenedWidth) -> Void = { _ in }
    var setOpenedCorners: (IslandOpenedCorners) -> Void = { _ in }
}

/// What the user chose in one run of the tour, kept by the tour itself.
/// It is what lets a choice on one page survive a choice on another: a
/// template sets a glow style of its own, and a glow style picked here is
/// put back after it.
struct OnboardingPicks: Equatable, Sendable {
    var template: PersonalizationTemplate.ID?
    var glowStyle: IslandHaloStyle?
    /// Agents whose Connect button was pressed.
    var connectAttempts: Set<OnboardingAgent> = []
}

/// One run of the welcome tour: its flow, where it reads the app's state
/// from and what its buttons do.
@MainActor
@Observable
final class OnboardingTour {
    private(set) var flow: OnboardingFlow
    /// What was chosen in this run. The pages read it through `state`.
    private(set) var picks = OnboardingPicks()

    @ObservationIgnored private let readState: () -> OnboardingState
    /// The doors into the app, as they were handed in.
    @ObservationIgnored private let appActions: OnboardingActions
    /// Set the first time the real island is seen open, and never cleared.
    @ObservationIgnored private var hasSeenIslandOpen = false
    /// Runs once, when the tour ends by its last button, by Skip or by its
    /// window closing.
    @ObservationIgnored private let onEnd: (OnboardingOutcome) -> Void

    init(
        startingAt page: OnboardingPage = .welcome,
        state: @escaping () -> OnboardingState,
        actions: OnboardingActions = OnboardingActions(),
        onEnd: @escaping (OnboardingOutcome) -> Void = { _ in }
    ) {
        flow = OnboardingFlow(startingAt: page)
        readState = state
        appActions = actions
        self.onEnd = onEnd
    }

    var page: OnboardingPage { flow.page }

    /// The app's state with this run's picks laid over it. What the state
    /// already says about a pick, a failure or the island having been
    /// opened is kept, which lets a snapshot hand in a fixed one.
    var state: OnboardingState {
        var state = readState()
        if state.isIslandOpen { hasSeenIslandOpen = true }
        state.hasOpenedIsland = state.hasOpenedIsland || hasSeenIslandOpen
        state.pickedTemplate = picks.template ?? state.pickedTemplate
        for agent in picks.connectAttempts {
            var status = state.status(of: agent)
            status.didFail = !status.isConnected && !status.isBusy
            state.agents[agent] = status
        }
        return state
    }

    /// What the pages' buttons call. Each one goes through to the app, and
    /// three of them also keep a note of the pick.
    var actions: OnboardingActions {
        var actions = appActions
        actions.connect = { [weak self, appActions] agent in
            self?.picks.connectAttempts.insert(agent)
            appActions.connect(agent)
        }
        actions.applyTemplate = { [weak self, appActions] template in
            appActions.applyTemplate(template)
            guard let self else { return }
            picks.template = template.id
            // A template carries a glow style. One picked on the glow page
            // is the user's and comes back.
            if let style = picks.glowStyle { appActions.setGlowStyle(style) }
        }
        actions.setGlowStyle = { [weak self, appActions] style in
            self?.picks.glowStyle = style
            appActions.setGlowStyle(style)
        }
        return actions
    }

    func next() { move { $0.next() } }
    func back() { move { $0.back() } }
    func skip() { move { $0.skip() } }
    func go(to page: OnboardingPage) { move { $0.go(to: page) } }

    private func move(_ change: (inout OnboardingFlow) -> Void) {
        let hadEnded = flow.hasEnded
        change(&flow)
        if !hadEnded, let outcome = flow.outcome {
            onEnd(outcome)
        }
    }
}

extension OnboardingTour {
    /// A tour whose end is put on record in `store` before `close` runs.
    /// Finishing, skipping and closing are recorded alike, and that record
    /// is what keeps the tour from coming up by itself again.
    static func recording(
        in store: AgentIntentStore,
        startingAt page: OnboardingPage = .welcome,
        state: @escaping () -> OnboardingState,
        actions: OnboardingActions = OnboardingActions(),
        close: @escaping @MainActor () -> Void = {}
    ) -> OnboardingTour {
        OnboardingTour(startingAt: page, state: state, actions: actions) { _ in
            store.welcomeTourEnded = true
            store.firstLaunchCompleted = true
            close()
        }
    }
}

/// Spells a shortcut out as the words printed on the keys. The symbols
/// macOS menus use are hard to read for anyone who has not learned them.
enum OnboardingShortcutWords {
    static func caps(for combo: AgentHotkeyCombo, keyName: (UInt16) -> String?) -> [String] {
        var caps: [String] = []
        if combo.modifiers.contains(.control) { caps.append("control") }
        if combo.modifiers.contains(.option) { caps.append("option") }
        if combo.modifiers.contains(.shift) { caps.append("shift") }
        if combo.modifiers.contains(.command) { caps.append("command") }
        caps.append(keyName(combo.keyCode) ?? "Key \(combo.keyCode)")
        return caps
    }
}
