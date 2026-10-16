import Foundation
import Testing
@testable import OpenIslandApp

/// A folder or a file that cannot be read (N6). It used to look like "No
/// notes yet", an unreadable note vanished from the list, and the open note
/// was taken for deleted and written again as "Title 2.md". Every folder is a
/// temporary one.
@MainActor
@Suite struct NookNotesUnreadableTests {
    private let notText = Data([0xFF, 0xFE, 0xFD, 0x00, 0x80])

    private func writeUnreadable(_ harness: NookNotesHarness, _ name: String) throws {
        try FileManager.default.createDirectory(at: harness.folder, withIntermediateDirectories: true)
        try notText.write(to: harness.folder.appendingPathComponent(name))
    }

    // MARK: A file that cannot be read

    @Test func anUnreadableFileStaysInTheListAsARowMarkedSo() throws {
        let harness = NookNotesHarness()
        harness.writeOutside("Good.md", "Good\nbody")
        try writeUnreadable(harness, "Bad.md")

        let store = harness.makeStore()

        let bad = try #require(store.notes.first { $0.id == "Bad.md" })
        #expect(bad.state == .unreadable)
        #expect(bad.text.isEmpty)
        #expect(store.notes.first { $0.id == "Good.md" }?.state == .readable)
        #expect(store.notes.count == 2)
    }

    @Test func anUnreadableRowIsKnownByItsFileName() throws {
        let harness = NookNotesHarness()
        try writeUnreadable(harness, "Bad one.md")
        let store = harness.makeStore()
        let bad = try #require(store.notes.first)

        #expect(NookNoteListRules.rowTitle(for: bad, untitled: "Untitled") == "Bad one")
    }

    @Test func anUnreadableFileIsNotOpenedAndTheProblemIsToldWhereItCanBeRead() throws {
        let harness = NookNotesHarness()
        try writeUnreadable(harness, "Bad.md")
        let store = harness.makeStore()

        store.open("Bad.md")

        #expect(!store.isEditorOpen)
        #expect(store.problem == .noteUnreadable("Bad"))
    }

    @Test func anUnreadableFileCanStillBeDeleted() throws {
        let harness = NookNotesHarness()
        try writeUnreadable(harness, "Bad.md")
        let store = harness.makeStore()

        store.delete("Bad.md")

        #expect(store.notes.isEmpty)
        #expect(harness.trashed() == ["Bad.md"])
    }

    @Test func aFileThatCanBeReadAgainBecomesANoteAgain() throws {
        let harness = NookNotesHarness()
        try writeUnreadable(harness, "Bad.md")
        let store = harness.makeStore()
        #expect(store.notes.first?.state == .unreadable)

        harness.writeOutside("Bad.md", "Bad\nmended")
        store.reload()

        #expect(store.notes.first?.state == .readable)
        #expect(store.notes.first?.text == "Bad\nmended")
    }

    @Test func theOpenNoteThatCannotBeReadIsNotTakenForDeletedAndNotWrittenAgain() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Plan\nmine")
        store.flush()
        store.edit("Plan\nmine, more")
        try notText.write(to: harness.folder.appendingPathComponent("Plan.md"))

        harness.watcher.fire()
        store.flush()

        #expect(harness.fileNames() == ["Plan.md"], "no Plan 2.md")
        #expect(store.editorText == "Plan\nmine, more", "what was typed is still there")
        #expect(store.holdsUnsavedDraft)
        #expect(try Data(contentsOf: harness.folder.appendingPathComponent("Plan.md")) == notText, "and the file is not written over")
        #expect(store.problem == .notSavedInFolder("Notes Folder"))
    }

    @Test func theOpenNoteThatTurnsUnreadableKeepsItsTextInTheEditor() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Plan\nmine")
        store.flush()
        try notText.write(to: harness.folder.appendingPathComponent("Plan.md"))

        harness.watcher.fire()

        #expect(store.isEditorOpen)
        #expect(store.editorText == "Plan\nmine", "an unreadable file is not an empty one")
        #expect(!store.holdsUnsavedDraft)
    }

    // MARK: A folder that cannot be read

    @Test func aFolderThatCannotBeListedIsToldAndNotShownAsEmpty() throws {
        let harness = NookNotesHarness()
        try Data("x".utf8).write(to: harness.folder)

        let store = harness.makeStore()

        #expect(store.problem == .cantReadFolder("Notes Folder"))
        #expect(harness.notices == [.cantReadFolder("Notes Folder")])
        #expect(!NookNoteListRules.showsEmptyState(notes: store.notes, problem: store.problem))
    }

    @Test func theEmptyStateIsShownForAFolderWithNoNotesAndNotForOneThatCannotBeRead() {
        #expect(NookNoteListRules.showsEmptyState(notes: [], problem: nil))
        #expect(NookNoteListRules.showsEmptyState(notes: [], problem: .notDeleted))
        #expect(!NookNoteListRules.showsEmptyState(notes: [], problem: .cantReadFolder("x")))
        #expect(!NookNoteListRules.showsEmptyState(notes: [], problem: .folderGone("x")))
    }

    @Test func aListThatCannotBeReadKeepsTheListThatWasThere() throws {
        let harness = NookNotesHarness()
        harness.writeOutside("Kept.md", "Kept\nbody")
        let store = harness.makeStore()
        #expect(store.notes.count == 1)

        try FileManager.default.removeItem(at: harness.folder)
        try Data("x".utf8).write(to: harness.folder)
        store.reload()

        #expect(store.notes.map(\.id) == ["Kept.md"])
        #expect(store.problem == .cantReadFolder("Notes Folder"))
    }

    @Test func aListThatWorksAgainEndsTheProblem() throws {
        let harness = NookNotesHarness()
        try Data("x".utf8).write(to: harness.folder)
        let store = harness.makeStore()
        #expect(store.problem != nil)

        try FileManager.default.removeItem(at: harness.folder)
        harness.writeOutside("Back.md", "Back\nbody")
        store.reload()

        #expect(store.problem == nil)
        #expect(store.notes.map(\.id) == ["Back.md"])
    }

    @Test func theFolderChosenIsReadWhenItIsChosen() throws {
        let harness = NookNotesHarness()
        try Data("x".utf8).write(to: harness.folder)
        let store = harness.makeStore()
        let other = harness.home.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try "Other\nbody".write(to: other.appendingPathComponent("Other.md"), atomically: true, encoding: .utf8)

        store.setFolder(other)

        #expect(store.problem == nil)
        #expect(store.notes.map(\.id) == ["Other.md"])
    }

    // MARK: A folder that is gone

    @Test func aFolderThatWasThereAndIsGoneIsToldAndNotMadeAgain() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Plan\nbody")
        store.flush()
        store.closeEditor()
        #expect(FileManager.default.fileExists(atPath: harness.folder.path))

        try FileManager.default.removeItem(at: harness.folder)
        store.reload()

        #expect(store.problem == .folderGone("Notes Folder"))
        #expect(!FileManager.default.fileExists(atPath: harness.folder.path))
        #expect(NookNotesNotice.folderGone("x").actions == [.chooseFolder, .createFolder])
    }

    @Test func aNoteTypedWhileTheFolderIsGoneIsKeptAndTheFolderIsNotMadeSilently() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Plan\nbody")
        store.flush()
        store.closeEditor()
        try FileManager.default.removeItem(at: harness.folder)
        store.reload()

        store.beginNewNote()
        store.edit("Another\nnote")
        let saved = store.flush()

        #expect(!saved)
        #expect(!FileManager.default.fileExists(atPath: harness.folder.path), "not made again behind the user's back")
        #expect(store.problem == .folderGone("Notes Folder"))
        let stash = NookNoteLocations.unsavedFolder(home: harness.home)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: stash.path)) ?? []).count == 1)
    }

    @Test func creatingTheFolderAgainSavesTheNoteThatWaited() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Plan\nbody")
        store.flush()
        store.closeEditor()
        try FileManager.default.removeItem(at: harness.folder)
        store.reload()
        store.beginNewNote()
        store.edit("Another\nnote")
        store.flush()

        store.perform(.createFolder)
        let saved = store.flush()

        #expect(saved)
        #expect(store.problem == nil)
        #expect(harness.fileNames() == ["Another.md"])
    }

    @Test func aFolderNeverSeenIsMadeAtTheFirstSave() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        #expect(!FileManager.default.fileExists(atPath: harness.folder.path))
        #expect(store.problem == nil, "a new install is not a folder that is gone")

        store.beginNewNote()
        store.edit("First\nnote")
        store.flush()

        #expect(harness.fileNames() == ["First.md"])
    }

    @Test func aFolderSeenAtAnEarlierLaunchIsGoneAtTheNextOne() throws {
        let harness = NookNotesHarness()
        harness.writeOutside("Plan.md", "Plan\nbody")
        _ = harness.makeStore()
        try FileManager.default.removeItem(at: harness.folder)

        let later = harness.makeStore()

        #expect(later.problem == .folderGone("Notes Folder"))
    }

    // MARK: The destination

    @Test func theDestinationThrowsForAFolderItCannotListAndForAGoneOne() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NookGone-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let gone = NookFolderDestination(folder: folder, calendar: NookNotesHarness.calendar, isFolderExpected: { true })
        let fresh = NookFolderDestination(folder: folder, calendar: NookNotesHarness.calendar, isFolderExpected: { false })

        #expect(throws: NookNoteStorageError.folderGone) { try gone.load() }
        #expect(throws: NookNoteStorageError.folderGone) {
            try gone.write(text: "A\nb", id: nil, created: Date(), now: Date())
        }
        #expect(try fresh.load().isEmpty)

        try Data("x".utf8).write(to: folder)
        #expect(throws: NookNoteStorageError.cannotRead) { try fresh.load() }
    }
}
