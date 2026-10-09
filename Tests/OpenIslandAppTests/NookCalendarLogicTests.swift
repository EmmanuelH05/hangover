import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

@Suite struct NookCalendarLogicTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .current
        return calendar
    }()

    private static func stamp(_ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)) ?? Date()
    }

    private static func event(_ title: String, _ start: Date, _ end: Date, allDay: Bool = false) -> NookCalendarEvent {
        NookCalendarEvent(id: title, title: title, start: start, end: end, isAllDay: allDay, calendarColor: .blue, location: nil)
    }

    // MARK: Quick add

    @Test func capitalSATIsAnExamNotSaturday() {
        let day = Self.stamp(7)
        let exam = NookEventQuickAdd.parse("SAT prep", on: day, now: Self.stamp(7, 9), calendar: Self.calendar)
        let weekday = NookEventQuickAdd.parse("gym sat", on: day, now: Self.stamp(7, 9), calendar: Self.calendar)

        #expect(exam?.title == "SAT prep")
        #expect(exam?.start == day)
        #expect(weekday?.start == Self.stamp(10))
    }

    @Test func absurdDurationFallsBackToTheDefaultLength() {
        let digits = String(repeating: "9", count: 320)
        let draft = NookEventQuickAdd.parse("study 1pm for \(digits) hours", on: Self.stamp(7), now: Self.stamp(7, 9), calendar: Self.calendar)

        #expect(draft?.start == Self.stamp(7, 13))
        #expect(draft?.end == Self.stamp(7, 14))
    }

    // MARK: Month grid

    @Test func multiDayEventMarksEveryDayItCovers() {
        let trip = Self.event("Trip", Self.stamp(9), Self.stamp(12), allDay: true)
        let late = Self.event("Late", Self.stamp(14, 22), Self.stamp(15, 2))
        let single = Self.event("Class", Self.stamp(20, 10), Self.stamp(20, 11))

        let grouped = NookCalendarMonthView.group([trip, late, single], calendar: Self.calendar)

        #expect(grouped[Self.stamp(9)]?.count == 1)
        #expect(grouped[Self.stamp(10)]?.count == 1)
        #expect(grouped[Self.stamp(11)]?.count == 1)
        #expect(grouped[Self.stamp(12)] == nil)
        #expect(grouped[Self.stamp(14)]?.first?.title == "Late")
        #expect(grouped[Self.stamp(15)]?.first?.title == "Late")
        #expect(grouped[Self.stamp(20)]?.count == 1)
        #expect(grouped[Self.stamp(21)] == nil)
    }

    @Test func zeroLengthEventStillMarksItsDay() {
        let ping = Self.event("Ping", Self.stamp(7, 9), Self.stamp(7, 9))

        #expect(NookCalendarMonthView.group([ping], calendar: Self.calendar)[Self.stamp(7)]?.count == 1)
    }

    // MARK: Timer

    @Test @MainActor func timerFormatsHoursOnlyFromOneHourUp() {
        #expect(NookFocusTimer.format(59 * 60 + 59) == "59:59")
        #expect(NookFocusTimer.format(90 * 60) == "1:30:00")
    }

    @Test @MainActor func nextEventTargetSkipsAllDayAndFarEvents() {
        let now = Self.stamp(7, 9)
        let allDay = Self.event("Holiday", Self.stamp(7), Self.stamp(8), allDay: true)
        let soon = Self.event("Class", Self.stamp(7, 10), Self.stamp(7, 11))
        let far = Self.event("Dinner", Self.stamp(7, 19), Self.stamp(7, 20))

        #expect(NookFocusTimer.nextEventTarget(events: [allDay, soon, far], now: now)?.title == "Class")
        #expect(NookFocusTimer.nextEventTarget(events: [allDay, far], now: now) == nil)
    }
}
