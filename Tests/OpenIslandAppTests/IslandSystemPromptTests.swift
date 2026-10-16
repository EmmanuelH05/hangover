import AppKit
import EventKit
import Testing
@testable import OpenIslandApp

// A macOS permission prompt comes up under the open island: the island's
// panel is on the status bar level, the prompt on the modal panel level, and
// the prompt's frame lies inside the panel's. The welcome tour holds the
// island open, which left its "Allow access to Reminders" button a dead end.
// While the app has a request up, an open island steps below the prompt.

struct IslandPanelLevelTests {
    /// What the fix rests on: the island's two levels sit on either side of
    /// the level macOS shows an alert on, and both are above app windows.
    @Test func aSystemAlertSitsBetweenTheTwoLevelsTheIslandUses() {
        #expect(IslandPanelLevel.standard.rawValue > NSWindow.Level.modalPanel.rawValue)
        #expect(IslandPanelLevel.underSystemPrompt.rawValue < NSWindow.Level.modalPanel.rawValue)
        #expect(IslandPanelLevel.underSystemPrompt.rawValue > NSWindow.Level.normal.rawValue)
    }

    @Test func onlyAnOpenIslandStepsBelowAPrompt() {
        #expect(IslandPanelLevel.level(isOpen: true, isSystemPromptUp: true) == IslandPanelLevel.underSystemPrompt)
        #expect(IslandPanelLevel.level(isOpen: false, isSystemPromptUp: true) == IslandPanelLevel.standard)
        #expect(IslandPanelLevel.level(isOpen: true, isSystemPromptUp: false) == IslandPanelLevel.standard)
        #expect(IslandPanelLevel.level(isOpen: false, isSystemPromptUp: false) == IslandPanelLevel.standard)
    }
}

@MainActor
@Suite(.noNewWindows)
struct IslandSystemPromptTests {
    private static func nook() -> NookModel {
        NookModel(defaults: MemoryDefaults(), looksForImportedGIF: false)
    }

    // MARK: The count

    @Test func theIslandIsToldOnceWhenTheFirstPromptGoesUpAndOnceWhenTheLastIsAnswered() {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }

        nook.systemPromptBegan()
        nook.systemPromptBegan()
        #expect(told == [true])
        #expect(nook.isSystemPromptUp)

        nook.systemPromptEnded()
        #expect(told == [true])
        #expect(nook.isSystemPromptUp)

        nook.systemPromptEnded()
        #expect(told == [true, false])
        #expect(nook.isSystemPromptUp == false)
    }

    @Test func anAnswerToAPromptThatWasNeverCountedChangesNothing() {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }

        nook.systemPromptEnded()

        #expect(told.isEmpty)
        #expect(nook.isSystemPromptUp == false)
    }

    // MARK: The requests

    /// The button on the tour's to-dos page ends in this call.
    @Test func aRemindersRequestCountsAsAPromptWhileMacOSIsAsking() async {
        let nook = Self.nook()
        let permission = FakeEventKitPermission(status: .notDetermined, answer: .denied)
        var wasUpDuringThePrompt = false
        permission.whilePromptIsUp = { wasUpDuringThePrompt = nook.isSystemPromptUp }
        let reminders = NookRemindersService(access: permission.access, defaults: MemoryDefaults())
        reminders.start(nook: nook)
        #expect(nook.isSystemPromptUp == false)

        await reminders.requestAccessIfUndecided()

        #expect(permission.requestCount == 1)
        #expect(wasUpDuringThePrompt)
        #expect(nook.isSystemPromptUp == false, "the answer ends it")
    }

    @Test func aCalendarRequestCountsAsAPromptWhileMacOSIsAsking() async {
        let nook = Self.nook()
        let permission = FakeEventKitPermission(status: .notDetermined, answer: .denied)
        var wasUpDuringThePrompt = false
        permission.whilePromptIsUp = { wasUpDuringThePrompt = nook.isSystemPromptUp }
        let calendar = NookCalendarService(access: permission.access, defaults: MemoryDefaults())
        calendar.start(nook: nook)

        await calendar.requestAccessIfUndecided()

        #expect(permission.requestCount == 1)
        #expect(wasUpDuringThePrompt)
        #expect(nook.isSystemPromptUp == false)
    }

    /// A permission that was answered before raises no prompt and moves nothing.
    @Test func aRequestThatAsksMacOSNothingIsNotCounted() async {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let permission = FakeEventKitPermission(status: .denied)
        let reminders = NookRemindersService(access: permission.access, defaults: MemoryDefaults())
        reminders.start(nook: nook)

        await reminders.requestAccessIfUndecided()

        #expect(permission.requestCount == 0)
        #expect(told.isEmpty)
    }

    // MARK: The panel

    /// The open island steps below the prompt and comes back when it is
    /// answered. A closed one stays put, and one opened while the prompt is
    /// up steps below it too.
    @Test func theOpenIslandStepsBelowAPromptAndComesBack() throws {
        guard !NSScreen.screens.isEmpty else { return }
        let model = AppModel(defaults: MemoryDefaults())
        model.disablesOverlayEventMonitoringDuringHarness = true
        model.overlay.ensureOverlayPanel()
        model.letSystemPromptsShowOverTheIsland()
        let controller = model.overlay.overlayPanelController
        #expect(controller.panelLevel == IslandPanelLevel.standard)

        model.nook.systemPromptBegan()
        #expect(controller.panelLevel == IslandPanelLevel.standard, "a closed island covers nothing")

        model.notchOpen(reason: .click)
        #expect(controller.panelLevel == IslandPanelLevel.underSystemPrompt)

        model.nook.systemPromptEnded()
        #expect(controller.panelLevel == IslandPanelLevel.standard)

        model.nook.systemPromptBegan()
        #expect(controller.panelLevel == IslandPanelLevel.underSystemPrompt)

        model.notchClose()
        #expect(controller.panelLevel == IslandPanelLevel.standard)
        model.nook.systemPromptEnded()

        // The camera's request reaches the same count through its own hook.
        NookMirrorController.shared.onSystemPromptChange?(true)
        #expect(model.nook.isSystemPromptUp)
        NookMirrorController.shared.onSystemPromptChange?(false)
        #expect(model.nook.isSystemPromptUp == false)
    }

    /// The hooks are installed where the app starts. Without that call no
    /// prompt would move the island.
    @Test func theAppInstallsTheHooksWhenItStarts() throws {
        let source = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/AppModel.swift")
        let start = try #require(source.range(of: "func startIfNeeded("))

        #expect(source[start.upperBound...].contains("        letSystemPromptsShowOverTheIsland()\n"))
    }

    // MARK: Notes

    /// macOS asks once whether the app may control Notes, at the first send.
    /// That send counts as a prompt. Later ones do not, allowed or refused.
    @Test func onlyTheFirstSendToNotesCountsAsAPrompt() async {
        for refusal in [NookAppleNotesError?.none, .notPermitted] {
            let nook = Self.nook()
            var told: [Bool] = []
            nook.onSystemPromptChange = { told.append($0) }
            let harness = NookNotesHarness()
            harness.bridge.fail(with: refusal)
            let notes = harness.makeStore(saveTo: .appleNotes, start: false)
            notes.start(nook: nook)
            #expect(notes.hasNotesAnswer == false)

            notes.beginNewNote()
            notes.edit("first")
            notes.flush()
            await notes.lastSync?.value
            #expect(told == [true, false])
            #expect(notes.hasNotesAnswer)

            notes.edit("first and second")
            notes.flush()
            await notes.lastSync?.value
            #expect(told == [true, false], "macOS asks no second time")
        }
    }

    /// A send that failed some other way may have come before macOS asked.
    @Test func aSendThatFailedForAnotherReasonStillCountsNextTime() async {
        let nook = Self.nook()
        var told: [Bool] = []
        nook.onSystemPromptChange = { told.append($0) }
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let notes = harness.makeStore(saveTo: .appleNotes, start: false)
        notes.start(nook: nook)

        notes.beginNewNote()
        notes.edit("first")
        notes.flush()
        await notes.lastSync?.value
        notes.edit("first and second")
        notes.flush()
        await notes.lastSync?.value

        #expect(told == [true, false, true, false])
        #expect(notes.hasNotesAnswer == false)
    }
}
