import Foundation
import Testing
@testable import OpenIslandApp

/// The reminder says why it did or did not speak, and the sources say why a
/// write failed (D6 of the review fixes). The reasons are plain values first,
/// and one test reads the real log to see them land in it.
@MainActor
@Suite struct NookTodoDueLoggingTests {
    private typealias F = NookTodoDueFixtures

    private let calendar = F.calendar()
    private func dueToday(_ id: String) -> NookTodoItem { F.item(id, "Task \(id)", due: F.moment(14, in: calendar)) }
    private func overdue(_ id: String) -> NookTodoItem { F.item(id, "Old \(id)", due: F.moment(11, in: calendar)) }

    private func silence(
        _ items: [NookTodoItem], at moment: Date? = nil, shown: NookTodoDueShown = NookTodoDueShown()
    ) -> NookTodoDueNotice.Silence? {
        NookTodoDueNotice.silence(
            items: items, now: moment ?? F.moment(14, 10, in: calendar), calendar: calendar, shown: shown
        )
    }

    // MARK: Why nothing was said

    @Test func beforeTheReminderTimeIsTheReason() {
        #expect(silence([dueToday("a")], at: F.moment(14, 8, 59, in: calendar)) == .beforeReminderTime)
    }

    @Test func nothingDueIsTheReason() {
        let undated = F.item("u", "No date")
        let done = F.item("d", "Done", due: F.moment(14, in: calendar), done: true)
        let later = F.item("l", "Later", due: F.moment(20, in: calendar))

        #expect(silence([]) == .nothingDue)
        #expect(silence([undated, done, later]) == .nothingDue)
    }

    @Test func everythingSaidAlreadyIsTheReason() {
        let shown = NookTodoDueShown()
            .recording(NookTodoDueNotice.notices(
                items: [dueToday("a"), overdue("b")], now: F.moment(14, 10, in: calendar),
                calendar: calendar, shown: NookTodoDueShown()
            ))

        #expect(silence([dueToday("a"), overdue("b")], shown: shown) == .alreadyShown)
    }

    @Test func somethingToSayIsNoSilence() {
        #expect(silence([dueToday("a")]) == nil)
        #expect(silence([overdue("b")]) == nil)
    }

    @Test(arguments: [
        NookTodoDueNotice.Silence.beforeReminderTime, .nothingDue, .alreadyShown,
    ])
    func everyReasonReadsAsAPlainSentenceFragment(silence: NookTodoDueNotice.Silence) {
        #expect(!silence.logText.isEmpty)
        #expect(silence.logText.range(of: "\\bso\\b", options: .regularExpression) == nil)
    }

    @Test func aNoticeIsNamedByKindAndNeverByTitle() {
        let notices = NookTodoDueNotice.notices(
            items: [dueToday("a"), overdue("b"), overdue("c")], now: F.moment(14, 10, in: calendar),
            calendar: calendar, shown: NookTodoDueShown()
        )

        #expect(notices.map(\.logKind) == ["one due today", "overdue"])
        #expect(!notices.map(\.logKind).joined().contains("Task"))
    }

    // MARK: Why nobody could see it

    @Test func theSightGivesOneReasonAtATimeInOrder() {
        let hidden = NookTodoDueSight(isScreenOn: false, isIslandOpen: true, showsNotices: false, isRecording: true)

        #expect(hidden.reasonHidden == "the screen is off or locked")
        #expect(NookTodoDueSight(isScreenOn: true, isIslandOpen: false, showsNotices: true, isRecording: false).reasonHidden == nil)
    }

    @Test func theReminderAsksForTheReasonWhenItHoldsBack() {
        let rig = NookTodoDueRig(items: [dueToday("a")])
        rig.sight.canSee = false
        var asked = 0

        rig.reminder.start(
            items: { rig.list.items },
            canShow: { rig.sight.canSee },
            whyHidden: {
                asked += 1
                return "the screen is off or locked"
            },
            show: { _ in { true } }
        )

        #expect(asked == 1, "it explained itself once, at the first look")
        #expect(rig.shown.isEmpty)
    }

    @Test func theReminderDoesNotAskWhenAPersonCanSee() {
        let rig = NookTodoDueRig(items: [dueToday("a")])
        var asked = 0

        rig.reminder.start(
            items: { rig.list.items },
            canShow: { rig.sight.canSee },
            whyHidden: {
                asked += 1
                return nil
            },
            show: { _ in { true } }
        )

        #expect(asked == 0)
    }
}
