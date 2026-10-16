import Foundation
import Testing
@testable import OpenIslandApp

/// The folder watcher, when it fails and when the folder is not there yet
/// (N9). A stream the system would not start was dropped without a word, and
/// a folder that did not exist yet was not watched at all, so a notes list
/// stayed as it was until the app restarted.
@MainActor
@Suite struct NookNotesWatchTests {
    private func makeFolder(_ harness: NookNotesHarness) {
        try? FileManager.default.createDirectory(at: harness.folder, withIntermediateDirectories: true)
    }

    // MARK: A watcher that would not start

    @Test func aWatcherThatCouldNotStartIsTriedAgainAtTheNextSave() {
        let harness = NookNotesHarness()
        makeFolder(harness)
        harness.watcher.accepts = false
        let store = harness.makeStore()
        #expect(harness.watcher.watchCount == 1, "it was tried at the start")
        #expect(harness.watcher.watched == nil)

        harness.watcher.accepts = true
        store.beginNewNote()
        store.edit("A note\nbody")
        store.flush()

        #expect(harness.watcher.watched == harness.folder, "the save tried again")
    }

    @Test func aWatcherThatCouldNotStartIsTriedAgainWhenTheIslandOpens() {
        let harness = NookNotesHarness()
        makeFolder(harness)
        harness.watcher.accepts = false
        let store = harness.makeStore()
        // A note arrives while nothing is watching.
        harness.writeOutside("Missed.md", "Missed\nwhile blind", modified: harness.date)
        #expect(store.notes.isEmpty)

        harness.watcher.accepts = true
        store.islandOpened()

        #expect(harness.watcher.watched == harness.folder)
        #expect(store.notes.map(\.title) == ["Missed"], "and the list was read, because changes were missed")
    }

    @Test func aWatcherThatKeepsFailingIsTriedAtEveryOpeningAndNeverCrashes() {
        let harness = NookNotesHarness()
        makeFolder(harness)
        harness.watcher.accepts = false
        let store = harness.makeStore()

        store.islandOpened()
        store.islandOpened()

        #expect(harness.watcher.watchCount == 3)
        #expect(harness.watcher.watched == nil)
    }

    @Test func aWatcherThatIsRunningIsLeftAloneWhenTheIslandOpens() {
        let harness = NookNotesHarness()
        makeFolder(harness)
        let store = harness.makeStore()
        #expect(harness.watcher.watched == harness.folder)
        let before = harness.watcher.watchCount

        store.islandOpened()
        store.islandOpened()

        #expect(harness.watcher.watchCount == before, "no new stream for a stream that works")
    }

    @Test func aStoreThatDoesNotUseAFolderWatchesNothingWhenTheIslandOpens() {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .appleNotes)
        let before = harness.watcher.watchCount

        store.islandOpened()

        #expect(harness.watcher.watchCount == before)
        #expect(harness.watcher.watched == nil)
    }

    // MARK: A folder that is not there yet

    @Test func aFolderNotThereYetIsWatchedThroughTheFolderItWillBeMadeIn() {
        let harness = NookNotesHarness()

        let store = harness.makeStore()
        defer { withExtendedLifetime(store) {} }

        #expect(harness.watcher.watched == harness.home)
        #expect(!FileManager.default.fileExists(atPath: harness.folder.path), "and it is still not made")
    }

    @Test func aFolderMadeByHandIsNoticedAndWatchedInItsOwnRight() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        #expect(harness.watcher.watched == harness.home)

        // The user makes the folder in Finder and drops a note in it.
        harness.writeOutside("Dropped in.md", "Dropped in\nby hand", modified: harness.date)
        harness.watcher.fire()

        #expect(store.notes.map(\.title) == ["Dropped in"])
        #expect(harness.watcher.watched == harness.folder, "watched itself now, not its parent")
    }

    @Test func theFirstSaveMovesTheWatchFromTheParentToTheFolder() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        #expect(harness.watcher.watched == harness.home)

        store.beginNewNote()
        store.edit("First note ever")
        store.flush()

        #expect(harness.watcher.watched == harness.folder)
    }

    @Test func aParentThatIsNotThereEitherWatchesNothingAndSaysNothingIsWrong() {
        let harness = NookNotesHarness(folderIsSet: false)
        let far = harness.home.appendingPathComponent("not/made/yet/Notes", isDirectory: true)
        harness.defaults.set(far.path, forKey: NookNotesStore.folderKey)

        let store = harness.makeStore()

        #expect(harness.watcher.watched == nil)
        #expect(store.notes.isEmpty)
        #expect(store.problem == nil)
        // A save makes every folder on the way, and then watches.
        store.beginNewNote()
        store.edit("Deep note")
        store.flush()
        #expect(harness.watcher.watched == far)
    }

    // MARK: The real thing

    @Test func theRealWatcherSaysWhetherItStartedAndStaysQuietAfterStopping() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookWatchStart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let watcher = NookNoteFolderWatcher()

        #expect(watcher.watch(folder) {}, "a folder that is there is watched")
        watcher.stop()
    }
}
