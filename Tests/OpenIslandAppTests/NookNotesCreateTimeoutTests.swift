import Foundation
import Testing
@testable import OpenIslandApp

/// A create that did not answer in time. The Apple event Hangover sent to
/// Notes still lands when the script is ended: the note is there, and the
/// retry found no mapping and made another. The retry now looks in Hangover's
/// folder in Notes for a note with the title first. Every Notes app here is a
/// fake.
@MainActor
@Suite struct NookNotesCreateTimeoutTests {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func note(_ id: String = "Plan.md", body: String = "Plan\nbody") -> NookNote {
        NookNote(id: id, text: body, created: moment, updated: moment, createdText: "2026-10-15T09:41:00")
    }

    private func parts(scope: String = "s") -> (FakeAppleNotesBridge, NookAppleNoteIDs, NookAppleNotesLink) {
        let bridge = FakeAppleNotesBridge()
        let ids = NookAppleNoteIDs(defaults: MemoryDefaults(), scope: scope)
        return (bridge, ids, NookAppleNotesLink(bridge: bridge, ids: ids))
    }

    // MARK: The retry

    @Test func aCreateThatTimedOutAndLandedIsAdoptedAtTheRetryAndNotMadeAgain() async throws {
        let (bridge, ids, link) = parts()
        bridge.timeOutNextCreate(landing: true)
        await #expect(throws: NookAppleNotesError.failed) { try await link.push(note(), replacing: nil) }
        #expect(bridge.noteCount == 1, "the note landed all the same")
        #expect(ids.appleID(for: "Plan.md") == nil, "and Hangover never heard of it")

        try await link.push(note(body: "Plan\nthe body now"), replacing: nil)

        #expect(bridge.createCount == 1, "no second note was made")
        #expect(bridge.noteCount == 1)
        #expect(ids.appleID(for: "Plan.md") == "apple-1", "the note that landed is the note's Apple note")
        #expect(bridge.calls.last == .update(id: "apple-1", html: NookAppleNotesBody.html(from: "Plan\nthe body now")),
                "and it has the text the note has now")
    }

    @Test func aCreateThatTimedOutAndNeverLandedIsMadeAtTheRetry() async throws {
        let (bridge, ids, link) = parts()
        bridge.timeOutNextCreate(landing: false)
        await #expect(throws: NookAppleNotesError.failed) { try await link.push(note(), replacing: nil) }
        #expect(bridge.noteCount == 0)

        try await link.push(note(), replacing: nil)

        #expect(bridge.createCount == 2, "it looked, found nothing and made one")
        #expect(bridge.noteCount == 1)
        #expect(ids.appleID(for: "Plan.md") == "apple-1")
        #expect(bridge.calls.contains(.find(title: "Plan")))
    }

    @Test func theLookIsMadeOnceAndThenTheNoteIsUpdatedAsAlways() async throws {
        let (bridge, _, link) = parts()
        bridge.timeOutNextCreate(landing: true)
        _ = try? await link.push(note(), replacing: nil)
        try await link.push(note(), replacing: nil)
        let before = bridge.calls.count

        try await link.push(note(body: "Plan\nanother edit"), replacing: nil)

        #expect(bridge.calls.count == before + 1)
        #expect(bridge.calls.last == .update(id: "apple-1", html: NookAppleNotesBody.html(from: "Plan\nanother edit")),
                "no look for a note that is known")
    }

    @Test func aNoteThatBelongsToAnotherNoteIsNotAdopted() async throws {
        let (bridge, ids, link) = parts()
        // Two notes with the title Plan, and the first one's Apple note made without trouble.
        try await link.push(note("Plan.md"), replacing: nil)
        bridge.timeOutNextCreate(landing: true)
        _ = try? await link.push(note("Plan 2.md"), replacing: nil)
        #expect(bridge.noteCount == 2)
        #expect(ids.appleID(for: "Plan.md") == "apple-1")

        try await link.push(note("Plan 2.md"), replacing: nil)

        #expect(ids.appleID(for: "Plan 2.md") == "apple-2", "the one that landed, and not the first note's")
        #expect(ids.appleID(for: "Plan.md") == "apple-1")
        #expect(bridge.createCount == 2)
    }

    @Test func aRefusalLeavesNothingToLookFor() async throws {
        let (bridge, _, link) = parts()
        bridge.fail(with: .notPermitted)
        _ = try? await link.push(note(), replacing: nil)
        bridge.fail(with: nil)

        try await link.push(note(), replacing: nil)

        #expect(!bridge.calls.contains { if case .find = $0 { true } else { false } }, "macOS refused: nothing was made")
        #expect(bridge.createCount == 2)
    }

    @Test func aLookThatFailsDoesNotLetTheNoteBeMadeTwice() async throws {
        let (bridge, _, link) = parts()
        bridge.timeOutNextCreate(landing: true)
        _ = try? await link.push(note(), replacing: nil)
        bridge.fail(with: .failed)
        // The look itself fails: the note is not made a second time on a guess.
        await #expect(throws: NookAppleNotesError.failed) { try await link.push(note(), replacing: nil) }
        bridge.fail(with: nil)

        try await link.push(note(), replacing: nil)

        #expect(bridge.createCount == 1)
        #expect(bridge.noteCount == 1)
    }

    @Test func aNoteRenamedBetweenTheTriesIsStillFoundByTheTitleItWasMadeWith() async throws {
        let (bridge, ids, link) = parts()
        bridge.timeOutNextCreate(landing: true)
        _ = try? await link.push(note(), replacing: nil)

        link.moved(from: "Plan.md", to: "Plan B.md")
        try await link.push(note("Plan B.md", body: "Plan B\nbody"), replacing: nil)

        #expect(bridge.createCount == 1)
        #expect(ids.appleID(for: "Plan B.md") == "apple-1")
        #expect(bridge.calls.last == .update(id: "apple-1", html: NookAppleNotesBody.html(from: "Plan B\nbody")))
    }

    @Test func aNoteDeletedBeforeTheRetryTakesTheNoteThatLandedWithIt() async throws {
        let (bridge, _, link) = parts()
        bridge.timeOutNextCreate(landing: true)
        _ = try? await link.push(note(), replacing: nil)

        try await link.remove(NookNoteErasure(noteID: "Plan.md", created: moment, createdText: "2026-10-15T09:41:00"))

        #expect(bridge.calls.last == .delete(id: "apple-1"))
        #expect(bridge.noteCount == 0, "no Apple note is left behind")
        // Nothing is left to look for.
        try await link.push(note("Plan.md", body: "Plan\na new note of the same name"), replacing: nil)
        #expect(bridge.createCount == 2)
        #expect(bridge.calls.filter { if case .find = $0 { true } else { false } }.count == 1)
    }

    // MARK: From the store

    @Test func aCreateThatTimedOutIsNotMadeAgainAtTheNextLaunch() async {
        let harness = NookNotesHarness()
        harness.bridge.timeOutNextCreate(landing: true)
        let first = harness.makeStore(saveTo: .both)
        first.beginNewNote()
        first.edit("Plan\nthe body")
        first.closeEditor()
        await harness.settle(first)
        #expect(first.appleNotesProblem == .failed)
        #expect(harness.bridge.noteCount == 1)

        let second = harness.makeStore()
        await harness.settle(second)

        #expect(harness.bridge.createCount == 1, "the launch found the note and made no second one")
        #expect(harness.bridge.noteCount == 1)
        #expect(second.appleNotesProblem == nil)
        let ids = NookAppleNoteIDs(defaults: harness.defaults, scope: harness.folder.standardizedFileURL.path)
        #expect(ids.appleID(for: "Plan.md") == "apple-1")
    }
}
