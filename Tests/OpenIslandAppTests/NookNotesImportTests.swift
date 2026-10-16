import Foundation
import Testing
@testable import OpenIslandApp

/// The one-time move of the old Quick Notes file into the new notes (D70),
/// and where notes live when nothing was chosen.
@MainActor
@Suite struct NookNotesImportTests {
    private static let oldText = "# Quick Notes\n\n- **2026-10-12 09:41** Call mom\n- **2026-10-12 10:02** Buy milk\n"

    /// Writes the old default file under the harness's home.
    private func writeOldFile(_ harness: NookNotesHarness, _ text: String = oldText) throws -> URL {
        let url = NookNoteLocations.oldNotesFile(storedPath: nil, home: harness.home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: Import

    @Test func theOldFileBecomesOneNoteTitledQuickNotes() throws {
        let harness = NookNotesHarness()
        let old = try writeOldFile(harness)

        let store = harness.makeStore()

        #expect(store.notes.map(\.title) == ["Quick Notes"])
        #expect(harness.fileNames() == ["Quick Notes.md"])
        let body = NookNoteFiles.parse(harness.text(of: "Quick Notes.md") ?? "", calendar: NookNotesHarness.calendar).body
        #expect(body == Self.oldText)
        #expect(try String(contentsOf: old, encoding: .utf8) == Self.oldText, "the old file is left as it was")
        #expect(harness.defaults.bool(forKey: NookNotesStore.importedKey))
    }

    @Test func theImportHappensOnlyOnce() throws {
        let harness = NookNotesHarness()
        _ = try writeOldFile(harness)
        let first = harness.makeStore()
        first.delete("Quick Notes.md")
        #expect(harness.fileNames().isEmpty)

        let second = harness.makeStore()

        #expect(second.notes.isEmpty, "a note the user deleted does not come back")
        #expect(harness.fileNames().isEmpty)
    }

    @Test func importingDoesNotCountAsASave() throws {
        let harness = NookNotesHarness()
        _ = try writeOldFile(harness)

        let store = harness.makeStore()

        #expect(store.savedCount == 0, "the tour counts saves to see a note go in")
    }

    @Test func aFilePickedInSettingsIsTheOneImported() throws {
        let harness = NookNotesHarness()
        let picked = harness.home.appendingPathComponent("Vault/Inbox.md")
        try FileManager.default.createDirectory(at: picked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "- **2026-10-01 08:00** from a picked file\n".write(to: picked, atomically: true, encoding: .utf8)
        harness.defaults.set(picked.path, forKey: NookNotesStore.legacyPathKey)

        let store = harness.makeStore()

        #expect(store.notes.map(\.title) == ["Quick Notes"])
        let body = NookNoteFiles.parse(harness.text(of: "Quick Notes.md") ?? "", calendar: NookNotesHarness.calendar).body
        #expect(body == "# Quick Notes\n\n- **2026-10-01 08:00** from a picked file\n")
    }

    @Test func aTildeInThePickedPathMeansTheHomeFolder() throws {
        let harness = NookNotesHarness()
        let picked = harness.home.appendingPathComponent("Notes/Inbox.md")
        try FileManager.default.createDirectory(at: picked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "- **2026-10-01 08:00** tilde\n".write(to: picked, atomically: true, encoding: .utf8)
        harness.defaults.set("~/Notes/Inbox.md", forKey: NookNotesStore.legacyPathKey)

        let store = harness.makeStore()

        #expect(store.notes.count == 1)
    }

    @Test func anOldFileThatIsAlreadyInTheNotesFolderIsNotImportedTwice() throws {
        let harness = NookNotesHarness()
        // The tour's folder choice kept "Quick Notes.md" in the folder.
        try FileManager.default.createDirectory(at: harness.folder, withIntermediateDirectories: true)
        let inside = harness.folder.appendingPathComponent("Quick Notes.md")
        try Self.oldText.write(to: inside, atomically: true, encoding: .utf8)
        harness.defaults.set(inside.path, forKey: NookNotesStore.legacyPathKey)

        let store = harness.makeStore()

        #expect(harness.fileNames() == ["Quick Notes.md"], "no 'Quick Notes 2'")
        #expect(store.notes.map(\.title) == ["Quick Notes"], "it is a note there already")
        #expect(harness.defaults.bool(forKey: NookNotesStore.importedKey))
    }

    @Test func noOldFileMeansNothingToImport() {
        let harness = NookNotesHarness()

        let store = harness.makeStore()

        #expect(store.notes.isEmpty)
        #expect(harness.defaults.bool(forKey: NookNotesStore.importedKey), "asked once, not at every launch")
    }

    @Test func anOldFileWithOnlyItsHeadingIsNotImported() throws {
        let harness = NookNotesHarness()
        _ = try writeOldFile(harness, "# Quick Notes\n\n")

        let store = harness.makeStore()

        #expect(store.notes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: harness.folder.path))
    }

    @Test func aFolderThatCannotBeWrittenKeepsTheImportForTheNextLaunch() throws {
        let harness = NookNotesHarness()
        _ = try writeOldFile(harness)
        try Data("x".utf8).write(to: harness.folder)

        let store = harness.makeStore()

        #expect(store.notes.isEmpty)
        #expect(harness.notices.contains(.notImported))
        #expect(!harness.defaults.bool(forKey: NookNotesStore.importedKey))
    }

    @Test func theImportGoesToAppleNotesWhenThatIsTheChoice() async throws {
        let harness = NookNotesHarness()
        _ = try writeOldFile(harness)

        let store = harness.makeStore(saveTo: .appleNotes)
        await harness.settle(store)

        #expect(store.notes.map(\.title) == ["Quick Notes"])
        #expect(harness.bridge.createCount == 1)
        #expect(harness.fileNames().isEmpty)
    }

    @Test func theImportGoesToBothWhenThatIsTheChoice() async throws {
        let harness = NookNotesHarness()
        _ = try writeOldFile(harness)

        let store = harness.makeStore(saveTo: .both)
        await harness.settle(store)

        #expect(harness.fileNames() == ["Quick Notes.md"])
        #expect(harness.bridge.createCount == 1)
    }

    @Test func theOldSingleAppleNoteIsLeftAlone() async throws {
        let harness = NookNotesHarness()
        _ = try writeOldFile(harness)

        let store = harness.makeStore(saveTo: .appleNotes)
        await harness.settle(store)

        // Only a new note in the Hangover folder is made; nothing is
        // updated or deleted in the note called Quick Notes.
        #expect(harness.bridge.calls.allSatisfy { if case .create = $0 { true } else { false } })
    }
}

/// Where notes live before anyone chooses (D70).
@Suite struct NookNoteLocationsTests {
    private func home() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NookLocations-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeVault(_ name: String, in home: URL, withObsidianFolder: Bool = true) throws {
        let vault = NookNoteLocations.obsidianDocuments(home: home).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        if withObsidianFolder {
            try FileManager.default.createDirectory(at: vault.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        }
    }

    @Test func withoutObsidianNotesGoInAVisibleFolderInDocuments() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }

        #expect(NookNoteLocations.defaultFolder(home: home) == home.appendingPathComponent("Documents/Hangover Notes", isDirectory: true))
    }

    @Test func withAnObsidianVaultNotesGoInsideIt() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeVault("Study-Notes", in: home)

        let folder = NookNoteLocations.defaultFolder(home: home)

        #expect(folder == NookNoteLocations.obsidianDocuments(home: home)
            .appendingPathComponent("Study-Notes/Hangover Notes", isDirectory: true))
    }

    @Test func theFirstVaultByNameIsTheOne() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeVault("Work", in: home)
        try makeVault("Archive", in: home)

        #expect(NookNoteLocations.defaultFolder(home: home).deletingLastPathComponent().lastPathComponent == "Archive")
    }

    @Test func aFolderWithNoObsidianFolderInItIsNotAVault() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeVault("Photos", in: home, withObsidianFolder: false)

        #expect(NookNoteLocations.defaultFolder(home: home) == home.appendingPathComponent("Documents/Hangover Notes", isDirectory: true))
    }

    @Test func thePickerOpensInTheObsidianFolderWhenItExists() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let current = home.appendingPathComponent("Somewhere")

        #expect(NookNoteLocations.pickerStart(home: home, current: current) == current)

        try makeVault("Study-Notes", in: home)
        #expect(NookNoteLocations.pickerStart(home: home, current: current) == NookNoteLocations.obsidianDocuments(home: home))
    }

    @Test func theOldFileDefaultsToTheAppsOwnFolder() {
        let home = URL(fileURLWithPath: "/tmp/someone")

        #expect(NookNoteLocations.oldNotesFile(storedPath: nil, home: home).path
            == "/tmp/someone/Library/Application Support/OpenIsland/Notes/Quick Notes.md")
        #expect(NookNoteLocations.oldNotesFile(storedPath: "/Volumes/x/Inbox.md", home: home).path == "/Volumes/x/Inbox.md")
        #expect(NookNoteLocations.oldNotesFile(storedPath: "~/Inbox.md", home: home).path == "/tmp/someone/Inbox.md")
    }

    @Test func aDefaultFolderIsKeptOnceItWasChosen() throws {
        let home = try home()
        defer { try? FileManager.default.removeItem(at: home) }
        let defaults = MemoryDefaults()
        let first = NookNotesStore.storedFolder(in: defaults, home: home)
        defaults.set(first.path, forKey: NookNotesStore.folderKey)

        // A vault appears afterwards. Notes do not move to it.
        try makeVault("Late Vault", in: home)

        #expect(NookNotesStore.storedFolder(in: defaults, home: home) == first)
    }
}
