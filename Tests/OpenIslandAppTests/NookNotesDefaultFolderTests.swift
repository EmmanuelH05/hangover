import Foundation
import Testing
@testable import OpenIslandApp

/// The default folder and showing the folder (N12). A first launch that could
/// not list the iCloud Obsidian folder saved the Documents folder for good;
/// now it is a stand-in for that launch and the next one looks again. The
/// Reveal button made a folder that had gone, silently.
@MainActor
@Suite struct NookNotesDefaultFolderTests {
    private func vaultsFolder(_ harness: NookNotesHarness) -> URL {
        NookNoteLocations.obsidianDocuments(home: harness.home)
    }

    private func makeVault(_ name: String, in harness: NookNotesHarness) throws {
        try FileManager.default.createDirectory(
            at: vaultsFolder(harness).appendingPathComponent(name).appendingPathComponent(".obsidian"),
            withIntermediateDirectories: true
        )
    }

    private func allowReading(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    // MARK: The look for a vault

    @Test func aFolderThatIsNotThereHasNoVaultAndAFolderThatCannotBeListedFailed() throws {
        let harness = NookNotesHarness(folderIsSet: false)
        #expect(NookNoteLocations.searchVaults(in: vaultsFolder(harness)) == .none)

        try makeVault("Study-Notes", in: harness)
        #expect(NookNoteLocations.searchVaults(in: vaultsFolder(harness)) == .found(vaultsFolder(harness).appendingPathComponent("Study-Notes", isDirectory: true)))

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: vaultsFolder(harness).path)
        defer { allowReading(vaultsFolder(harness)) }
        #expect(NookNoteLocations.searchVaults(in: vaultsFolder(harness)) == .failed)
        #expect(!NookNoteLocations.defaultChoice(home: harness.home).isSettled)
    }

    // MARK: Keeping it

    @Test func aFolderLookedUpProperlyIsKeptAtOnce() {
        let harness = NookNotesHarness(folderIsSet: false)

        let store = harness.makeStore()

        #expect(harness.defaults.string(forKey: NookNotesStore.folderKey) == store.folderURL.path)
    }

    @Test func aStandInFolderIsNotKeptWhenTheVaultsCouldNotBeListed() throws {
        let harness = NookNotesHarness(folderIsSet: false)
        try makeVault("Study-Notes", in: harness)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: vaultsFolder(harness).path)
        defer { allowReading(vaultsFolder(harness)) }

        let first = harness.makeStore()

        #expect(first.folderURL == harness.home.appendingPathComponent("Documents/Hangover Notes", isDirectory: true), "a stand-in for this launch")
        #expect(harness.defaults.string(forKey: NookNotesStore.folderKey) == nil, "and not kept for good")

        // The next launch can read the vaults and uses the one it finds.
        allowReading(vaultsFolder(harness))
        let second = harness.makeStore()
        #expect(second.folderURL == vaultsFolder(harness).appendingPathComponent("Study-Notes/Hangover Notes", isDirectory: true))
        #expect(harness.defaults.string(forKey: NookNotesStore.folderKey) == second.folderURL.path)
    }

    @Test func aStandInFolderIsKeptOnceANoteIsSavedInIt() throws {
        let harness = NookNotesHarness(folderIsSet: false)
        try makeVault("Study-Notes", in: harness)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: vaultsFolder(harness).path)
        defer { allowReading(vaultsFolder(harness)) }
        let store = harness.makeStore()
        #expect(harness.defaults.string(forKey: NookNotesStore.folderKey) == nil)

        store.beginNewNote()
        store.edit("First note\nbody")
        store.flush()

        #expect(harness.defaults.string(forKey: NookNotesStore.folderKey) == store.folderURL.path, "a folder that was made is a folder that was chosen")
        allowReading(vaultsFolder(harness))
        let relaunched = harness.makeStore()
        #expect(relaunched.folderURL == store.folderURL, "the notes do not move once there are notes in it")
    }

    @Test func aFolderTheUserChoosesIsKept() {
        let harness = NookNotesHarness(folderIsSet: false)
        let store = harness.makeStore()
        let chosen = harness.home.appendingPathComponent("Mine", isDirectory: true)

        store.setFolder(chosen)

        #expect(harness.defaults.string(forKey: NookNotesStore.folderKey) == chosen.path)
    }

    // MARK: Showing the folder

    @Test func showingAFolderThatIsThereShowsIt() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        var shown: [URL] = []
        store.revealInFinder = { shown.append($0) }
        try? FileManager.default.createDirectory(at: harness.folder, withIntermediateDirectories: true)

        store.revealFolder()

        #expect(shown == [harness.folder])
        #expect(store.problem == nil)
    }

    @Test func showingAFolderNeverMadeMakesIt() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        var shown: [URL] = []
        store.revealInFinder = { shown.append($0) }

        store.revealFolder()

        #expect(FileManager.default.fileExists(atPath: harness.folder.path))
        #expect(shown == [harness.folder])
    }

    @Test func showingAFolderThatWasThereAndIsGoneDoesNotMakeItAgain() {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("A note\nbody")
        store.flush()
        try? FileManager.default.removeItem(at: harness.folder)
        var shown: [URL] = []
        store.revealInFinder = { shown.append($0) }

        store.revealFolder()

        #expect(!FileManager.default.fileExists(atPath: harness.folder.path), "not made again behind the user's back")
        #expect(shown.isEmpty)
        #expect(store.problem == .folderGone(harness.folder.lastPathComponent), "and the card says it is gone")
    }
}
