import Foundation
import Testing
@testable import OpenIslandApp

/// Notes iCloud has not brought to this Mac (N17). Reading such a file waits
/// for the download, and the list was read on the main actor, so a dataless
/// file could hold the whole app up. Now the file is not read: iCloud is asked
/// for it once, the row says "downloading", and the list is read again
/// when it arrives. The fake iCloud holds the files back; nothing here
/// reaches the real one.
@MainActor
@Suite struct NookNotesDownloadTests {
    private func store(
        away: String..., in harness: NookNotesHarness, contents: [String: String] = [:]
    ) -> NookNotesStore {
        for name in away {
            harness.writeOutside(name, contents[name] ?? "\(NookNoteFiles.stem(of: name))\nits text", modified: harness.date)
            harness.iCloud.leaveNotDownloaded(name)
        }
        return harness.makeStore()
    }

    // MARK: The list

    @Test func aFileIsNotReadWhileItIsNotDownloaded() {
        let harness = NookNotesHarness()
        let store = store(away: "Away.md", in: harness)
        defer { withExtendedLifetime(store) {} }

        let row = store.notes.first
        #expect(store.notes.map(\.id) == ["Away.md"])
        #expect(row?.state == .downloading)
        #expect(row?.text == "", "it was not read; a read would have waited for the download")
        #expect(harness.iCloud.downloadsAsked == ["Away.md"], "iCloud was asked for it")
    }

    @Test func aFileThatIsHereIsReadAsAlways() {
        let harness = NookNotesHarness()
        harness.writeOutside("Here.md", "Here\nits text", modified: harness.date)
        let store = store(away: "Away.md", in: harness)
        defer { withExtendedLifetime(store) {} }

        #expect(store.notes.first { $0.id == "Here.md" }?.state == .readable)
        #expect(store.notes.first { $0.id == "Here.md" }?.title == "Here")
        #expect(store.notes.first { $0.id == "Away.md" }?.state == .downloading)
    }

    @Test func iCloudIsAskedOncePerFileHoweverOftenTheListIsRead() {
        let harness = NookNotesHarness()
        let store = store(away: "Away.md", in: harness)
        defer { withExtendedLifetime(store) {} }

        store.reload()
        store.reload()
        harness.watcher.fire()

        #expect(harness.iCloud.downloadsAsked == ["Away.md"])
    }

    @Test func theRowBecomesTheNoteWhenTheFileArrives() {
        let harness = NookNotesHarness()
        let store = store(away: "Away.md", in: harness)
        defer { withExtendedLifetime(store) {} }

        harness.iCloud.download("Away.md")
        harness.watcher.fire()

        #expect(store.notes.first?.state == .readable)
        #expect(store.notes.first?.title == "Away")
    }

    // MARK: The wait for it

    @Test func aListWithADownloadingRowIsReadAgainInAFewSeconds() {
        let harness = NookNotesHarness()
        let store = store(away: "Away.md", in: harness)
        defer { withExtendedLifetime(store) {} }
        #expect(harness.scheduler.delays == [NookNoteSizes.downloadCheckDelay])

        harness.iCloud.download("Away.md")
        harness.letTheSaveHappen()

        #expect(store.notes.first?.state == .readable, "found without the watcher saying anything")
        #expect(harness.scheduler.waitingCount == 0, "nothing left to wait for")
    }

    @Test func theWaitGivesUpAfterAWhile() {
        let harness = NookNotesHarness()
        let store = store(away: "Away.md", in: harness)
        defer { withExtendedLifetime(store) {} }

        var checks = 0
        while harness.scheduler.waitingCount > 0, checks < 100 {
            harness.letTheSaveHappen()
            checks += 1
        }

        #expect(checks == NookNoteSizes.downloadChecks, "it asks again \(NookNoteSizes.downloadChecks) times and stops")
        #expect(store.notes.first?.state == .downloading)
    }

    @Test func openingTheIslandLooksAgainAndStartsTheWaitOver() {
        let harness = NookNotesHarness()
        let store = store(away: "Away.md", in: harness)
        defer { withExtendedLifetime(store) {} }
        while harness.scheduler.waitingCount > 0 { harness.letTheSaveHappen() }

        harness.iCloud.download("Away.md")
        store.islandOpened()

        #expect(store.notes.first?.state == .readable)
    }

    // MARK: Opening and saving

    @Test func aNoteStillDownloadingDoesNotOpenAndSaysWhy() {
        let harness = NookNotesHarness()
        let store = store(away: "Away.md", in: harness)
        defer { withExtendedLifetime(store) {} }

        store.open("Away.md")

        #expect(!store.isEditorOpen)
        #expect(store.problem == .noteDownloading("Away"))
        #expect(harness.notices.last == .noteDownloading("Away"))
    }

    @Test func aNoteThatArrivedOpensWithItsText() {
        let harness = NookNotesHarness()
        let store = store(away: "Away.md", in: harness)
        defer { withExtendedLifetime(store) {} }
        harness.iCloud.download("Away.md")

        store.open("Away.md")

        #expect(store.isEditorOpen)
        #expect(store.editorText == "Away\nits text")
    }

    @Test func anOpenNoteWhoseFileGoesBackToICloudIsNotTakenForGoneAndIsNotWrittenOver() {
        let harness = NookNotesHarness()
        harness.writeOutside("Plan.md", "Plan\nmine", modified: harness.date)
        let store = harness.makeStore()
        defer { withExtendedLifetime(store) {} }
        store.open("Plan.md")
        // The file is evicted while the note is open, and changes under it.
        harness.date = harness.date.addingTimeInterval(60)
        harness.writeOutside("Plan.md", "Plan\nchanged elsewhere", modified: harness.date)
        harness.iCloud.leaveNotDownloaded("Plan.md")
        harness.watcher.fire()

        #expect(store.isEditorOpen, "the editor keeps the note")
        #expect(store.editorText == "Plan\nmine")

        store.edit("Plan\nmine and more")
        let saved = store.flush()

        #expect(!saved, "a file that is not here is not written over blind")
        #expect(store.problem == .noteDownloading("Plan"))
        #expect(harness.text(of: "Plan.md")?.hasSuffix("changed elsewhere") == true)
        #expect(store.holdsUnsavedDraft, "and what was typed is still the editor's")
    }

    // MARK: The row

    @Test func theRowSaysDownloadingInPlaceOfAnAge() {
        let note = NookNote(
            id: "Away.md", text: "", created: .distantPast, updated: .distantPast, state: .downloading
        )
        let lang = LanguageManager.shared

        let text = NookNoteRow.ageOrState(of: note, age: "2m ago", lang: lang)

        #expect(text == lang.t("nook.notes.row.downloading"))
        #expect(NookNoteRow.ageOrState(of: NookNote(id: "A.md", text: "", created: .distantPast, updated: .distantPast), age: "2m ago", lang: lang) == "2m ago")
        // The title of a note not read is its file name.
        #expect(NookNoteListRules.rowTitle(for: note, untitled: "Untitled") == "Away")
    }
}
