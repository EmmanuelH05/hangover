import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// Pomodoro mode on the focus timer: the round rules, the saved lengths,
/// and the timer running them. No test waits on the clock; a round ends by
/// being skipped, which takes the same path as running out.
@Suite struct NookPomodoroTests {
    private static let work: TimeInterval = 1500
    private static let shortBreak: TimeInterval = 300
    private static let longBreak: TimeInterval = 900

    /// A private settings store, held in memory, and the name its domain calls take.
    private static func makeDefaults() -> (defaults: UserDefaults, name: String) {
        (MemoryDefaults(), "NookPomodoroTests")
    }

    private static func state(_ phase: NookPomodoroPhase, _ round: Int) -> NookPomodoroState {
        NookPomodoroState(phase: phase, round: round)
    }

    // MARK: Round rules

    @Test func theDefaultPlanIsTwentyFiveFiveFifteenAndFour() {
        let plan = NookPomodoroPlan()
        let rounds = 4

        #expect(plan.work == Self.work)
        #expect(plan.shortBreak == Self.shortBreak)
        #expect(plan.longBreak == Self.longBreak)
        #expect(plan.rounds == rounds)
        #expect(plan.length(of: .work) == Self.work)
        #expect(plan.length(of: .shortBreak) == Self.shortBreak)
        #expect(plan.length(of: .longBreak) == Self.longBreak)
    }

    @Test func aSetRunsWorkAndShortBreaksThenALongBreakThenStartsOver() {
        var state = NookPomodoroState.first
        var seen = [state]
        for _ in 0..<8 {
            state = state.next(rounds: 4)
            seen.append(state)
        }

        #expect(seen == [
            Self.state(.work, 1), Self.state(.shortBreak, 1),
            Self.state(.work, 2), Self.state(.shortBreak, 2),
            Self.state(.work, 3), Self.state(.shortBreak, 3),
            Self.state(.work, 4), Self.state(.longBreak, 4),
            Self.state(.work, 1),
        ])
    }

    @Test func oneRoundPerSetGoesStraightToTheLongBreak() {
        let afterWork = NookPomodoroState.first.next(rounds: 1)

        #expect(afterWork == Self.state(.longBreak, 1))
        #expect(afterWork.next(rounds: 1) == .first)
    }

    @Test func loweringTheRoundsMidRunLeadsToTheLongBreak() {
        // On round three of four when the setting drops to two.
        #expect(Self.state(.work, 3).next(rounds: 2) == Self.state(.longBreak, 3))
        #expect(Self.state(.shortBreak, 3).next(rounds: 2) == Self.state(.work, 4))
    }

    @Test func onlyWorkIsNotABreak() {
        #expect(!NookPomodoroPhase.work.isBreak)
        #expect(NookPomodoroPhase.shortBreak.isBreak)
        #expect(NookPomodoroPhase.longBreak.isBreak)
    }

    // MARK: Saved lengths

    @Test func aPlanIsPulledInsideItsLimits() {
        let shortest: TimeInterval = 60
        let longest: TimeInterval = 10_800
        let low = NookPomodoroPlan(work: 0, shortBreak: -5, longBreak: 1, rounds: 0).clamped
        let high = NookPomodoroPlan(work: 99_999, shortBreak: 99_999, longBreak: 99_999, rounds: 99).clamped

        #expect(low.work == shortest)
        #expect(low.shortBreak == shortest)
        #expect(low.longBreak == shortest)
        #expect(low.rounds == 1)
        #expect(high.work == longest)
        #expect(high.shortBreak == longest)
        #expect(high.longBreak == longest)
        #expect(high.rounds == 12)
    }

    @Test func aSavedPlanComesBackAndNonsenseFallsBackToTheDefaults() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(NookPomodoroPlan.load(from: defaults) == NookPomodoroPlan())

        let custom = NookPomodoroPlan(work: 50 * 60, shortBreak: 10 * 60, longBreak: 30 * 60, rounds: 2)
        custom.save(to: defaults)
        #expect(NookPomodoroPlan.load(from: defaults) == custom)
        // Exactly the four lengths are written, nothing else.
        #expect(defaults.persistentDomain(forName: name)?.count == 4)

        defaults.set(5.0, forKey: "nook.timer.pomodoro.work")
        defaults.set("soon", forKey: "nook.timer.pomodoro.shortBreak")
        defaults.set(0, forKey: "nook.timer.pomodoro.rounds")
        let repaired = NookPomodoroPlan.load(from: defaults)
        #expect(repaired.work == Self.work)
        #expect(repaired.shortBreak == Self.shortBreak)
        #expect(repaired.longBreak == custom.longBreak)
        #expect(repaired.rounds == 4)
    }

    // MARK: How it reads

    @Test func theClosedIslandShowsTheRoundNumberForWorkAndACupForBreaks() {
        #expect(NookPomodoroLook.symbol(for: nil) == "timer")
        #expect(NookPomodoroLook.symbol(for: Self.state(.work, 1)) == "1.circle.fill")
        #expect(NookPomodoroLook.symbol(for: Self.state(.work, 12)) == "12.circle.fill")
        // Numbered circles stop at fifty.
        #expect(NookPomodoroLook.symbol(for: Self.state(.work, 73)) == "50.circle.fill")
        #expect(NookPomodoroLook.symbol(for: Self.state(.shortBreak, 2)) == "cup.and.saucer.fill")
        #expect(NookPomodoroLook.symbol(for: Self.state(.longBreak, 4)) == "cup.and.saucer.fill")

        #expect(NookPomodoroLook.tint(for: nil) == NookPomodoroLook.workTint)
        #expect(NookPomodoroLook.tint(for: Self.state(.work, 2)) == NookPomodoroLook.workTint)
        #expect(NookPomodoroLook.tint(for: Self.state(.shortBreak, 2)) == NookPomodoroLook.breakTint)
        #expect(NookPomodoroLook.tint(for: Self.state(.longBreak, 4)) == NookPomodoroLook.longBreakTint)
    }

    @Test func everyNumberedSymbolTheRoundsCanReachExists() {
        for round in NookPomodoroPlan.roundsRange {
            let name = NookPomodoroLook.symbol(for: Self.state(.work, round))
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name) is missing")
        }
        #expect(NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil) != nil)
    }

    @Test func theLabelNamesTheRoundOrTheBreak() {
        let lang = LanguageManager.shared

        #expect(NookPomodoroLook.label(for: Self.state(.work, 2), rounds: 4) == lang.t("nook.timer.pomodoro.focus", 2, 4))
        // A round past the setting never reads "5/4".
        #expect(NookPomodoroLook.label(for: Self.state(.work, 5), rounds: 4) == lang.t("nook.timer.pomodoro.focus", 5, 5))
        #expect(NookPomodoroLook.label(for: Self.state(.shortBreak, 2), rounds: 4) == lang.t("nook.timer.pomodoro.break"))
        #expect(NookPomodoroLook.label(for: Self.state(.longBreak, 4), rounds: 4) == lang.t("nook.timer.pomodoro.longBreak"))
    }

    // MARK: The timer running rounds

    @Test @MainActor func aPomodoroStartsOnTheFirstWorkRoundAndSkipWalksTheSet() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let timer = NookFocusTimer(defaults: defaults)
        defer { timer.reset() }

        timer.startPomodoro()
        #expect(timer.pomodoro == .first)
        #expect(timer.isRunning)
        #expect(timer.isActive)
        #expect(!timer.isOnBreak)
        #expect(timer.remaining == Self.work)
        #expect(timer.oneOffTotal == Self.work)
        #expect(timer.closedText != nil)

        timer.skipPomodoroPhase()
        #expect(timer.pomodoro == Self.state(.shortBreak, 1))
        #expect(timer.isOnBreak)
        #expect(timer.isRunning)
        #expect(timer.remaining == Self.shortBreak)

        // Work two, break, work three, break, work four.
        for _ in 0..<5 { timer.skipPomodoroPhase() }
        #expect(timer.pomodoro == Self.state(.work, 4))

        timer.skipPomodoroPhase()
        #expect(timer.pomodoro == Self.state(.longBreak, 4))
        #expect(timer.remaining == Self.longBreak)

        timer.skipPomodoroPhase()
        #expect(timer.pomodoro == .first)
        #expect(timer.remaining == Self.work)
    }

    @Test @MainActor func aPomodoroPausesResumesAndStops() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let timer = NookFocusTimer(defaults: defaults)
        defer { timer.reset() }
        let preset = timer.preset

        timer.startPomodoro()
        timer.skipPomodoroPhase()

        timer.pause()
        #expect(!timer.isRunning)
        #expect(timer.isActive)
        #expect(timer.pomodoro == Self.state(.shortBreak, 1))
        #expect(timer.remaining <= Self.shortBreak)

        timer.start()
        #expect(timer.isRunning)
        #expect(timer.pomodoro == Self.state(.shortBreak, 1))

        timer.reset()
        #expect(timer.pomodoro == nil)
        #expect(!timer.isRunning)
        #expect(!timer.isActive)
        #expect(timer.oneOffTotal == nil)
        #expect(timer.remaining == preset)
        #expect(timer.closedText == nil)
    }

    @Test @MainActor func changedLengthsAreSavedAndUsedByTheNextRun() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let timer = NookFocusTimer(defaults: defaults)
        defer { timer.reset() }
        let longWork: TimeInterval = 3000
        let longestBreak: TimeInterval = 10_800

        timer.set(pomodoroPlan: NookPomodoroPlan(work: longWork, shortBreak: 600, longBreak: 99_999, rounds: 1))
        #expect(timer.pomodoroPlan.longBreak == longestBreak)
        #expect(NookFocusTimer(defaults: defaults).pomodoroPlan == timer.pomodoroPlan)

        timer.startPomodoro()
        #expect(timer.remaining == longWork)
        timer.skipPomodoroPhase()
        #expect(timer.pomodoro == Self.state(.longBreak, 1))
        #expect(timer.remaining == longestBreak)
    }

    @Test @MainActor func aPlainTimerWorksAsBefore() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let timer = NookFocusTimer(defaults: defaults)
        defer { timer.reset() }
        let preset = timer.preset

        #expect(timer.pomodoro == nil)
        #expect(timer.closedText == nil)

        timer.start()
        #expect(timer.isRunning)
        #expect(timer.isActive)
        #expect(timer.pomodoro == nil)
        #expect(timer.oneOffTotal == nil)
        #expect(timer.closedText != nil)

        // Skip belongs to a pomodoro. A plain countdown ignores it.
        timer.skipPomodoroPhase()
        #expect(timer.isRunning)
        #expect(timer.pomodoro == nil)

        timer.pause()
        #expect(!timer.isRunning)
        #expect(timer.isActive)
        #expect(timer.remaining <= preset)

        timer.reset()
        #expect(!timer.isActive)
        #expect(timer.remaining == preset)

        let fifty: TimeInterval = 3000
        timer.set(preset: fifty)
        #expect(timer.preset == fifty)
        #expect(timer.remaining == fifty)
    }

    @Test @MainActor func aNamedLengthStartsInPlaceOfWhateverWasUpAndLeavesThePresetAlone() {
        let (defaults, name) = Self.makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let timer = NookFocusTimer(defaults: defaults)
        defer { timer.reset() }
        let preset = timer.preset
        let tenMinutes: TimeInterval = 600
        let aDay: TimeInterval = 86_400

        timer.startPomodoro()
        timer.start(length: tenMinutes)
        #expect(timer.pomodoro == nil)
        #expect(timer.isRunning)
        #expect(timer.oneOffTotal == tenMinutes)
        #expect(timer.remaining == tenMinutes)
        #expect(timer.preset == preset)

        // Out-of-range lengths are pulled in, never trusted.
        timer.start(length: 9_999_999)
        #expect(timer.oneOffTotal == aDay)

        // A pomodoro takes over a plain countdown the same way.
        timer.startPomodoro()
        #expect(timer.pomodoro == .first)
        #expect(timer.remaining == timer.pomodoroPlan.work)
    }

    // MARK: On the Nook

    @Test @MainActor func eachChangeOfRoundSaysWhatItIsInTheClosedIsland() {
        let nook = NookModel()
        nook.presentRingLight = { _ in }
        // Wires the timer to the model without starting the other widgets.
        nook.timer.start(nook: nook)
        defer { nook.timer.reset() }
        let lang = LanguageManager.shared
        let rounds = nook.timer.pomodoroPlan.rounds
        let preferences = NookDisplayPreferences()

        nook.timer.startPomodoro()
        // Starting is the user's own click and says nothing.
        #expect(nook.transient == nil)
        #expect(nook.isFocusModeActive)
        #expect(nook.closedActivity(for: preferences)?.leading == .symbol("1.circle.fill", NookPomodoroLook.workTint))

        nook.timer.skipPomodoroPhase()
        // The long break when a set is one round, the short one otherwise.
        let breakKey = rounds > 1 ? "nook.timer.pomodoro.break" : "nook.timer.pomodoro.longBreak"
        #expect(nook.timer.isOnBreak)
        #expect(nook.transient?.text == lang.t(breakKey))
        #expect(nook.transient?.symbol == "cup.and.saucer.fill")
        // A break is not focus time: completion cards come through.
        #expect(!nook.isFocusModeActive)

        if rounds > 1 {
            nook.timer.skipPomodoroPhase()
            #expect(nook.transient?.text == lang.t("nook.timer.pomodoro.focus", 2, rounds))
            #expect(nook.transient?.symbol == "2.circle.fill")
            #expect(nook.isFocusModeActive)
        }
    }

    @Test func aPlainCountdownKeepsTheTimerSymbolInTheClosedIsland() {
        let plain = NookClosedActivity.resolve(
            transient: nil, timerText: "24:59", media: nil, preferences: NookDisplayPreferences()
        )
        let onBreak = NookClosedActivity.resolve(
            transient: nil,
            timerText: "04:59",
            timerLeading: .symbol("cup.and.saucer.fill", NookPomodoroLook.breakTint),
            media: nil,
            preferences: NookDisplayPreferences()
        )

        #expect(plain?.leading == .symbol("timer", .orange))
        #expect(onBreak?.leading == .symbol("cup.and.saucer.fill", NookPomodoroLook.breakTint))
        #expect(onBreak?.trailing == .text("04:59"))
    }

    // MARK: Strings

    @Test func everyPomodoroStringExistsInEveryLanguage() throws {
        let keys = [
            "nook.timer.pomodoro", "nook.timer.pomodoro.help", "nook.timer.pomodoro.focus",
            "nook.timer.pomodoro.break", "nook.timer.pomodoro.longBreak", "nook.timer.pomodoro.skip",
            "nook.timer.pomodoro.stop", "nook.timer.pomodoro.settings.work",
            "nook.timer.pomodoro.settings.shortBreak", "nook.timer.pomodoro.settings.longBreak",
            "nook.timer.pomodoro.settings.rounds", "nook.timer.pomodoro.settings.note",
        ]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let url = root.appendingPathComponent("Sources/OpenIslandApp/Resources/\(language).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String], "\(language) did not load")
            for key in keys {
                #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
            }
        }
    }
}
