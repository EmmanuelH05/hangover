import Foundation
import Testing
@testable import OpenIslandApp

/// The time and the zone under the reminder move (D5 of the review fixes). A
/// flight, a set clock and a new day each change when 9 AM is and what day it
/// is, and the reminder sets its timer for the new 9 AM. A set clock and a new
/// day look again at once. A new time zone waits for the list to be read again
/// in it (D3 of the third review fixes): a due day is kept as midnight in the
/// zone it was read in, and the old list reads a day off in the new zone.
@MainActor
@Suite struct NookTodoDueClockChangeTests {
    private typealias F = NookTodoDueFixtures

    /// A clock and a calendar the test moves, and a center of its own for the
    /// system's notices.
    @MainActor
    private final class Rig {
        var now: Date
        var calendar: Calendar
        let center = NotificationCenter()
        let reminder: NookTodoDueReminder
        let defaults = MemoryDefaults()
        private(set) var shown: [NookTodoDueNotice] = []
        private let list: NookTodoDueListBox

        init(now: Date, calendar: Calendar, items: [NookTodoItem]) {
            self.now = now
            self.calendar = calendar
            list = NookTodoDueListBox(items)
            let box = ClockBox(now: now, calendar: calendar)
            clock = box
            reminder = NookTodoDueReminder(
                defaults: defaults,
                clock: { box.now },
                calendar: { box.calendar },
                spacing: .milliseconds(20),
                notifications: center
            )
        }

        private let clock: ClockBox

        func start() {
            let list = list
            reminder.start(
                items: { list.items },
                canShow: { true },
                show: { [weak self] notice in
                    self?.shown.append(notice)
                    return { true }
                }
            )
        }

        /// The source reads its list again and hands over the new one.
        func refreshLands(_ items: [NookTodoItem]) {
            list.items = items
        }

        /// Moves the clock and the zone the reminder reads.
        func move(to now: Date? = nil, calendar: Calendar? = nil) {
            if let now { clock.now = now }
            if let calendar { clock.calendar = calendar }
        }

        func post(_ name: Notification.Name) {
            center.post(name: name, object: nil)
        }

        /// The notices written to the saved record, as keys.
        var recorded: [String] { defaults.stringArray(forKey: NookTodoDueReminder.shownKey) ?? [] }

        func settle(until done: () -> Bool) async {
            for _ in 0..<200 {
                if done() { return }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    @MainActor
    private final class ClockBox {
        var now: Date
        var calendar: Calendar

        init(now: Date, calendar: Calendar) {
            self.now = now
            self.calendar = calendar
        }
    }

    private let losAngeles = F.calendar("America/Los_Angeles")
    private let newYork = F.calendar("America/New_York")

    /// 8:00 in Los Angeles on October 14, which is 11:00 in New York.
    private var earlyInLosAngeles: Date { F.moment(14, 8, in: losAngeles) }

    private func dueOct14(in calendar: Calendar) -> NookTodoItem {
        F.item("a", "HW3", due: F.moment(14, in: calendar))
    }

    // MARK: The time zone

    @Test func flyingEastSaysWhatIsDueOnceTheListIsReadAgainInTheNewZone() async {
        let rig = Rig(now: earlyInLosAngeles, calendar: losAngeles, items: [dueOct14(in: losAngeles)])
        rig.start()
        #expect(rig.shown.isEmpty, "8 AM in Los Angeles is before the reminder")

        // The same moment is 11 AM in New York, past 9.
        rig.move(calendar: newYork)
        rig.post(.NSSystemTimeZoneDidChange)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(rig.shown.isEmpty, "it waits for the list read in the new zone")

        rig.refreshLands([dueOct14(in: newYork)])
        await rig.settle { !rig.shown.isEmpty }

        #expect(rig.shown.map(\.wording) == [.oneDue(title: "HW3")])
    }

    @Test func flyingWestDoesNotCallTodaysTaskOverdueBeforeTheListIsReadAgain() async {
        // 1 PM in New York is 10 AM in Los Angeles. HW3 is due today, and its
        // day was read as midnight in New York: 9 PM yesterday in Los Angeles.
        let rig = Rig(now: F.moment(14, 13, in: newYork), calendar: newYork, items: [dueOct14(in: newYork)])
        rig.start()
        #expect(rig.shown.map(\.wording) == [.oneDue(title: "HW3")])
        // The notice has had its time and is in the record.
        await rig.settle { !rig.recorded.isEmpty }

        rig.move(calendar: losAngeles)
        rig.post(.NSSystemTimeZoneDidChange)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(rig.shown.map(\.wording) == [.oneDue(title: "HW3")], "no overdue notice for a task due today")

        rig.refreshLands([dueOct14(in: losAngeles)])
        try? await Task.sleep(for: .milliseconds(80))
        #expect(rig.shown.map(\.wording) == [.oneDue(title: "HW3")], "read in the new zone, it is due today")
    }

    @Test func theMorningTimerIsSetAgainForTheNewZone() {
        let rig = Rig(now: earlyInLosAngeles, calendar: losAngeles, items: [])
        rig.start()
        let before = rig.reminder.scheduledMorningDelay

        // 11 AM in New York: the next 9 AM is the next day's, about 22 hours away.
        rig.move(calendar: newYork)
        rig.post(.NSSystemTimeZoneDidChange)

        let after = rig.reminder.scheduledMorningDelay
        #expect(before != nil && after != nil)
        #expect((before ?? 0) < 2 * 3600, "an hour from 8 to 9 in Los Angeles, plus the padding")
        #expect(abs((after ?? 0) - (22 * 3600 + 1)) < 5, "\(after ?? 0)")
    }

    @Test func flyingWestKeepsTheDayWhenItsMorningHasNotCome() async {
        // 11:00 in New York is 8:00 in Los Angeles: nothing yet, and 9 AM is an hour away.
        let rig = Rig(now: earlyInLosAngeles, calendar: newYork, items: [dueOct14(in: newYork)])
        rig.start()
        #expect(!rig.shown.isEmpty)

        let shownBefore = rig.shown.count
        rig.move(calendar: losAngeles)
        rig.post(.NSSystemTimeZoneDidChange)
        rig.refreshLands([dueOct14(in: losAngeles)])
        try? await Task.sleep(for: .milliseconds(80))

        #expect(rig.shown.count == shownBefore, "it was shown for today already, and the record holds")
        #expect((rig.reminder.scheduledMorningDelay ?? 0) < 2 * 3600)
    }

    // MARK: The clock

    @Test func aClockSetPastNineLooksAgain() async {
        let rig = Rig(now: F.moment(14, 8, 59, in: losAngeles), calendar: losAngeles, items: [dueOct14(in: losAngeles)])
        rig.start()
        #expect(rig.shown.isEmpty)

        rig.move(to: F.moment(14, 9, 30, in: losAngeles))
        rig.post(.NSSystemClockDidChange)
        await rig.settle { !rig.shown.isEmpty }

        #expect(rig.shown.map(\.wording) == [.oneDue(title: "HW3")])
    }

    @Test func aClockSetAheadSetsTheTimerAgain() {
        let rig = Rig(now: F.moment(14, 8, in: losAngeles), calendar: losAngeles, items: [])
        rig.start()
        let before = rig.reminder.scheduledMorningDelay

        rig.move(to: F.moment(14, 10, in: losAngeles))
        rig.post(.NSSystemClockDidChange)

        // Once an hour away, and now the next day's 9 AM, 23 hours away.
        #expect(abs((before ?? 0) - (3600 + 1)) < 5)
        #expect(abs((rig.reminder.scheduledMorningDelay ?? 0) - (23 * 3600 + 1)) < 5)
    }

    // MARK: A new day

    @Test func aNewDayLooksAgainAtMidnightAndFindsNothingBeforeNine() async {
        let rig = Rig(now: F.moment(14, 23, 59, in: losAngeles), calendar: losAngeles, items: [dueOct14(in: losAngeles)])
        rig.start()
        let shownToday = rig.shown.count

        rig.move(to: F.moment(15, 0, 1, in: losAngeles))
        rig.post(.NSCalendarDayChanged)
        try? await Task.sleep(for: .milliseconds(80))

        #expect(rig.shown.count == shownToday, "nothing new is due, and it is before nine")
        #expect(abs((rig.reminder.scheduledMorningDelay ?? 0) - (9 * 3600 - 60 + 1)) < 5)
    }

    @Test func theNewDaysTaskIsSaidWhenTheDayChangesAfterNine() async {
        // A Mac left on over midnight and a late-set clock land on the new day after nine.
        let items = [dueOct14(in: losAngeles), F.item("b", "Lab", due: F.moment(15, in: losAngeles))]
        let rig = Rig(now: F.moment(14, 10, in: losAngeles), calendar: losAngeles, items: items)
        rig.start()
        await rig.settle { rig.shown.count == 1 }

        rig.move(to: F.moment(15, 9, 5, in: losAngeles))
        rig.post(.NSCalendarDayChanged)
        await rig.settle { rig.shown.count == 2 }

        #expect(rig.shown.map(\.wording) == [.oneDue(title: "HW3"), .oneDue(title: "Lab")])
    }

    // MARK: Nothing posted, nothing moved

    @Test func theClockMovingWithNoNoticeFromTheSystemChangesNothing() async {
        let rig = Rig(now: F.moment(14, 8, 59, in: losAngeles), calendar: losAngeles, items: [dueOct14(in: losAngeles)])
        rig.start()

        rig.move(to: F.moment(14, 9, 30, in: losAngeles))
        try? await Task.sleep(for: .milliseconds(80))

        #expect(rig.shown.isEmpty, "only a notice from the system makes it look again")
    }
}
