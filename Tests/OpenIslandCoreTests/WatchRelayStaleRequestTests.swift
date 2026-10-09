import Foundation
import Testing
@testable import OpenIslandCore

/// A card left open on a phone or a watch must only ever decide the request
/// it shows. Nothing here listens on the network.
struct WatchRelayStaleRequestTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Bool] = []
        func record(_ approved: Bool) { lock.withLock { stored.append(approved) } }
        var decisions: [Bool] { lock.withLock { stored } }
    }

    private static let session = AgentSession(
        id: "stale-session",
        title: "Claude · app",
        tool: .claudeCode,
        phase: .waitingForApproval,
        summary: "Waiting",
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )

    private static func request(_ summary: String) -> PermissionRequest {
        PermissionRequest(
            title: "Run a command",
            summary: summary,
            affectedPath: "",
            primaryActionTitle: "Allow Once",
            secondaryActionTitle: "Deny"
        )
    }

    private static func makeRelay() -> (WatchNotificationRelay, Recorder) {
        let relay = WatchNotificationRelay()
        let recorder = Recorder()
        relay.onResolvePermission = { _, approved in recorder.record(approved) }
        return (relay, recorder)
    }

    private static func push(_ request: PermissionRequest, to relay: WatchNotificationRelay) {
        relay.notifyEvent(
            .permissionRequested(PermissionRequested(sessionID: session.id, request: request, timestamp: .now)),
            session: session
        )
    }

    private static func answer(_ action: String, _ request: PermissionRequest, on relay: WatchNotificationRelay) -> WatchResolutionOutcome {
        relay.resolve(WatchResolutionRequest(requestID: request.id.uuidString, action: action))
    }

    @Test func anOlderCardCannotDecideTheSessionsNewerRequest() {
        let (relay, recorder) = Self.makeRelay()
        let first = Self.request("git status")
        let second = Self.request("rm -rf build")
        Self.push(first, to: relay)
        // The first request was answered on the Mac: the session runs again.
        relay.notifyEvent(
            .activityUpdated(SessionActivityUpdated(
                sessionID: Self.session.id, summary: "Running", phase: .running, timestamp: .now
            )),
            session: Self.session
        )
        Self.push(second, to: relay)

        #expect(Self.answer("allow", first, on: relay) == .unknownRequest)
        #expect(recorder.decisions.isEmpty)
        #expect(Self.answer("deny", second, on: relay) == .accepted)
        #expect(recorder.decisions == [false])
    }

    @Test func aNewRequestRetiresTheOneBeforeItWithNoEventBetween() {
        let (relay, recorder) = Self.makeRelay()
        let first = Self.request("git status")
        let second = Self.request("rm -rf build")
        Self.push(first, to: relay)
        Self.push(second, to: relay)

        #expect(Self.answer("allow", first, on: relay) == .unknownRequest)
        #expect(recorder.decisions.isEmpty)
        let one: Int = 1
        #expect(relay.pendingRequestCountForTests(sessionID: Self.session.id) == one)
    }

    @Test func anUpdateThatStillWaitsKeepsTheRequest() {
        let (relay, recorder) = Self.makeRelay()
        let request = Self.request("git status")
        Self.push(request, to: relay)
        relay.notifyEvent(
            .activityUpdated(SessionActivityUpdated(
                sessionID: Self.session.id, summary: "Waiting", phase: .waitingForApproval, timestamp: .now
            )),
            session: Self.session
        )

        #expect(Self.answer("allow", request, on: relay) == .accepted)
        #expect(recorder.decisions == [true])
    }

    @Test func aFinishedSessionRetiresItsRequest() {
        let (relay, recorder) = Self.makeRelay()
        let request = Self.request("git status")
        Self.push(request, to: relay)
        relay.notifyEvent(
            .sessionCompleted(SessionCompleted(sessionID: Self.session.id, summary: "Done", timestamp: .now)),
            session: Self.session
        )

        #expect(Self.answer("allow", request, on: relay) == .unknownRequest)
        #expect(recorder.decisions.isEmpty)
    }

    @Test func aPlainWordIsReadBeforeAnyButtonTitle() {
        #expect(WatchNotificationRelay.permissionAnswer(for: "deny", primaryAction: "Deny", secondaryAction: "Later") == .deny)
        #expect(WatchNotificationRelay.permissionAnswer(for: "allow", primaryAction: "Later", secondaryAction: "Allow") == .approve)
    }
}
