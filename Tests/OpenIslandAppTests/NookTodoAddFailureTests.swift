import EventKit
import Foundation
import Testing
@testable import OpenIslandApp

// A task the source refused is not lost, and the reason shows (D2 of the review
// fixes). Nothing here reaches Reminders, Notion, TickTick or the network: the
// EventKit calls are replaced, and a permission is made up and turned off
// before a service can read the real event store.

/// A source that refuses, or takes, what it is handed.
@MainActor
private final class AnswerSource: NookTodoSource {
    var items: [NookTodoItem] = []
    var displayName = "Answer"
    var connection: NookTodoConnection = .ready
    var errorMessage: String?
    var isShowingCachedItems = false
    var canAdd = true
    var canComplete = true
    var canEditNotes = true
    var notesUnavailableReason: String?
    var canSetDue = true
    var dueUnavailableReason: String?
    var addPlaceholder = "Add"
    var autoRefreshInterval: Duration?
    var takes = false
    private(set) var asked: [String] = []

    func refresh() {}
    func refreshOnTimer() {}
    func complete(_ id: String) {}
    func setNotes(_ notes: String, for id: String) {}
    func add(_ title: String, due: DateComponents?) {}

    func addConfirmed(_ title: String, due: DateComponents?) async -> Bool {
        asked.append(title)
        if !takes { errorMessage = "Refused" }
        return takes
    }
}

@MainActor
@Suite struct NookTodoAddAnswerTests {
    private typealias F = NookTodoDueFixtures

    @Test func aRefusedTaskIsReportedAsNotAdded() async {
        let source = AnswerSource()

        let added = await NookTodoAdding.submit(draft: "HW3", due: F.day(2026, 10, 16), to: source)

        #expect(!added)
        #expect(source.asked == ["HW3"])
    }

    @Test func aTaskTheSourceTookIsReportedAsAdded() async {
        let source = AnswerSource()
        source.takes = true

        let added = await NookTodoAdding.submit(draft: "HW3", due: nil, to: source)

        #expect(added)
    }

    // MARK: What the card keeps

    @Test func aRefusedTaskKeepsTheTitleAndThePickedDay() {
        let day = F.day(2026, 10, 16)

        let kept = NookTodoAdding.fields(afterAdding: false, sent: "HW3", sentDue: day, draft: "HW3", dueDraft: day)

        #expect(kept.draft == "HW3")
        #expect(kept.dueDraft == day)
    }

    @Test func aTaskTheSourceTookClearsTheTitleAndTheDay() {
        let day = F.day(2026, 10, 16)

        let kept = NookTodoAdding.fields(afterAdding: true, sent: "HW3", sentDue: day, draft: "HW3", dueDraft: day)

        #expect(kept.draft.isEmpty)
        #expect(kept.dueDraft == nil)
    }

    @Test func textTypedAfterReturnIsTheNextTasksAndStays() {
        let sent = F.day(2026, 10, 16)
        let later = F.day(2026, 10, 20)

        let kept = NookTodoAdding.fields(
            afterAdding: true, sent: "HW3", sentDue: sent, draft: "Lab report", dueDraft: later
        )

        #expect(kept.draft == "Lab report")
        #expect(kept.dueDraft == later)
    }

    @Test func aTaskWithNoDayLeavesNoDayBehind() {
        let kept = NookTodoAdding.fields(afterAdding: true, sent: "HW3", sentDue: nil, draft: "HW3", dueDraft: nil)

        #expect(kept.draft.isEmpty)
        #expect(kept.dueDraft == nil)
    }

    @Test func aSourceWithNoWayToTellIsTakenAtItsWord() async {
        let source = NookTodoDueFakeSource()

        let added = await source.addConfirmed("HW3", due: F.day(2026, 10, 16))

        #expect(added)
        #expect(source.added == [.init(title: "HW3", due: F.day(2026, 10, 16))])
    }
}

// MARK: - Reminders

/// A Reminders service whose permission is made up and whose EventKit calls are
/// the test's own. `failure` is what saving throws, nil to save.
@MainActor
private struct RemindersRig {
    let permission = FakeEventKitPermission(status: .fullAccess)
    let service: NookRemindersService
    let saves: SaveLog

    @MainActor
    final class SaveLog {
        var failure: (any Error)?
        var hasList = true
        var saved: [String] = []
    }

    struct Refused: Error {}

    init() {
        let permission = permission
        let log = SaveLog()
        saves = log
        let writes = NookRemindersWrites(
            listForNewReminder: { store, _ in
                log.hasList ? EKCalendar(for: .reminder, eventStore: store) : nil
            },
            reminder: { store, _ in EKReminder(eventStore: store) },
            save: { _, reminder in
                if let failure = log.failure { throw failure }
                log.saved.append(reminder.title ?? "")
                // A service that still believes it has access would read the
                // real event store to refresh. It does not.
                permission.status = .denied
            }
        )
        service = NookRemindersService(access: permission.access, defaults: MemoryDefaults(), writes: writes)
    }

    /// The permission is back on for the next write.
    func allowAgain() {
        permission.status = .fullAccess
    }

    func message(_ key: String) -> String { LanguageManager.shared.t(key) }
}

@MainActor
@Suite struct NookRemindersWriteErrorTests {
    @Test func aRefusedAddIsNotAddedAndSaysWhy() async {
        let rig = RemindersRig()
        rig.saves.failure = RemindersRig.Refused()

        let added = await rig.service.addConfirmed("HW3", due: nil)

        #expect(!added)
        #expect(rig.service.lastWriteError == .addFailed)
        #expect(rig.service.errorMessage == rig.message("nook.todo.reminders.error.addFailed"))
        #expect(rig.saves.saved.isEmpty)
    }

    @Test func noListToAddToSaysSo() async {
        let rig = RemindersRig()
        rig.saves.hasList = false

        let added = await rig.service.addConfirmed("HW3", due: nil)

        #expect(!added)
        #expect(rig.service.lastWriteError == .noList)
        #expect(rig.service.errorMessage == rig.message("nook.todo.reminders.error.noList"))
    }

    @Test func theFireAndForgetAddReportsTheSameFailure() {
        let rig = RemindersRig()
        rig.saves.failure = RemindersRig.Refused()

        rig.service.add("HW3", due: nil)

        #expect(rig.service.errorMessage != nil)
    }

    @Test func aTaskThatSavedIsAddedAndLeavesNoMessage() async {
        let rig = RemindersRig()

        let added = await rig.service.addConfirmed("  HW3  ", due: nil)

        #expect(added)
        #expect(rig.saves.saved == ["HW3"])
        #expect(rig.service.errorMessage == nil)
    }

    @Test func theNextWriteClearsTheMessageOfTheLastOne() async {
        let rig = RemindersRig()
        rig.saves.failure = RemindersRig.Refused()
        _ = await rig.service.addConfirmed("HW3", due: nil)
        #expect(rig.service.errorMessage != nil)

        rig.saves.failure = nil
        let added = await rig.service.addConfirmed("HW3", due: nil)

        #expect(added)
        #expect(rig.service.errorMessage == nil)
    }

    @Test func aBlankTitleIsNotAFailure() async {
        let rig = RemindersRig()

        let added = await rig.service.addConfirmed("   ", due: nil)

        #expect(!added)
        #expect(rig.service.errorMessage == nil, "nothing was refused")
        #expect(rig.saves.saved.isEmpty)
    }

    @Test func aRefusedCompletionAndARefusedNoteSaveAreReportedToo() {
        let rig = RemindersRig()
        rig.saves.failure = RemindersRig.Refused()

        rig.service.complete("any")
        #expect(rig.service.lastWriteError == .completeFailed)

        rig.service.setNotes("text", for: "any")
        #expect(rig.service.lastWriteError == .notesFailed)
        #expect(rig.service.errorMessage == rig.message("nook.todo.reminders.error.notesFailed"))
    }

    @Test func onlyAFailedNoteSaveIsOneForTheNotesPage() async {
        let rig = RemindersRig()
        rig.saves.failure = RemindersRig.Refused()

        _ = await rig.service.addConfirmed("HW3", due: nil)
        #expect(rig.service.errorMessage != nil)
        #expect(!rig.service.notesSaveFailed, "a refused add says nothing about the notes")

        rig.service.complete("any")
        #expect(!rig.service.notesSaveFailed)

        rig.service.setNotes("text", for: "any")
        #expect(rig.service.notesSaveFailed)
    }

    @Test func theSampleListNeverReportsAnError() async {
        let service = NookRemindersService(defaults: MemoryDefaults(), sample: [])

        let added = await service.addConfirmed("HW3", due: nil)

        #expect(added)
        #expect(service.errorMessage == nil)
    }
}

// MARK: - The words

@Suite struct NookRemindersWriteErrorStringsTests {
    private static let keys = [
        NookRemindersWriteError.noList, .addFailed, .completeFailed, .notesFailed,
    ].map(\.messageKey)

    @Test(arguments: HangoverBrandTests.languages)
    func everyMessageIsThereInEveryLanguage(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for key in Self.keys {
            #expect(!(table[key] ?? "").isEmpty, "\(language) is missing \(key)")
        }
    }

    @Test(arguments: ["zh-Hans", "zh-Hant"])
    func theChineseMessagesAreInChinese(language: String) throws {
        let table = try HangoverBrandTests.table(language)
        for key in Self.keys {
            let value = try #require(table[key])
            let hasChinese = value.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
            #expect(hasChinese, "\(language) \(key) has no Chinese in it")
        }
    }

    @Test func theEnglishMessagesAreWrittenPlainly() throws {
        let english = try HangoverBrandTests.table("en")
        for key in Self.keys {
            let value = try #require(english[key])
            #expect(value.range(of: "\\bso\\b", options: [.regularExpression, .caseInsensitive]) == nil, "\(key)")
            #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(key) has a dash")
        }
    }
}
