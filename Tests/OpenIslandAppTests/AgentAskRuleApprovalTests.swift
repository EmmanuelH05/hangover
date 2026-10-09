import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// A request Claude Code wants approved in its terminal, which is a call
/// one of its ask rules matches. The island can deny it and cannot approve
/// it.
private enum AskRuleFixtures {
    static func request() -> PermissionRequest {
        PermissionRequest(
            title: "Allow Bash",
            summary: "Run launchctl version",
            affectedPath: "/tmp/project",
            primaryActionTitle: "Allow Once",
            secondaryActionTitle: "Deny",
            toolName: "Bash",
            requiresTerminalApproval: true
        )
    }

    static func session(id: String = "ask-session") -> AgentSession {
        AgentToolsFixtures.approvalSession(id: id, request: request())
    }
}

/// The pure rules: where the answer goes and what a key press does.
struct AgentAskRuleRulesTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let requestID = UUID()
    private static let card = AgentHotkeyCard(sessionID: "ask", requestID: requestID)

    private static func context(
        card: AgentHotkeyCard? = card,
        shownSecondsAgo: TimeInterval = 30,
        canApprove: Bool = false
    ) -> AgentHotkeyContext {
        AgentHotkeyContext(
            card: card,
            foldedCard: nil,
            cardShownAt: card == nil ? nil : now.addingTimeInterval(-shownSecondsAgo),
            lastDecisionAt: nil,
            waiting: [AgentHotkeyCandidate(sessionID: "ask", requestID: requestID, canApprove: canApprove)],
            now: now
        )
    }

    @Test
    func aRequestMarkedForTheTerminalCanOnlyBeDenied() {
        let tracker = AgentApprovalTracker()
        #expect(tracker.route(for: AskRuleFixtures.session()) == .denyOnly)
        #expect(tracker.route(for: AgentToolsFixtures.approvalSession()) == .bridge)
        #expect(!AgentApprovalRoute.denyOnly.canApprove)
        #expect(!AgentApprovalRoute.agentOnly.canApprove)
        #expect(AgentApprovalRoute.bridge.canApprove)
    }

    @Test
    func aRequestWithNoWayToTheAgentStaysOneTheIslandCannotAnswer() {
        let session = AskRuleFixtures.session()
        var tracker = AgentApprovalTracker()
        tracker.noteAppServerRequest(session.permissionRequest!.id)

        #expect(tracker.route(for: session) == .agentOnly)
    }

    @Test
    func theApproveKeyNeverDecidesItAndTheDenyKeyDoes() {
        let context = Self.context()

        #expect(AgentHotkeyRules.decision(for: .approve, in: context) == .needsTerminal(sessionID: "ask"))
        #expect(AgentHotkeyRules.decision(for: .deny, in: context) == .act(sessionID: "ask", requestID: Self.requestID))
    }

    @Test
    func bothKeysDecideARequestTheIslandCanApprove() {
        let context = Self.context(canApprove: true)
        let act = AgentHotkeyDecision.act(sessionID: "ask", requestID: Self.requestID)

        #expect(AgentHotkeyRules.decision(for: .approve, in: context) == act)
        #expect(AgentHotkeyRules.decision(for: .deny, in: context) == act)
    }

    @Test
    func theRulesForShowingAndForTooSoonAreTheSameForBothKeys() {
        let inList = Self.context(card: nil)
        let justShown = Self.context(shownSecondsAgo: 0.2)

        for action in AgentHotkeyAction.allCases {
            #expect(AgentHotkeyRules.decision(for: action, in: inList) == .reveal(sessionID: "ask"))
            #expect(AgentHotkeyRules.decision(for: action, in: justShown) == .tooSoon)
        }
    }
}

/// The same on a live `AppModel`. Its bridge is never started and its
/// shortcuts run through `FakeHotkeyRegistrar`: no agent is answered and
/// nothing is registered with macOS.
@MainActor
@Suite(.serialized)
struct AgentAskRuleModelTests {
    private static var later: Date { Date.now.addingTimeInterval(5) }

    private static func silentModel() -> AppModel {
        let model = AppModel()
        model.overlay.isSoundMutedAccessor = { true }
        return model
    }

    private static func showCard(for sessionID: String, on model: AppModel) {
        model.notchStatus = .opened
        model.notchOpenReason = .notification
        model.islandSurface = .sessionList(actionableSessionID: sessionID)
    }

    /// Long enough for a send that fails at once, as every send of this
    /// model does, to report back.
    private static func settle() async throws {
        try await Task.sleep(for: .milliseconds(300))
    }

    @Test
    func theCardOffersDenyAndTheWayToTheTerminal() throws {
        let model = Self.silentModel()
        model.agentHotkeys.activate(registrar: FakeHotkeyRegistrar())
        let session = AskRuleFixtures.session()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)
        defer { model.notchClose() }

        #expect(model.agentRowTools(for: session).approvalRoute == .denyOnly)
        // Only the key that does something is named.
        #expect(model.agentHotkeyHint(for: session) == AgentHotkeyHint(approve: nil, deny: "⌃⌥N"))
        let expected: CGFloat = AgentApprovalMetrics.denyOnlyExtraHeight + AgentHotkeyHint.lineHeight
        #expect(model.agentApprovalExtraHeight(for: session) == expected)
    }

    @Test
    func withoutShortcutsTheCardIsOnlyTallerByItsLine() {
        let model = Self.silentModel()
        let session = AskRuleFixtures.session()
        model.state = SessionState(sessions: [session])

        let expected: CGFloat = AgentApprovalMetrics.denyOnlyExtraHeight
        #expect(model.agentApprovalExtraHeight(for: session) == expected)
    }

    @Test
    func anApprovalIsRefusedAndNothingIsSent() async throws {
        let model = Self.silentModel()
        let session = AskRuleFixtures.session()
        let request = try #require(session.permissionRequest)
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)
        defer { model.notchClose() }
        let messageBefore = model.lastActionMessage

        model.approvePermission(for: session.id, action: .allowOnce)
        model.approvePermission(for: session.id, action: .allowWithUpdates([]))
        // The way an answer from the watch comes in.
        model.approvePermission(for: session.id, approved: true)

        let after = try #require(model.state.session(id: session.id))
        #expect(after.phase == .waitingForApproval)
        #expect(after.permissionRequest?.id == request.id)
        #expect(model.islandSurface.sessionID == session.id)
        #expect(model.lastActionMessage == messageBefore)

        // A send would have failed, this model has no bridge, and said that
        // the answer was not delivered.
        try await Self.settle()
        #expect(model.nook.transient == nil)
        #expect(!model.agentRowTools(for: after).approvalWasNotDelivered)
    }

    /// The focused approval is the one way out the other tests did not
    /// take. It refuses an approval the same way and still sends a denial.
    @Test
    func theFocusedApprovalIsRefusedAndTheFocusedDenialIsSent() {
        let model = Self.silentModel()
        let session = AskRuleFixtures.session()
        let plain = AgentToolsFixtures.approvalSession(id: "plain-session")
        model.state = SessionState(sessions: [session, plain])
        defer { model.notchClose() }
        let before = model.lastActionMessage

        model.selectedSessionID = session.id
        model.approveFocusedPermission(true)
        let afterRefusal = model.lastActionMessage
        model.approveFocusedPermission(false)
        let afterDenial = model.lastActionMessage

        // A request the island can approve takes the same call.
        model.selectedSessionID = plain.id
        model.approveFocusedPermission(true)

        #expect(afterRefusal == before)
        #expect(afterDenial == "Denying permission for \(session.title).")
        #expect(model.lastActionMessage == "Approving permission for \(plain.title).")
        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)
    }

    /// A question Claude Code keeps in the terminal shows the card that
    /// says where to answer, and an answer from the island, the watch or
    /// the phone changes nothing.
    @Test
    func aQuestionForTheTerminalIsNotAnsweredFromTheIsland() {
        let model = Self.silentModel()
        let prompt = QuestionPrompt(title: "Environment", options: ["Prod", "Staging"], requiresTerminalAnswer: true)
        let marked = AgentToolsFixtures.questionSession(id: "marked-question", prompt: prompt)
        let open = AgentToolsFixtures.questionSession(
            id: "open-question",
            prompt: QuestionPrompt(title: "Region", options: ["West", "East"])
        )
        model.state = SessionState(sessions: [marked, open])
        defer { model.notchClose() }
        let before = model.lastActionMessage

        #expect(model.agentRowTools(for: marked).questionRoute == .terminalOnly)
        #expect(model.agentRowTools(for: open).questionRoute == .bridge)

        model.answerQuestion(for: marked.id, answer: QuestionPromptResponse(answer: "Prod"))
        model.selectedSessionID = marked.id
        model.answerFocusedQuestion("Prod")

        #expect(model.lastActionMessage == before)
        #expect(model.state.session(id: marked.id)?.phase == .waitingForAnswer)
        #expect(model.state.session(id: marked.id)?.questionPrompt?.id == prompt.id)

        model.answerQuestion(for: open.id, answer: QuestionPromptResponse(answer: "West"))
        #expect(model.lastActionMessage == "Sending answer for \(open.title).")
    }

    @Test
    func aDenialGoesThroughAsForAnyRequest() {
        let model = Self.silentModel()
        let session = AskRuleFixtures.session()
        model.state = SessionState(sessions: [session])
        defer { model.notchClose() }

        model.approvePermission(for: session.id, action: .deny)

        let after = model.state.session(id: session.id)
        #expect(after?.permissionRequest == nil)
        #expect(after?.phase == .completed)
    }

    @Test
    func theApproveKeyDecidesNothingAndTheDenyKeyDenies() {
        let model = Self.silentModel()
        let registrar = FakeHotkeyRegistrar()
        model.agentHotkeys.activate(registrar: registrar)
        let session = AskRuleFixtures.session()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)
        defer { model.notchClose() }

        // Both keys are held: the request waits, and a press can show it.
        #expect(registrar.registered.count == 2)
        #expect(model.agentHotkeyWaiting() == [
            AgentHotkeyCandidate(sessionID: session.id, requestID: session.permissionRequest!.id, canApprove: false),
        ])

        model.handleAgentHotkey(.approve, now: Self.later)
        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)
        #expect(model.islandSurface.sessionID == session.id)

        // The approve press decided nothing, which leaves no wait after it.
        model.handleAgentHotkey(.deny, now: Self.later.addingTimeInterval(0.1))
        #expect(model.state.session(id: session.id)?.phase == .completed)
    }

    @Test
    func theApproveKeyStillShowsItAsTheCardFromTheList() {
        let model = Self.silentModel()
        model.agentHotkeys.activate(registrar: FakeHotkeyRegistrar())
        let session = AskRuleFixtures.session()
        model.state = SessionState(sessions: [session])
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.islandSurface = .sessionList()
        model.nook.pageOverride = .agents
        defer { model.notchClose() }

        model.handleAgentHotkey(.approve, now: Self.later)

        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface.sessionID == session.id)
    }
}
