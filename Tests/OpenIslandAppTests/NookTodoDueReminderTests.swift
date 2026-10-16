import Foundation
import Observation
import Testing
@testable import OpenIslandApp

/// The list a test hands the reminder. Observable, like the real sources.
@MainActor
@Observable
final class NookTodoDueListBox {
    var items: [NookTodoItem]

    init(_ items: [NookTodoItem] = []) {
        self.items = items
    }
}

/// A moment a test moves by hand.
@MainActor
final class NookTodoDueMoment {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// Whether a person could see the closed notch, which a test moves by hand.
/// Observable, like the screen and island state the real answer reads.
@MainActor
@Observable
final class NookTodoDueSightBox {
    var canSee = true
}

/// One reminder with a made-up list, clock and closed notch, on a settings
/// store held in memory.
@MainActor
final class NookTodoDueRig {
    typealias F = NookTodoDueFixtures

    let defaults: UserDefaults
    let calendar = F.calendar()
    let list: NookTodoDueListBox
    let moment: NookTodoDueMoment
    let sight = NookTodoDueSightBox()
    let reminder: NookTodoDueReminder
    private(set) var shown: [NookTodoDueNotice] = []
    /// What the closed notch answers when the reminder asks whether a notice
    /// stayed up its whole time. False stands for another notice replacing it.
    var staysUp = true

    init(
        items: [NookTodoItem] = [],
        at moment: Date? = nil,
        defaults: UserDefaults = MemoryDefaults(),
        spacing: Duration = .milliseconds(20)
    ) {
        let calendar = calendar
        let start = moment ?? F.moment(14, 10, in: calendar)
        let clock = NookTodoDueMoment(start)
        self.defaults = defaults
        self.moment = clock
        list = NookTodoDueListBox(items)
        reminder = NookTodoDueReminder(
            defaults: defaults, clock: { clock.now }, calendar: { calendar }, spacing: spacing
        )
    }

    func start() {
        let list = list
        let sight = sight
        reminder.start(
            items: { list.items },
            canShow: { sight.canSee },
            show: { [weak self] notice in
                self?.shown.append(notice)
                return { [weak self] in self?.staysUp ?? false }
            }
        )
    }

    var wordings: [NookTodoDueNotice.Wording] { shown.map(\.wording) }

    /// The notices written to the saved record, as keys.
    var recorded: [String] { defaults.stringArray(forKey: NookTodoDueReminder.shownKey) ?? [] }

    /// A made-up reminder on the same store, the way a relaunch makes one.
    func relaunched() -> NookTodoDueRig {
        NookTodoDueRig(items: list.items, at: moment.now, defaults: defaults)
    }

    /// Waits for the hops the observation and the queue make.
    func settle(until done: () -> Bool = { false }) async {
        for _ in 0..<200 {
            if done() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// What the reminder does when it looks: when, how often, and what it
/// remembers (D69).
@MainActor
@Suite struct NookTodoDueReminderTests {
    private typealias F = NookTodoDueFixtures

    private func dueToday(_ id: String, _ title: String = "Task") -> NookTodoItem {
        F.item(id, title, due: F.moment(14, in: F.calendar()))
    }

    private func overdue(_ id: String) -> NookTodoItem {
        F.item(id, "Old \(id)", due: F.moment(11, in: F.calendar()))
    }

    // MARK: The switch and the record

    @Test func theSwitchIsOnByDefaultAndSavesUnderItsKey() {
        let defaults = MemoryDefaults()
        let reminder = NookTodoDueReminder(defaults: defaults)

        #expect(reminder.isEnabled)
        #expect(NookTodoDueReminder.enabledKey == "nook.todo.remindOnDueDay")
        #expect(NookTodoDueReminder.shownKey == "nook.todo.dueNoticesShown")

        reminder.isEnabled = false
        #expect(defaults.object(forKey: "nook.todo.remindOnDueDay") as? Bool == false)
        #expect(NookTodoDueReminder(defaults: defaults).isEnabled == false)

        reminder.isEnabled = true
        #expect(NookTodoDueReminder(defaults: defaults).isEnabled)
    }

    // MARK: Looking

    @Test func startingAfterNineSaysWhatIsDueToday() {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")])

        rig.start()

        #expect(rig.wordings == [.oneDue(title: "HW3")])
    }

    @Test func nothingIsRepeatedWhenItLooksAgain() {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3"), overdue("b")])
        rig.start()

        rig.reminder.check()
        rig.reminder.check()
        rig.start()

        #expect(rig.wordings == [.oneDue(title: "HW3")])
    }

    @Test func aRelaunchDoesNotRepeatTheDay() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")])
        rig.start()
        // The record is written once the notice has had its time.
        await rig.settle { !rig.recorded.isEmpty }

        let again = rig.relaunched()
        again.start()

        #expect(rig.wordings == [.oneDue(title: "HW3")])
        #expect(again.shown.isEmpty)
        #expect(rig.recorded == [NookTodoDueShown.taskKey("a", day: "2026-10-14")])
    }

    @Test func aNewDayBringsTheDayBack() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")])
        rig.start()

        rig.moment.now = F.moment(15, 10, in: rig.calendar)
        rig.reminder.check()
        // The new notice waits for the first one's time on screen.
        await rig.settle { rig.shown.count == 2 }

        // Due yesterday, so overdue today.
        #expect(rig.wordings == [.oneDue(title: "HW3"), .overdue(count: 1)])
    }

    @Test func nothingShowsBeforeNineAndEverythingDoesAtNine() {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")], at: F.moment(14, 8, 59, in: F.calendar()))
        rig.start()
        #expect(rig.shown.isEmpty)

        rig.moment.now = F.moment(14, 9, in: rig.calendar)
        rig.reminder.check()

        #expect(rig.wordings == [.oneDue(title: "HW3")])
    }

    @Test func aToDoAddedLaterTodayGetsItsOwnNotice() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")])
        rig.start()

        rig.moment.now = F.moment(14, 15, in: rig.calendar)
        rig.list.items.append(dueToday("b", "Call mom"))
        await rig.settle { rig.shown.count == 2 }

        // The change in the list was enough: nothing called `check`.
        #expect(rig.wordings == [.oneDue(title: "HW3"), .oneDue(title: "Call mom")])
    }

    @Test func aLoadThatBringsTheListInLateIsSeen() async {
        let rig = NookTodoDueRig(items: [])
        rig.start()
        #expect(rig.shown.isEmpty)

        rig.list.items = [dueToday("a", "HW3"), dueToday("b", "Lab")]
        await rig.settle { !rig.shown.isEmpty }

        #expect(rig.wordings == [.manyDue(count: 2)])
    }

    @Test func aDoneToDoNeverSpeaks() async {
        let rig = NookTodoDueRig(items: [])
        rig.start()

        rig.list.items = [F.item("a", due: F.moment(14, in: rig.calendar), done: true)]
        await rig.settle()

        #expect(rig.shown.isEmpty)
    }

    @Test func dueTodayAndOverdueComeOneAfterTheOther() async {
        let rig = NookTodoDueRig(items: [overdue("b"), dueToday("a", "HW3")], spacing: .milliseconds(30))

        rig.start()

        // The first at once, the second when the first has had its time.
        #expect(rig.wordings == [.oneDue(title: "HW3")])
        await rig.settle { rig.shown.count == 2 }
        #expect(rig.wordings == [.oneDue(title: "HW3"), .overdue(count: 1)])
    }

    // MARK: The switch at work

    @Test func withTheSwitchOffNothingShowsAndNothingIsRemembered() async {
        let defaults = MemoryDefaults()
        defaults.set(false, forKey: NookTodoDueReminder.enabledKey)
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3"), overdue("b")], defaults: defaults)

        rig.start()
        rig.reminder.check()
        rig.list.items.append(dueToday("c"))
        await rig.settle()

        #expect(rig.shown.isEmpty)
        #expect(defaults.stringArray(forKey: NookTodoDueReminder.shownKey) == nil)
    }

    @Test func turningTheSwitchOnLooksAtOnce() {
        let defaults = MemoryDefaults()
        defaults.set(false, forKey: NookTodoDueReminder.enabledKey)
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")], defaults: defaults)
        rig.start()
        #expect(rig.shown.isEmpty)

        rig.reminder.isEnabled = true

        #expect(rig.wordings == [.oneDue(title: "HW3")])
    }

    @Test func turningTheSwitchOffDropsNoticesStillWaiting() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3"), overdue("b")], spacing: .milliseconds(80))
        rig.start()
        #expect(rig.shown.count == 1)

        rig.reminder.isEnabled = false
        await rig.settle(until: { false })

        #expect(rig.wordings == [.oneDue(title: "HW3")])
    }

    // MARK: The record

    @Test func theSavedRecordKeepsSevenDays() async {
        let defaults = MemoryDefaults()
        defaults.set([
            NookTodoDueShown.overdueKey(day: "2026-10-01"),
            NookTodoDueShown.overdueKey(day: "2026-10-08"),
            "not a key",
        ], forKey: NookTodoDueReminder.shownKey)
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")], defaults: defaults)

        rig.start()
        // The old days are trimmed at once; today's notice is added once it was seen.
        #expect(rig.recorded == [NookTodoDueShown.overdueKey(day: "2026-10-08")])
        await rig.settle { rig.recorded.count == 2 }

        let saved = defaults.stringArray(forKey: NookTodoDueReminder.shownKey) ?? []
        #expect(saved.sorted() == [
            NookTodoDueShown.overdueKey(day: "2026-10-08"),
            NookTodoDueShown.taskKey("a", day: "2026-10-14"),
        ])
    }

    // MARK: The next 9 AM

    @Test func theTimerWaitsForTodaysNineWhileItIsComing() {
        let calendar = F.calendar()

        let delay = NookTodoDueReminder.delayUntilNext(.morning, after: F.moment(14, 6, 30, in: calendar), calendar: calendar)

        #expect(delay == 2.5 * 3600)
    }

    @Test func theTimerWaitsForTomorrowsNineOnceTodaysHasCome() {
        let calendar = F.calendar()

        let atNine = NookTodoDueReminder.delayUntilNext(.morning, after: F.moment(14, 9, in: calendar), calendar: calendar)
        let evening = NookTodoDueReminder.delayUntilNext(.morning, after: F.moment(14, 21, in: calendar), calendar: calendar)

        #expect(atNine == 24 * 3600)
        #expect(evening == 12 * 3600)
    }

    @Test func theTimerCountsTheClockChangeNight() {
        // US clocks fall back on Sunday, November 1, 2026, so that night has 25 hours.
        let calendar = F.calendar()

        let delay = NookTodoDueReminder.delayUntilNext(.morning, after: F.moment(31, 21, in: calendar), calendar: calendar)

        #expect(delay == 13 * 3600)
    }

    // MARK: On the closed notch

    @Test func theHubShowsTheNoticeOnTheClosedNotchWithTheChecklist() {
        let defaults = MemoryDefaults()
        let calendar = F.calendar()
        let reminders = NookRemindersService(defaults: defaults, sample: [dueToday("a", "HW3")])
        let hub = NookTodoHub(
            defaults: defaults,
            dueReminder: NookTodoDueReminder(
                defaults: defaults, clock: { F.moment(14, 10, in: calendar) }, calendar: { calendar }
            )
        )
        let nook = NookModel(
            reminders: reminders, todo: hub, defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false
        )

        hub.start(nook: nook)

        #expect(nook.transient?.symbol == "checklist")
        #expect(nook.transient?.text == NookTodoDueNotice(wording: .oneDue(title: "HW3"), itemIDs: ["a"], day: "2026-10-14").text(lang: .shared))
    }

    @Test func theClosedNotchDrawsItOnlyWhereNoticesAreOn() {
        let defaults = MemoryDefaults()
        let calendar = F.calendar()
        let reminders = NookRemindersService(defaults: defaults, sample: [dueToday("a", "HW3")])
        let hub = NookTodoHub(
            defaults: defaults,
            dueReminder: NookTodoDueReminder(
                defaults: defaults, clock: { F.moment(14, 10, in: calendar) }, calendar: { calendar }
            )
        )
        let nook = NookModel(
            reminders: reminders, todo: hub, defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false
        )
        hub.start(nook: nook)
        var on = NookDisplayPreferences()
        on.showsNotices = true
        var off = on
        off.showsNotices = false

        let drawn = nook.closedActivity(for: on)
        let silent = nook.closedActivity(for: off)

        #expect(drawn?.leading == .symbol("checklist", .white))
        #expect(silent == nil)
    }

    @Test func theHubOnlyReadsTheListOfTheSourceInUse() async throws {
        // The made-up zone is the machine's own: Notion reads a bare date in it.
        let calendar = Calendar.current
        let harness = try NotionTodoServiceTests.Harness()
        harness.serve(pages: [NotionFixtures.page(id: "n1", title: "Lab 4", due: "2026-10-14")])
        harness.defaults.set(NookTodoSourceKind.notion.rawValue, forKey: NookTodoHub.sourceKey)
        // The Reminders list has a to-do due today too. Notion is the source in use.
        let reminders = NookRemindersService(defaults: harness.defaults, sample: [dueToday("a", "HW3")])
        let hub = NookTodoHub(
            defaults: harness.defaults,
            notion: harness.service,
            dueReminder: NookTodoDueReminder(
                defaults: harness.defaults, clock: { F.moment(14, 10, in: calendar) }, calendar: { calendar }
            )
        )
        let nook = NookModel(
            reminders: reminders, todo: hub, defaults: MemoryDefaults(), looksForImportedGIF: false, asksMacOSForAccess: false
        )

        hub.start(nook: nook)
        await harness.service.setupTask?.value
        for _ in 0..<200 where nook.transient == nil { try? await Task.sleep(for: .milliseconds(10)) }

        let expected = NookTodoDueNotice(wording: .oneDue(title: "Lab 4"), itemIDs: ["n1"], day: "2026-10-14")
        #expect(nook.transient?.text == expected.text(lang: .shared))
    }
}
