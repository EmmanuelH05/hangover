import AppKit
import Foundation
import SwiftUI
import Testing
@testable import OpenIslandApp

/// A note that cannot be saved (N1): the problem is kept where the user can
/// read it while the island is open, the text waits in a file of its own, and
/// the next launch puts it back. Every folder is a temporary one.
@MainActor
@Suite struct NookNotesProblemTests {
    /// The notes folder is a file, so nothing can be made in it.
    private func blockedStore(_ harness: NookNotesHarness) throws -> NookNotesStore {
        try Data("x".utf8).write(to: harness.folder)
        return harness.makeStore()
    }

    private func stashed(_ harness: NookNotesHarness) -> [String] {
        let folder = NookNoteLocations.unsavedFolder(home: harness.home)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    private func stashText(_ harness: NookNotesHarness) -> String? {
        let folder = NookNoteLocations.unsavedFolder(home: harness.home)
        guard let name = stashed(harness).first else { return nil }
        return try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
    }

    // MARK: The problem stays

    @Test func aSaveThatFailsLeavesAProblemTheEditorCanShow() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        #expect(store.problem == .cantReadFolder("Notes Folder"), "the folder is a file: it is told at launch")
        store.beginNewNote()

        store.edit("Cannot land")
        harness.letTheSaveHappen()

        #expect(store.problem == .notSavedInFolder("Notes Folder"))
        #expect(store.isEditorOpen && store.holdsUnsavedDraft)
    }

    @Test func theProblemIsToldToTheClosedIslandOnceNotAtEveryFailedSave() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        store.beginNewNote()

        for text in ["A", "A b", "A b c"] {
            store.edit(text)
            harness.letTheSaveHappen()
        }

        #expect(harness.notices == [.cantReadFolder("Notes Folder"), .notSavedInFolder("Notes Folder")])
        #expect(store.problem == .notSavedInFolder("Notes Folder"), "the editor keeps showing it")
    }

    @Test func theNextSaveThatWorksClearsTheProblem() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        store.beginNewNote()
        store.edit("Stuck for now")
        store.flush()
        #expect(store.problem != nil)

        try FileManager.default.removeItem(at: harness.folder)
        store.edit("Stuck for now, then free")
        #expect(store.flush())

        #expect(store.problem == nil)
        #expect(harness.fileNames() == ["Stuck for now, then free.md"])
    }

    @Test func aProblemIsToldAgainWhenItComesBackAfterASuccess() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Fine")
        store.flush()
        try FileManager.default.removeItem(at: harness.folder)
        try Data("x".utf8).write(to: harness.folder)
        store.edit("Fine then broken")
        store.flush()
        #expect(store.problem == .notSavedInFolder("Notes Folder"))

        // The folder is gone now, and is made again only when the user says so.
        try FileManager.default.removeItem(at: harness.folder)
        store.createFolder()
        store.edit("Fine then mended")
        store.flush()
        #expect(store.problem == nil)
        try FileManager.default.removeItem(at: harness.folder)
        try Data("x".utf8).write(to: harness.folder)
        store.edit("Fine then broken again")
        store.flush()

        #expect(harness.notices == [.notSavedInFolder("Notes Folder"), .notSavedInFolder("Notes Folder")])
    }

    @Test func aFailedDeleteIsAProblemToo() {
        let harness = NookNotesHarness()
        try? FileManager.default.createDirectory(at: harness.home, withIntermediateDirectories: true)
        try? Data("x".utf8).write(to: harness.trashFolder)
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Stuck")
        store.closeEditor()

        store.delete("Stuck.md")

        #expect(store.problem == .notDeleted)
    }

    @Test func aDeleteThatWorksClearsTheProblem() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        store.beginNewNote()
        store.edit("Stuck")
        store.flush()
        #expect(store.problem != nil)
        try FileManager.default.removeItem(at: harness.folder)
        harness.writeOutside("Other.md", "Other")
        store.reload()

        store.delete("Other.md")

        #expect(store.problem == nil)
    }

    @Test func aFolderProblemOffersChoosingAnotherFolderAndAnAppleOnlyOneDoesNot() {
        #expect(NookNotesNotice.notSavedInFolder("Notes").actions == [.chooseFolder])
        #expect(NookNotesNotice.notSaved.actions.isEmpty)
        #expect(NookNotesNotice.notSavedInFolder("Notes").subject == "Notes")
    }

    @Test func anAppleNotesOnlyStoreSaysNotSavedWithoutAFolder() throws {
        let harness = NookNotesHarness()
        let notesFolder = NookNoteLocations.appleNotesRecord(home: harness.home).deletingLastPathComponent()
        // Hangover's own record cannot be written: its folder takes no new files.
        try FileManager.default.createDirectory(at: notesFolder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: notesFolder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: notesFolder.path) }
        let store = harness.makeStore(saveTo: .appleNotes)
        store.beginNewNote()

        store.edit("Nowhere to go")
        store.flush()

        #expect(store.problem == .notSaved)
    }

    // MARK: The text is kept

    @Test func aFailedSaveKeepsTheTextInAFileOfItsOwn() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        store.beginNewNote()

        store.edit("Do not lose me\nsecond line")
        store.flush()

        #expect(stashed(harness).count == 1)
        #expect(stashText(harness) == "Do not lose me\nsecond line")
    }

    @Test func aSecondFailureOfTheSameNoteWritesTheSameFileAgain() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        store.beginNewNote()
        store.edit("First try")
        store.flush()

        store.edit("First try and more")
        store.flush()

        #expect(stashed(harness).count == 1)
        #expect(stashText(harness) == "First try and more")
    }

    @Test func theStashGoesWhenTheNoteIsSavedAfterAll() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        store.beginNewNote()
        store.edit("Saved in the end")
        store.flush()
        #expect(stashed(harness).count == 1)

        try FileManager.default.removeItem(at: harness.folder)
        store.edit("Saved in the end!")
        #expect(store.flush())

        #expect(stashed(harness).isEmpty)
    }

    @Test func quittingWithANoteThatCannotBeSavedKeepsItsText() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        store.beginNewNote()
        store.edit("Typed when the app quit")

        store.appWillTerminate()

        #expect(stashText(harness) == "Typed when the app quit")
    }

    @Test func quittingWithANoteThatCanBeSavedSavesItAndKeepsNoStash() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Typed when the app quit")

        store.appWillTerminate()

        #expect(harness.fileNames() == ["Typed when the app quit.md"])
        #expect(stashed(harness).isEmpty)
    }

    @Test func aNoteCarriedToAnotherFolderLeavesNoStashBehind() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        store.beginNewNote()
        store.edit("Rescued")
        store.flush()
        #expect(stashed(harness).count == 1)

        store.setFolder(harness.home.appendingPathComponent("Other", isDirectory: true))

        #expect(stashed(harness).isEmpty)
        #expect(store.problem == nil)
    }

    @Test func aNoteEmptiedAfterAFailureHasNothingToKeep() throws {
        let harness = NookNotesHarness()
        let store = try blockedStore(harness)
        store.beginNewNote()
        store.edit("Typed")
        store.flush()
        #expect(stashed(harness).count == 1)

        store.edit("")
        store.flush()

        #expect(stashed(harness).isEmpty)
        #expect(store.problem == nil)
    }

    // MARK: Put back at the next launch

    @Test func theNextLaunchPutsAStashedNoteBackAsANote() throws {
        let harness = NookNotesHarness()
        let first = try blockedStore(harness)
        first.beginNewNote()
        first.edit("Kept over a quit\nbody")
        first.appWillTerminate()
        try FileManager.default.removeItem(at: harness.folder)

        let second = harness.makeStore()

        #expect(harness.fileNames() == ["Kept over a quit.md"])
        #expect(second.notes.map(\.title) == ["Kept over a quit"])
        #expect(stashed(harness).isEmpty, "the stash is used up")
        #expect(second.problem == .restored)
        #expect(harness.notices.last == .restored)
        #expect(second.savedCount == 0, "putting a note back is not a save the tour counts")
    }

    @Test func aRestoredNoteNeverOverwritesANoteWithTheSameName() throws {
        let harness = NookNotesHarness()
        let first = try blockedStore(harness)
        first.beginNewNote()
        first.edit("Plan\nthe one I could not save")
        first.appWillTerminate()
        try FileManager.default.removeItem(at: harness.folder)
        harness.writeOutside("Plan.md", "Plan\nthe one in the folder")

        _ = harness.makeStore()

        #expect(harness.fileNames() == ["Plan 2.md", "Plan.md"])
        #expect(harness.text(of: "Plan.md")?.contains("the one in the folder") == true)
    }

    @Test func aStashThatCannotBePutBackStaysForTheNextLaunch() throws {
        let harness = NookNotesHarness()
        let first = try blockedStore(harness)
        first.beginNewNote()
        first.edit("Still stuck")
        first.appWillTerminate()

        let second = harness.makeStore()

        #expect(stashed(harness).count == 1)
        #expect(second.problem == .notSavedInFolder("Notes Folder"))
    }

    @Test func anEmptyStashIsLetGo() throws {
        let harness = NookNotesHarness()
        let folder = NookNoteLocations.unsavedFolder(home: harness.home)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "  \n".write(to: folder.appendingPathComponent("blank.md"), atomically: true, encoding: .utf8)

        let store = harness.makeStore()

        #expect(stashed(harness).isEmpty)
        #expect(store.problem == nil)
        #expect(harness.fileNames().isEmpty)
    }

    @Test func aRestoredNoteGoesToAppleNotesToo() async throws {
        let harness = NookNotesHarness()
        let folder = NookNoteLocations.unsavedFolder(home: harness.home)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "From before\nbody".write(to: folder.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)

        let store = harness.makeStore(saveTo: .appleNotes)
        await harness.settle(store)

        #expect(store.notes.map(\.title) == ["From before"])
        #expect(harness.bridge.createCount == 1)
    }

    // MARK: Where the user can see it

    @Test func everyNoticeHasASentenceForTheHeader() throws {
        let english = try HangoverBrandTests.table("en")
        let notices: [NookNotesNotice] = [
            .notSaved, .notSavedInFolder("Notes"), .notDeleted, .notImported, .restored,
            .appleNotesOff(keptIn: .folder), .appleNotesFailed(keptIn: .hangover),
            .appleNotesListSetAside("x.json"), .appleNotesListUnreadable,
            .savedAsCopy("x.md"), .noteUnreadable("x"), .cantReadFolder("x"), .folderGone("x"),
        ]
        for notice in notices {
            #expect(english[notice.problemKey] != nil, "\(notice.problemKey)")
            #expect(NookNotesProblemLine.sentence(for: notice).isEmpty == false)
        }
    }

}

/// The header over the editor and the card, drawn with and without a problem.
@MainActor
@Suite(.noNewWindows)
struct NookNotesProblemRenderTests {
    @Test func theHeaderDrawsTheProblem() throws {
        let harness = NookNotesHarness()
        try Data("x".utf8).write(to: harness.folder)
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Cannot land")
        let calm = try renderHeader(store)

        store.flush()
        let troubled = try renderHeader(store)

        #expect(store.problem != nil)
        #expect(calm != troubled)
    }

    @Test func theCardDrawsTheProblemInPlaceOfARow() throws {
        let harness = NookNotesHarness()
        try? FileManager.default.createDirectory(at: harness.home, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: harness.trashFolder)
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("A note\nbody")
        store.closeEditor()
        let nook = NookModel(notes: store, defaults: MemoryDefaults(), looksForImportedGIF: false)
        let calm = try renderCard(nook)

        store.delete("A note.md")
        let troubled = try renderCard(nook)

        #expect(store.problem == .notDeleted)
        #expect(calm != troubled)
    }

    private func renderHeader(_ store: NookNotesStore) throws -> Data {
        let view = NookNoteEditorHeader(store: store)
            .frame(width: 416)
            .padding(8)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        return try render(view)
    }

    private func renderCard(_ nook: NookModel) throws -> Data {
        let view = NookNotesCard(nook: nook, isStill: true)
            .environment(\.nookWidgetSize, .medium)
            .frame(width: 416, height: NookNotesCard.height(for: .medium))
            .padding(8)
            .background(V6Palette.ink)
            .environment(\.colorScheme, .dark)
        return try render(view)
    }

    private func render(_ view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try #require(renderer.cgImage, "ImageRenderer returned no image")
        return try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    }
}
