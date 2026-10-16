import Foundation
import Testing
@testable import OpenIslandApp

/// The days the date menu offers, the whole-day helpers behind every source,
/// and the words on the date button (D69).
@Suite struct NookTodoDueChoicesTests {
    private typealias F = NookTodoDueFixtures

    // MARK: The menu

    @Test func theMenuIsTodayTomorrowThenTheNextFiveDays() {
        let calendar = F.calendar()

        let options = NookTodoDueChoices.options(now: F.moment(14, 10, 30, in: calendar), calendar: calendar)

        #expect(options.map(\.kind) == [.today, .tomorrow, .day, .day, .day, .day, .day])
        #expect(options.map(\.day) == [14, 15, 16, 17, 18, 19, 20].map { F.day(2026, 10, $0) })
    }

    @Test func theTimeOfDayNeverMovesTheDays() {
        let calendar = F.calendar()

        let late = NookTodoDueChoices.options(now: F.moment(14, 23, 59, in: calendar), calendar: calendar)
        let early = NookTodoDueChoices.options(now: F.moment(14, 0, 1, in: calendar), calendar: calendar)

        #expect(late == early)
        #expect(late.first?.day == F.day(2026, 10, 14))
    }

    @Test func theDaysRollOverTheEndOfAMonthAndTheYear() {
        let calendar = F.calendar()

        let october = NookTodoDueChoices.options(now: F.moment(29, 12, in: calendar), calendar: calendar)
        let december = NookTodoDueChoices.options(now: F.moment(30, 12, month: 12, in: calendar), calendar: calendar)

        #expect(october.map(\.day) == [
            F.day(2026, 10, 29), F.day(2026, 10, 30), F.day(2026, 10, 31),
            F.day(2026, 11, 1), F.day(2026, 11, 2), F.day(2026, 11, 3), F.day(2026, 11, 4),
        ])
        #expect(december.map(\.day) == [
            F.day(2026, 12, 30), F.day(2026, 12, 31), F.day(2027, 1, 1),
            F.day(2027, 1, 2), F.day(2027, 1, 3), F.day(2027, 1, 4), F.day(2027, 1, 5),
        ])
    }

    @Test func aDaylightSavingChangeSkipsNoDayAndRepeatsNone() {
        // US clocks fall back on Sunday, November 1, 2026.
        let calendar = F.calendar()

        let options = NookTodoDueChoices.options(now: F.moment(31, 12, in: calendar), calendar: calendar)

        #expect(options.map(\.day) == [
            F.day(2026, 10, 31), F.day(2026, 11, 1), F.day(2026, 11, 2),
            F.day(2026, 11, 3), F.day(2026, 11, 4), F.day(2026, 11, 5), F.day(2026, 11, 6),
        ])
    }

    @Test func theDayIsTheOneOnTheCalendarsClock() {
        // 8 PM in Los Angeles is already the next morning in Tokyo.
        let instant = F.moment(14, 20, in: F.calendar("America/Los_Angeles"))
        let tokyo = F.calendar("Asia/Tokyo")

        let options = NookTodoDueChoices.options(now: instant, calendar: tokyo)

        #expect(options.first?.day == F.day(2026, 10, 15))
        #expect(options.first?.date == tokyo.startOfDay(for: instant))
    }

    @Test func eachChoiceCarriesTheStartOfItsDay() {
        let calendar = F.calendar()

        let options = NookTodoDueChoices.options(now: F.moment(14, 15, in: calendar), calendar: calendar)

        #expect(options.map(\.date) == (14...20).map { F.moment($0, in: calendar) })
    }

    @Test func eachChoiceHasAnIDOfItsOwn() {
        let calendar = F.calendar()

        let options = NookTodoDueChoices.options(now: F.moment(14, in: calendar), calendar: calendar)

        #expect(Set(options.map(\.id)).count == options.count)
    }

    // MARK: Words

    @Test func todayAndTomorrowAreNamedAndTheRestShowTheirDate() {
        let calendar = F.calendar()
        let lang = LanguageManager.shared

        let options = NookTodoDueChoices.options(now: F.moment(14, 9, in: calendar), calendar: calendar)
        let titles = options.map { $0.title(lang: lang, locale: F.english, calendar: calendar) }

        #expect(titles[0] == lang.t("nook.todo.due.today"))
        #expect(titles[1] == lang.t("nook.todo.due.tomorrow"))
        #expect(titles.dropFirst(2) == ["Fri, Oct 16", "Sat, Oct 17", "Sun, Oct 18", "Mon, Oct 19", "Tue, Oct 20"][...])
    }

    @Test func theButtonShowsTheWeekdayForTheComingWeekAndTheDateBeyond() {
        let calendar = F.calendar()
        let now = F.moment(14, 9, in: calendar)
        let lang = LanguageManager.shared

        func label(_ day: DateComponents) -> String {
            NookTodoDueChoices.buttonLabel(for: day, now: now, calendar: calendar, lang: lang, locale: F.english)
        }

        #expect(label(F.day(2026, 10, 14)) == lang.t("nook.todo.due.today"))
        #expect(label(F.day(2026, 10, 15)) == lang.t("nook.todo.due.tomorrow"))
        #expect(label(F.day(2026, 10, 16)) == "Fri")
        #expect(label(F.day(2026, 10, 20)) == "Tue")
        #expect(label(F.day(2026, 10, 21)) == "Oct 21")
        #expect(label(F.day(2027, 3, 4)) == "Mar 4")
    }

    // MARK: Whole days

    @Test func aDayIsYearMonthAndDayWithNoTime() {
        let calendar = F.calendar()

        let day = NookTodoDay.components(of: F.moment(16, 17, 45, in: calendar), calendar: calendar)

        #expect(day == F.day(2026, 10, 16))
        #expect(day.hour == nil && day.minute == nil)
    }

    @Test func aDayIsAlwaysGregorianWhateverCalendarTheUserPrefers() {
        // Notion and TickTick take Gregorian years. A Buddhist calendar counts 2569.
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Asia/Bangkok") ?? .gmt
        let instant = F.moment(16, 12, in: F.calendar("Asia/Bangkok"))

        let day = NookTodoDay.components(of: instant, calendar: buddhist)

        #expect(day == F.day(2026, 10, 16))
        #expect(NookTodoDay.isoString(day) == "2026-10-16")
    }

    @Test func theISOStringIsPaddedAndNeedsAFullDay() {
        #expect(NookTodoDay.isoString(F.day(2026, 3, 5)) == "2026-03-05")
        #expect(NookTodoDay.isoString(DateComponents(year: 2026, month: 3)) == nil)
        #expect(NookTodoDay.isoString(DateComponents(month: 3, day: 5)) == nil)
        #expect(NookTodoDay.isoString(nil) == nil)
    }

    @Test func normalizingKeepsOnlyARealDay() {
        let withTime = DateComponents(year: 2026, month: 10, day: 16, hour: 15, minute: 30)

        #expect(NookTodoDay.normalized(withTime) == F.day(2026, 10, 16))
        #expect(NookTodoDay.normalized(F.day(2026, 2, 30)) == nil)
        #expect(NookTodoDay.normalized(F.day(2026, 13, 1)) == nil)
        #expect(NookTodoDay.normalized(DateComponents(year: 2026, month: 10)) == nil)
        #expect(NookTodoDay.normalized(nil) == nil)
    }

    @Test func aDayBecomesTheStartOfThatDayOnTheCalendarsClock() {
        let calendar = F.calendar()

        let date = NookTodoDay.date(from: F.day(2026, 10, 16), calendar: calendar)

        #expect(date == F.moment(16, in: calendar))
        #expect(NookTodoDay.date(from: DateComponents(year: 2026), calendar: calendar) == nil)
    }

    @Test func theKeyOfADaySortsInTimeOrder() {
        let calendar = F.calendar()

        let keys = [F.moment(9, in: calendar), F.moment(10, in: calendar), F.moment(2, month: 11, in: calendar)]
            .map { NookTodoDay.key(of: $0, calendar: calendar) }

        #expect(keys == ["2026-10-09", "2026-10-10", "2026-11-02"])
        #expect(keys == keys.sorted())
    }
}
