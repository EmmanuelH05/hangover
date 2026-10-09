import Foundation
import Testing
@testable import OpenIslandCore

/// What the relay does with an answer a phone or a watch sends. Nothing
/// here listens on the network: the endpoint is never started, and its
/// answer handler is called directly, the way a posted answer reaches it.
struct WatchRelayAnswerTests {
    /// Collects what the relay hands on.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [(sessionID: String, approved: Bool)] = []

        func record(_ sessionID: String, _ approved: Bool) {
            lock.withLock { stored.append((sessionID, approved)) }
        }

        var decisions: [Bool] { lock.withLock { stored.map(\.approved) } }
    }

    private static let session = AgentSession(
        id: "relay-session",
        title: "Claude · app",
        tool: .claudeCode,
        phase: .waitingForApproval,
        summary: "Waiting",
        updatedAt: Date(timeIntervalSince1970: 1_000)
    )

    /// A relay with one request pushed to it, and the id a device answers by.
    private static func relay(
        needsTerminal: Bool,
        primaryAction: String = "Allow Once"
    ) -> (relay: WatchNotificationRelay, recorder: Recorder, requestID: String) {
        let relay = WatchNotificationRelay()
        let recorder = Recorder()
        relay.onResolvePermission = { sessionID, approved in recorder.record(sessionID, approved) }
        let request = PermissionRequest(
            title: "Run a command",
            summary: "launchctl version",
            affectedPath: "",
            primaryActionTitle: primaryAction,
            secondaryActionTitle: "Deny",
            requiresTerminalApproval: needsTerminal
        )
        relay.notifyEvent(
            .permissionRequested(PermissionRequested(sessionID: session.id, request: request, timestamp: .now)),
            session: session
        )
        return (relay, recorder, request.id.uuidString)
    }

    private static func post(_ action: String, _ requestID: String, to relay: WatchNotificationRelay) {
        _ = relay.endpoint.onResolution?(WatchResolutionRequest(requestID: requestID, action: action))
    }

    // MARK: Found by the review, each failing before the fix

    /// The phone's own button sends the title it shows, lowercased. The
    /// relay read anything but "allow" as a denial, which made the phone's
    /// Allow Once deny the request.
    @Test
    func thePhonesAllowOnceButtonApproves() {
        let (relay, recorder, requestID) = Self.relay(needsTerminal: false)

        Self.post("allow once", requestID, to: relay)

        #expect(recorder.decisions == [true])
    }

    /// An approval of a request Claude Code keeps in the terminal is not
    /// passed on, and does not use the request up: the same device can
    /// still deny it.
    @Test
    func aRefusedApprovalLeavesTheRequestDeniable() {
        let (relay, recorder, requestID) = Self.relay(needsTerminal: true)

        Self.post("allow once", requestID, to: relay)
        Self.post("allow", requestID, to: relay)
        let afterApprovals = recorder.decisions
        let stillWaiting = relay.pendingRequestCountForTests(sessionID: Self.session.id)
        Self.post("deny", requestID, to: relay)

        #expect(afterApprovals.isEmpty)
        let one: Int = 1
        let none: Int = 0
        #expect(stillWaiting == one)
        #expect(recorder.decisions == [false])
        #expect(relay.pendingRequestCountForTests(sessionID: Self.session.id) == none)
    }

    // MARK: What the device is told

    @Test
    func eachAnswerGetsTheOutcomeTheEndpointReportsBack() {
        let (relay, _, requestID) = Self.relay(needsTerminal: true)
        func outcome(_ action: String, _ id: String = requestID) -> WatchResolutionOutcome {
            relay.resolve(WatchResolutionRequest(requestID: id, action: action))
        }

        #expect(outcome("Allow Once") == .needsTerminal)
        #expect(outcome("always allow") == .unknownAction)
        #expect(outcome("deny", UUID().uuidString) == .unknownRequest)
        #expect(outcome("DENY") == .accepted)
        // Used up by the denial that was taken.
        #expect(outcome("deny") == .unknownRequest)
    }

    @Test(arguments: [
        ("allow", "Allow Once", "Deny", WatchNotificationRelay.PermissionAnswer.approve),
        ("allow once", "Allow Once", "Deny", .approve),
        (" Allow Once\n", "Allow Once", "Deny", .approve),
        ("approve", "Approve", "Reject", .approve),
        ("deny", "Allow Once", "Deny", .deny),
        ("reject", "Approve", "Reject", .deny),
        ("DENY", "Approve", "Reject", .deny),
    ])
    func anAnswerIsOneOfTheTwoButtonsOrOneOfTheTwoPlainWords(
        action: String,
        primary: String,
        secondary: String,
        expected: WatchNotificationRelay.PermissionAnswer
    ) {
        let answer = WatchNotificationRelay.permissionAnswer(for: action, primaryAction: primary, secondaryAction: secondary)
        #expect(answer == expected)
    }

    @Test(arguments: ["", "  ", "allowed", "allow always", "yes", "approve"])
    func anythingElseIsNoAnswer(action: String) {
        let answer = WatchNotificationRelay.permissionAnswer(for: action, primaryAction: "Allow Once", secondaryAction: "Deny")
        #expect(answer == nil)
    }

    /// A question the agent wants answered in the terminal takes no
    /// answer from a device, and is not used up by one.
    @Test
    func aQuestionForTheTerminalTakesNoAnswerFromADevice() {
        final class Answers: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: [String] = []
            func record(_ answer: String) { lock.withLock { stored.append(answer) } }
            var all: [String] { lock.withLock { stored } }
        }
        let relay = WatchNotificationRelay()
        let answers = Answers()
        relay.onAnswerQuestion = { _, answer in answers.record(answer) }
        let marked = QuestionPrompt(title: "Environment", options: ["Prod", "Staging"], requiresTerminalAnswer: true)
        let open = QuestionPrompt(title: "Region", options: ["West", "East"])
        // Two sessions: a session's newer request retires its older one.
        var other = Self.session
        other.id = "relay-session-2"
        for (prompt, session) in [(marked, Self.session), (open, other)] {
            relay.notifyEvent(
                .questionAsked(QuestionAsked(sessionID: session.id, prompt: prompt, timestamp: .now)),
                session: session
            )
        }

        let refused = relay.resolve(WatchResolutionRequest(requestID: marked.id.uuidString, action: "Prod"))
        let taken = relay.resolve(WatchResolutionRequest(requestID: open.id.uuidString, action: "West"))

        #expect(refused == .needsTerminal)
        #expect(taken == .accepted)
        #expect(answers.all == ["West"])
        let one: Int = 1
        #expect(relay.pendingRequestCountForTests(sessionID: Self.session.id) == one)
    }

    /// The mark travels with the request, which lets a device leave the
    /// approve button off.
    @Test
    func theRequestADeviceIsSentSaysWhenItNeedsTheTerminal() throws {
        func sent(needsTerminal: Bool) throws -> [String: Any] {
            let event = WatchPermissionEvent(
                sessionID: "s",
                agentTool: "Claude Code",
                title: "Run a command",
                summary: "launchctl version",
                workingDirectory: nil,
                primaryAction: "Allow Once",
                secondaryAction: "Deny",
                requestID: "r",
                requiresTerminalApproval: needsTerminal
            )
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event))
            return try #require(object as? [String: Any])
        }

        #expect(try sent(needsTerminal: true)["requiresTerminalApproval"] as? Bool == true)
        #expect(try sent(needsTerminal: false)["requiresTerminalApproval"] as? Bool == false)
    }

    /// Text the relay cannot read decides nothing. It used to deny.
    @Test
    func anActionThatIsNeitherButtonDecidesNothing() {
        let (relay, recorder, requestID) = Self.relay(needsTerminal: false)

        Self.post("always allow", requestID, to: relay)
        Self.post("", requestID, to: relay)

        #expect(recorder.decisions.isEmpty)
        let one: Int = 1
        #expect(relay.pendingRequestCountForTests(sessionID: Self.session.id) == one)
    }
}
