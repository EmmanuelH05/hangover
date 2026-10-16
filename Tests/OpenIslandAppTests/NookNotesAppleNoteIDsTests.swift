import Foundation
import Testing
@testable import OpenIslandApp

/// Which Apple note is which note (N14). A file deleted or renamed outside
/// Hangover left its mapping behind, and a later note with the same name
/// updated an Apple note that was never its own.
@MainActor
@Suite struct NookNotesAppleNoteIDsTests {
    private let created = Date(timeIntervalSince1970: 1_800_000_000)
    private let later = Date(timeIntervalSince1970: 1_800_003_600)

    // MARK: The mapping

    @Test func aMappingIsOnlyForTheNoteItWasMadeFor() {
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: "s")
        ids.set("apple-1", for: "Plan.md", created: created)

        #expect(ids.appleID(for: "Plan.md", created: created) == "apple-1")
        #expect(ids.appleID(for: "Plan.md", created: later) == nil, "another note with the same name")
        #expect(ids.appleID(for: "Plan.md") == "apple-1", "asked without a date, whatever is stored")
    }

    @Test func aMappingWithoutADateIsTakenAsItStands() {
        let defaults = MemoryDefaults()
        defaults.set(["s\nPlan.md": "apple-3"], forKey: NookAppleNoteIDs.defaultsKey)
        let ids = NookAppleNoteIDs(defaults: defaults, scope: "s")

        #expect(ids.appleID(for: "Plan.md", created: later) == "apple-3")
        #expect(!ids.isUnreadable)
    }

    @Test func theDateTravelsWithTheMappingToANewName() {
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: "s")
        ids.set("apple-1", for: "Gro.md", created: created)

        ids.move(from: "Gro.md", to: "Groceries.md")

        #expect(ids.appleID(for: "Gro.md") == nil)
        #expect(ids.appleID(for: "Groceries.md", created: created) == "apple-1")
        #expect(ids.appleID(for: "Groceries.md", created: later) == nil)
    }

    @Test func theDateIsKeptToTheSecond() {
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: "s")
        ids.set("apple-1", for: "Plan.md", created: created.addingTimeInterval(0.75))

        #expect(ids.appleID(for: "Plan.md", created: created) == "apple-1")
    }

    // MARK: Sending

    @Test func aNoteWithTheNameOfAFileDeletedOutsideIsANewAppleNote() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Plan\nthe first one")
        store.flush()
        await harness.settle(store)
        harness.removeOutside("Plan.md")
        store.closeEditor()
        store.reload()
        harness.date = harness.date.addingTimeInterval(3600)

        store.beginNewNote()
        store.edit("Plan\nan unrelated note")
        store.flush()
        await harness.settle(store)

        #expect(harness.bridge.createCount == 2)
        #expect(!harness.bridge.calls.contains { if case .update = $0 { true } else { false } },
                "the first note's Apple note is not given this one's text")
    }

    @Test func aRenameByHangoverMovesTheMappingBeforeTheSendIsMade() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Plan\nbody")
        store.flush()
        await harness.settle(store)
        let ids = NookAppleNoteIDs(defaults: harness.defaults, scope: harness.folder.standardizedFileURL.path)
        #expect(ids.appleID(for: "Plan.md") == "apple-1")

        store.edit("Plan B\nbody")
        store.flush()
        // No send has been made: the queue has not had its turn.

        #expect(harness.fileNames() == ["Plan B.md"])
        #expect(ids.appleID(for: "Plan.md") == nil, "a new note called Plan must not find it")
        #expect(ids.appleID(for: "Plan B.md") == "apple-1")
        await harness.settle(store)
    }


    @Test func aNoteDeletedWithAnAppleNoteOfAnotherNoteDoesNotDeleteIt() async throws {
        let bridge = FakeAppleNotesBridge()
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: "s")
        ids.set("apple-9", for: "Plan.md", created: created)
        let link = NookAppleNotesLink(bridge: bridge, ids: ids)

        try await link.remove(NookNoteErasure(noteID: "Plan.md", created: later))
        #expect(bridge.calls.isEmpty)
        #expect(ids.appleID(for: "Plan.md") == "apple-9", "the other note's mapping is left alone")

        try await link.remove(NookNoteErasure(noteID: "Plan.md", created: created))
        #expect(bridge.calls == [.delete(id: "apple-9")])
        #expect(ids.appleID(for: "Plan.md") == nil)
    }

    @Test func aDeleteInHangoverStillDeletesTheAppleNote() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Plan\nbody")
        store.flush()
        await harness.settle(store)
        store.closeEditor()

        store.delete("Plan.md")
        await harness.settle(store)

        #expect(harness.bridge.calls.last == .delete(id: "apple-1"))
    }
}
