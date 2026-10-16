import Foundation
import Testing
@testable import OpenIslandApp

/// The notes store with notes kept as files (D70): saving by itself, the
/// list, the editor, deleting and reading what another program changed.
/// Every folder is a temporary one; no real Notes app, vault or Trash.
@MainActor
@Suite struct NookNotesStoreTests {
    // MARK: Saving by itself

    @Test func aNoteIsSavedAfterTheLastKeyAndNotBefore() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore()

        store.beginNewNote()
        store.edit("Groceries\nmilk")

        #expect(harness.scheduler.waitingCount == 1)
        #expect(harness.scheduler.delays == [NookNoteSizes.saveDelay])
        #expect(harness.fileNames().isEmpty, "nothing is written while the wait runs")
        #expect(store.notes.isEmpty)
        #expect(store.savedCount == 0)

        harness.letTheSaveHappen()

        #expect(harness.fileNames() == ["Groceries.md"])
        #expect(store.notes.map(\.title) == ["Groceries"])
        #expect(store.savedCount == 1)
    }

    @Test func theFileCarriesFrontMatterAndTheTextAsTyped() async throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()

        store.beginNewNote()
        store.edit("Groceries\nmilk\n\neggs")
        harness.letTheSaveHappen()

        let text = try #require(harness.text(of: "Groceries.md"))
        let parsed = NookNoteFiles.parse(text, calendar: NookNotesHarness.calendar)
        #expect(parsed.body == "Groceries\nmilk\n\neggs")
        #expect(parsed.created == harness.date)
        #expect(parsed.updated == harness.date)
    }

    @Test func typingAgainStartsTheWaitOver() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore()

        store.beginNewNote()
        store.edit("One")
        store.edit("One two")
        store.edit("One two three")

        // The first two waits ended when they were replaced.
        #expect(harness.scheduler.waitingCount == 1)
        harness.letTheSaveHappen()

        #expect(harness.fileNames() == ["One two three.md"])
        #expect(store.savedCount == 1, "three keys, one save")
    }

    @Test func aWaitThatWakesUpAfterItWasReplacedDoesNothing() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("First words")
        store.edit("First words and more")

        // The replaced wait wakes late, the way a task can.
        harness.scheduler.fireCancelled()

        #expect(harness.fileNames().isEmpty, "only the last wait may save")
        #expect(store.savedCount == 0)
    }

    @Test func aWaitThatWakesUpAfterTheEditorClosedDoesNothing() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Saved by closing")
        store.closeEditor()
        store.beginNewNote()
        store.edit("A second note")

        harness.scheduler.fireCancelled()

        #expect(harness.fileNames() == ["Saved by closing.md"])
    }

    @Test func theWaitIsOneSecond() {
        #expect(NookNoteSizes.saveDelay == .seconds(1))
    }

    @Test func closingTheEditorSavesAtOnce() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()

        store.beginNewNote()
        store.edit("Quick one")
        store.closeEditor()

        #expect(harness.fileNames() == ["Quick one.md"])
        #expect(!store.isEditorOpen)
        #expect(!store.hasPendingSave && harness.scheduler.waitingCount == 0, "the wait was dropped")
    }

    @Test func flushSavesWithoutClosing() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()

        store.beginNewNote()
        store.edit("Keep typing")

        #expect(store.flush())
        #expect(store.isEditorOpen)
        #expect(harness.fileNames() == ["Keep typing.md"])
    }

    @Test func theIslandClosingSavesTheNoteAndClosesTheEditor() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Typed when the island closed")

        store.islandClosed()

        #expect(harness.fileNames() == ["Typed when the island closed.md"])
        #expect(!store.isEditorOpen)
    }

    @Test func anEditWithNothingNewIsNotWrittenAgain() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Same")
        store.flush()
        let first = harness.text(of: "Same.md")

        harness.date = harness.date.addingTimeInterval(600)
        store.edit("Same changed")
        store.edit("Same")
        store.flush()

        #expect(harness.text(of: "Same.md") == first)
        #expect(store.savedCount == 1)
    }

    // MARK: Empty notes

    @Test func aNoteLeftEmptyIsNeverSaved() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()

        store.beginNewNote()
        store.edit("   \n  ")
        store.closeEditor()

        #expect(harness.fileNames().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: harness.folder.path), "not even the folder is made")
        #expect(store.notes.isEmpty)
        #expect(store.savedCount == 0)
    }

    @Test func anExistingNoteEmptiedByTheUserIsMovedToTheTrash() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Doomed")
        store.flush()

        store.edit("")
        harness.letTheSaveHappen()

        #expect(harness.fileNames().isEmpty)
        #expect(harness.trashed() == ["Doomed.md"])
        #expect(store.notes.isEmpty)
        #expect(store.isEditorOpen, "the editor stays, blank")
    }

    @Test func typingAfterEmptyingAMakesANewNote() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Old words")
        store.flush()
        store.edit("")
        store.flush()
        harness.date = harness.date.addingTimeInterval(60)

        store.edit("Fresh start")
        store.flush()

        #expect(harness.fileNames() == ["Fresh start.md"])
        #expect(harness.trashed() == ["Old words.md"])
    }

    // MARK: Names

    @Test func theFileKeepsItsNameWhileTheTitleStaysTheSame() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Plan\none")
        store.flush()

        store.edit("Plan\none\ntwo")
        store.flush()

        #expect(harness.fileNames() == ["Plan.md"])
        #expect(store.notes.first?.id == "Plan.md")
    }

    @Test func aNewTitleRenamesTheFileOnSave() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Plan\nbody")
        store.flush()
        let created = try #require(store.notes.first?.created)

        harness.date = harness.date.addingTimeInterval(3_600)
        store.edit("Plan the week\nbody")
        store.flush()

        #expect(harness.fileNames() == ["Plan the week.md"], "renamed, not copied")
        #expect(store.notes.map(\.id) == ["Plan the week.md"])
        #expect(store.notes.first?.created == created)
    }

    @Test func twoNotesWithOneTitleGetANumber() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Ideas")
        store.flush()
        store.beginNewNote()
        store.edit("Ideas\nsecond")
        store.flush()

        #expect(harness.fileNames() == ["Ideas 2.md", "Ideas.md"])
    }

    @Test func aTitleThatCannotBeAFileNameSavesAsUntitled() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("???\nbody")
        store.flush()

        #expect(harness.fileNames() == ["Untitled.md"])
    }

    // MARK: Opening

    @Test func aNoteFromTheListOpensInTheEditorAndSavesToItsFile() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Recipe\nflour")
        store.flush()
        store.closeEditor()

        store.open("Recipe.md")
        #expect(store.isEditorOpen)
        #expect(store.editorText == "Recipe\nflour")

        harness.date = harness.date.addingTimeInterval(90)
        store.edit("Recipe\nflour\nsugar")
        store.closeEditor()

        #expect(harness.fileNames() == ["Recipe.md"])
        #expect(NookNoteFiles.parse(harness.text(of: "Recipe.md") ?? "", calendar: NookNotesHarness.calendar).body == "Recipe\nflour\nsugar")
    }

    @Test func aNewNoteWhileOneIsOpenSavesTheFirst() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("First note")

        store.beginNewNote()

        #expect(harness.fileNames() == ["First note.md"])
        #expect(store.editorText == "")
        #expect(store.isEditorOpen)
    }

    @Test func aNewNoteOverABlankOneJustGivesItTheCursor() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        let focus = store.focusRequest
        let revision = store.editorRevision

        store.beginNewNote()

        #expect(store.focusRequest == focus + 1)
        #expect(store.editorRevision == revision)
    }

    @Test func openingAnUnknownNoteDoesNothing() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()

        store.open("Nothing here.md")

        #expect(!store.isEditorOpen)
    }

    // MARK: Order

    @Test func theNoteEditedLastIsFirstInTheList() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        for title in ["Alpha", "Beta", "Gamma"] {
            harness.date = harness.date.addingTimeInterval(60)
            store.beginNewNote()
            store.edit(title)
            store.closeEditor()
        }
        #expect(store.notes.map(\.title) == ["Gamma", "Beta", "Alpha"])

        harness.date = harness.date.addingTimeInterval(60)
        store.open("Alpha.md")
        store.edit("Alpha edited")
        store.closeEditor()

        #expect(store.notes.map(\.title) == ["Alpha edited", "Gamma", "Beta"])
    }

    // MARK: Deleting

    @Test func deletingMovesTheFileToTheTrash() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Throw away")
        store.closeEditor()

        store.delete("Throw away.md")

        #expect(harness.fileNames().isEmpty)
        #expect(harness.trashed() == ["Throw away.md"])
        #expect(store.notes.isEmpty)
    }

    @Test func deletingTheOpenNoteClosesTheEditor() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Open and gone")
        store.flush()

        store.delete("Open and gone.md")

        #expect(!store.isEditorOpen)
        #expect(harness.trashed() == ["Open and gone.md"])
    }

    @Test func aFileThatCannotBeTrashedKeepsItsRowAndSaysSo() {
        let harness = NookNotesHarness()
        // A Trash that is a file cannot take anything.
        try? FileManager.default.createDirectory(at: harness.home, withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: harness.trashFolder)
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Stuck")
        store.closeEditor()

        store.delete("Stuck.md")

        #expect(harness.notices == [.notDeleted])
        #expect(store.notes.map(\.title) == ["Stuck"])
        #expect(harness.fileNames() == ["Stuck.md"])
    }

    // MARK: The draft guard

    @Test func textNotYetSavedHoldsTheIslandOpen() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        #expect(!store.holdsUnsavedDraft)

        store.edit("Half a thought")
        #expect(store.holdsUnsavedDraft)
        #expect(harness.drafts.last == true)

        harness.letTheSaveHappen()
        #expect(!store.holdsUnsavedDraft)
        #expect(harness.drafts.last == false)
    }

    @Test func blankTextHoldsNothing() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()

        store.edit("  \n")

        #expect(!store.holdsUnsavedDraft)
    }

    @Test func closingTheEditorLetsGoOfTheDraft() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Typed")

        store.closeEditor()

        #expect(harness.drafts.last == false)
    }

    // MARK: A write that fails

    @Test func aNoteThatCannotBeWrittenStaysInTheEditorWithANotice() throws {
        let harness = NookNotesHarness()
        // The notes folder is a file, so nothing can be made in it.
        try Data("x".utf8).write(to: harness.folder)
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Cannot land")

        store.islandClosed()

        #expect(harness.notices == [.cantReadFolder("Notes Folder"), .notSavedInFolder("Notes Folder")])
        #expect(store.isEditorOpen, "the text is still there")
        #expect(store.editorText == "Cannot land")
        #expect(store.holdsUnsavedDraft)
        #expect(store.savedCount == 0)
    }

    // MARK: Changes made elsewhere

    @Test func aNoteAddedInObsidianShowsInTheList() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        #expect(store.notes.isEmpty)

        harness.writeOutside("From Obsidian.md", "From Obsidian\nhello", modified: harness.date)
        store.reload()

        #expect(store.notes.map(\.title) == ["From Obsidian"])
    }

    @Test func aNoteEditedInObsidianShowsItsNewTextAndRises() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        for title in ["Older", "Newer"] {
            harness.date = harness.date.addingTimeInterval(60)
            store.beginNewNote()
            store.edit(title)
            store.closeEditor()
        }
        #expect(store.notes.map(\.title) == ["Newer", "Older"])

        harness.writeOutside("Older.md", "Older\nedited elsewhere", modified: harness.date.addingTimeInterval(600))
        store.reload()

        #expect(store.notes.map(\.title) == ["Older", "Newer"])
        #expect(store.notes.first?.text == "Older\nedited elsewhere")
    }

    @Test func aNoteDeletedInObsidianLeavesTheList() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Soon gone")
        store.closeEditor()

        harness.removeOutside("Soon gone.md")
        store.reload()

        #expect(store.notes.isEmpty)
    }

    @Test func anOpenNoteWithNothingUnsavedFollowsAnEditMadeElsewhere() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Shared\nline one")
        store.flush()
        let revision = store.editorRevision

        harness.writeOutside("Shared.md", "Shared\nline one\nline two", modified: harness.date.addingTimeInterval(120))
        store.reload()

        #expect(store.editorText == "Shared\nline one\nline two")
        #expect(store.editorRevision == revision + 1)
        #expect(!store.holdsUnsavedDraft)
    }

    @Test func anOpenNoteWithTextTypedKeepsItWhenTheFileChangesElsewhere() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Shared\nline one")
        store.flush()
        store.edit("Shared\nline one\nmy new line")

        harness.writeOutside("Shared.md", "Shared\nline one\ntheir line", modified: harness.date.addingTimeInterval(120))
        store.reload()

        #expect(store.editorText == "Shared\nline one\nmy new line")
        #expect(store.holdsUnsavedDraft)
    }

    @Test func anOpenNoteDeletedElsewhereClosesTheEditorWhenNothingIsUnsaved() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Doomed elsewhere")
        store.flush()

        harness.removeOutside("Doomed elsewhere.md")
        store.reload()

        #expect(!store.isEditorOpen)
    }

    @Test func anOpenNoteDeletedElsewhereWithTextTypedBecomesANewNote() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Doomed elsewhere")
        store.flush()
        store.edit("Doomed elsewhere, but I kept typing")

        harness.removeOutside("Doomed elsewhere.md")
        store.reload()
        store.flush()

        #expect(store.isEditorOpen)
        #expect(harness.fileNames() == ["Doomed elsewhere, but I kept typing.md"])
    }

    // MARK: Watching the folder

    @Test func aFolderThatExistsIsWatchedFromTheStart() {
        let harness = NookNotesHarness()
        try? FileManager.default.createDirectory(at: harness.folder, withIntermediateDirectories: true)

        let store = harness.makeStore()
        defer { withExtendedLifetime(store) {} }

        #expect(harness.watcher.watched == harness.folder)
    }

    @Test func aFolderThatDoesNotExistYetIsNotMadeJustToBeWatched() {
        let harness = NookNotesHarness()

        let store = harness.makeStore()

        #expect(harness.watcher.watched == harness.home, "the folder it will be made in is watched instead (N9)")
        #expect(!FileManager.default.fileExists(atPath: harness.folder.path))

        store.beginNewNote()
        store.edit("First note ever")
        store.flush()

        #expect(harness.watcher.watched == harness.folder, "watched once the first note made the folder")
    }

    @Test func aReportFromTheWatcherReadsTheFolderAgain() {
        let harness = NookNotesHarness()
        try? FileManager.default.createDirectory(at: harness.folder, withIntermediateDirectories: true)
        let store = harness.makeStore()

        harness.writeOutside("Added.md", "Added\nlater", modified: harness.date)
        harness.watcher.fire()

        #expect(store.notes.map(\.title) == ["Added"])
    }

    // MARK: Choosing where notes go

    @Test func changingTheFolderLeavesOldNotesWhereTheyWereAndStartsAnEmptyList() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Stays behind")
        store.closeEditor()
        let other = harness.home.appendingPathComponent("Other", isDirectory: true)

        store.setFolder(other)

        #expect(store.folderURL == other)
        #expect(store.notes.isEmpty)
        #expect(harness.fileNames() == ["Stays behind.md"])
        #expect(harness.defaults.string(forKey: NookNotesStore.folderKey) == other.path)

        store.beginNewNote()
        store.edit("Lands in the new folder")
        store.closeEditor()
        #expect(try FileManager.default.contentsOfDirectory(atPath: other.path) == ["Lands in the new folder.md"])
    }

    @Test func aNoteBeingTypedIsSavedInTheOldPlaceBeforeTheChange() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Half typed")

        store.setFolder(harness.home.appendingPathComponent("Other", isDirectory: true))

        #expect(harness.fileNames() == ["Half typed.md"])
        #expect(!store.isEditorOpen)
    }

    @Test func aNoteThatCannotBeSavedWhereItWasIsCarriedToTheNewPlace() throws {
        let harness = NookNotesHarness()
        try Data("x".utf8).write(to: harness.folder)
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Rescued")
        let other = harness.home.appendingPathComponent("Other", isDirectory: true)

        store.setFolder(other)

        #expect(try FileManager.default.contentsOfDirectory(atPath: other.path) == ["Rescued.md"])
        #expect(store.notes.map(\.title) == ["Rescued"])
    }

    @Test func theChoiceIsKeptForTheNextStart() {
        let harness = NookNotesHarness()
        let first = harness.makeStore()

        first.setSaveTo(.both)

        let second = harness.makeStore(start: false)
        #expect(second.saveTo == .both)
        #expect(harness.defaults.string(forKey: NookNotesStore.saveToKey) == "both")
    }

    @Test func anAppleNotesChoiceFromTheOldQuickNotesCarriesOver() {
        let harness = NookNotesHarness()
        harness.defaults.set("appleNotes", forKey: NookNotesStore.legacyDestinationKey)

        let store = harness.makeStore(start: false)

        #expect(store.saveTo == .appleNotes)
    }

    @Test func aNewInstallSavesToAFolder() {
        let harness = NookNotesHarness(folderIsSet: false)

        let store = harness.makeStore(start: false)

        #expect(store.saveTo == .folder)
        #expect(store.folderURL == harness.home.appendingPathComponent("Documents/Hangover Notes", isDirectory: true))
    }
}
