import Foundation
import SwiftUI

/// The lengths of a pomodoro run: work rounds with a short break between
/// them and a long break after the last round of a set. Changed in the
/// timer settings.
struct NookPomodoroPlan: Equatable, Sendable {
    var work: TimeInterval = 25 * 60
    var shortBreak: TimeInterval = 5 * 60
    var longBreak: TimeInterval = 15 * 60
    /// Work rounds before the long break.
    var rounds = 4

    static let lengthRange: ClosedRange<TimeInterval> = 60...(180 * 60)
    static let roundsRange = 1...12

    private static let workKey = "nook.timer.pomodoro.work"
    private static let shortBreakKey = "nook.timer.pomodoro.shortBreak"
    private static let longBreakKey = "nook.timer.pomodoro.longBreak"
    private static let roundsKey = "nook.timer.pomodoro.rounds"

    /// The same plan with every value pulled inside its range.
    var clamped: NookPomodoroPlan {
        NookPomodoroPlan(
            work: Self.clamp(work),
            shortBreak: Self.clamp(shortBreak),
            longBreak: Self.clamp(longBreak),
            rounds: min(max(Self.roundsRange.lowerBound, rounds), Self.roundsRange.upperBound)
        )
    }

    func length(of phase: NookPomodoroPhase) -> TimeInterval {
        switch phase {
        case .work: work
        case .shortBreak: shortBreak
        case .longBreak: longBreak
        }
    }

    /// The saved plan. A missing or out-of-range value falls back to its
    /// default, never to zero.
    static func load(from defaults: UserDefaults) -> NookPomodoroPlan {
        let fallback = NookPomodoroPlan()
        func length(_ key: String, _ fallback: TimeInterval) -> TimeInterval {
            let stored = defaults.double(forKey: key)
            return lengthRange.contains(stored) ? stored : fallback
        }
        let storedRounds = defaults.integer(forKey: roundsKey)
        return NookPomodoroPlan(
            work: length(workKey, fallback.work),
            shortBreak: length(shortBreakKey, fallback.shortBreak),
            longBreak: length(longBreakKey, fallback.longBreak),
            rounds: roundsRange.contains(storedRounds) ? storedRounds : fallback.rounds
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(work, forKey: Self.workKey)
        defaults.set(shortBreak, forKey: Self.shortBreakKey)
        defaults.set(longBreak, forKey: Self.longBreakKey)
        defaults.set(rounds, forKey: Self.roundsKey)
    }

    private static func clamp(_ length: TimeInterval) -> TimeInterval {
        min(max(lengthRange.lowerBound, length), lengthRange.upperBound)
    }
}

enum NookPomodoroPhase: String, Equatable, Sendable {
    case work
    case shortBreak
    case longBreak

    var isBreak: Bool { self != .work }
}

/// Where a pomodoro run stands: which round, and work or break. A pure
/// state machine; the timer owns the clock and asks this what comes next.
struct NookPomodoroState: Equatable, Sendable {
    var phase: NookPomodoroPhase = .work
    /// The work round within the current set, counted from one. A break
    /// carries the round it follows.
    var round = 1

    /// The first work round of a set.
    static let first = NookPomodoroState()

    /// What follows when this phase runs out or is skipped. Work leads to a
    /// short break, or to the long break after the last round of the set.
    /// A short break leads to the next round and the long break starts a
    /// new set.
    func next(rounds: Int) -> NookPomodoroState {
        switch phase {
        case .work:
            NookPomodoroState(phase: round >= rounds ? .longBreak : .shortBreak, round: round)
        case .shortBreak:
            NookPomodoroState(phase: .work, round: round + 1)
        case .longBreak:
            .first
        }
    }
}

/// How a countdown reads on the card and in the closed island. Pure.
enum NookPomodoroLook {
    /// Numbered circle symbols stop at fifty.
    private static let highestNumberedSymbol = 50
    static let workTint = Color.orange
    static let breakTint = Color(red: 111 / 255, green: 185 / 255, blue: 130 / 255)
    static let longBreakTint = Color(red: 110 / 255, green: 167 / 255, blue: 255 / 255)

    /// The closed island has room for the time and one symbol: a work
    /// round shows its number in a circle and a break shows a cup. A plain
    /// countdown keeps the timer symbol.
    static func symbol(for state: NookPomodoroState?) -> String {
        guard let state else { return "timer" }
        switch state.phase {
        case .work: return "\(min(max(1, state.round), highestNumberedSymbol)).circle.fill"
        case .shortBreak, .longBreak: return "cup.and.saucer.fill"
        }
    }

    static func tint(for state: NookPomodoroState?) -> Color {
        switch state?.phase {
        case nil, .work: workTint
        case .shortBreak: breakTint
        case .longBreak: longBreakTint
        }
    }

    /// "Focus 2/4", "Break" or "Long break". Short, because the closed
    /// island shows it as the notice when a round changes.
    static func label(for state: NookPomodoroState, rounds: Int, lang: LanguageManager = .shared) -> String {
        switch state.phase {
        case .work: lang.t("nook.timer.pomodoro.focus", state.round, max(rounds, state.round))
        case .shortBreak: lang.t("nook.timer.pomodoro.break")
        case .longBreak: lang.t("nook.timer.pomodoro.longBreak")
        }
    }
}
