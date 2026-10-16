import Foundation
import Testing
@testable import OpenIslandApp

/// Listing and renaming in a notes folder (N7). A folder that could not be
/// listed skipped the check for a name already taken, so a new "Plan"
/// overwrote "Plan.md"; a rename that failed was swallowed; a rename moved
/// the file before its new text was safe. Every folder is a temporary one.
@MainActor
@Suite struct NookNotesRenameTests {
    /// A destination in a folder of its own, with a Trash the test can watch.
    @MainActor private final class Rig {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookRename-\(UUID().uuidString)", isDirectory: true)
        var trashed: [String] = []
        /// What stood in the folder when each file was trashed.
        var folderAtTrash: [[String]] = []
        var trashFails = false
        var destination: NookFolderDestination!

        init() {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            destination = NookFolderDestination(
                folder: folder, calendar: NookNotesHarness.calendar,
                trash: { [unowned self] url in
                    if trashFails { throw CocoaError(.fileWriteNoPermission) }
                    folderAtTrash.append(names())
                    trashed.append(url.lastPathComponent)
                    try FileManager.default.removeItem(at: url)
                }
            )
        }

        deinit {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }

        func names() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
        }

        func text(_ name: String) -> String? {
            try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8)
        }

        func save(_ text: String, id: String? = nil, base: String? = nil) throws -> NookNote {
            try destination.save(text: text, id: id, base: base, created: Date(timeIntervalSince1970: 1_800_000_000), now: Date(timeIntervalSince1970: 1_800_000_100)).note
        }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: A folder that cannot be listed

    @Test func aFolderThatCannotBeListedIsAnErrorAndNothingIsWrittenOver() throws {
        let rig = Rig()
        let first = try rig.save("Plan\nthe first")
        #expect(first.id == "Plan.md")
        // The folder can be written to and entered, but not read.
        try FileManager.default.setAttributes([.posixPermissions: 0o300], ofItemAtPath: rig.folder.path)

        #expect(throws: NookNoteStorageError.cannotRead) { _ = try rig.save("Plan\na different note") }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rig.folder.path)
        #expect(rig.names() == ["Plan.md"])
        #expect(rig.text("Plan.md")?.hasSuffix("Plan\nthe first") == true, "the note that was there is as it was")
    }

    // MARK: A rename

    @Test func aNewTitleWritesTheNewFileFirstAndThenTrashesTheOldOne() throws {
        let rig = Rig()
        let first = try rig.save("Gro\nmilk")

        let second = try rig.save("Groceries\nmilk", id: first.id, base: "Gro\nmilk")

        #expect(second.id == "Groceries.md")
        #expect(rig.names() == ["Groceries.md"])
        #expect(rig.trashed == ["Gro.md"])
        #expect(rig.folderAtTrash == [["Gro.md", "Groceries.md"]], "the new file stood there before the old one went")
        #expect(rig.text("Groceries.md")?.hasSuffix("Groceries\nmilk") == true)
    }

    @Test func aRenameKeepsTheDatesAndTheFrontMatterAnotherProgramAdded() throws {
        let rig = Rig()
        try "---\ncreated: 2026-10-01T09:00:00\ntags: [work]\n---\nGro\nmilk".write(
            to: rig.folder.appendingPathComponent("Gro.md"), atomically: true, encoding: .utf8
        )

        let renamed = try rig.save("Groceries\nmilk", id: "Gro.md", base: "Gro\nmilk")

        #expect(rig.names() == ["Groceries.md"])
        let saved = try #require(rig.text("Groceries.md"))
        #expect(saved.contains("tags: [work]"))
        #expect(saved.contains("created: 2026-10-01T09:00:00"))
        #expect(renamed.created == NookNoteFiles.date(from: "2026-10-01T09:00:00", calendar: NookNotesHarness.calendar))
    }

    @Test func aRenameIntoATakenNameGetsANumberAndNeverOverwrites() throws {
        let rig = Rig()
        _ = try rig.save("Plan\nthe other one")
        let draft = try rig.save("Draft\nmine")

        let renamed = try rig.save("Plan\nmine", id: draft.id, base: "Draft\nmine")

        #expect(renamed.id == "Plan 2.md")
        #expect(rig.text("Plan.md")?.hasSuffix("Plan\nthe other one") == true)
        #expect(rig.names() == ["Plan 2.md", "Plan.md"])
    }

    @Test func aTrashThatFailsLeavesTheOldFileAsAnOlderVersionAndTheNoteSaved() throws {
        let rig = Rig()
        let first = try rig.save("Gro\nmilk")
        rig.trashFails = true

        let second = try rig.save("Groceries\nmilk", id: first.id, base: "Gro\nmilk")

        #expect(second.id == "Groceries.md", "the note is saved under its new name")
        #expect(rig.names() == ["Gro.md", "Groceries.md"], "nothing is lost")
    }

    @Test func aRenameThatCannotBeWrittenKeepsTheOldNoteAndItsName() throws {
        let rig = Rig()
        let first = try rig.save("Gro\nmilk")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: rig.folder.path)

        #expect(throws: NookNoteStorageError.cannotWrite) {
            _ = try rig.save("Groceries\nmilk", id: first.id, base: "Gro\nmilk")
        }

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rig.folder.path)
        #expect(rig.names() == ["Gro.md"])
        #expect(rig.trashed.isEmpty)
        #expect(rig.text("Gro.md")?.hasSuffix("Gro\nmilk") == true)
    }

    @Test func theStoreKeepsTheOldIdWhenARenameCannotBeWritten() throws {
        let harness = NookNotesHarness()
        let store = harness.makeStore()
        store.beginNewNote()
        store.edit("Gro\nmilk")
        store.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: harness.folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: harness.folder.path) }

        store.edit("Groceries\nmilk")
        let saved = store.flush()

        #expect(!saved)
        #expect(store.notes.map(\.id) == ["Gro.md"])
        #expect(store.holdsUnsavedDraft)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: harness.folder.path)
        store.edit("Groceries\nmilk and eggs")
        #expect(store.flush())
        #expect(harness.fileNames() == ["Groceries.md"], "one file, not a Gro.md and a Groceries.md")
    }
}
