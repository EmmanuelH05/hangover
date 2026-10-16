import Foundation
import Testing
@testable import OpenIslandApp

/// A send to Apple Notes that is waiting when the app quits. The send was
/// only kept for a retry when it failed, and a send that was still in line
/// when the app exited neither worked nor failed: the Apple note never heard
/// of the edit, and nothing said it should. Every Notes app here is a fake.
@MainActor
@Suite struct NookNotesQuitSendTests {
    private func backlog(_ harness: NookNotesHarness) -> NookNotesBacklog {
        NookNotesBacklog(defaults: harness.defaults)
    }

    private func scope(_ harness: NookNotesHarness) -> String {
        harness.folder.standardizedFileURL.path
    }

    /// Lets the tasks the store started run as far as they can.
    private func letTasksRun() async {
        for _ in 0..<20 { await Task.yield() }
    }

    /// Waits for what a test cannot see coming, with a limit that fails the test and not the run.
    private func until(_ what: String, _ condition: () -> Bool) async {
        for _ in 0..<2000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(condition(), "\(what) did not happen")
    }

    // MARK: A note

    @Test func aSendThatNeverRunsLeavesItsNoteInTheBacklogAndTheNextLaunchSendsIt() async {
        let harness = NookNotesHarness()
        var store: NookNotesStore? = harness.makeStore(saveTo: .both)
        store?.beginNewNote()
        store?.edit("Plan\nthe body")
        // The quit: what is typed is saved, and the send is queued.
        store?.appWillTerminate()

        #expect(backlog(harness).noteIDs(scope: scope(harness)) == ["Plan.md"], "kept from the moment it is queued")

        // The app is gone before the send's turn comes.
        store = nil
        await letTasksRun()
        #expect(harness.bridge.calls.isEmpty, "the send never ran")

        let next = harness.makeStore()
        await harness.settle(next)

        #expect(harness.bridge.createCount == 1, "the next launch sent it")
        #expect(backlog(harness).noteIDs(scope: scope(harness)).isEmpty, "and it is done with")
        #expect(NookAppleNoteIDs(defaults: harness.defaults, scope: scope(harness)).appleID(for: "Plan.md") == "apple-1")
    }

    @Test func aSendThatWorksLeavesTheBacklog() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Plan\nthe body")
        store.flush()

        #expect(backlog(harness).noteIDs(scope: scope(harness)) == ["Plan.md"], "kept while it waits")

        await harness.settle(store)

        #expect(harness.bridge.createCount == 1)
        #expect(backlog(harness).noteIDs(scope: scope(harness)).isEmpty, "gone once Notes has it")
    }

    @Test func aNoteSavedAgainWhileItsFirstSendWaitsStaysInTheBacklogUntilTheLastSendIsDone() async {
        let harness = NookNotesHarness()
        harness.bridge.hold()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Plan\nthe first body")
        store.flush()
        store.edit("Plan\nthe second body")
        store.flush()
        await until("the first send reaches Notes") { harness.bridge.heldCount == 1 }

        harness.bridge.releaseNext()
        await until("the second send reaches Notes") { harness.bridge.heldCount == 1 && harness.bridge.calls.count == 2 }

        #expect(backlog(harness).noteIDs(scope: scope(harness)) == ["Plan.md"], "the second send has not been made")

        harness.bridge.releaseAll()
        await harness.settle(store)

        #expect(backlog(harness).noteIDs(scope: scope(harness)).isEmpty)
    }

    // MARK: A delete

    @Test func aDeleteQueuedAtQuitIsSentAtTheNextLaunch() async {
        let harness = NookNotesHarness()
        var store: NookNotesStore? = harness.makeStore(saveTo: .both)
        store?.beginNewNote()
        store?.edit("Plan\nthe body")
        store?.flush()
        await harness.settle(store!)
        store?.closeEditor()
        #expect(harness.bridge.calls.count == 1)

        store?.delete("Plan.md")
        #expect(backlog(harness).erasures(scope: scope(harness)).map(\.noteID) == ["Plan.md"], "kept from the moment it is queued")

        // The app is gone before the send's turn comes.
        store = nil
        await letTasksRun()
        #expect(harness.bridge.calls.count == 1, "the delete never ran")

        let next = harness.makeStore()
        await harness.settle(next)

        #expect(harness.bridge.calls.last == .delete(id: "apple-1"), "the next launch deleted the Apple note")
        #expect(backlog(harness).erasures(scope: scope(harness)).isEmpty)
    }

    // MARK: The wait at quit

    @Test func theQuitHasSomethingToWaitForWhileASendIsInLine() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)
        #expect(!store.hasPendingAppleSync, "nothing is waiting")

        store.beginNewNote()
        store.edit("Plan\nthe body")
        store.flush()
        #expect(store.hasPendingAppleSync, "a send is in line")

        await harness.settle(store)
        #expect(!store.hasPendingAppleSync, "and then it is not")
    }

    @Test func theQuitWaitsForTheSendsInLineAndForNothingElse() async {
        let harness = NookNotesHarness()
        harness.bridge.slowDown()
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Plan\nthe body")
        store.appWillTerminate()
        #expect(harness.bridge.calls.isEmpty, "not sent yet")

        await store.waitForAppleNotes()

        #expect(harness.bridge.createCount == 1, "the send was made before the wait ended")
        #expect(!store.hasPendingAppleSync)
        #expect(backlog(harness).noteIDs(scope: scope(harness)).isEmpty)
    }

    @Test func aWaitWithNothingInLineEndsAtOnce() async {
        let harness = NookNotesHarness()
        let store = harness.makeStore(saveTo: .both)

        await store.waitForAppleNotes()

        #expect(harness.bridge.calls.isEmpty)
    }

    @Test func aSendThatNeverEndsIsGivenUpOnAtTheLimitAndStaysInTheBacklog() async {
        let harness = NookNotesHarness()
        harness.bridge.hold()
        defer { harness.bridge.releaseAll() }
        let store = harness.makeStore(saveTo: .both)
        store.beginNewNote()
        store.edit("Plan\nthe body")
        store.flush()

        let gaveUp = await NookQuitWait.run(
            [NookQuitJob(name: "Apple Notes sends", limit: .milliseconds(200)) { await store.waitForAppleNotes() }],
            pollEvery: .milliseconds(10)
        )

        #expect(gaveUp == ["Apple Notes sends"])
        #expect(backlog(harness).noteIDs(scope: scope(harness)) == ["Plan.md"], "the next launch sends it")
    }

    @Test func theQuitWaitsForNotesForNoLongerThanItWaitsForTheDesignKit() throws {
        let app = try HangoverBrandTests.text(of: "Sources/OpenIslandApp/OpenIslandApp.swift")

        #expect(app.contains("NookQuitJob(name: \"Apple Notes sends\", limit: NookQuitWait.writesLimit)"))
        #expect(app.contains("model.flushNotesBeforeQuit()"))
        #expect(NookQuitWait.writesLimit == .seconds(3))
    }
}
