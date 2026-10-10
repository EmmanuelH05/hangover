import Foundation
import Testing
@testable import OpenIslandApp

// The closed island's three newer side items: the temperature, the time left
// on the focus timer and the open to-dos (D39, D43).

struct NookSideSlotWeatherTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static func report(celsius: Double, code: Int = 0, isDay: Bool = true, age: TimeInterval = 60) -> NookWeatherReport {
        let moment = NookWeatherReport.Moment(
            time: now.addingTimeInterval(-age), temperature: celsius, code: code, isDay: isDay
        )
        return NookWeatherReport(
            fetchedAt: now.addingTimeInterval(-age),
            utcOffsetSeconds: 0,
            current: moment,
            feelsLike: nil,
            hours: [],
            days: []
        )
    }

    @Test func aReportAndACityGiveTheTemperatureAndASymbol() {
        let content = NookSideSlotContent.resolvedWeather(
            report: Self.report(celsius: 22), hasPlace: true, unit: .fahrenheit, now: Self.now
        )
        #expect(content == .weather(text: "72°", symbol: "sun.max.fill"))

        let night = NookSideSlotContent.resolvedWeather(
            report: Self.report(celsius: 4, code: 3, isDay: false), hasPlace: true, unit: .celsius, now: Self.now
        )
        #expect(night == .weather(text: "4°", symbol: "cloud.fill"))
    }

    @Test func noCityNoReportOrAnOldReportShowNothing() {
        let fresh = Self.report(celsius: 22)
        #expect(NookSideSlotContent.resolvedWeather(report: fresh, hasPlace: false, unit: .celsius, now: Self.now) == nil)
        #expect(NookSideSlotContent.resolvedWeather(report: nil, hasPlace: true, unit: .celsius, now: Self.now) == nil)

        let old = Self.report(celsius: 22, age: NookSideSlotContent.weatherMaxAge + 1)
        #expect(NookSideSlotContent.resolvedWeather(report: old, hasPlace: true, unit: .celsius, now: Self.now) == nil)
        let justInside = Self.report(celsius: 22, age: NookSideSlotContent.weatherMaxAge - 60)
        #expect(NookSideSlotContent.resolvedWeather(report: justInside, hasPlace: true, unit: .celsius, now: Self.now) != nil)
    }

    @Test func belowZeroKeepsItsSignAndNeverReadsMinusZero() {
        let cold = NookSideSlotContent.resolvedWeather(
            report: Self.report(celsius: -5.4), hasPlace: true, unit: .celsius, now: Self.now
        )
        #expect(cold == .weather(text: "-5°", symbol: "sun.max.fill"))
        let nearZero = NookSideSlotContent.resolvedWeather(
            report: Self.report(celsius: -0.2), hasPlace: true, unit: .celsius, now: Self.now
        )
        #expect(nearZero == .weather(text: "0°", symbol: "sun.max.fill"))
    }
}

struct NookSideSlotTimerTests {
    @Test(arguments: [
        (1500.0, "25m"), (1499.2, "25m"), (61.0, "2m"), (60.0, "60s"), (59.0, "59s"), (0.4, "1s"),
        (3600.0, "1h"), (7200.0, "2h"), (5400.0, "1h"),
    ])
    func theTimeLeftIsShortAndRoundsUp(remaining: TimeInterval, text: String) {
        #expect(NookSideSlotContent.timerText(remaining: remaining, isActive: true) == text)
    }

    @Test func noTimerRunningShowsNothing() {
        #expect(NookSideSlotContent.timerText(remaining: 1500, isActive: false) == nil)
        #expect(NookSideSlotContent.timerText(remaining: 0, isActive: true) == nil)
    }

    /// The timer's own notice takes both wings while it runs and notices are
    /// on, and the pill hides a side's item under any activity, which keeps
    /// the time from being drawn twice.
    @Test func aRunningTimerNoticeCoversTheSideItem() {
        let activity = NookClosedActivity.resolve(
            transient: nil,
            timerText: "24:59",
            media: nil,
            preferences: NookDisplayPreferences()
        )
        #expect(activity?.trailing == .text("24:59"))
        #expect(activity?.yieldsToAgents == false)

        var quiet = NookDisplayPreferences()
        quiet.showsNotices = false
        #expect(NookClosedActivity.resolve(transient: nil, timerText: "24:59", media: nil, preferences: quiet) == nil)
    }
}

@MainActor
struct NookSideSlotTodoTests {
    private static func item(_ id: String, done: Bool = false) -> NookTodoItem {
        NookTodoItem(id: id, title: id, dueDate: nil, isCompleted: done, listName: "List")
    }

    @Test func theOpenTasksAreCounted() {
        let items = [Self.item("a"), Self.item("b", done: true), Self.item("c"), Self.item("d")]
        #expect(NookSideSlotContent.resolvedTodos(items: items, connection: .ready) == .todos(3))
    }

    @Test func noSourceOrNothingOpenShowsNothing() {
        let items = [Self.item("a")]
        #expect(NookSideSlotContent.resolvedTodos(items: items, connection: .unavailable(message: "Reminders access needed")) == nil)
        #expect(NookSideSlotContent.resolvedTodos(items: [], connection: .ready) == nil)
        #expect(NookSideSlotContent.resolvedTodos(items: [Self.item("a", done: true)], connection: .ready) == nil)
    }

    @Test func aLongCountStopsAtNinetyNinePlus() {
        #expect(NookSideSlotContent.todosText(7) == "7")
        #expect(NookSideSlotContent.todosText(99) == "99")
        #expect(NookSideSlotContent.todosText(100) == "99+")
    }
}

struct NookSideSlotSavingTests {
    @Test func theNewSlotsDoNotNeedAgentsAndStayWhenTheyAreOff() {
        for slot in [NookSideSlot.weather, .timer, .todos] {
            #expect(!slot.needsAgents)
            #expect(AgentsSwitch.shown(slot, agentsEnabled: false) == slot)
        }
    }

    @Test func aSavedNewSlotLoadsBack() {
        let defaults = MemoryDefaults()
        var preferences = NookDisplayPreferences()
        preferences.leftSlot = .todos
        preferences.rightSlot = .weather
        preferences.persist(for: .notch, defaults: defaults)

        let loaded = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        #expect(loaded.leftSlot == .todos)
        #expect(loaded.rightSlot == .weather)
    }

    /// What an older build does with a value this build saved: its
    /// `NookSideSlot(rawValue:)` is nil for "weather". The left stays on the
    /// bars and the right gives the side back to the island's own slot. The
    /// same read here, with a raw value no build knows.
    @Test func aValueNoBuildKnowsLoadsAsTheDefaultAndDoesNotCrash() {
        let defaults = MemoryDefaults()
        defaults.set("sunrise", forKey: "nook.display.notch.leftSlot")
        defaults.set("sunrise", forKey: "nook.display.notch.rightSlot")

        let loaded = NookDisplayPreferences.load(for: .notch, defaults: defaults)
        #expect(loaded.leftSlot == .agents)
        #expect(loaded.rightSlot == nil)
        #expect(NookSideSlot(rawValue: "sunrise") == nil)
    }

    @Test func theNewRawValuesAreStable() {
        #expect(NookSideSlot.weather.rawValue == "weather")
        #expect(NookSideSlot.timer.rawValue == "timer")
        #expect(NookSideSlot.todos.rawValue == "todos")
    }
}
