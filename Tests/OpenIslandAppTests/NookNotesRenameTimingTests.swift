import Foundation
import Testing
@testable import OpenIslandApp

/// When a note's file is renamed (N16). A note typed as "Gro" and then
/// "Groceries" was two renames, one at each autosave, while the spec says a
/// file is never renamed mid-typing. Now the file keeps its first name while
/// the user types, and takes the title's name when the editor closes or the
/// first line has held still for five seconds.
@MainActor
@Suite struct NookNotesRenameTimingTests {
    /// A store with "Gro" typed and autosaved, and then "Groceries" typed
    /// and autosaved. The file is still Gro.md.
    private func typedGroThenGroceries() -> (NookNotesHarness, NookNotesStore) {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Gro\nmilk")
        harness.letTheSaveHappen()
        store.edit("Groceries\nmilk")
        harness.letTheSaveHappen()
        return (harness, store)
    }

    // MARK: While typing

    @Test func anAutosaveKeepsTheFilesNameWhileTheFirstLineChanges() {
        let (harness, store) = typedGroThenGroceries()

        #expect(harness.fileNames() == ["Gro.md"], "one file, still named for the first thing typed")
        #expect(harness.text(of: "Gro.md")?.hasSuffix("Groceries\nmilk") == true, "its text is up to date")
        #expect(store.notes.map(\.id) == ["Gro.md"])
        #expect(harness.trashed().isEmpty)
    }

    @Test func aFirstLineThatStillFitsTheNameStartsNoWaitForARename() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Plan\none")
        harness.letTheSaveHappen()
        store.edit("Plan\none\ntwo")
        harness.letTheSaveHappen()

        #expect(harness.scheduler.delays.isEmpty, "nothing to rename, nothing waiting")
        #expect(harness.fileNames() == ["Plan.md"])
    }

    // MARK: The rename

    @Test func closingTheEditorRenamesTheFile() {
        let (harness, store) = typedGroThenGroceries()

        store.closeEditor()

        #expect(harness.fileNames() == ["Groceries.md"])
        #expect(harness.trashed() == ["Gro.md"])
        #expect(store.notes.map(\.id) == ["Groceries.md"])
    }

    @Test func openingAnotherNoteRenamesTheFirst() {
        let (harness, store) = typedGroThenGroceries()
        harness.writeOutside("Other.md", "Other\ntext")
        store.reload()

        store.open("Other.md")

        #expect(harness.fileNames() == ["Groceries.md", "Other.md"])
    }

    @Test func startingANewNoteRenamesTheFirst() {
        let (harness, store) = typedGroThenGroceries()

        store.beginNewNote()

        #expect(harness.fileNames() == ["Groceries.md"])
    }

    @Test func quittingRenamesTheFile() {
        let (harness, store) = typedGroThenGroceries()

        store.appWillTerminate()

        #expect(harness.fileNames() == ["Groceries.md"])
    }

    @Test func aFirstLineThatHoldsStillForFiveSecondsRenamesTheFile() {
        let (harness, store) = typedGroThenGroceries()
        #expect(harness.scheduler.delays == [NookNoteSizes.renameDelay], "the wait for the rename is running")
        #expect(NookNoteSizes.renameDelay == .seconds(5))

        harness.letTheSaveHappen()

        #expect(harness.fileNames() == ["Groceries.md"])
        #expect(store.notes.map(\.id) == ["Groceries.md"])
        #expect(store.isEditorOpen, "the editor stays open")
        // What is typed next goes to the file under its new name.
        store.edit("Groceries\nmilk\neggs")
        harness.letTheSaveHappen()
        #expect(harness.fileNames() == ["Groceries.md"])
        #expect(harness.text(of: "Groceries.md")?.hasSuffix("eggs") == true)
    }

    @Test func aNewFirstLineStartsTheFiveSecondsOver() {
        let (harness, store) = typedGroThenGroceries()
        #expect(harness.scheduler.delays == [NookNoteSizes.renameDelay])

        store.edit("Groceries and more\nmilk")

        #expect(harness.scheduler.delays == [NookNoteSizes.saveDelay], "only the autosave waits; the rename wait was dropped")
        harness.letTheSaveHappen()
        #expect(harness.fileNames() == ["Gro.md"], "the autosave did not rename")
        #expect(harness.scheduler.delays == [NookNoteSizes.renameDelay], "and the five seconds began again")
        harness.letTheSaveHappen()
        #expect(harness.fileNames() == ["Groceries and more.md"])
    }

    @Test func aWaitThatWasDroppedAndEndsLateDoesNothing() {
        let (harness, store) = typedGroThenGroceries()
        store.edit("Another title\nmilk")

        harness.scheduler.fireCancelled()

        #expect(harness.fileNames() == ["Gro.md"], "a cancelled wait that wakes up late renames nothing")
    }

    @Test func aTitleTypedBackToTheFilesNameNeedsNoRename() {
        let (harness, store) = typedGroThenGroceries()
        store.edit("Gro\nmilk")
        harness.letTheSaveHappen()

        #expect(harness.scheduler.delays.isEmpty)
        store.closeEditor()
        #expect(harness.fileNames() == ["Gro.md"])
        #expect(harness.trashed().isEmpty)
    }

    @Test func aRenameThatClashesGetsANumberAndNeverOverwrites() {
        let harness = NookNotesHarness()
        harness.writeOutside("Groceries.md", "Groceries\nsomeone else's note")
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Gro\nmilk")
        harness.letTheSaveHappen()
        store.edit("Groceries\nmilk")
        harness.letTheSaveHappen()

        store.closeEditor()

        #expect(harness.fileNames() == ["Groceries 2.md", "Groceries.md"])
        #expect(harness.text(of: "Groceries.md")?.hasSuffix("someone else's note") == true)
    }

    @Test func anEmptiedNoteLeavesNoRenameBehind() {
        let (harness, store) = typedGroThenGroceries()

        store.edit("")
        harness.letTheSaveHappen()
        store.edit("Fresh\nstart")
        harness.letTheSaveHappen()

        #expect(harness.fileNames() == ["Fresh.md"], "the emptied note was deleted and the new one has its own name")
    }

    // MARK: The destination

    @Test func aSaveAskedNotToRenameKeepsTheNameAndSaysSo() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookRenameTiming-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = NookFolderDestination(folder: folder, calendar: NookNotesHarness.calendar, trash: { url in
            try FileManager.default.removeItem(at: url)
        })
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try destination.save(text: "Gro\nmilk", id: nil, base: nil, created: when, now: when, renaming: false)
        #expect(first.note.id == "Gro.md", "a new note is named at its first save")
        #expect(!first.isRenamePending)

        let kept = try destination.save(text: "Groceries\nmilk", id: first.note.id, base: "Gro\nmilk", created: when, now: when, renaming: false)
        #expect(kept.note.id == "Gro.md")
        #expect(kept.isRenamePending)

        let renamed = try destination.save(text: "Groceries\nmilk", id: kept.note.id, base: "Groceries\nmilk", created: when, now: when, renaming: true)
        #expect(renamed.note.id == "Groceries.md")
        #expect(!renamed.isRenamePending)
    }
}
