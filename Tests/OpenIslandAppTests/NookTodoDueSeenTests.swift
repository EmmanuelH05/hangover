import Foundation
import Observation
import Testing
@testable import OpenIslandApp

/// The due-day reminder counts a notice as shown only once a person could see
/// it: the screen unlocked, the island closed, notices on, no recording (D1 of
/// the review fixes).
@Suite struct NookTodoDueSightTests {
    private let allClear = NookTodoDueSight(isScreenOn: true, isIslandOpen: false, showsNotices: true, isRecording: false)

    @Test func aNoticeIsSeenWhenNothingHidesIt() {
        #expect(allClear.canSee)
        #expect(allClear.reasonHidden == nil)
    }

    @Test func aLockedOrSleepingScreenHidesIt() {
        var sight = allClear
        sight.isScreenOn = false

        #expect(!sight.canSee)
        #expect(sight.reasonHidden == "the screen is off or locked")
    }

    @Test func anOpenIslandHidesIt() {
        var sight = allClear
        sight.isIslandOpen = true

        #expect(!sight.canSee)
        #expect(sight.reasonHidden == "the island is open")
    }

    @Test func noticesTurnedOffHideIt() {
        var sight = allClear
        sight.showsNotices = false

        #expect(!sight.canSee)
        #expect(sight.reasonHidden == "notices are off on this display")
    }

    @Test func aRunningRecordingHidesIt() {
        var sight = allClear
        sight.isRecording = true

        #expect(!sight.canSee)
        #expect(sight.reasonHidden == "a recording is running")
    }
}

/// What the reminder does about a notice nobody saw.
@MainActor
@Suite struct NookTodoDueSeenTests {
    private typealias F = NookTodoDueFixtures

    private func dueToday(_ id: String, _ title: String = "Task") -> NookTodoItem {
        F.item(id, title, due: F.moment(14, in: F.calendar()))
    }

    private func overdue(_ id: String) -> NookTodoItem {
        F.item(id, "Old \(id)", due: F.moment(11, in: F.calendar()))
    }

    // MARK: Nobody can see it

    @Test func nothingIsSaidOrRecordedWhileNobodyCanSeeTheNotch() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3"), overdue("b")])
        rig.sight.canSee = false

        rig.start()
        rig.reminder.check()
        await rig.settle()

        #expect(rig.shown.isEmpty)
        #expect(rig.recorded.isEmpty)
    }

    @Test func theNoticeComesWhenThePersonCanSeeAgain() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")])
        rig.sight.canSee = false
        rig.start()
        #expect(rig.shown.isEmpty)

        // The screen unlocks, or the island closes: nothing calls `check`.
        rig.sight.canSee = true
        await rig.settle { !rig.shown.isEmpty }

        #expect(rig.wordings == [.oneDue(title: "HW3")])
    }

    @Test func aDayThatPassedUnseenStillGetsItsNoticeWhenSomeoneComes() async {
        // A Mac asleep at 9 AM: the timer fires on the lock screen and finds no one.
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")], at: F.moment(14, 9, in: F.calendar()))
        rig.sight.canSee = false
        rig.start()
        rig.moment.now = F.moment(14, 9, 1, in: rig.calendar)
        rig.reminder.check()
        #expect(rig.recorded.isEmpty)

        rig.moment.now = F.moment(14, 13, in: rig.calendar)
        rig.sight.canSee = true
        await rig.settle { !rig.shown.isEmpty }

        #expect(rig.wordings == [.oneDue(title: "HW3")])
    }

    // MARK: Seen to the end

    @Test func aNoticeIsRecordedOnlyAfterItStayedItsWholeTime() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")])

        rig.start()

        // On the notch, but its time has not run out.
        #expect(rig.wordings == [.oneDue(title: "HW3")])
        #expect(rig.recorded.isEmpty)
        await rig.settle { !rig.recorded.isEmpty }
        #expect(rig.recorded == [NookTodoDueShown.taskKey("a", day: "2026-10-14")])
    }

    @Test func aNoticeAnotherNoticeReplacedIsShownAgainAndRecordedOnlyThen() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")])
        rig.staysUp = false

        rig.start()
        await rig.settle { rig.shown.count == 2 }

        // Replaced the first time. It came back, and nothing was recorded.
        #expect(rig.wordings == [.oneDue(title: "HW3"), .oneDue(title: "HW3")])
        #expect(rig.recorded.isEmpty)

        rig.staysUp = true
        await rig.settle { !rig.recorded.isEmpty }
        #expect(rig.recorded == [NookTodoDueShown.taskKey("a", day: "2026-10-14")])
    }

    @Test func aNoticeCutShortByTheIslandOpeningIsNotRecordedAndComesBackWhenItCloses() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")], spacing: .milliseconds(60))
        rig.start()
        #expect(rig.shown.count == 1)

        // The island opens while the notice is up.
        rig.sight.canSee = false
        await rig.settle()
        #expect(rig.recorded.isEmpty)
        #expect(rig.shown.count == 1)

        rig.sight.canSee = true
        await rig.settle { rig.shown.count == 2 }
        #expect(rig.wordings == [.oneDue(title: "HW3"), .oneDue(title: "HW3")])
        await rig.settle { !rig.recorded.isEmpty }
        #expect(rig.recorded == [NookTodoDueShown.taskKey("a", day: "2026-10-14")])
    }

    @Test func aRelaunchBeforeTheNoticeHadItsTimeSaysItAgain() {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")])
        rig.start()

        let again = rig.relaunched()
        again.start()

        #expect(rig.wordings == [.oneDue(title: "HW3")])
        #expect(again.wordings == [.oneDue(title: "HW3")])
    }

    @Test func aNoticeThatIsWaitingIsNotQueuedTwice() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3"), overdue("b")], spacing: .milliseconds(40))
        rig.start()

        // Looking again while the first is up, and while the second waits.
        rig.reminder.check()
        rig.list.items.append(dueToday("c", "Lab"))
        await rig.settle { rig.shown.count == 3 }
        await rig.settle()

        #expect(rig.wordings == [.oneDue(title: "HW3"), .oneDue(title: "Lab"), .overdue(count: 1)])
    }

    @Test func turningTheSwitchOffMidNoticeRecordsNothing() async {
        let rig = NookTodoDueRig(items: [dueToday("a", "HW3")], spacing: .milliseconds(40))
        rig.start()

        rig.reminder.isEnabled = false
        await rig.settle()

        #expect(rig.recorded.isEmpty)
    }
}

// MARK: - The hub's wiring

/// The island's open state, which a test moves by hand. Observable, like the
/// notch status it stands for.
@MainActor
@Observable
private final class IslandOpenBox {
    var isOpen = false
}

/// A hub, a model and a screen presence of their own, with the reminder on
/// a made-up morning.
@MainActor
private struct HubSightRig {
    let nook: NookModel
    let hub: NookTodoHub
    let presence = IslandScreenPresence()
    let island = IslandOpenBox()

    init(duration: Duration = .milliseconds(20)) {
        let defaults = MemoryDefaults()
        let calendar = NookTodoDueFixtures.calendar()
        let reminders = NookRemindersService(
            defaults: defaults,
            sample: [NookTodoDueFixtures.item("a", "HW3", due: NookTodoDueFixtures.moment(14, in: calendar))]
        )
        let reminder = NookTodoDueReminder(
            defaults: defaults,
            clock: { NookTodoDueFixtures.moment(14, 10, in: calendar) },
            calendar: { calendar },
            spacing: duration
        )
        hub = NookTodoHub(defaults: defaults, dueReminder: reminder, presence: presence)
        nook = NookModel(
            reminders: reminders, todo: hub, defaults: defaults, looksForImportedGIF: false, asksMacOSForAccess: false
        )
        let island = island
        nook.isIslandOpen = { island.isOpen }
    }

    func start() {
        hub.start(nook: nook)
    }

    func settle(until done: () -> Bool = { false }) async {
        for _ in 0..<100 {
            if done() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

@MainActor
@Suite struct NookTodoDueHubSightTests {
    @Test func aLockedScreenKeepsTheNoticeOffTheNotchUntilItUnlocks() async {
        let rig = HubSightRig()
        rig.presence.note(.locked)

        rig.start()
        await rig.settle()
        #expect(rig.nook.transient == nil)

        rig.presence.note(.unlocked)
        await rig.settle { rig.nook.transient != nil }

        #expect(rig.nook.transient?.symbol == NookTodoDueNotice.symbol)
    }

    @Test func aMacAsleepOrAnotherUsersSessionKeepsItOff() async {
        let rig = HubSightRig()
        rig.presence.note(.willSleep)
        rig.start()
        await rig.settle()
        #expect(rig.nook.transient == nil)

        rig.presence.note(.didWake)
        rig.presence.note(.sessionResigned)
        await rig.settle()
        #expect(rig.nook.transient == nil)

        rig.presence.note(.sessionBecameActive)
        await rig.settle { rig.nook.transient != nil }
        #expect(rig.nook.transient != nil)
    }

    @Test func anOpenIslandHoldsTheNoticeUntilItCloses() async {
        let rig = HubSightRig()
        rig.island.isOpen = true

        rig.start()
        await rig.settle()
        #expect(rig.nook.transient == nil)

        rig.island.isOpen = false
        await rig.settle { rig.nook.transient != nil }

        #expect(rig.nook.transient?.symbol == NookTodoDueNotice.symbol)
    }

    @Test func noticesTurnedOffKeepItOffUntilTheyAreOn() async {
        let rig = HubSightRig()
        rig.nook.updateDisplayPreferences(for: rig.nook.activeProfile()) { $0.showsNotices = false }

        rig.start()
        await rig.settle()
        #expect(rig.nook.transient == nil)

        rig.nook.updateDisplayPreferences(for: rig.nook.activeProfile()) { $0.showsNotices = true }
        await rig.settle { rig.nook.transient != nil }

        #expect(rig.nook.transient?.symbol == NookTodoDueNotice.symbol)
    }

    @Test func aRecordingRunningKeepsItOffUntilItEnds() async {
        let rig = HubSightRig()
        rig.nook.record.phase = .recording(startedAt: Date(), pausedTotal: 0)

        rig.start()
        await rig.settle()
        #expect(rig.nook.transient == nil)

        rig.nook.record.phase = .idle
        await rig.settle { rig.nook.transient != nil }

        #expect(rig.nook.transient?.symbol == NookTodoDueNotice.symbol)
    }
}

/// The closed notch tells the reminder whether a notice stayed its whole time.
@MainActor
@Suite struct NookTransientRanItsTimeTests {
    private func model() -> NookModel {
        NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false, asksMacOSForAccess: false)
    }

    @Test func aNoticeThatRanItsWholeTimeSaysSo() async {
        let nook = model()

        let serial = nook.showTransient(symbol: "bolt", text: "Charging", duration: .milliseconds(30))

        #expect(!nook.transientRanItsTime(serial))
        for _ in 0..<100 where nook.transient != nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(nook.transientRanItsTime(serial))
    }

    @Test func aNoticeAnotherOneReplacedNeverSaysSo() async {
        let nook = model()

        let first = nook.showTransient(symbol: "bolt", text: "Charging", duration: .seconds(5))
        let second = nook.showTransient(symbol: "airpods", text: "AirPods", duration: .milliseconds(30))
        for _ in 0..<100 where nook.transient != nil { try? await Task.sleep(for: .milliseconds(10)) }

        #expect(!nook.transientRanItsTime(first))
        #expect(nook.transientRanItsTime(second))
    }
}
