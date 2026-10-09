import Foundation
import Testing
@testable import OpenIslandApp

struct NookEventQuickAddTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        return calendar
    }()

    /// Wednesday 2026-10-07 09:00 local.
    private static let now = stamp(2026, 10, 7, 9, 0)

    private static func stamp(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private func parse(_ text: String, on day: Date = NookEventQuickAddTests.stamp(2026, 10, 7)) -> NookEventDraft? {
        NookEventQuickAdd.parse(text, on: day, now: Self.now, calendar: Self.calendar)
    }

    private func expectTimed(_ text: String, _ start: Date, _ end: Date, title: String? = nil) {
        let draft = parse(text)
        #expect(draft?.isAllDay == false)
        #expect(draft?.start == start)
        #expect(draft?.end == end)
        if let title { #expect(draft?.title == title) }
    }

    private func expectAllDay(_ text: String, title: String) {
        let draft = parse(text)
        #expect(draft?.isAllDay == true)
        #expect(draft?.title == title)
        #expect(draft?.start == Self.stamp(2026, 10, 7))
        #expect(draft?.end == Self.stamp(2026, 10, 8))
    }

    // MARK: Basics

    @Test func emptyInputReturnsNil() {
        #expect(parse("") == nil)
        #expect(parse("   \n ") == nil)
    }

    @Test func plainTitleIsAllDayOnPickedDay() {
        expectAllDay("Study group", title: "Study group")
    }

    @Test func onlyATimeFallsBackToDefaultTitle() {
        expectTimed("3pm", Self.stamp(2026, 10, 7, 15), Self.stamp(2026, 10, 7, 16), title: "New event")
    }

    @Test func usesPickedDayWhenTextNamesNone() {
        let picked = Self.stamp(2026, 10, 20)
        let draft = parse("lunch 1pm", on: picked)
        #expect(draft?.start == Self.stamp(2026, 10, 20, 13))
        #expect(draft?.title == "Lunch")
    }

    // MARK: Single times

    @Test(arguments: [("lunch 1pm", 13, 0), ("lunch 1 pm", 13, 0), ("lunch 1:30pm", 13, 30),
                      ("lunch 1:30 PM", 13, 30), ("lunch 13:00", 13, 0), ("lunch 12am", 0, 0), ("lunch 12pm", 12, 0)])
    func parsesSingleTimes(text: String, hour: Int, minute: Int) {
        let start = Self.stamp(2026, 10, 7, hour, minute)
        expectTimed(text, start, start.addingTimeInterval(3600), title: "Lunch")
    }

    @Test func parsesNoonAndMidnight() {
        expectTimed("lunch at noon", Self.stamp(2026, 10, 7, 12), Self.stamp(2026, 10, 7, 13), title: "Lunch")
        expectTimed("party midnight", Self.stamp(2026, 10, 7, 0), Self.stamp(2026, 10, 7, 1), title: "Party")
    }

    @Test(arguments: [("meet at 3", 15), ("meet at 7", 19), ("meet at 8", 8), ("meet at 11", 11), ("meet at 12", 12)])
    func bareHourAfterAt(text: String, hour: Int) {
        expectTimed(text, Self.stamp(2026, 10, 7, hour), Self.stamp(2026, 10, 7, hour + 1), title: "Meet")
    }

    @Test func timeCanLeadTheText() {
        expectTimed("1pm lunch with Sam", Self.stamp(2026, 10, 7, 13), Self.stamp(2026, 10, 7, 14), title: "Lunch with Sam")
    }

    // MARK: Ranges

    @Test func parsesRangesWithMeridiems() {
        expectTimed("class 1-2pm", Self.stamp(2026, 10, 7, 13), Self.stamp(2026, 10, 7, 14), title: "Class")
        expectTimed("class 1pm-2pm", Self.stamp(2026, 10, 7, 13), Self.stamp(2026, 10, 7, 14), title: "Class")
        expectTimed("class 1:30 to 3pm", Self.stamp(2026, 10, 7, 13, 30), Self.stamp(2026, 10, 7, 15), title: "Class")
        expectTimed("class 11am-1pm", Self.stamp(2026, 10, 7, 11), Self.stamp(2026, 10, 7, 13), title: "Class")
    }

    @Test func startInheritsMeridiemUnlessItWouldPassTheEnd() {
        expectTimed("class 11-1pm", Self.stamp(2026, 10, 7, 11), Self.stamp(2026, 10, 7, 13))
        expectTimed("class 9-10pm", Self.stamp(2026, 10, 7, 21), Self.stamp(2026, 10, 7, 22))
    }

    @Test func bareRangeAfterAt() {
        expectTimed("lab at 9-10", Self.stamp(2026, 10, 7, 9), Self.stamp(2026, 10, 7, 10), title: "Lab")
        expectTimed("dinner from 6 to 8pm", Self.stamp(2026, 10, 7, 18), Self.stamp(2026, 10, 7, 20), title: "Dinner")
    }

    @Test func rangeCrossingMidnightEndsNextDay() {
        expectTimed("party 10pm-2am", Self.stamp(2026, 10, 7, 22), Self.stamp(2026, 10, 8, 2), title: "Party")
    }

    @Test func bareNumbersWithoutMarkersAreNotRanges() {
        expectAllDay("CS 180-200 review", title: "CS 180-200 review")
    }

    // MARK: Duration

    @Test(arguments: [("for 30m", 1800.0), ("for 45 min", 2700.0), ("for 2h", 7200.0),
                      ("for 1.5 hours", 5400.0), ("for 90 minutes", 5400.0)])
    func parsesDurations(suffix: String, seconds: Double) {
        let start = Self.stamp(2026, 10, 7, 13)
        expectTimed("sync 1pm \(suffix)", start, start.addingTimeInterval(seconds), title: "Sync")
    }

    @Test func rangeWinsOverDuration() {
        expectTimed("sync 1-2pm for 3h", Self.stamp(2026, 10, 7, 13), Self.stamp(2026, 10, 7, 14), title: "Sync")
    }

    // MARK: Days

    @Test func parsesTodayTomorrowAndTmrw() {
        expectAllDay("gym today", title: "Gym")
        #expect(parse("gym tomorrow")?.start == Self.stamp(2026, 10, 8))
        #expect(parse("gym tmrw")?.start == Self.stamp(2026, 10, 8))
        #expect(parse("gym TOMORROW 6pm")?.start == Self.stamp(2026, 10, 8, 18))
    }

    @Test func weekdaysResolveToNextOccurrence() {
        #expect(parse("lunch fri")?.start == Self.stamp(2026, 10, 9))
        #expect(parse("lunch on friday")?.start == Self.stamp(2026, 10, 9))
        #expect(parse("lunch sat")?.start == Self.stamp(2026, 10, 10))
        #expect(parse("lunch next mon")?.start == Self.stamp(2026, 10, 12))
        #expect(parse("lunch on friday")?.title == "Lunch")
    }

    @Test func fridayWithTimeCombines() {
        expectTimed("lunch fri 1pm", Self.stamp(2026, 10, 9, 13), Self.stamp(2026, 10, 9, 14), title: "Lunch")
    }

    @Test func nextWednesdayOnAWednesdayIsAWeekOut() {
        #expect(parse("review next wed")?.start == Self.stamp(2026, 10, 14))
        #expect(parse("review next wed")?.title == "Review")
        #expect(parse("review wed")?.start == Self.stamp(2026, 10, 14))
    }

    @Test func todaysWeekdayWithLaterTimeMeansToday() {
        #expect(parse("review wed 3pm")?.start == Self.stamp(2026, 10, 7, 15))
        #expect(parse("review wed 8am")?.start == Self.stamp(2026, 10, 14, 8))
        #expect(parse("review next wed 3pm")?.start == Self.stamp(2026, 10, 14, 15))
    }

    @Test func parsesMonthDates() {
        #expect(parse("exam oct 12")?.start == Self.stamp(2026, 10, 12))
        #expect(parse("exam October 12")?.start == Self.stamp(2026, 10, 12))
        #expect(parse("exam 10/12")?.start == Self.stamp(2026, 10, 12))
        #expect(parse("exam on oct 12th")?.title == "Exam")
        #expect(parse("exam dec 5pm")?.start == Self.stamp(2026, 10, 7, 17))
    }

    @Test func monthDateWithTime() {
        expectTimed("dentist oct 12 at 3", Self.stamp(2026, 10, 12, 15), Self.stamp(2026, 10, 12, 16), title: "Dentist")
    }

    @Test func pastMonthDateRollsToNextYear() {
        #expect(parse("trip oct 1")?.start == Self.stamp(2027, 10, 1))
        #expect(parse("trip 3/4")?.start == Self.stamp(2027, 3, 4))
        #expect(parse("trip oct 7")?.start == Self.stamp(2026, 10, 7))
    }

    @Test func impossibleDatesStayInTheTitle() {
        expectAllDay("trip 2/30", title: "Trip 2/30")
    }

    // MARK: Must not match

    @Test(arguments: ["Chat with Sam", "Friend dinner", "Saturn project", "Market run", "Afternoon walk",
                      "CS 180 homework", "Ling 132 reading"])
    func wordsContainingTokensStayInTheTitle(text: String) {
        expectAllDay(text, title: text)
    }

    @Test func courseNumbersDoNotBecomeTimes() {
        expectTimed("CS 180 at 5", Self.stamp(2026, 10, 7, 17), Self.stamp(2026, 10, 7, 18), title: "CS 180")
        expectTimed("Ling 132 5pm", Self.stamp(2026, 10, 7, 17), Self.stamp(2026, 10, 7, 18), title: "Ling 132")
    }

    @Test func connectivesInsideWordsSurvive() {
        expectTimed("Chat at 3 with Sam", Self.stamp(2026, 10, 7, 15), Self.stamp(2026, 10, 7, 16), title: "Chat with Sam")
    }

    // MARK: The add form

    @Test func aDayInTheTextIsNoticed() {
        func namesDay(_ text: String) -> Bool {
            NookEventQuickAdd.namesDay(text, now: Self.now, calendar: Self.calendar)
        }

        #expect(namesDay("dinner fri 7pm"))
        #expect(namesDay("dentist 5/12"))
        #expect(namesDay("call mom tomorrow"))
        #expect(namesDay("trip may 3"))
        #expect(!namesDay("dinner 7pm"))
        #expect(!namesDay("standup"))
        #expect(!namesDay(""))
    }

    @Test func aDayInTheTextWinsOverTheDayPickedInTheForm() {
        let friday = parse("dinner fri 7pm", on: Self.stamp(2026, 10, 20))
        let picked = parse("dinner 7pm", on: Self.stamp(2026, 10, 20))

        #expect(friday?.start == Self.stamp(2026, 10, 9, 19))
        #expect(picked?.start == Self.stamp(2026, 10, 20, 19))
    }

    @Test func theSummarySaysWhatWillBeSaved() throws {
        let locale = Locale(identifier: "en_US")
        // Newer systems put a narrow no-break space before AM and PM.
        func plain(_ text: String) -> String {
            text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
        }

        let timed = try #require(parse("dinner fri 7pm"))
        // The next May 12 after October 2026 is in 2027, a Wednesday.
        let allDay = try #require(parse("dentist 5/12"))

        #expect(plain(timed.summary(now: Self.now, calendar: Self.calendar, locale: locale)) == "Fri, Oct 9, 7:00 PM to 8:00 PM")
        // A day in another year says which year.
        #expect(plain(allDay.summary(now: Self.now, calendar: Self.calendar, locale: locale)) == "Wed, May 12, 2027, all day")
    }
}
