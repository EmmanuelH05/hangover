import Foundation
import Testing
@testable import OpenIslandApp

/// The pure model behind the event editor.
@Suite struct NookEventFormTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }()

    private static let locale = Locale(identifier: "en_US")

    /// Wednesday 2026-10-07 09:10 local.
    private static let now = stamp(2026, 10, 7, 9, 10)

    private static func stamp(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private static func form(on day: Date = stamp(2026, 10, 9)) -> NookEventForm {
        NookEventForm.new(on: day, now: now, calendar: calendar)
    }

    /// Newer systems put a narrow no-break space before AM and PM.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    // MARK: A fresh form

    @Test func todayStartsAtTheNextHalfHour() {
        let form = NookEventForm.new(on: Self.now, now: Self.now, calendar: Self.calendar)

        #expect(form.day == Self.stamp(2026, 10, 7))
        #expect(form.startMinute == 9 * 60 + 30)
        #expect(form.durationMinutes == 60)
        #expect(form.isAllDay == false)
    }

    @Test func anotherDayStartsAtNine() {
        let form = Self.form()

        #expect(form.day == Self.stamp(2026, 10, 9))
        #expect(form.startMinute == 9 * 60)
    }

    @Test func lateAtNightStaysOnToday() {
        let late = Self.stamp(2026, 10, 7, 23, 50)
        let form = NookEventForm.new(on: late, now: late, calendar: Self.calendar)

        #expect(form.day == Self.stamp(2026, 10, 7))
        #expect(form.startMinute == 23 * 60 + 30)
    }

    // MARK: What gets saved

    @Test func theDraftCarriesEveryField() {
        var form = Self.form()
        form.title = "  Dinner with Sam  "
        form.location = " Westwood "
        form.notes = "Bring the notes\n"
        form.calendarID = "home"
        form.alert = .fifteenMinutes
        form.repeats = .weekly
        let draft = form.settingStart(minute: 19 * 60).settingDuration(minutes: 90).draft(calendar: Self.calendar)

        #expect(draft.title == "Dinner with Sam")
        #expect(draft.start == Self.stamp(2026, 10, 9, 19))
        #expect(draft.end == Self.stamp(2026, 10, 9, 20, 30))
        #expect(draft.isAllDay == false)
        #expect(draft.location == "Westwood")
        #expect(draft.notes == "Bring the notes")
        #expect(draft.calendarID == "home")
        #expect(draft.alert == .fifteenMinutes)
        #expect(draft.repeats == .weekly)
    }

    @Test func anAllDayDraftCoversTheWholeDay() {
        var form = Self.form().settingAllDay(true)
        form.title = "Midterm"
        let draft = form.draft(calendar: Self.calendar)

        #expect(draft.isAllDay)
        #expect(draft.start == Self.stamp(2026, 10, 9))
        #expect(draft.end == Self.stamp(2026, 10, 10))
    }

    @Test func anEventCanRunPastMidnight() {
        let form = Self.form().settingStart(minute: 23 * 60).settingDuration(minutes: 120)

        #expect(form.end(calendar: Self.calendar) == Self.stamp(2026, 10, 10, 1))
    }

    @Test func aBlankTitleCannotBeSaved() {
        var form = Self.form()
        #expect(!form.canSave)
        #expect(!form.hasContent)

        form.title = "   "
        #expect(!form.canSave)

        form.notes = "remember this"
        #expect(form.hasContent)
        #expect(!form.canSave)

        form.title = "Call"
        #expect(form.canSave)
    }

    // MARK: Changes

    @Test func pickingATimeEndsAllDay() {
        let allDay = Self.form().settingAllDay(true)

        #expect(allDay.settingStart(minute: 600).isAllDay == false)
        #expect(allDay.settingDuration(minutes: 30).isAllDay == false)
    }

    @Test func timesAreKeptInsideTheDay() {
        let form = Self.form()

        #expect(form.settingStart(minute: -30).startMinute == 0)
        #expect(form.settingStart(minute: 5000).startMinute == 24 * 60 - 15)
        #expect(form.settingDuration(minutes: 0).durationMinutes == 15)
        #expect(form.settingDuration(minutes: 99_999).durationMinutes == 24 * 60)
    }

    // MARK: Alerts

    @Test func allDayEventsOfferTheirOwnAlerts() {
        #expect(NookEventAlert.options(isAllDay: true) == [.none, .atStart, .oneDay])
        #expect(NookEventAlert.options(isAllDay: false) == NookEventAlert.allCases)
    }

    @Test func switchingToAllDayMovesAnAlertItCannotKeep() {
        var form = Self.form()
        form.alert = .fifteenMinutes

        #expect(form.settingAllDay(true).alert == .atStart)

        form.alert = .oneDay
        #expect(form.settingAllDay(true).alert == .oneDay)

        form.alert = .none
        #expect(form.settingAllDay(true).alert == .none)
    }

    @Test func alertOffsetsCountFromTheStart() {
        #expect(NookEventAlert.none.offset(isAllDay: false) == nil)
        #expect(NookEventAlert.atStart.offset(isAllDay: false) == 0)
        #expect(NookEventAlert.fifteenMinutes.offset(isAllDay: false) == -900)
        #expect(NookEventAlert.oneHour.offset(isAllDay: false) == -3600)
        #expect(NookEventAlert.oneDay.offset(isAllDay: false) == -86_400)
        // All-day events start at midnight; their alerts ring at nine.
        #expect(NookEventAlert.atStart.offset(isAllDay: true) == 32_400)
        #expect(NookEventAlert.oneDay.offset(isAllDay: true) == -54_000)
    }

    // MARK: The start-time menu

    @Test func thePartsOfTheDayCoverEveryQuarterHourOnce() {
        let minutes = NookEventDayPart.allCases.flatMap(\.minutes)

        #expect(minutes.count == 96)
        #expect(Set(minutes).count == 96)
        #expect(minutes.min() == 0)
        #expect(minutes.max() == 24 * 60 - 15)
        #expect(NookEventDayPart.morning.minutes.first == 6 * 60)
        #expect(NookEventDayPart.evening.minutes.first == 18 * 60)
    }

    @Test func lengthsReadNaturally() {
        #expect(NookEventText.duration(minutes: 15) == "15 min")
        #expect(NookEventText.duration(minutes: 45) == "45 min")
        #expect(NookEventText.duration(minutes: 60) == "1 hr")
        #expect(NookEventText.duration(minutes: 90) == "1.5 hr")
        #expect(NookEventText.duration(minutes: 480) == "8 hr")
    }

    // MARK: A time or a day typed into the title

    @Test func aPlainTitleSuggestsNothing() {
        var form = Self.form()
        form.title = "Standup"

        #expect(form.suggestion(now: Self.now, calendar: Self.calendar) == nil)
    }

    @Test func aTitleWithADayAndATimeIsOfferedAndTakingItCleansTheTitle() throws {
        var form = Self.form(on: Self.stamp(2026, 10, 20))
        form.title = "dinner fri 7pm"
        let suggestion = try #require(form.suggestion(now: Self.now, calendar: Self.calendar))

        let taken = form.applying(suggestion, calendar: Self.calendar)

        #expect(taken.title == "Dinner")
        #expect(taken.day == Self.stamp(2026, 10, 9))
        #expect(taken.startMinute == 19 * 60)
        #expect(taken.durationMinutes == 60)
        #expect(taken.isAllDay == false)
        // Nothing is left to offer once it is taken.
        #expect(taken.suggestion(now: Self.now, calendar: Self.calendar) == nil)
    }

    @Test func aTitleWithOnlyADayMovesTheDayAndLeavesTheTimes() throws {
        var form = Self.form(on: Self.stamp(2026, 10, 20)).settingStart(minute: 14 * 60)
        form.title = "dentist 5/12"
        let suggestion = try #require(form.suggestion(now: Self.now, calendar: Self.calendar))

        let taken = form.applying(suggestion, calendar: Self.calendar)

        #expect(taken.title == "Dentist")
        #expect(taken.day == Self.stamp(2027, 5, 12))
        #expect(taken.startMinute == 14 * 60)
        #expect(taken.isAllDay == false)
    }

    @Test func nothingChangesUntilTheSuggestionIsTaken() {
        var form = Self.form(on: Self.stamp(2026, 10, 20))
        let before = form
        form.title = "lunch at 12"

        #expect(form.day == before.day)
        #expect(form.startMinute == before.startMinute)
        #expect(form.draft(calendar: Self.calendar).title == "lunch at 12")
    }

    @Test func aRangeInTheTitleSetsTheLength() throws {
        var form = Self.form()
        form.title = "review 2-3:30pm"
        let suggestion = try #require(form.suggestion(now: Self.now, calendar: Self.calendar))

        let taken = form.applying(suggestion, calendar: Self.calendar)

        #expect(taken.startMinute == 14 * 60)
        #expect(taken.durationMinutes == 90)
    }

    // MARK: The line that says what will be saved

    @Test func theSummarySaysWhatWillBeSaved() {
        var form = Self.form().settingStart(minute: 19 * 60)
        form.title = "Dinner"

        let timed = form.draft(calendar: Self.calendar)
            .summary(now: Self.now, calendar: Self.calendar, locale: Self.locale)
        let allDay = form.settingAllDay(true).draft(calendar: Self.calendar)
            .summary(now: Self.now, calendar: Self.calendar, locale: Self.locale)
        var nextYear = form
        nextYear.day = Self.stamp(2027, 5, 12)
        let later = nextYear.draft(calendar: Self.calendar)
            .summary(now: Self.now, calendar: Self.calendar, locale: Self.locale)

        #expect(Self.plain(timed) == "Fri, Oct 9, 7:00 PM to 8:00 PM")
        #expect(Self.plain(allDay) == "Fri, Oct 9, all day")
        // A day in another year says which year.
        #expect(Self.plain(later) == "Wed, May 12, 2027, 7:00 PM to 8:00 PM")
    }
}
