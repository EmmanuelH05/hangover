import Foundation

/// What the tour offers for the right of the closed island: every card the
/// Personalization tab offers for that side (D43), the island's own three
/// (`rightSlotSection` in `AppearanceSettingsPane`) and the Nook's extras
/// (`nookRightSlotExtras`). With the agents off, Settings keeps one row of
/// four (`nookRightSlotWithoutAgents`), and this page offers the same four.
enum OnboardingClosedSide: String, CaseIterable, Identifiable, Sendable {
    /// How many agent sessions there are.
    case count
    /// One dot for each agent.
    case agents
    /// The activity bars, the Nook's extra `NookSideSlot.agents`.
    case bars
    case date
    case battery
    /// Time left until the next event. It reads the calendar.
    case countdown
    /// The temperature now. It needs a city in the Weather widget.
    case weather
    /// Time left on the focus timer.
    case timer
    /// How many tasks are still open. It needs a to-do source.
    case todos
    case nothing

    var id: String { rawValue }

    /// True for a pick that shows agent sessions.
    var needsAgents: Bool { self == .count || self == .agents || self == .bars }

    /// True for a pick that reads the calendar, which macOS asks about the
    /// first time an island the user opened shows the Calendar widget
    /// (`NookAccessTiming`). Picking it asks for nothing.
    var needsCalendar: Bool { need == .calendar }

    /// What the pick needs before it has anything to show.
    var need: OnboardingClosedNeed? {
        switch self {
        case .countdown: .calendar
        case .weather: .weatherCity
        case .todos: .todoSource
        default: nil
        }
    }

    var titleKey: String { "onboarding.closed.\(rawValue).title" }
    var noteKey: String { "onboarding.closed.\(rawValue).note" }

    /// The cards the page shows. Off leaves out those that show agents.
    static func offered(agentsEnabled: Bool) -> [OnboardingClosedSide] {
        agentsEnabled ? allCases : allCases.filter { !$0.needsAgents }
    }

    /// The pick as Personalization writes it (D39): one choice for the
    /// whole right side.
    var choice: IslandRightSideChoice {
        switch self {
        case .count: .own(.count)
        case .agents: .own(.agents)
        case .bars: .extra(.agents)
        case .date: .extra(.date)
        case .battery: .extra(.battery)
        case .countdown: .extra(.countdown)
        case .weather: .extra(.weather)
        case .timer: .extra(.timer)
        case .todos: .extra(.todos)
        case .nothing: .own(.none)
        }
    }

    /// The pick a display's two saved slots read as. Nil for something the
    /// tour does not offer: the agent tiles, which Settings offers only on
    /// the left.
    static func reading(
        own: IslandRightSlot,
        nook: NookSideSlot?,
        agentsEnabled: Bool
    ) -> OnboardingClosedSide? {
        if let nook {
            switch AgentsSwitch.shown(nook, agentsEnabled: agentsEnabled) {
            case .agents: return .bars
            case .date: return .date
            case .battery: return .battery
            case .countdown: return .countdown
            case .weather: return .weather
            case .timer: return .timer
            case .todos: return .todos
            case .none: return .nothing
            case .count, .grid: return nil
            }
        }
        switch AgentsSwitch.shown(own, agentsEnabled: agentsEnabled) {
        case .count: return .count
        case .agents: return .agents
        case .none: return .nothing
        }
    }
}

/// What a choice of the closed page needs before it has anything to show.
/// The page names it in a line under the group (D43).
enum OnboardingClosedNeed: CaseIterable, Sendable {
    /// The calendar, which macOS asks about when the user first opens the
    /// island with the Calendar widget on it.
    case calendar
    /// A city chosen in the Weather widget.
    case weatherCity
    /// A to-do source that is connected.
    case todoSource

    var textKey: String {
        switch self {
        case .calendar: "onboarding.closed.calendar"
        case .weatherCity: "onboarding.closed.weather.need"
        case .todoSource: "onboarding.closed.todos.need"
        }
    }
}

/// What a pick of the tour writes to a display's two slots.
enum OnboardingClosedWrite: Equatable, Sendable {
    /// One choice for the whole right side, as a card in Personalization
    /// writes it (D39).
    case choice(IslandRightSideChoice)
    /// Takes a Nook item off the side and leaves the island's own saved
    /// slot alone, which brings that slot back with the agents switch (D41).
    case clearNookItem

    /// The two slots after the write.
    func applied(own: IslandRightSlot, nook: NookSideSlot?) -> (own: IslandRightSlot, nook: NookSideSlot?) {
        switch self {
        case .choice(let choice): (choice.ownSlot, choice.nookSlot)
        case .clearNookItem: (own, nook?.needsAgents == false ? nil : nook)
        }
    }
}

extension OnboardingClosedSide {
    /// What picking this side writes. With the agents switched off, Nothing
    /// only clears a Nook item: the island's own slot shows agents, is not
    /// on screen then, and is the user's to keep.
    func write(agentsEnabled: Bool) -> OnboardingClosedWrite {
        self == .nothing && !agentsEnabled ? .clearNookItem : .choice(choice)
    }
}

extension AppModel {
    /// Applies the tour's pick for the right of the closed island to the
    /// display in use, with the writes the cards in Personalization make.
    func chooseClosedSide(_ side: OnboardingClosedSide) {
        let profile = activeAppearanceProfile
        switch side.write(agentsEnabled: agentsEnabled) {
        case .choice(let choice):
            chooseRightSide(choice, for: profile)
        case .clearNookItem:
            nook.updateDisplayPreferences(for: profile) { preferences in
                if preferences.rightSlot?.needsAgents == false { preferences.rightSlot = nil }
            }
        }
    }
}
