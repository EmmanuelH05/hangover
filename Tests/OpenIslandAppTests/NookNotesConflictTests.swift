import Foundation
import Testing
@testable import OpenIslandApp

/// A note changed by another program (Obsidian, iCloud) while Hangover has it
/// open (N8 and N13). Hangover's save used to replace the file, and the other
/// program's edit was gone without a word. Every folder is a temporary one.
@MainActor
@Suite struct NookNotesConflictTests {
    private func openPlan(_ harness: NookNotesHarness, saveTo: NookNotesSaveTo? = nil) -> NookNotesStore {
        let store = harness.makeStore(saveTo: saveTo)
        store.beginNewNote()
        store.edit("Plan\nmine")
        store.flush()
        return store
    }

    // MARK: A save that would overwrite

    @Test func aFileChangedByAnotherProgramIsNotWrittenOver() {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        harness.writeOutside("Plan.md", "Plan\ntheirs")

        store.edit("Plan\nmine, and more")
        store.flush()

        #expect(harness.text(of: "Plan.md") == "Plan\ntheirs", "the other program's version is untouched")
        #expect(harness.text(of: "Plan (Hangover).md")?.hasSuffix("Plan\nmine, and more") == true)
        #expect(harness.fileNames() == ["Plan (Hangover).md", "Plan.md"])
    }

    @Test func theCopyIsToldWhereTheUserCanSeeIt() {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        harness.writeOutside("Plan.md", "Plan\ntheirs")

        store.edit("Plan\nmine, and more")
        store.flush()

        #expect(store.problem == .savedAsCopy("Plan (Hangover).md"))
        #expect(harness.notices == [.savedAsCopy("Plan (Hangover).md")])
    }

    @Test func theEditorGoesOnInTheCopyAndMakesNoThirdFile() {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        harness.writeOutside("Plan.md", "Plan\ntheirs")
        store.edit("Plan\nmine, and more")
        store.flush()

        store.edit("Plan\nmine, and more again")
        store.flush()

        #expect(harness.fileNames() == ["Plan (Hangover).md", "Plan.md"])
        #expect(harness.text(of: "Plan (Hangover).md")?.hasSuffix("Plan\nmine, and more again") == true)
        #expect(harness.text(of: "Plan.md") == "Plan\ntheirs")
        #expect(store.notes.map(\.id).sorted() == ["Plan (Hangover).md", "Plan.md"])
    }

    @Test func theNoteAboutACopyStaysThroughLaterSavesAndGoesWhenAnotherNoteIsOpened() {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        harness.writeOutside("Plan.md", "Plan\ntheirs")
        store.edit("Plan\nmine, and more")
        store.flush()

        store.edit("Plan\nmine, and more again")
        store.flush()
        #expect(store.problem == .savedAsCopy("Plan (Hangover).md"), "a save that works does not take it away")

        store.open("Plan.md")
        #expect(store.problem == nil)
    }

    @Test func aSecondConflictMakesASecondCopyAndNeverOverwritesTheFirst() {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        harness.writeOutside("Plan.md", "Plan\ntheirs")
        store.edit("Plan\nfirst")
        store.flush()
        store.open("Plan.md")
        harness.writeOutside("Plan.md", "Plan\ntheirs again")
        store.edit("Plan\nsecond")
        store.flush()

        #expect(harness.fileNames() == ["Plan (Hangover) 2.md", "Plan (Hangover).md", "Plan.md"])
        #expect(harness.text(of: "Plan (Hangover).md")?.hasSuffix("Plan\nfirst") == true)
    }

    @Test func aFileThatIsNotChangedIsSavedInPlaceWithItsOwnFrontMatter() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        harness.writeOutside("Plan.md", "---\ncreated: 2026-10-01T09:00:00\ntags: [work]\n---\nPlan\nmine")
        store.reload()
        store.open("Plan.md")

        store.edit("Plan\nmine, edited")
        store.flush()

        #expect(harness.fileNames() == ["Plan.md"])
        let saved = try #require(harness.text(of: "Plan.md"))
        #expect(saved.contains("tags: [work]"))
        #expect(saved.hasSuffix("Plan\nmine, edited"))
    }

    @Test func aNoteDeletedOutsideIsStillSavedAsANote() {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        harness.removeOutside("Plan.md")

        store.edit("Plan\nmine, and more")
        store.flush()

        #expect(harness.fileNames() == ["Plan.md"])
        #expect(store.problem == nil)
    }

    @Test func aWatcherReportWhileTypingDoesNotReplaceTheTypedText() {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        store.edit("Plan\nmine, and more")
        harness.writeOutside("Plan.md", "Plan\ntheirs")

        harness.watcher.fire()

        #expect(store.editorText == "Plan\nmine, and more")
        store.flush()
        #expect(harness.text(of: "Plan.md") == "Plan\ntheirs")
    }

    // MARK: Opening

    @Test func openingANoteReadsTheFileAgainAndNotTheList() {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        store.closeEditor()
        harness.writeOutside("Plan.md", "Plan\nchanged since the list was read")
        #expect(store.notes.first?.text == "Plan\nmine", "the list has not heard of it")

        store.open("Plan.md")

        #expect(store.editorText == "Plan\nchanged since the list was read")
        #expect(store.notes.first?.text == "Plan\nchanged since the list was read")
    }

    @Test func aNoteThatWentWhileTheListWasOldIsNotOpened() {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        store.closeEditor()
        harness.removeOutside("Plan.md")

        store.open("Plan.md")

        #expect(!store.isEditorOpen)
        #expect(store.notes.isEmpty)
    }

    @Test func aNoteThatCannotBeReadIsToldAndNotOpened() throws {
        let harness = NookNotesHarness()
        let store = openPlan(harness)
        store.closeEditor()
        // Bytes that are not text.
        try Data([0xFF, 0xFE, 0xFD, 0x00, 0x80]).write(to: harness.folder.appendingPathComponent("Plan.md"))

        store.open("Plan.md")

        #expect(!store.isEditorOpen)
        #expect(store.problem == .noteUnreadable("Plan"))
    }

    // MARK: Apple Notes

    @Test func aCopyIsANewAppleNoteAndTheOriginalKeepsItsOwn() async {
        let harness = NookNotesHarness()
        let store = openPlan(harness, saveTo: .both)
        await harness.settle(store)
        harness.writeOutside("Plan.md", "Plan\ntheirs")

        store.edit("Plan\nmine, and more")
        store.flush()
        await harness.settle(store)

        #expect(harness.bridge.createCount == 2)
        #expect(harness.bridge.calls.contains { if case .update = $0 { true } else { false } } == false)
    }

    // MARK: The rules

    @Test func theCopyNameFitsTheTitleSoTheCopyIsNotRenamed() {
        #expect(NookNoteFiles.fileName("Plan (Hangover).md", stillFits: "Plan"))
        #expect(NookNoteFiles.fileName("Plan (Hangover) 2.md", stillFits: "Plan"))
        #expect(!NookNoteFiles.fileName("Plan (Hangover).md", stillFits: "Other"))
    }
}
