import Foundation
import Testing
@testable import OpenIslandApp

/// Which Apple note is which note, when the date the note was created drifts
/// (N14 again). A note was told from an earlier one of the same name by the
/// seconds its `created:` line reads as, and those seconds move: a line
/// Hangover cannot read falls back to the file's birth date, which every
/// atomic save changes, and a line with no zone reads as different seconds
/// once the clock's zone changes. The mapping then missed, a second Apple
/// note was made, and the first was left behind. Every Notes app here is a
/// fake, and every folder a temporary one.
@MainActor
@Suite struct NookNotesCreatedIdentityTests {
    /// Gives the file the birth date a program that saved it atomically would
    /// have given it. The test does not depend on the clock.
    private func setBirth(_ harness: NookNotesHarness, _ name: String, to seconds: Double) throws {
        try FileManager.default.setAttributes(
            [.creationDate: Date(timeIntervalSince1970: seconds)],
            ofItemAtPath: harness.folder.appendingPathComponent(name).path
        )
    }

    private func plant(_ harness: NookNotesHarness, created: String) {
        harness.writeOutside("Plan.md", "---\ncreated: \(created)\ntags: [plan]\n---\nPlan\nthe first body\n")
    }

    private var farEast: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }

    // MARK: A line Hangover cannot read

    @Test(arguments: [
        "\"[[2026-10-15]]\"",
        "2026-10-15T16:41:00Z",
        "2026-10-15T16:41:00.250",
        "2026-10-15T16:41:00+02:00",
    ])
    func aNoteWithACreatedLineHangoverCannotReadMakesOneAppleNoteWhenSavedTwice(created: String) async throws {
        let harness = NookNotesHarness()
        plant(harness, created: created)
        let store = harness.makeStore(saveTo: .both)

        for (round, body) in ["the second body", "the third body"].enumerated() {
            // Each save gave the file a new birth date, which the next read finds.
            try setBirth(harness, "Plan.md", to: 1_700_000_000 + Double(round) * 1000)
            store.open("Plan.md")
            store.edit("Plan\n\(body)")
            store.closeEditor()
            await harness.settle(store)
        }

        #expect(harness.bridge.createCount == 1, "the second save found the first one's Apple note")
        #expect(harness.bridge.calls.last == .update(
            id: "apple-1", html: NookAppleNotesBody.html(from: "Plan\nthe third body")
        ))
        #expect(harness.text(of: "Plan.md")?.contains("created: \(created)\n") == true, "the line is left as the file has it")
    }

    // MARK: A clock in another zone

    @Test func aNoteMadeInOneTimeZoneAndEditedAfterTheZoneChangedMakesNoSecondAppleNote() async {
        let harness = NookNotesHarness()
        do {
            let first = harness.makeStore(saveTo: .both)
            first.beginNewNote()
            first.edit("Plan\nthe first body")
            first.closeEditor()
            await harness.settle(first)
        }
        #expect(harness.bridge.createCount == 1)

        // The next launch reads the same line in another zone, as other seconds.
        let second = harness.makeStore(calendar: farEast)
        second.open("Plan.md")
        second.edit("Plan\nthe second body")
        second.closeEditor()
        await harness.settle(second)

        #expect(harness.bridge.createCount == 1, "the note is the same note in any zone")
        #expect(harness.bridge.calls.last == .update(
            id: "apple-1", html: NookAppleNotesBody.html(from: "Plan\nthe second body")
        ))
    }

    // MARK: A delete after the drift

    @Test func aNoteWhoseCreatedLineHangoverCannotReadDeletesItsAppleNote() async throws {
        let harness = NookNotesHarness()
        plant(harness, created: "\"[[2026-10-15]]\"")
        try setBirth(harness, "Plan.md", to: 1_700_000_000)
        do {
            let first = harness.makeStore(saveTo: .both)
            first.open("Plan.md")
            first.edit("Plan\nthe second body")
            first.closeEditor()
            await harness.settle(first)
        }
        // The save gave the file a new birth date, and the next launch reads it.
        try setBirth(harness, "Plan.md", to: 1_700_001_000)

        let second = harness.makeStore()
        second.delete("Plan.md")
        await harness.settle(second)

        #expect(harness.bridge.calls.last == .delete(id: "apple-1"), "the Apple note is not left behind")
        #expect(NookNotesBacklog(defaults: harness.defaults).erasures(scope: harness.folder.standardizedFileURL.path).isEmpty)
    }

    @Test func aNoteDeletedAfterTheTimeZoneChangedDeletesItsAppleNote() async {
        let harness = NookNotesHarness()
        do {
            let first = harness.makeStore(saveTo: .both)
            first.beginNewNote()
            first.edit("Plan\nthe first body")
            first.closeEditor()
            await harness.settle(first)
        }

        let second = harness.makeStore(calendar: farEast)
        second.delete("Plan.md")
        await harness.settle(second)

        #expect(harness.bridge.calls.last == .delete(id: "apple-1"), "the Apple note is not left behind")
    }
}

// MARK: The mapping, apart from the store

@MainActor
@Suite struct NookNotesCreatedTextTests {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(text: String? = "2026-10-15T09:41:00", created: Date? = nil, body: String = "Plan\nbody") -> NookNote {
        NookNote(id: "Plan.md", text: body, created: created ?? moment, updated: moment, createdText: text)
    }

    private func storedEntry(_ defaults: MemoryDefaults, _ key: String = "s\nPlan.md") -> [String: Any]? {
        (defaults.object(forKey: NookAppleNoteIDs.defaultsKey) as? [String: Any])?[key] as? [String: Any]
    }

    // MARK: Reading the line

    @Test func theCreatedLineIsKeptAsTheFileHasItWhetherOrNotItReadsAsADate() {
        let calendar = NookNotesHarness.calendar
        func parsed(_ line: String) -> NookNoteFiles.Parsed {
            NookNoteFiles.parse("---\n\(line)\n---\nbody", calendar: calendar)
        }

        #expect(parsed("created: 2026-10-15T09:41:00").createdText == "2026-10-15T09:41:00")
        #expect(parsed("created: 2026-10-15T09:41:00").created != nil)
        #expect(parsed("created: \"[[2026-10-15]]\"").createdText == "[[2026-10-15]]", "quotes are not part of it")
        #expect(parsed("created: \"[[2026-10-15]]\"").created == nil)
        #expect(parsed("created: 2026-10-15T16:41:00Z").createdText == "2026-10-15T16:41:00Z")
        #expect(parsed("created:   2026-10-15  ").createdText == "2026-10-15")
        #expect(parsed("created: 2026-10-15T09:41:00\r").createdText == "2026-10-15T09:41:00", "a Windows line end is not part of it")
        #expect(parsed("created:").createdText == nil)
        #expect(parsed("tags: [plan]").createdText == nil)
        #expect(NookNoteFiles.parse("no front matter", calendar: calendar).createdText == nil)
    }

    @Test func aSaveAnswersTheCreatedTextTheFileNowHas() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("NookCreatedText-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let destination = NookFolderDestination(folder: folder, calendar: NookNotesHarness.calendar, trash: { try FileManager.default.removeItem(at: $0) })
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let made = try destination.save(text: "Plan\nbody", id: nil, base: nil, created: now, now: now).note
        #expect(made.createdText == NookNoteFiles.dateText(now, calendar: NookNotesHarness.calendar))
        #expect(try destination.read(id: made.id)?.createdText == made.createdText, "what is answered is what is read back")

        try "---\ncreated: \"[[2026-10-15]]\"\n---\nOther\nbody\n".write(
            to: folder.appendingPathComponent("Other.md"), atomically: true, encoding: .utf8
        )
        let kept = try destination.save(text: "Other\nnew body", id: "Other.md", base: "Other\nbody\n", created: now, now: now).note
        #expect(kept.createdText == "[[2026-10-15]]", "a line left as the file had it is answered as the file has it")
    }

    // MARK: The stored mapping

    @Test func aMappingIsToldByTheTextAndNotBySecondsThatMove() {
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: "s")
        ids.set("apple-1", for: "Plan.md", created: moment, createdText: "2026-10-15T09:41:00")

        #expect(ids.appleID(for: "Plan.md", created: moment.addingTimeInterval(28_800), createdText: "2026-10-15T09:41:00") == "apple-1")
        #expect(ids.appleID(for: "Plan.md", created: moment, createdText: "2026-10-16T09:41:00") == nil, "another note of the same name")
        #expect(ids.appleID(for: "Plan.md") == "apple-1", "asked with no text, whatever is stored")
    }

    @Test func aMappingStoredWithSecondsIsMatchedTheOldWayAndRewrittenWithTheText() async throws {
        let defaults = MemoryDefaults()
        defaults.set(["s\nPlan.md": ["apple": "apple-3", "created": 1_800_000_000]], forKey: NookAppleNoteIDs.defaultsKey)
        let bridge = FakeAppleNotesBridge()
        let ids = NookAppleNoteIDs(defaults: defaults, scope: "s")
        let link = NookAppleNotesLink(bridge: bridge, ids: ids)

        try await link.push(note(), replacing: nil)

        #expect(bridge.createCount == 0, "the old entry still finds its Apple note")
        #expect(bridge.calls == [.update(id: "apple-3", html: NookAppleNotesBody.html(from: "Plan\nbody"))])
        #expect(storedEntry(defaults)?["createdText"] as? String == "2026-10-15T09:41:00", "rewritten in the new form")
        #expect(storedEntry(defaults)?["created"] == nil)
        #expect(storedEntry(defaults)?["apple"] as? String == "apple-3")

        // From here on the seconds do not matter.
        try await link.push(note(created: moment.addingTimeInterval(28_800)), replacing: nil)

        #expect(bridge.createCount == 0)
        #expect(bridge.calls.count == 2)
    }

    @Test func aMappingStoredWithSecondsForAnotherMomentIsStillAnotherNote() async throws {
        let defaults = MemoryDefaults()
        defaults.set(["s\nPlan.md": ["apple": "apple-3", "created": 1_700_000_000]], forKey: NookAppleNoteIDs.defaultsKey)
        let bridge = FakeAppleNotesBridge()
        let link = NookAppleNotesLink(bridge: bridge, ids: NookAppleNoteIDs(defaults: defaults, scope: "s"))

        try await link.push(note(), replacing: nil)

        #expect(bridge.createCount == 1, "the old way of telling notes apart still tells them apart")
        #expect(storedEntry(defaults)?["apple"] as? String == "apple-1")
        #expect(storedEntry(defaults)?["createdText"] as? String == "2026-10-15T09:41:00")
    }

    @Test func aNoteWithNoCreatedTextTakesWhateverIsStoredAndLeavesItAlone() async throws {
        let defaults = MemoryDefaults()
        let bridge = FakeAppleNotesBridge()
        let ids = NookAppleNoteIDs(defaults: defaults, scope: "s")
        ids.set("apple-5", for: "Plan.md", created: moment, createdText: "2026-10-15T09:41:00")
        let link = NookAppleNotesLink(bridge: bridge, ids: ids)

        // The file's birth date is all it has, and it is not looked at.
        try await link.push(note(text: nil, created: moment.addingTimeInterval(99_999)), replacing: nil)

        #expect(bridge.createCount == 0)
        #expect(storedEntry(defaults)?["createdText"] as? String == "2026-10-15T09:41:00")
    }

    @Test func aMappingMadeForANoteWithNoCreatedTextHoldsNothingToCompare() async throws {
        let defaults = MemoryDefaults()
        let bridge = FakeAppleNotesBridge()
        let ids = NookAppleNoteIDs(defaults: defaults, scope: "s")
        let link = NookAppleNotesLink(bridge: bridge, ids: ids)

        try await link.push(note(text: nil, created: moment), replacing: nil)

        #expect(storedEntry(defaults)?["created"] == nil, "the birth date is not stored")
        #expect(storedEntry(defaults)?["createdText"] == nil)

        // Once the file has the line, the next push gives the mapping its text.
        try await link.push(note(), replacing: nil)

        #expect(bridge.createCount == 1)
        #expect(storedEntry(defaults)?["createdText"] as? String == "2026-10-15T09:41:00")
    }

    @Test func theTextTravelsWithTheMappingToANewName() {
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: "s")
        ids.set("apple-1", for: "Gro.md", created: moment, createdText: "T1")

        ids.move(from: "Gro.md", to: "Groceries.md")

        #expect(ids.appleID(for: "Groceries.md", createdText: "T1") == "apple-1")
        #expect(ids.appleID(for: "Groceries.md", createdText: "T2") == nil)
    }

    // MARK: A delete that waits

    @Test func aDeleteThatWaitsKeepsTheTextToTellItsNoteBy() async throws {
        let defaults = MemoryDefaults()
        let backlog = NookNotesBacklog(defaults: defaults)
        let erasure = NookNoteErasure(noteID: "Plan.md", created: moment, createdText: "[[2026-10-15]]")
        backlog.add(erasure, scope: "s")
        backlog.add(NookNoteErasure(noteID: "Bare.md"), scope: "s")

        #expect(backlog.erasures(scope: "s") == [erasure, NookNoteErasure(noteID: "Bare.md")])

        backlog.remove(erasure, scope: "s")
        #expect(backlog.erasures(scope: "s") == [NookNoteErasure(noteID: "Bare.md")])
    }

    @Test func aDeleteKeptByAnEarlierVersionIsStillRead() {
        let defaults = MemoryDefaults()
        defaults.set(["s\nPlan.md\n1800000000", "s\nBare.md\n"], forKey: NookNotesBacklog.erasuresKey)

        #expect(NookNotesBacklog(defaults: defaults).erasures(scope: "s") == [
            NookNoteErasure(noteID: "Plan.md", created: moment),
            NookNoteErasure(noteID: "Bare.md"),
        ])
    }

    @Test func aDeleteIsToldByTheTextThatWasKept() async throws {
        let bridge = FakeAppleNotesBridge()
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: "s")
        ids.set("apple-9", for: "Plan.md", created: moment, createdText: "T1")
        let link = NookAppleNotesLink(bridge: bridge, ids: ids)

        try await link.remove(NookNoteErasure(noteID: "Plan.md", created: moment, createdText: "T2"))
        #expect(bridge.calls.isEmpty, "another note's Apple note is not deleted")

        // The seconds moved and the text did not.
        try await link.remove(NookNoteErasure(noteID: "Plan.md", created: moment.addingTimeInterval(28_800), createdText: "T1"))
        #expect(bridge.calls == [.delete(id: "apple-9")])
    }

    // MARK: Apple Notes only

    @Test func aNoteInHangoversOwnRecordIsToldByItsAbsoluteMoment() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("NookRecordText-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let record = NookAppleNotesRecord(fileURL: file)
        try record.upsert(NookNote(id: "a", text: "A\nbody", created: moment, updated: moment))

        #expect(record.notes.first?.createdText == "2027-01-15T08:00:00Z")
        #expect(NookAppleNotesRecord(fileURL: file).notes.first?.createdText == "2027-01-15T08:00:00Z", "the same after a launch")
    }

    @Test func aNoteForAppleNotesOnlyMakesOneAppleNoteHoweverOftenItIsSaved() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .appleNotes)
        store.beginNewNote()
        store.edit("Plan\none")
        store.flush()
        await harness.settle(store)
        store.closeEditor()
        let id = store.notes.first?.id

        let again = harness.makeStore()
        harness.date = harness.date.addingTimeInterval(60)
        again.open(id ?? "")
        again.edit("Plan\ntwo")
        again.closeEditor()
        await harness.settle(again)

        #expect(harness.bridge.createCount == 1)
        #expect(harness.bridge.calls.last == .update(id: "apple-1", html: NookAppleNotesBody.html(from: "Plan\ntwo")))
    }
}
