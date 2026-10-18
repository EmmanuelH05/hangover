import Foundation
import Testing
@testable import OpenIslandApp

/// The one service behind Asana, monday and Canvas (D83), run against a
/// scripted backend. Serialized because the scripted backend is shared.
@MainActor
@Suite(.serialized) struct NookRemoteTodoServiceTests {
    private typealias Service = RemoteTodoHarness.Service

    /// A harness that is connected to the place "w1" and showing `items`.
    private func connected(_ items: [NookTodoItem]) async -> RemoteTodoHarness {
        let harness = RemoteTodoHarness(placeID: "w1", placeName: "Work")
        harness.script.onLoad { _ in RemoteTodoFixtures.load(items) }
        await harness.activate()
        return harness
    }

    private func isUnavailable(_ connection: NookTodoConnection) -> Bool {
        if case .unavailable = connection { return true }
        return false
    }

    // MARK: Activation

    @Test func staysIdleUntilItIsSetActive() {
        let harness = RemoteTodoHarness()

        #expect(harness.service.isActive == false)
        #expect(harness.service.state == .inactive)
        #expect(harness.tokens.readCount == 0)
        #expect(harness.script.calls.isEmpty)
    }

    @Test func noTokenGivesTheNoTokenStateAndAnUnavailableCard() async {
        let harness = RemoteTodoHarness(token: nil)
        await harness.activate()

        #expect(harness.service.state == .noToken)
        #expect(isUnavailable(harness.service.connection))
        #expect(harness.service.hasToken == false)
        #expect(harness.script.calls.isEmpty)
    }

    @Test func aTokenWithNoPlaceGivesNoPlaceAndLoadsThePlaces() async {
        let harness = RemoteTodoHarness()
        await harness.activate()

        #expect(harness.service.state == .noPlace)
        #expect(isUnavailable(harness.service.connection))
        #expect(harness.service.places == TestTodoScript.defaultPlaces)
        #expect(harness.service.hasLoadedPlaces)
        #expect(harness.script.calls == ["check"])
    }

    // MARK: Connect

    @Test func connectChecksSavesAdoptsThePlacesAndLoadsTheOnlyPlace() async {
        let harness = RemoteTodoHarness(token: nil)
        harness.script.onLoad { _ in RemoteTodoFixtures.load([RemoteTodoFixtures.item("a", "Read")]) }
        await harness.activate()

        await harness.service.connect(token: "  tok_pasted_value \n")

        #expect(harness.tokens.token == "tok_pasted_value")
        #expect(harness.service.hasToken)
        #expect(harness.service.places == TestTodoScript.defaultPlaces)
        #expect(harness.service.accountName == "Sam")
        #expect(harness.service.selectedPlaceID == "w1")
        #expect(harness.service.placeName == "Work")
        #expect(harness.defaults.string(forKey: Service.placeIDKey) == "w1")
        #expect(harness.script.calls == ["check", "load:w1"])
        #expect(harness.service.state == .ready)
        #expect(harness.service.items.map(\.id) == ["a"])
    }

    @Test func aBadTokenOnConnectGivesInvalidTokenAndSavesNothing() async {
        let harness = RemoteTodoHarness(token: nil)
        harness.script.onCheck { _ in throw NookTodoRemoteError.unauthorized }
        await harness.activate()

        await harness.service.connect(token: "tok_wrong")

        #expect(harness.service.state == .invalidToken)
        #expect(harness.tokens.token == nil)
        #expect(harness.service.hasToken == false)
        #expect(harness.service.selectedPlaceID == nil)
        #expect(harness.script.calls == ["check"])
    }

    @Test func aTokenWithBlankSpaceInsideIsRefusedBeforeAnyRequest() async {
        let harness = RemoteTodoHarness(token: nil)
        await harness.activate()

        await harness.service.connect(token: "tok with space")

        #expect(harness.service.state == .invalidToken)
        #expect(harness.tokens.token == nil)
        #expect(harness.script.calls.isEmpty)
    }

    @Test func disconnectDeletesTheTokenFileAndClearsThePlace() async {
        let harness = await connected([RemoteTodoFixtures.item("a")])
        #expect(harness.service.state == .ready)

        await harness.service.disconnect()

        #expect(harness.tokens.token == nil)
        #expect(harness.service.hasToken == false)
        #expect(harness.service.selectedPlaceID == nil)
        #expect(harness.service.placeName == nil)
        #expect(harness.defaults.string(forKey: Service.placeIDKey) == nil)
        #expect(harness.defaults.string(forKey: Service.placeNameKey) == nil)
        #expect(harness.service.items.isEmpty)
        #expect(harness.service.state == .noToken)
    }

    // MARK: Failures on load

    @Test func a401OnLoadGivesInvalidTokenAndMarksTheTokenRejected() async {
        let harness = RemoteTodoHarness(placeID: "w1", placeName: "Work")
        harness.script.onLoad { _ in throw NookTodoRemoteError.unauthorized }
        await harness.activate()

        #expect(harness.service.state == .invalidToken)
        #expect(harness.service.tokenRejected)
        #expect(harness.service.items.isEmpty)
        #expect(isUnavailable(harness.service.connection))
    }

    @Test func a429SetsTheGateAndGivesRateLimited() async {
        let harness = RemoteTodoHarness(placeID: "w1", placeName: "Work")
        harness.script.onLoad { _ in throw NookTodoRemoteError.rateLimited(retryAfter: 120) }
        await harness.activate()

        #expect(harness.service.state == .rateLimited)
        #expect(harness.service.isRateLimited)

        // Nothing is sent while the wait is open, a manual refresh included.
        harness.service.refresh(.manual)
        await harness.service.refreshTask?.value
        #expect(harness.script.count(prefix: "load") == 1)

        harness.clock.advance(121)
        #expect(harness.service.isRateLimited == false)
    }

    // MARK: Writes

    @Test func completeRemovesTheRowAtOnce() async {
        let harness = await connected([RemoteTodoFixtures.item("a"), RemoteTodoFixtures.item("b")])
        let latch = TodoLatch()
        harness.script.onComplete { await latch.wait() }
        harness.script.onLoad { _ in RemoteTodoFixtures.load([RemoteTodoFixtures.item("b")]) }

        let work = Task { await harness.service.performComplete("a") }
        await harness.waitUntil { harness.script.calls.contains("complete:a") }

        #expect(harness.service.items.map(\.id) == ["b"], "the row went before the app answered")
        await latch.open()
        await work.value
        await harness.service.refreshTask?.value
        #expect(harness.service.items.map(\.id) == ["b"])
        #expect(harness.service.actionError == nil)
    }

    @Test func aFailedCompletePutsTheRowBackAndReports() async {
        let harness = await connected([
            RemoteTodoFixtures.item("a"), RemoteTodoFixtures.item("b"), RemoteTodoFixtures.item("c")
        ])
        harness.script.onComplete { throw NookTodoRemoteError.server(status: 500) }

        await harness.service.performComplete("b")

        #expect(harness.service.items.map(\.id) == ["a", "b", "c"])
        #expect(harness.service.actionError == .completeFailed)
    }

    @Test func addSendsTheTrimmedTitleAndTheDayThenReloads() async {
        let harness = await connected([])
        let added = RemoteTodoFixtures.item("new", "Buy milk")
        harness.script.onAdd {}
        harness.script.onLoad { _ in RemoteTodoFixtures.load([added]) }

        let took = await harness.service.performAdd(
            "  Buy milk \n", due: DateComponents(year: 2026, month: 10, day: 20)
        )

        #expect(took)
        #expect(harness.script.calls.contains("add:Buy milk:2026-10-20:w1"))
        #expect(harness.script.count(prefix: "load") == 2, "one load on activation, one after the add")
        #expect(harness.service.items.map(\.id) == ["new"])
    }

    @Test func setNotesShowsTheTextAtOnceAndTellsTheHubWhenTheAppHasIt() async {
        let harness = await connected([RemoteTodoFixtures.item("a", notes: "old")])
        let latch = TodoLatch()
        harness.script.onSetNotes { await latch.wait() }
        let finished = NotesReports()
        harness.service.onNotesWriteFinished = { id, text, saved in finished.add(id, text, saved) }

        let work = Task { await harness.service.performSetNotes("new", for: "a") }
        await harness.waitUntil { harness.script.calls.contains("notes:a:new") }

        #expect(harness.service.items.first?.notes == "new")
        #expect(finished.all.isEmpty)
        await latch.open()
        await work.value
        #expect(finished.all == ["a|new|true"])
        #expect(harness.service.items.first?.notes == "new")
    }

    @Test func aFailedNotesSavePutsTheOldNotesBackAndReports() async {
        let harness = await connected([RemoteTodoFixtures.item("a", notes: "old")])
        harness.script.onSetNotes { throw NookTodoRemoteError.badRequest }
        let finished = NotesReports()
        harness.service.onNotesWriteFinished = { id, text, saved in finished.add(id, text, saved) }

        await harness.service.performSetNotes("new", for: "a")

        #expect(harness.service.items.first?.notes == "old")
        #expect(harness.service.actionError == .notesFailed)
        #expect(harness.service.notesSaveFailed)
        #expect(finished.all == ["a|new|false"])
    }

    // MARK: Switching off

    @Test func switchingOffCancelsAndClears() async {
        let harness = RemoteTodoHarness(placeID: "w1", placeName: "Work")
        let latch = TodoLatch()
        harness.script.onLoad { _ in
            await latch.wait()
            return RemoteTodoFixtures.load([RemoteTodoFixtures.item("late")])
        }
        harness.service.setActive(true)
        let setup = harness.service.setupTask
        await harness.waitUntil { harness.script.count(prefix: "load") == 1 }

        harness.service.setActive(false)
        await latch.open()
        await setup?.value

        #expect(harness.service.isActive == false)
        #expect(harness.service.state == .inactive)
        #expect(harness.service.items.isEmpty)
        #expect(harness.service.hasToken == false)
        #expect(harness.service.token == nil)
    }
}

/// Collects what the notes callback was told, as `id|text|saved`.
@MainActor
private final class NotesReports {
    private(set) var all: [String] = []

    func add(_ id: String, _ text: String, _ saved: Bool) {
        all.append("\(id)|\(text)|\(saved)")
    }
}
