import Foundation

/// What the tour offers for the left of the closed island: every card the
/// Personalization tab offers for that side (`nookLeftSlotSection`), one for
/// each `NookSideSlot`. With the agents off, Settings keeps four, and this page offers
/// the same four. A pick is the `leftSlot` of the display's Nook preferences, the
/// write that section makes.
enum OnboardingClosedLeft: String, CaseIterable, Identifiable, Sendable {
    /// The activity bars, `NookSideSlot.agents`.
    case bars
    case count
    /// One tile per agent session, `NookSideSlot.grid`.
    case grid
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

    /// The slot the pick saves.
    var slot: NookSideSlot {
        switch self {
        case .bars: .agents
        case .count: .count
        case .grid: .grid
        case .date: .date
        case .battery: .battery
        case .countdown: .countdown
        case .weather: .weather
        case .timer: .timer
        case .todos: .todos
        case .nothing: .none
        }
    }

    var needsAgents: Bool { slot.needsAgents }
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

    /// The names and notes are the right side's: a count, a date or the
    /// bars read the same on either side.
    var titleKey: String { "onboarding.closed.\(rawValue).title" }
    var noteKey: String { "onboarding.closed.\(rawValue).note" }

    /// The cards the page shows. Off leaves out those that show agents.
    static func offered(agentsEnabled: Bool) -> [OnboardingClosedLeft] {
        agentsEnabled ? allCases : allCases.filter { !$0.needsAgents }
    }

    /// The pick a saved left slot reads as. With the agents off, a saved
    /// slot that shows agents reads as Nothing and is left as it is.
    static func reading(_ slot: NookSideSlot, agentsEnabled: Bool) -> OnboardingClosedLeft {
        switch AgentsSwitch.shown(slot, agentsEnabled: agentsEnabled) {
        case .agents: .bars
        case .count: .count
        case .grid: .grid
        case .date: .date
        case .battery: .battery
        case .countdown: .countdown
        case .weather: .weather
        case .timer: .timer
        case .todos: .todos
        case .none: .nothing
        }
    }

    /// The left slot after the pick. With the agents off, Nothing must not
    /// throw away a saved choice that shows agents (the guard in Settings).
    func written(over current: NookSideSlot, agentsEnabled: Bool) -> NookSideSlot {
        self == .nothing && !agentsEnabled && current.needsAgents ? current : slot
    }
}

extension AppModel {
    /// Applies the tour's pick for the left of the closed island to the
    /// display in use, with the write the cards in Personalization make.
    func chooseClosedLeft(_ left: OnboardingClosedLeft) {
        let enabled = agentsEnabled
        nook.updateDisplayPreferences(for: activeAppearanceProfile) { preferences in
            preferences.leftSlot = left.written(over: preferences.leftSlot, agentsEnabled: enabled)
        }
    }
}
