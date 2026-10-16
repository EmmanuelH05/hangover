import Foundation
import Testing
@testable import OpenIslandApp

/// Hangover's own list of Apple notes, and the list of which Apple note is
/// which, when they cannot be read (N2). Both used to read as empty and were
/// written over by the next save. Every file is in a temporary folder.
@MainActor
@Suite struct NookNotesRecordTests {
    private func recordURL(_ harness: NookNotesHarness) -> URL {
        NookNoteLocations.appleNotesRecord(home: harness.home)
    }

    private func plant(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func asideNames(_ harness: NookNotesHarness) -> [String] {
        let folder = recordURL(harness).deletingLastPathComponent()
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.contains("unreadable") }.sorted()
    }

    // MARK: The record

    @Test func aRecordThatIsNotThereIsAnEmptyOneAndNothingIsSetAside() {
        let harness = NookNotesHarness()

        let record = NookAppleNotesRecord(fileURL: recordURL(harness))

        #expect(record.notes.isEmpty)
        #expect(record.standing == .ready)
        #expect(asideNames(harness).isEmpty)
    }

    @Test func aRecordThatCannotBeReadIsSetAsideWithItsBytesKept() throws {
        let harness = NookNotesHarness()
        try plant("{ this is not a record", at: recordURL(harness))

        let record = NookAppleNotesRecord(fileURL: recordURL(harness), now: { harness.date })

        let aside = "apple-notes.unreadable-20270115-080000.json"
        #expect(record.standing == .setAside(aside))
        #expect(record.notes.isEmpty)
        #expect(asideNames(harness) == [aside])
        let kept = try String(contentsOf: recordURL(harness).deletingLastPathComponent().appendingPathComponent(aside), encoding: .utf8)
        #expect(kept == "{ this is not a record")
        #expect(!FileManager.default.fileExists(atPath: recordURL(harness).path), "nothing stands where the record was")
    }

    @Test func twoRecordsSetAsideInTheSameSecondKeepBoth() throws {
        let harness = NookNotesHarness()
        try plant("first", at: recordURL(harness))
        _ = NookAppleNotesRecord(fileURL: recordURL(harness), now: { harness.date })
        try plant("second", at: recordURL(harness))

        _ = NookAppleNotesRecord(fileURL: recordURL(harness), now: { harness.date })

        #expect(asideNames(harness).count == 2)
    }

    @Test func aSaveAfterTheSetAsideWritesANewRecordAndLeavesTheOldFileAlone() throws {
        let harness = NookNotesHarness()
        try plant("garbage", at: recordURL(harness))
        let store = harness.makeStore(saveTo: .appleNotes)

        store.beginNewNote()
        store.edit("After the trouble")
        store.flush()

        let aside = try #require(asideNames(harness).first)
        let kept = try String(contentsOf: recordURL(harness).deletingLastPathComponent().appendingPathComponent(aside), encoding: .utf8)
        #expect(kept == "garbage")
        #expect(NookAppleNotesRecord(fileURL: recordURL(harness)).notes.map(\.text) == ["After the trouble"])
    }

    @Test func aRecordThatCannotBeReadOrSetAsideIsNeverWrittenOver() throws {
        let harness = NookNotesHarness()
        try plant("garbage", at: recordURL(harness))
        let folder = recordURL(harness).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let record = NookAppleNotesRecord(fileURL: recordURL(harness))
        let note = NookNote(id: "a", text: "A\nbody", created: harness.date, updated: harness.date)

        #expect(record.standing == .blocked)
        #expect(throws: NookNoteStorageError.recordUnreadable) { try record.upsert(note) }
        #expect(throws: NookNoteStorageError.recordUnreadable) { try record.remove(id: "a") }

        #expect(try String(contentsOf: recordURL(harness), encoding: .utf8) == "garbage")
    }

    @Test func aBlockedRecordTriesAgainAtTheNextWriteAndMendsWhenItCan() throws {
        let harness = NookNotesHarness()
        try plant("garbage", at: recordURL(harness))
        let folder = recordURL(harness).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        let record = NookAppleNotesRecord(fileURL: recordURL(harness), now: { harness.date })
        #expect(record.standing == .blocked)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)

        try record.upsert(NookNote(id: "a", text: "A\nbody", created: harness.date, updated: harness.date))

        #expect(asideNames(harness).count == 1, "the old file was set aside this time")
        #expect(NookAppleNotesRecord(fileURL: recordURL(harness)).notes.map(\.text) == ["A\nbody"])
    }

    @Test func aFailedWriteLeavesTheRecordAsItWas() throws {
        let harness = NookNotesHarness()
        let record = NookAppleNotesRecord(fileURL: recordURL(harness))
        let a = NookNote(id: "a", text: "A\nbody", created: harness.date, updated: harness.date)
        let b = NookNote(id: "b", text: "B\nbody", created: harness.date, updated: harness.date)
        try record.upsert(a)
        let folder = recordURL(harness).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }

        #expect(throws: NookNoteStorageError.cannotWrite) { try record.remove(id: "a") }
        #expect(record.notes.map(\.id) == ["a"], "a delete that failed is not a delete")
        #expect(throws: NookNoteStorageError.cannotWrite) { try record.upsert(b) }
        #expect(record.notes.map(\.id) == ["a"])

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try record.upsert(b)
        #expect(NookAppleNotesRecord(fileURL: recordURL(harness)).notes.map(\.id) == ["a", "b"])
    }

    // MARK: Told where the user can see it

    @Test func aSetAsideRecordIsToldToTheEditorAndTheCardAtLaunch() throws {
        let harness = NookNotesHarness()
        try plant("garbage", at: recordURL(harness))

        let store = harness.makeStore(saveTo: .appleNotes)

        let aside = try #require(asideNames(harness).first)
        #expect(store.problem == .appleNotesListSetAside(aside))
        #expect(harness.notices == [.appleNotesListSetAside(aside)])
    }

    @Test func aRecordThatCannotBeSetAsideStopsTheSaveAndKeepsTheText() throws {
        let harness = NookNotesHarness()
        try plant("garbage", at: recordURL(harness))
        // The text waits in a folder of its own, made before the record's folder is closed.
        try FileManager.default.createDirectory(at: NookNoteLocations.unsavedFolder(home: harness.home), withIntermediateDirectories: true)
        let folder = recordURL(harness).deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let store = harness.makeStore(saveTo: .appleNotes)
        #expect(store.problem == .appleNotesListUnreadable)

        store.beginNewNote()
        store.edit("Nowhere to go")
        let saved = store.flush()

        #expect(!saved)
        #expect(store.problem == .appleNotesListUnreadable)
        #expect(try String(contentsOf: recordURL(harness), encoding: .utf8) == "garbage")
        let stash = NookNoteLocations.unsavedFolder(home: harness.home)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: stash.path)) ?? []).count == 1)
    }

    // MARK: The list of which Apple note is which

    @Test func aListOfAppleNoteIdsThatCannotBeReadIsNotWrittenOver() {
        let defaults = MemoryDefaults()
        defaults.set("junk", forKey: NookAppleNoteIDs.defaultsKey)
        let ids = NookAppleNoteIDs(defaults: defaults, scope: "s")

        ids.set("apple-1", for: "Note.md")
        ids.move(from: "Note.md", to: "Other.md")

        #expect(ids.isUnreadable)
        #expect(ids.appleID(for: "Note.md") == nil)
        #expect(defaults.object(forKey: NookAppleNoteIDs.defaultsKey) as? String == "junk")
    }

    @Test func aListOfAppleNoteIdsThatIsNotThereIsAnEmptyOne() {
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: "s")

        ids.set("apple-1", for: "Note.md")

        #expect(!ids.isUnreadable)
        #expect(ids.appleID(for: "Note.md") == "apple-1")
    }

    @Test func withoutTheListOfAppleNoteIdsNoSecondAppleNoteIsMade() async {
        let harness = NookNotesHarness()
        harness.defaults.set(["not": "a list of the right shape", "x": 1] as [String: Any], forKey: NookAppleNoteIDs.defaultsKey)
        let store = harness.makeStore(saveTo: .both)

        store.beginNewNote()
        store.edit("Has an Apple note already")
        store.flush()
        await harness.settle(store)
        store.edit("Has an Apple note already\nand more")
        store.flush()
        await harness.settle(store)

        #expect(harness.bridge.calls.isEmpty, "a note is not sent on when it could be sent twice")
        #expect(harness.fileNames() == ["Has an Apple note already.md"], "the note itself is saved")
        #expect(harness.notices == [.appleNotesFailed(keptIn: .folder)])
    }
}
