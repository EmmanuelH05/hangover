import Foundation
import Testing
@testable import OpenIslandApp

/// The folder watcher (D70). The paths that matter are pure; one test lets
/// the real file system events report a change in a temporary folder.
@MainActor
@Suite struct NookNoteFolderWatcherTests {
    @Test func aFileDirectlyInTheFolderIsAChange() {
        #expect(NookNoteFolderWatcher.isRelevant("/vault/Hangover Notes/Plan.md", watched: "/vault/Hangover Notes"))
        #expect(NookNoteFolderWatcher.isRelevant("/vault/Hangover Notes", watched: "/vault/Hangover Notes"))
    }

    @Test func aFileInAFolderInsideItIsNot() {
        #expect(!NookNoteFolderWatcher.isRelevant("/vault/Hangover Notes/Sub/Deep.md", watched: "/vault/Hangover Notes"))
        // A vault's own settings change all the time.
        #expect(!NookNoteFolderWatcher.isRelevant("/vault/.obsidian/workspace.json", watched: "/vault"))
        #expect(NookNoteFolderWatcher.isRelevant("/vault/Note.md", watched: "/vault"))
    }

    @Test func aSiblingFolderWithTheSamePrefixIsNot() {
        #expect(!NookNoteFolderWatcher.isRelevant("/vault/Hangover Notes 2/Plan.md", watched: "/vault/Hangover Notes"))
    }

    /// The real thing: the temporary folder sits behind the `/var` link, which
    /// events name by its real path. A note written by another program is
    /// reported, and a note written in a folder inside it is not.
    @Test func aNoteWrittenInTheFolderIsReported() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookWatcher-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let watcher = NookNoteFolderWatcher()
        var reports = 0
        watcher.watch(folder) { reports += 1 }
        defer { watcher.stop() }

        // The stream starts a moment after the call. Write until it is heard.
        var attempt = 0
        while reports == 0, attempt < 80 {
            try "Note \(attempt)\nbody".write(
                to: folder.appendingPathComponent("From outside.md"), atomically: false, encoding: .utf8
            )
            try await Task.sleep(for: .milliseconds(250))
            attempt += 1
        }

        #expect(reports > 0, "the change was never reported")
    }

    @Test func stoppingEndsTheReports() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookWatcherStop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let watcher = NookNoteFolderWatcher()
        var reports = 0
        watcher.watch(folder) { reports += 1 }
        watcher.stop()

        for attempt in 0..<4 {
            try "Note \(attempt)".write(to: folder.appendingPathComponent("After stop.md"), atomically: false, encoding: .utf8)
            try await Task.sleep(for: .milliseconds(250))
        }

        #expect(reports == 0)
    }
}
