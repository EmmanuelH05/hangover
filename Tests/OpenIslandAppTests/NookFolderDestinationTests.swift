import Foundation
import Testing
@testable import OpenIslandApp

/// Notes as Markdown files in a folder (D70), read and written the way
/// Obsidian leaves them. Every folder is a temporary one.
@MainActor
@Suite struct NookFolderDestinationTests {
    private final class Folder {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookFolderTests-\(UUID().uuidString)", isDirectory: true)
        var trashed: [URL] = []

        init() {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit {
            try? FileManager.default.removeItem(at: url)
        }

        func write(_ name: String, _ text: String, modified: Date? = nil) throws {
            let file = url.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
            if let modified { try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path) }
        }

        func read(_ name: String) -> String? {
            try? String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
        }
    }

    private static let calendar = NookNotesHarness.calendar
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func destination(_ folder: Folder) -> NookFolderDestination {
        NookFolderDestination(folder: folder.url, calendar: Self.calendar, trash: { url in
            try FileManager.default.removeItem(at: url)
        })
    }

    // MARK: Reading

    @Test func onlyMarkdownFilesDirectlyInTheFolderAreNotes() throws {
        let folder = Folder()
        try folder.write("Real.md", "Real\ntext")
        try folder.write("Upper.MD", "Upper\ntext")
        try folder.write("readme.txt", "not a note")
        try folder.write(".Hidden.md", "hidden")
        try folder.write("Sub/Inner.md", "inside a folder")
        try folder.write("image.png", "not text")

        let names = try destination(folder).load().map(\.id).sorted()

        #expect(names == ["Real.md", "Upper.MD"])
    }

    @Test func aMissingFolderHasNoNotes() throws {
        let folder = Folder()
        let missing = NookFolderDestination(folder: folder.url.appendingPathComponent("nope"), calendar: Self.calendar)

        #expect(try missing.load().isEmpty)
    }

    @Test func theDatesComeFromTheFrontMatter() throws {
        let folder = Folder()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = Date(timeIntervalSince1970: 1_750_000_000)
        try folder.write(
            "Dated.md",
            NookNoteFiles.render(body: "Dated\nbody", created: created, updated: updated, calendar: Self.calendar),
            modified: Date(timeIntervalSince1970: 1_000_000_000)
        )

        let note = try #require(try destination(folder).load().first)

        #expect(note.created == created)
        #expect(note.updated == updated)
        #expect(note.text == "Dated\nbody")
    }

    @Test func aFileWithNoFrontMatterUsesItsOwnDates() throws {
        let folder = Folder()
        let modified = Date(timeIntervalSince1970: 1_750_000_000)
        try folder.write("Plain.md", "Plain\nfile", modified: modified)

        let note = try #require(try destination(folder).load().first)

        #expect(note.text == "Plain\nfile")
        #expect(note.updated == modified)
    }

    @Test func aFileEditedLaterThanItsFrontMatterSaysIsNewer() throws {
        let folder = Folder()
        let updated = Date(timeIntervalSince1970: 1_700_000_000)
        let edited = Date(timeIntervalSince1970: 1_760_000_000)
        try folder.write(
            "Edited.md",
            NookNoteFiles.render(body: "Edited", created: updated, updated: updated, calendar: Self.calendar),
            modified: edited
        )

        #expect(try destination(folder).load().first?.updated == edited)
    }

    @Test func aChangedFileIsReadAgainAndAnUnchangedOneIsNot() throws {
        let folder = Folder()
        try folder.write("Same.md", "Same\none", modified: Date(timeIntervalSince1970: 1_700_000_000))
        let destination = destination(folder)
        #expect(try destination.load().first?.text == "Same\none")

        // Rewritten, with a new date.
        try folder.write("Same.md", "Same\ntwo!", modified: Date(timeIntervalSince1970: 1_700_000_100))

        #expect(try destination.load().first?.text == "Same\ntwo!")
    }

    // MARK: Writing

    @Test func aNewNoteIsAFileNamedAfterItsTitle() throws {
        let folder = Folder()

        let note = try destination(folder).write(text: "Weekly plan\nmon: gym", id: nil, created: Self.now, now: Self.now)

        #expect(note.id == "Weekly plan.md")
        #expect(note.created == Self.now && note.updated == Self.now)
        let parsed = NookNoteFiles.parse(try #require(folder.read("Weekly plan.md")), calendar: Self.calendar)
        #expect(parsed.body == "Weekly plan\nmon: gym")
        #expect(parsed.created == Self.now)
    }

    @Test func theFolderIsMadeWithTheFirstNote() throws {
        let folder = Folder()
        let deep = folder.url.appendingPathComponent("a/b/c", isDirectory: true)
        let destination = NookFolderDestination(folder: deep, calendar: Self.calendar)

        _ = try destination.write(text: "Deep", id: nil, created: Self.now, now: Self.now)

        #expect(FileManager.default.fileExists(atPath: deep.appendingPathComponent("Deep.md").path))
    }

    @Test func theFilesDateMatchesTheTimeOfTheEdit() throws {
        let folder = Folder()

        _ = try destination(folder).write(text: "Stamped", id: nil, created: Self.now, now: Self.now)

        let values = try folder.url.appendingPathComponent("Stamped.md").resourceValues(forKeys: [.contentModificationDateKey])
        #expect(values.contentModificationDate == Self.now)
    }

    @Test func otherFrontMatterAndTheCreationDateSurviveARewrite() throws {
        let folder = Folder()
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        try folder.write("Tagged.md", """
        ---
        tags: [work]
        created: \(NookNoteFiles.dateText(original, calendar: Self.calendar))
        ---
        Tagged
        old body
        """)

        let note = try destination(folder).write(text: "Tagged\nnew body", id: "Tagged.md", created: Self.now, now: Self.now)

        #expect(note.created == original, "Hangover does not change the creation date a file has")
        let text = try #require(folder.read("Tagged.md"))
        #expect(text.contains("tags: [work]"))
        #expect(NookNoteFiles.parse(text, calendar: Self.calendar).body == "Tagged\nnew body")
    }

    /// N18: the front matter is Obsidian's. Its lines, its blank lines and a
    /// creation date Hangover cannot read all come back as they were; only the
    /// `updated` line and the text change.
    @Test func aRewriteLeavesEveryFrontMatterLineAsItWas() throws {
        let folder = Folder()
        try folder.write(
            "Tagged.md",
            "---\ntags: [work]\n\naliases:\n  - old\n\ncreated: last Tuesday\nupdated: 2026-10-01T08:00:00\ncssclasses: wide\n---\nTagged\nold body"
        )

        _ = try destination(folder).write(text: "Tagged\nnew body", id: "Tagged.md", created: Self.now, now: Self.now)

        let updated = NookNoteFiles.dateText(NookNoteFiles.wholeSeconds(Self.now), calendar: Self.calendar)
        #expect(folder.read("Tagged.md") == "---\ntags: [work]\n\naliases:\n  - old\n\ncreated: last Tuesday\nupdated: \(updated)\ncssclasses: wide\n---\nTagged\nnew body")
    }

    @Test func aNewTitleRenamesTheFileAndKeepsItsContentPlace() throws {
        let folder = Folder()
        let destination = destination(folder)
        let first = try destination.write(text: "Old\nbody", id: nil, created: Self.now, now: Self.now)

        let second = try destination.write(text: "New\nbody", id: first.id, created: Self.now, now: Self.now)

        #expect(second.id == "New.md")
        #expect(folder.read("Old.md") == nil)
        #expect(folder.read("New.md") != nil)
    }

    @Test func aRenameToATakenNameGetsANumber() throws {
        let folder = Folder()
        let destination = destination(folder)
        _ = try destination.write(text: "Taken", id: nil, created: Self.now, now: Self.now)
        let other = try destination.write(text: "Other", id: nil, created: Self.now, now: Self.now)

        let renamed = try destination.write(text: "Taken\nnow", id: other.id, created: Self.now, now: Self.now)

        #expect(renamed.id == "Taken 2.md")
        #expect(folder.read("Taken.md") != nil)
    }

    @Test func aNoteWhoseFileWasDeletedIsWrittenAsANewFile() throws {
        let folder = Folder()
        let destination = destination(folder)
        let first = try destination.write(text: "Lost\nbody", id: nil, created: Self.now, now: Self.now)
        try FileManager.default.removeItem(at: folder.url.appendingPathComponent(first.id))

        let again = try destination.write(text: "Lost\nbody", id: first.id, created: Self.now, now: Self.now)

        #expect(again.id == "Lost.md")
        #expect(folder.read("Lost.md") != nil)
    }

    // MARK: Removing

    @Test func erasingHandsTheFileToTheTrash() throws {
        let folder = Folder()
        var handed: [URL] = []
        let destination = NookFolderDestination(folder: folder.url, calendar: Self.calendar, trash: { handed.append($0) })
        let note = try destination.write(text: "Bye", id: nil, created: Self.now, now: Self.now)

        let erasure = try destination.erase(id: note.id)

        #expect(handed.map(\.lastPathComponent) == ["Bye.md"])
        #expect(erasure == NookNoteErasure(noteID: "Bye.md"))
    }

    @Test func erasingAFileThatIsAlreadyGoneIsNotAnError() throws {
        let folder = Folder()

        #expect(try destination(folder).erase(id: "Never existed.md") == NookNoteErasure(noteID: "Never existed.md"))
    }

    @Test func aTrashThatRefusesIsAnError() throws {
        let folder = Folder()
        let destination = NookFolderDestination(folder: folder.url, calendar: Self.calendar, trash: { _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        let note = try destination.write(text: "Stuck", id: nil, created: Self.now, now: Self.now)

        #expect(throws: NookNoteStorageError.cannotRemove) { try destination.erase(id: note.id) }
    }
}

/// A note comes back from the folder as it went in (D70).
@MainActor
@Suite struct NookFolderRoundTripTests {
    @Test func aDateWithAFractionIsKeptToTheSecondSoTheNoteReadsBackEqual() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookRoundTrip-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = NookFolderDestination(folder: folder, calendar: NookNotesHarness.calendar)
        let now = Date(timeIntervalSince1970: 1_800_000_000.75)

        let written = try destination.write(text: "Round trip\nbody", id: nil, created: now, now: now)
        let loaded = try #require(try destination.load().first)

        #expect(written == loaded, "a note that reads back different would redraw the list at every change")
        #expect(written.updated == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func theNotesRecordKeepsWholeSecondsToo() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("NookRecord-\(UUID().uuidString)/apple-notes.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: "record")
        let destination = NookAppleNotesDestination(
            record: NookAppleNotesRecord(fileURL: file),
            link: NookAppleNotesLink(bridge: NookInertAppleNotesBridge(), ids: ids)
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000.75)

        let written = try destination.write(text: "Record\nbody", id: nil, created: now, now: now)
        let again = NookAppleNotesDestination(
            record: NookAppleNotesRecord(fileURL: file),
            link: NookAppleNotesLink(bridge: NookInertAppleNotesBridge(), ids: ids)
        )

        #expect(try again.load() == [written])
    }
}
