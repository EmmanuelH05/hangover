import Foundation
import Testing
@testable import OpenIslandApp

/// The number of the notice Record last put on the closed notch.
@MainActor
private final class RecordNoticeSerial {
    var serial: Int?
}

/// A hub, a model with a fake recorder and a reminder on a made-up morning.
/// Record's notice stays up for a short time of its own.
@MainActor
private struct OtherNoticeRig {
    typealias F = NookTodoDueFixtures

    let nook: NookModel
    let hub: NookTodoHub
    let recorder = FakeRecorder()
    let recordNotice = RecordNoticeSerial()
    let presence = IslandScreenPresence()

    init(recordNoticeTime: Duration = .milliseconds(300)) {
        let defaults = MemoryDefaults()
        let calendar = F.calendar()
        let reminders = NookRemindersService(
            defaults: defaults, sample: [F.item("a", "HW3", due: F.moment(14, in: calendar))]
        )
        let reminder = NookTodoDueReminder(
            defaults: defaults,
            clock: { F.moment(14, 10, in: calendar) },
            calendar: { calendar },
            spacing: .milliseconds(20)
        )
        hub = NookTodoHub(defaults: defaults, dueReminder: reminder, presence: presence)
        let record = NookRecordModel(
            recorder: recorder,
            defaults: defaults,
            folder: URL(fileURLWithPath: "/tmp/hangover-due-notice-tests", isDirectory: true),
            createFolder: { _ in },
            sleep: { _ in },
            fileExists: { _ in false },
            now: { Date(timeIntervalSince1970: 0) }
        )
        nook = NookModel(
            reminders: reminders, todo: hub, record: record, defaults: defaults,
            looksForImportedGIF: false, asksMacOSForAccess: false
        )
        let serial = recordNotice
        record.showNotice = { [weak nook] symbol, text, tint in
            serial.serial = nook?.showTransient(symbol: symbol, text: text, tint: tint, duration: recordNoticeTime)
        }
    }

    func startWhileRecording() {
        recorder.onPhaseChange?(.recording(startedAt: Date(timeIntervalSince1970: 0), pausedTotal: 0))
        hub.start(nook: nook)
    }

    func waitFor(_ done: () -> Bool) async {
        for _ in 0..<200 {
            if done() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// The due-day reminder does not take the closed notch from a notice that
/// another feature put there (D1 of the third review fixes).
@MainActor
@Suite struct NookTodoDueOtherNoticeTests {
    @Test func aRecordingSavedKeepsItsNoticeAndTheDueNoticeWaitsForIt() async throws {
        let saved = NookRecordPhase.finished(URL(fileURLWithPath: "/tmp/hangover-due-notice-tests/a.mov"), endedBy: .user)
        try await expectDueNoticeWaits(forRecordEnding: saved)
    }

    @Test func aRecordingFailedKeepsItsNoticeAndTheDueNoticeWaitsForIt() async throws {
        try await expectDueNoticeWaits(forRecordEnding: .failed(.writeFailed))
    }

    private func expectDueNoticeWaits(forRecordEnding end: NookRecordPhase) async throws {
        let rig = OtherNoticeRig()
        rig.startWhileRecording()
        try await Task.sleep(for: .milliseconds(60))
        #expect(rig.nook.transient == nil, "the reminder holds back while a recording runs")

        rig.recorder.onPhaseChange?(end)
        let recordSymbol = try #require(rig.nook.transient?.symbol)
        #expect(recordSymbol != NookTodoDueNotice.symbol)
        let recordSerial = try #require(rig.recordNotice.serial)

        await rig.waitFor { rig.nook.transient?.symbol == NookTodoDueNotice.symbol }

        #expect(rig.nook.transient?.symbol == NookTodoDueNotice.symbol, "the due notice shows once Record's is gone")
        #expect(rig.nook.transientRanItsTime(recordSerial), "Record's notice stayed up its whole time")
    }
}

/// Whether a notice is on the closed notch, which a test moves by hand.
/// Observable, like the notch's notice it stands for.
@MainActor
@Observable
private final class NoticeOnNotch {
    var isUp = false
}

/// The reminder alone, with a made-up closed notch that holds one notice.
@MainActor
@Suite struct NookTodoDueNoticeSlotTests {
    private typealias F = NookTodoDueFixtures

    private let calendar = F.calendar()

    private func dueToday(_ id: String, _ title: String) -> NookTodoItem {
        F.item(id, title, due: F.moment(14, in: calendar))
    }

    private func overdue(_ id: String) -> NookTodoItem {
        F.item(id, "Old \(id)", due: F.moment(11, in: calendar))
    }

    private func reminder(spacing: Duration = .milliseconds(40)) -> NookTodoDueReminder {
        let calendar = calendar
        return NookTodoDueReminder(
            defaults: MemoryDefaults(),
            clock: { F.moment(14, 10, in: calendar) },
            calendar: { calendar },
            spacing: spacing
        )
    }

    private func waitFor(_ done: () -> Bool) async {
        for _ in 0..<200 {
            if done() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aNoticeOfAnotherFeatureHoldsItBackUntilItIsGone() async throws {
        let reminder = reminder()
        let notch = NoticeOnNotch()
        notch.isUp = true
        var shown: [NookTodoDueNotice.Wording] = []

        reminder.start(
            items: { [self.dueToday("a", "HW3")] },
            canShow: { true },
            isOtherNoticeUp: { notch.isUp },
            show: { notice in
                shown.append(notice.wording)
                return { true }
            }
        )
        try await Task.sleep(for: .milliseconds(80))
        #expect(shown.isEmpty, "another feature's notice is on the notch")

        notch.isUp = false
        await waitFor { !shown.isEmpty }

        #expect(shown == [.oneDue(title: "HW3")])
    }

    @Test func itsOwnNoticeDoesNotHoldBackTheNextOne() async throws {
        let reminder = reminder(spacing: .milliseconds(60))
        let notch = NoticeOnNotch()
        var shown: [NookTodoDueNotice.Wording] = []

        reminder.start(
            items: { [self.dueToday("a", "HW3"), self.overdue("b")] },
            canShow: { true },
            isOtherNoticeUp: { notch.isUp },
            show: { notice in
                shown.append(notice.wording)
                // Up on the notch for less than the spacing, like the real
                // notice (6 seconds against 6.5).
                notch.isUp = true
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(30))
                    notch.isUp = false
                }
                return { true }
            }
        )
        await waitFor { shown.count == 2 }

        #expect(shown == [.oneDue(title: "HW3"), .overdue(count: 1)])
    }
}
