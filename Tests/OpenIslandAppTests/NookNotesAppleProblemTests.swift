import Foundation
import Testing
@testable import OpenIslandApp

/// Apple Notes not taking the notes (N4). The refusal used to be said once
/// to the closed island, a send that failed was dropped, and the tour ticked
/// "Saved" for a note that never reached Notes. Every Notes app here is a
/// fake.
@MainActor
@Suite struct NookNotesAppleProblemTests {
    private func save(_ store: NookNotesStore, _ text: String, harness: NookNotesHarness) async {
        store.beginNewNote()
        store.edit(text)
        store.flush()
        store.closeEditor()
        await harness.settle(store)
    }

    // MARK: The problem stays

    @Test func aRefusalStaysWhereTheEditorAndTheCardCanShowIt() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .notPermitted)
        let store = harness.makeStore(saveTo: .both)

        await save(store, "Plan\nbody", harness: harness)

        #expect(store.appleNotesProblem == .notPermitted)
        #expect(store.shownProblem == .appleNotesOff(keptIn: .folder))
        #expect(harness.notices == [.appleNotesOff(keptIn: .folder)], "said to the closed island once as well")
    }

    @Test func aRefusalForAppleNotesOnlyIsToldAsKeptInHangover() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .notPermitted)
        let store = harness.makeStore(saveTo: .appleNotes)

        await save(store, "Plan\nbody", harness: harness)

        #expect(store.shownProblem == .appleNotesOff(keptIn: .hangover))
    }

    @Test func theProblemSurvivesAQuitAndALaunch() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .notPermitted)
        let first = harness.makeStore(saveTo: .both)
        await save(first, "Plan\nbody", harness: harness)

        let second = harness.makeStore()
        // The next launch tries the note again; the answer has not come yet.
        #expect(second.appleNotesProblem == .notPermitted)
        #expect(second.shownProblem == .appleNotesOff(keptIn: .folder))
        await harness.settle(second)
    }

    @Test func anotherFailureIsToldAsAFailureAndNotAsARefusal() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)

        await save(store, "Plan\nbody", harness: harness)

        #expect(store.appleNotesProblem == .failed)
        #expect(store.shownProblem == .appleNotesFailed(keptIn: .folder))
    }

    @Test func aSendThatWorksTakesTheProblemAway() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)
        await save(store, "Plan\nbody", harness: harness)
        harness.bridge.fail(with: nil)

        await save(store, "Other\nbody", harness: harness)

        #expect(store.appleNotesProblem == nil)
        #expect(store.shownProblem == nil)
        #expect(harness.defaults.string(forKey: NookNotesStore.appleProblemKey) == nil)
    }

    @Test func theProblemIsNotShownWhenNotesDoNotGoToAppleNotes() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)
        await save(store, "Plan\nbody", harness: harness)

        store.setSaveTo(.folder)

        #expect(store.appleNotesNotice == nil)
        #expect(store.shownProblem == nil)
    }

    @Test func aSaveProblemComesBeforeTheAppleOne() async throws {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)
        await save(store, "Plan\nbody", harness: harness)
        try FileManager.default.removeItem(at: harness.folder)
        try Data("x".utf8).write(to: harness.folder)
        store.beginNewNote()
        store.edit("Other\nbody")
        store.flush()

        #expect(store.shownProblem == .notSavedInFolder("Notes Folder"))
    }

    @Test func aRefusalOffersTheAutomationPageOfSystemSettings() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        #expect(NookNotesNotice.appleNotesOff(keptIn: .folder).actions == [.openAutomationSettings])
        #expect(NookNotesNotice.appleNotesFailed(keptIn: .folder).actions.isEmpty)

        store.perform(.openAutomationSettings)

        #expect(harness.openedSettings.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        ])
    }

    @Test func settingsAndTheCardAndTheEditorShowIt() throws {
        let settings = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Notes/NookNotesSettings.swift")
        let card = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Notes/NookNotesCard.swift")
        let editor = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/Nook/Widgets/Notes/NookNoteEditor.swift")

        #expect(settings.contains("store.appleNotesNotice"))
        #expect(settings.contains("store.perform(action)"))
        #expect(card.contains("store.shownProblem"))
        #expect(editor.contains("store.shownProblem"))
    }

    // MARK: A send that failed is kept

    @Test func aNoteNotesDidNotTakeIsSentAgainAtTheNextLaunch() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let first = harness.makeStore(saveTo: .both)
        await save(first, "Plan\nbody", harness: harness)
        #expect(harness.bridge.createCount == 1, "tried once, and failed")
        harness.bridge.fail(with: nil)

        let second = harness.makeStore()
        await harness.settle(second)

        #expect(harness.bridge.createCount == 2, "the note reached Notes at the next launch")
        #expect(second.appleNotesProblem == nil)
        #expect(NookNotesBacklog(defaults: harness.defaults).noteIDs(scope: harness.folder.standardizedFileURL.path).isEmpty)
    }

    @Test func aNoteThatFailsAgainAtLaunchStaysKeptAndIsNotToldToTheClosedIslandAgain() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let first = harness.makeStore(saveTo: .both)
        await save(first, "Plan\nbody", harness: harness)
        let told = harness.notices.count

        let second = harness.makeStore()
        await harness.settle(second)

        #expect(harness.notices.count == told, "the problem is on the card; the closed island is not bothered again")
        #expect(NookNotesBacklog(defaults: harness.defaults).noteIDs(scope: harness.folder.standardizedFileURL.path) == ["Plan.md"])
    }

    @Test func theNotesThatWaitedAreSentAfterTheNextSendThatWorks() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)
        await save(store, "Alpha\nbody", harness: harness)
        await save(store, "Beta\nbody", harness: harness)
        #expect(harness.bridge.createCount == 2)
        harness.bridge.fail(with: nil)

        await save(store, "Gamma\nbody", harness: harness)

        // Gamma, then Alpha and Beta again.
        #expect(harness.bridge.createCount == 5)
        #expect(NookNotesBacklog(defaults: harness.defaults).noteIDs(scope: harness.folder.standardizedFileURL.path).isEmpty)
        #expect(store.appleNotesProblem == nil)
    }

    @Test func aRetryThatWorksDoesNotStartAnotherRound() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)
        await save(store, "Alpha\nbody", harness: harness)
        harness.bridge.fail(with: nil)

        await save(store, "Beta\nbody", harness: harness)
        await harness.settle(store)

        // Beta and Alpha again: two sends, not a loop.
        #expect(harness.bridge.createCount == 1 + 2)
    }

    @Test func aDeleteNotesDidNotTakeIsSentAgainAtTheNextLaunch() async {
        let harness = NookNotesHarness()
        let first = harness.makeStore(saveTo: .both)
        await save(first, "Plan\nbody", harness: harness)
        harness.bridge.fail(with: .failed)
        first.delete("Plan.md")
        await harness.settle(first)
        harness.bridge.fail(with: nil)

        let second = harness.makeStore()
        await harness.settle(second)

        #expect(harness.bridge.calls.last == .delete(id: "apple-1"))
        #expect(NookNotesBacklog(defaults: harness.defaults).erasures(scope: harness.folder.standardizedFileURL.path).isEmpty)
    }

    @Test func aNoteDeletedWhileItWaitedIsLetGoOf() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let first = harness.makeStore(saveTo: .both)
        await save(first, "Plan\nbody", harness: harness)
        harness.removeOutside("Plan.md")
        harness.bridge.fail(with: nil)

        let second = harness.makeStore()
        await harness.settle(second)

        #expect(harness.bridge.createCount == 1, "nothing to send")
        #expect(NookNotesBacklog(defaults: harness.defaults).noteIDs(scope: harness.folder.standardizedFileURL.path).isEmpty)
    }

    @Test func aRenameMovesWhatWaitsToTheNewName() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Plan\nbody")
        store.flush()
        await harness.settle(store)
        store.edit("Plan B\nbody")
        store.flush()
        await harness.settle(store)

        let waiting = NookNotesBacklog(defaults: harness.defaults).noteIDs(scope: harness.folder.standardizedFileURL.path)

        #expect(waiting == ["Plan B.md"])
    }

    // MARK: The tour's tick

    @Test func aNoteIsCountedAsSavedForAppleNotesOnlyWhenNotesTookIt() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .appleNotes)

        await save(store, "Plan\nbody", harness: harness)
        #expect(store.savedCount == 0, "Notes did not take it: the tour must not say Saved")

        harness.bridge.fail(with: nil)
        await save(store, "Other\nbody", harness: harness)
        #expect(store.savedCount == 1, "Other; Plan is sent again after it and is not a new save")
    }

    @Test func aNoteIsCountedAsSavedAtOnceWhenItIsAFile() async {
        let harness = NookNotesHarness()
        harness.bridge.fail(with: .failed)
        let store = harness.makeStore(saveTo: .both)

        store.beginNewNote()
        store.edit("Plan\nbody")
        store.flush()

        #expect(store.savedCount == 1)
        await harness.settle(store)
        #expect(store.savedCount == 1)
    }
}
