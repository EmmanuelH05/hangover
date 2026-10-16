import Foundation
import Testing
@testable import OpenIslandApp

/// The old Quick Notes import when the file cannot be read (N3). It used to
/// be marked done, and the old notes were never moved in. A file that is
/// really not there is still done. Every folder is a temporary one.
@MainActor
@Suite struct NookNotesImportRetryTests {
    private static let oldText = "# Quick Notes\n\n- **2026-10-12 09:41** Call mom\n"

    private func oldFileURL(_ harness: NookNotesHarness) -> URL {
        let url = NookNoteLocations.oldNotesFile(storedPath: nil, home: harness.home)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return url
    }

    // MARK: Done

    @Test func aFileThatIsNotThereAndHasNoStandInIsDone() {
        let harness = NookNotesHarness()

        let store = harness.makeStore()

        #expect(harness.defaults.bool(forKey: NookNotesStore.importedKey))
        #expect(store.problem == nil)
        #expect(harness.iCloud.downloadsAsked.isEmpty)
    }

    // MARK: Tried again at the next launch

    @Test func aFileOnlyICloudHasAStandInForIsAskedForAndNotGivenUpOn() throws {
        let harness = NookNotesHarness()
        let old = oldFileURL(harness)
        try Data().write(to: NookNoteICloud.standIn(for: old))

        let store = harness.makeStore()

        #expect(!harness.defaults.bool(forKey: NookNotesStore.importedKey))
        #expect(harness.iCloud.downloadsAsked == ["Quick Notes.md"])
        #expect(store.problem == .notImported)
        #expect(harness.notices == [.notImported])
    }

    @Test func aFileICloudHasNotDownloadedIsAskedForAndNotReadAtLaunch() throws {
        let harness = NookNotesHarness()
        let old = oldFileURL(harness)
        try Self.oldText.write(to: old, atomically: true, encoding: .utf8)
        harness.iCloud.leaveNotDownloaded("Quick Notes.md")

        let store = harness.makeStore()

        #expect(!harness.defaults.bool(forKey: NookNotesStore.importedKey))
        #expect(harness.iCloud.downloadsAsked == ["Quick Notes.md"])
        #expect(store.notes.isEmpty)
        #expect(store.problem == .notImported)
    }

    @Test func theImportHappensAtTheNextLaunchOnceTheFileArrives() throws {
        let harness = NookNotesHarness()
        let old = oldFileURL(harness)
        try Self.oldText.write(to: old, atomically: true, encoding: .utf8)
        harness.iCloud.leaveNotDownloaded("Quick Notes.md")
        _ = harness.makeStore()
        harness.iCloud.download("Quick Notes.md")

        let later = harness.makeStore()

        #expect(later.notes.map(\.title) == ["Quick Notes"])
        #expect(harness.defaults.bool(forKey: NookNotesStore.importedKey))
    }

    @Test func aFileThatCannotBeReadForAnotherReasonIsNotGivenUpOn() throws {
        let harness = NookNotesHarness()
        let old = oldFileURL(harness)
        try Self.oldText.write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: old.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: old.path) }

        let store = harness.makeStore()

        #expect(!harness.defaults.bool(forKey: NookNotesStore.importedKey))
        #expect(store.problem == .notImported)
    }

    @Test func aFileThatCannotBeReadHasItsImportTriedAgainAndWorks() throws {
        let harness = NookNotesHarness()
        let old = oldFileURL(harness)
        try Self.oldText.write(to: old, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: old.path)
        _ = harness.makeStore()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: old.path)

        let later = harness.makeStore()

        #expect(later.notes.map(\.title) == ["Quick Notes"])
        #expect(harness.defaults.bool(forKey: NookNotesStore.importedKey))
    }

    // MARK: Another encoding

    @Test func aFileThatIsNotUTF8IsReadInTheEncodingItIsIn() throws {
        let harness = NookNotesHarness()
        let old = oldFileURL(harness)
        // UTF-16 with its byte order mark is not valid UTF-8.
        let text = "# Quick Notes\n\n- Caf\u{E9} with mom\n"
        try #require(text.data(using: .utf16)).write(to: old)

        let store = harness.makeStore()

        #expect(harness.defaults.bool(forKey: NookNotesStore.importedKey))
        #expect(store.notes.map(\.title) == ["Quick Notes"])
        #expect(store.notes.first?.text.contains("Caf\u{E9} with mom") == true)
    }
}
