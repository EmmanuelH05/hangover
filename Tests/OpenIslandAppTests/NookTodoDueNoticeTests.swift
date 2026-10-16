import Foundation
import Testing
@testable import OpenIslandApp

/// The notice for a to-do that is due today, the one for to-dos past their
/// date, and the record of what was already shown (D69).
@Suite struct NookTodoDueNoticeTests {
    private typealias F = NookTodoDueFixtures
    private let lang = LanguageManager.shared

    /// The 14th of October 2026 is a Wednesday. Ten in the morning unless a
    /// test says otherwise.
    private func notices(
        _ items: [NookTodoItem],
        at moment: Date? = nil,
        calendar: Calendar = F.calendar(),
        shown: NookTodoDueShown = NookTodoDueShown(),
        remindAt: NookTodoDueTime = .morning
    ) -> [NookTodoDueNotice] {
        NookTodoDueNotice.notices(
            items: items,
            now: moment ?? F.moment(14, 10, in: calendar),
            calendar: calendar,
            shown: shown,
            remindAt: remindAt
        )
    }

    private func dueToday(_ id: String, _ title: String = "Task", hour: Int = 0) -> NookTodoItem {
        F.item(id, title, due: F.moment(14, hour, in: F.calendar()))
    }

    private func dueOn(_ day: Int, _ id: String, month: Int = 10) -> NookTodoItem {
        F.item(id, "Old \(id)", due: F.moment(day, month: month, in: F.calendar()))
    }

    // MARK: Due today

    @Test func oneToDoDueTodayNamesItself() {
        let result = notices([dueToday("a", "HW3")])

        #expect(result.map(\.wording) == [.oneDue(title: "HW3")])
        #expect(result.first?.itemIDs == ["a"])
        #expect(result.first?.text(lang: lang) == lang.t("nook.todo.due.notice.one", "HW3"))
    }

    @Test func severalDueTodayAreOneNoticeWithTheCount() {
        let result = notices([dueToday("a", "HW3"), dueToday("b", "Lab"), dueToday("c", "Essay")])

        #expect(result.map(\.wording) == [.manyDue(count: 3)])
        #expect(result.first?.itemIDs == ["a", "b", "c"])
        #expect(result.first?.text(lang: lang) == lang.t("nook.todo.due.notice.many", 3))
    }

    @Test func aTimeOnTheDueDateStillMeansThatDay() {
        // Notion can hold a time. Only the day counts.
        let evening = F.item("a", "HW3", due: F.moment(14, 23, 30, in: F.calendar()))
        let midnight = F.item("b", "Lab", due: F.moment(14, in: F.calendar()))

        #expect(notices([evening]).map(\.wording) == [.oneDue(title: "HW3")])
        #expect(notices([midnight]).map(\.wording) == [.oneDue(title: "Lab")])
    }

    @Test func tomorrowAndNoDateSayNothing() {
        let tomorrow = F.item("a", due: F.moment(15, in: F.calendar()))
        let undated = F.item("b")

        #expect(notices([tomorrow, undated]).isEmpty)
    }

    @Test func aCompletedToDoNeverSpeaks() {
        let done = F.item("a", due: F.moment(14, in: F.calendar()), done: true)
        let doneAndLate = F.item("b", due: F.moment(10, in: F.calendar()), done: true)

        #expect(notices([done, doneAndLate]).isEmpty)
    }

    @Test func theDayIsTheOneOnTheCalendarsClock() {
        // 8 PM in Los Angeles on the 14th is the morning of the 15th in Tokyo.
        let instant = F.moment(14, 20, in: F.calendar("America/Los_Angeles"))
        let tokyo = F.calendar("Asia/Tokyo")
        let dueInTokyo = F.item("a", "HW3", due: F.moment(15, in: tokyo))

        let result = notices([dueInTokyo], at: instant, calendar: tokyo, remindAt: NookTodoDueTime(hour: 0))

        #expect(result.map(\.wording) == [.oneDue(title: "HW3")])
    }

    // MARK: Overdue

    @Test func toDosPastTheirDateAreOneNoticeWithTheCount() {
        let result = notices([dueOn(12, "a"), dueOn(3, "b"), dueOn(13, "c")])

        #expect(result.map(\.wording) == [.overdue(count: 3)])
        #expect(result.first?.itemIDs == ["a", "b", "c"])
        #expect(result.first?.text(lang: lang) == lang.t("nook.todo.due.notice.overdue.many", 3))
    }

    @Test func oneToDoPastItsDateSaysOneNotAPlural() {
        let result = notices([dueOn(13, "a")])

        #expect(result.map(\.wording) == [.overdue(count: 1)])
        #expect(result.first?.text(lang: lang) == lang.t("nook.todo.due.notice.overdue.one"))
        #expect(lang.t("nook.todo.due.notice.overdue.one") != lang.t("nook.todo.due.notice.overdue.many", 1))
    }

    @Test func lateTonightIsNotOverdueUntilTheDayIsOver() {
        let lateToday = F.item("a", due: F.moment(14, 23, 59, in: F.calendar()))
        let lastNight = F.item("b", due: F.moment(13, 23, 59, in: F.calendar()))

        #expect(notices([lateToday]).map(\.wording) == [.oneDue(title: "Task")])
        #expect(notices([lastNight]).map(\.wording) == [.overdue(count: 1)])
    }

    @Test func dueTodayComesBeforeOverdue() {
        let result = notices([dueOn(12, "late"), dueToday("a", "HW3")])

        #expect(result.map(\.wording) == [.oneDue(title: "HW3"), .overdue(count: 1)])
    }

    // MARK: Once a day

    @Test func aToDoAlreadyShownTodayIsNotShownAgain() {
        let shown = NookTodoDueShown().recording(notices([dueToday("a", "HW3")]))

        #expect(notices([dueToday("a", "HW3")], shown: shown).isEmpty)
    }

    @Test func theOverdueNoticeIsShownOnceADay() {
        let items = [dueOn(12, "a")]
        let shown = NookTodoDueShown().recording(notices(items))

        #expect(notices(items, shown: shown).isEmpty)
        // A second one going overdue the same day does not bring it back.
        #expect(notices(items + [dueOn(13, "b")], shown: shown).isEmpty)
    }

    @Test func aToDoAddedLaterTodayGetsItsOwnNotice() {
        let morning = notices([dueToday("a", "HW3")])
        let shown = NookTodoDueShown().recording(morning)

        let afternoon = notices(
            [dueToday("a", "HW3"), dueToday("b", "Call mom")],
            at: F.moment(14, 15, in: F.calendar()),
            shown: shown
        )

        #expect(afternoon.map(\.wording) == [.oneDue(title: "Call mom")])
        #expect(afternoon.first?.itemIDs == ["b"])
    }

    @Test func manyAddedLaterCountOnlyTheNewOnes() {
        let shown = NookTodoDueShown().recording(notices([dueToday("a", "HW3")]))

        let later = notices([dueToday("a"), dueToday("b"), dueToday("c")], shown: shown)

        #expect(later.map(\.wording) == [.manyDue(count: 2)])
        #expect(later.first?.itemIDs == ["b", "c"])
    }

    @Test func recordingWhatWasShownSilencesTheSameInputs() {
        let items = [dueToday("a", "HW3"), dueToday("b", "Lab"), dueOn(11, "c")]
        let first = notices(items)

        let shown = NookTodoDueShown().recording(first)

        #expect(first.count == 2)
        #expect(notices(items, shown: shown).isEmpty)
    }

    @Test func aNewDayStartsWithNothingShown() {
        let late = dueOn(11, "late")
        let yesterday = NookTodoDueShown().recording(notices([late], at: F.moment(13, 10, in: F.calendar())))
        #expect(yesterday.hasShownOverdue(on: "2026-10-13"))

        let today = notices([dueToday("a", "HW3"), late], shown: yesterday)

        // Yesterday's overdue notice does not cover today's.
        #expect(today.map(\.wording) == [.oneDue(title: "HW3"), .overdue(count: 1)])
    }

    @Test func aToDoThatWasDueTodayIsOverdueTheNextDayAndCountedThere() {
        let dueDay = NookTodoDueShown().recording(notices([dueToday("a", "HW3")]))

        let nextDay = notices([dueToday("a", "HW3")], at: F.moment(15, 10, in: F.calendar()), shown: dueDay)

        #expect(nextDay.map(\.wording) == [.overdue(count: 1)])
    }

    // MARK: The hour

    @Test func nothingShowsBeforeNineInTheMorning() {
        let items = [dueToday("a"), dueOn(12, "late")]

        #expect(notices(items, at: F.moment(14, 0, in: F.calendar())).isEmpty)
        #expect(notices(items, at: F.moment(14, 8, 59, in: F.calendar())).isEmpty)
    }

    @Test func nineSharpAndAnyTimeAfterItShow() {
        let items = [dueToday("a", "HW3")]

        #expect(notices(items, at: F.moment(14, 9, 0, in: F.calendar())).count == 1)
        #expect(notices(items, at: F.moment(14, 9, 1, in: F.calendar())).count == 1)
        #expect(notices(items, at: F.moment(14, 23, 59, in: F.calendar())).count == 1)
    }

    @Test func theHourComesFromTheCaller() {
        let items = [dueToday("a", "HW3")]
        let seven = NookTodoDueTime(hour: 7)
        let halfPastNine = NookTodoDueTime(hour: 9, minute: 30)

        #expect(notices(items, at: F.moment(14, 7, in: F.calendar()), remindAt: seven).count == 1)
        #expect(notices(items, at: F.moment(14, 6, 59, in: F.calendar()), remindAt: seven).isEmpty)
        #expect(notices(items, at: F.moment(14, 9, 29, in: F.calendar()), remindAt: halfPastNine).isEmpty)
        #expect(notices(items, at: F.moment(14, 9, 30, in: F.calendar()), remindAt: halfPastNine).count == 1)
    }

    @Test func theHourIsOnTheCalendarsClockOnAClockChangeDay() {
        // US clocks fall back on Sunday, November 1, 2026, and the 9 AM that day is a normal 9 AM.
        let calendar = F.calendar()
        let sunday = F.item("a", "HW3", due: F.moment(1, month: 11, in: calendar))

        #expect(notices([sunday], at: F.moment(1, 8, 59, month: 11, in: calendar)).isEmpty)
        #expect(notices([sunday], at: F.moment(1, 9, month: 11, in: calendar)).count == 1)
    }

    // MARK: Words

    @Test func aLongTitleIsCutSoTheWordsAfterItStayInView() {
        let result = notices([dueToday("a", "Read chapter twelve of the book")])

        #expect(result.map(\.wording) == [.oneDue(title: "Read ch…")])
        #expect(NookTodoDueNotice.shortTitle("Short") == "Short")
        #expect(NookTodoDueNotice.shortTitle("Exactly8") == "Exactly8")
        #expect(NookTodoDueNotice.shortTitle("Nine char") == "Nine ch…")
        #expect(NookTodoDueNotice.shortTitle("  padded  ") == "padded")
    }

    @Test func aTitleWithNoWordsIsCalledUntitled() {
        let result = notices([dueToday("a", "  ")])

        #expect(result.first?.text(lang: lang) == lang.t("nook.todo.due.notice.one", lang.t("nook.todo.notion.untitled")))
    }

    @Test func theNoticeIsDrawnWithTheChecklistSymbol() {
        #expect(NookTodoDueNotice.symbol == "checklist")
    }

    @Test func theEnglishLinesHaveNoDashAndNoSo() throws {
        let table = try HangoverBrandTests.table("en")
        let lines = Self.noticeKeys.compactMap { table[$0] }

        #expect(lines.count == Self.noticeKeys.count)
        for line in lines {
            #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "\(line) has a dash")
            #expect(!line.lowercased().split(whereSeparator: { !$0.isLetter }).contains("so"), "\(line) says so")
        }
        #expect(table["nook.todo.due.notice.one"] == "%@ due today")
        #expect(table["nook.todo.due.notice.many"] == "%d to-dos due today")
        #expect(table["nook.todo.due.notice.overdue.one"] == "1 to-do overdue")
        #expect(table["nook.todo.due.notice.overdue.many"] == "%d to-dos overdue")
    }

    @Test(arguments: HangoverBrandTests.languages)
    func everyNoticeLineIsInEveryLanguageWithItsPlaceholder(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        let placeholders: [String: String] = [
            "nook.todo.due.notice.one": "%@",
            "nook.todo.due.notice.many": "%d",
            "nook.todo.due.notice.overdue.many": "%d",
        ]
        for key in Self.noticeKeys {
            let value = try #require(table[key], "\(language) is missing \(key)")
            #expect(!value.isEmpty)
            if let placeholder = placeholders[key] {
                #expect(value.contains(placeholder), "\(language) \(key) lost \(placeholder)")
            }
        }
    }

    private static let noticeKeys = [
        "nook.todo.due.notice.one", "nook.todo.due.notice.many",
        "nook.todo.due.notice.overdue.one", "nook.todo.due.notice.overdue.many",
    ]

    // MARK: The record of what was shown

    @Test func theRecordKeepsTheLastSevenDays() {
        let calendar = F.calendar()
        let now = F.moment(14, 10, in: calendar)
        let shown = NookTodoDueShown(keys: [
            NookTodoDueShown.taskKey("a", day: "2026-10-06"),
            NookTodoDueShown.taskKey("b", day: "2026-10-07"),
            NookTodoDueShown.taskKey("c", day: "2026-10-08"),
            NookTodoDueShown.overdueKey(day: "2026-10-13"),
            NookTodoDueShown.taskKey("d", day: "2026-10-14"),
        ])

        let kept = shown.trimmed(now: now, calendar: calendar)

        // Today and the six days before it.
        #expect(kept.keys == [
            NookTodoDueShown.taskKey("c", day: "2026-10-08"),
            NookTodoDueShown.overdueKey(day: "2026-10-13"),
            NookTodoDueShown.taskKey("d", day: "2026-10-14"),
        ])
    }

    @Test func trimmingAcrossAMonthEndCountsRealDays() {
        let calendar = F.calendar()
        let now = F.moment(3, 10, month: 11, in: calendar)
        let shown = NookTodoDueShown(keys: [
            NookTodoDueShown.overdueKey(day: "2026-10-27"),
            NookTodoDueShown.overdueKey(day: "2026-10-28"),
        ])

        let kept = shown.trimmed(now: now, calendar: calendar)

        #expect(kept.keys == [NookTodoDueShown.overdueKey(day: "2026-10-28")])
    }

    @Test func trimmingDropsKeysThatAreNotWhatWeWrote() {
        let calendar = F.calendar()
        let shown = NookTodoDueShown(keys: ["garbage", "", "zzzz-zz-zz|task|a", "2026-10-14|task|ok"])

        let kept = shown.trimmed(now: F.moment(14, in: calendar), calendar: calendar)

        #expect(kept.keys == ["2026-10-14|task|ok"])
    }

    @Test func aTaskIDWithABarInItStillKeepsItsDay() {
        let calendar = F.calendar()
        let key = NookTodoDueShown.taskKey("a|b|c", day: "2026-10-14")

        let kept = NookTodoDueShown(keys: [key]).trimmed(now: F.moment(14, in: calendar), calendar: calendar)

        #expect(kept.hasShown(task: "a|b|c", on: "2026-10-14"))
        #expect(!kept.hasShown(task: "a", on: "2026-10-14"))
    }

    @Test func theRecordSavesAsSortedTextAndComesBack() {
        let shown = NookTodoDueShown(keys: [
            NookTodoDueShown.taskKey("b", day: "2026-10-14"),
            NookTodoDueShown.overdueKey(day: "2026-10-13"),
        ])

        let restored = NookTodoDueShown(keys: shown.saved)

        #expect(shown.saved == shown.saved.sorted())
        #expect(restored == shown)
    }

    @Test func recordingAddsEveryItemOfTheNoticeUnderTheDayItWasMadeFor() {
        let result = notices([dueToday("a"), dueToday("b"), dueOn(11, "c")])

        let shown = NookTodoDueShown().recording(result)

        #expect(shown.hasShown(task: "a", on: "2026-10-14"))
        #expect(shown.hasShown(task: "b", on: "2026-10-14"))
        #expect(!shown.hasShown(task: "c", on: "2026-10-14"))
        #expect(shown.hasShownOverdue(on: "2026-10-14"))
        #expect(!shown.hasShownOverdue(on: "2026-10-13"))
    }
}
