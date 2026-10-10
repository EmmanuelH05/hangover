import Foundation

/// The agents switch (D41): one preference for the whole agent half of the
/// app. On, the app is as it always was. Off, nothing of that half runs or
/// shows, and the app is the Nook alone.
///
/// This file holds what the switch means as plain values: where it is
/// saved, which parts of a launch it holds back, and which choices on
/// screen only make sense with agents. `AppModel` starts and stops the
/// running parts.
enum AgentsSwitch {
    static let defaultsKey = "app.agentsEnabled"

    /// On unless it was switched off. An install from before the switch
    /// existed has nothing saved and keeps its agents.
    static func load(from defaults: UserDefaults) -> Bool {
        defaults.object(forKey: defaultsKey) as? Bool ?? true
    }

    static func save(_ isOn: Bool, to defaults: UserDefaults) {
        defaults.set(isOn, forKey: defaultsKey)
    }

    /// The choices a row of cards offers. Off leaves out every card that
    /// would show something of the agents.
    static func offered<Choice: AgentsDependent>(_ choices: [Choice], agentsEnabled: Bool) -> [Choice] {
        agentsEnabled ? choices : choices.filter { !$0.needsAgents }
    }

    /// The choice a row marks as picked. Off, a saved choice that needs
    /// agents reads as the empty one. The saved choice itself is left as it
    /// is, which brings it back with the switch.
    static func shown<Choice: AgentsDependent>(_ choice: Choice, agentsEnabled: Bool) -> Choice {
        !agentsEnabled && choice.needsAgents ? Choice.withoutAgents : choice
    }

    /// Every string the switch added, for the test that checks each one is
    /// in every language.
    static let stringKeys = [
        "settings.general.agents.section",
        "settings.general.agents.toggle",
        "settings.general.agents.note",
        "settings.appearance.openedPart.title",
        "settings.appearance.nook.leftSlot.note.nookOnly",
        "settings.appearance.nook.halo.note.nookOnly",
        "settings.appearance.nook.track.note.nookOnly",
        "settings.appearance.nook.nextEvent.note.nookOnly",
        "onboarding.purpose.title",
        "onboarding.purpose.body",
        "onboarding.purpose.note",
        "onboarding.purpose.day.title",
        "onboarding.purpose.day.text",
        "onboarding.purpose.agents.title",
        "onboarding.purpose.agents.text",
    ] + TemplateText.pointsAboutAgents.sorted().map { $0 + TemplateText.nookOnlySuffix }
}

/// A choice on screen that may show something of the agents.
protocol AgentsDependent: Equatable {
    /// True when the choice shows agent sessions and nothing else.
    var needsAgents: Bool { get }
    /// The choice that stands in for one that needs agents while the
    /// agents switch is off.
    static var withoutAgents: Self { get }
}

extension IslandRightSlot: AgentsDependent {
    var needsAgents: Bool { self != .none }
    static var withoutAgents: IslandRightSlot { .none }
}

extension IslandCenterLabel: AgentsDependent {
    var needsAgents: Bool { self != .off }
    static var withoutAgents: IslandCenterLabel { .off }
}

extension NookSideSlot: AgentsDependent {
    var needsAgents: Bool {
        switch self {
        case .agents, .count, .grid: true
        case .date, .battery, .countdown, .weather, .timer, .todos, .none: false
        }
    }

    static var withoutAgents: NookSideSlot { .none }
}

extension NookOpenedPage: AgentsDependent {
    /// Auto picks between the two pages by what the agents do.
    var needsAgents: Bool { self != .nook }
    static var withoutAgents: NookOpenedPage { .nook }
}

/// The parts of the agent half that run in the background.
struct AgentRuntimeParts: OptionSet, Sendable {
    let rawValue: Int

    /// Session discovery, hook status reads and repair, process and
    /// terminal monitoring, and the usage meters.
    static let sessions = AgentRuntimeParts(rawValue: 1 << 0)
    /// The socket server the hooks talk to, and the app's own connection
    /// to it.
    static let bridge = AgentRuntimeParts(rawValue: 1 << 1)

    /// What a launch asks for. A harness launch asks for less.
    static func launch(startBridge: Bool, loadRuntimeState: Bool) -> AgentRuntimeParts {
        var parts: AgentRuntimeParts = []
        if loadRuntimeState { parts.insert(.sessions) }
        if startBridge { parts.insert(.bridge) }
        return parts
    }

    /// What the agents switch lets run: all of it or none of it.
    func allowed(agentsEnabled: Bool) -> AgentRuntimeParts {
        agentsEnabled ? self : []
    }
}
