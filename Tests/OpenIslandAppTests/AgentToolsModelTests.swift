import Foundation
import Testing
@testable import OpenIslandApp
import OpenIslandCore

/// The agent tools on a live `AppModel`. The model here never starts its
/// bridge, which means a decision it "sends" reaches no agent, and the
/// shortcuts run through `FakeHotkeyRegistrar`: nothing is registered with
/// macOS and no real agent is approved, denied or answered.
@MainActor
@Suite(.serialized)
struct AgentToolsModelTests {
    /// Long enough after a card comes on screen for a shortcut to decide it.
    private static var later: Date { Date.now.addingTimeInterval(5) }

    /// The island open on its list of agents.
    private static func showList(on model: AppModel) {
        model.notchStatus = .opened
        model.notchOpenReason = .click
        model.islandSurface = .sessionList()
        model.nook.pageOverride = .agents
    }

    /// Makes the card on screen look as if it came up `seconds` ago.
    private static func backdateCard(on model: AppModel, by seconds: TimeInterval) {
        guard let card = model.agentHotkeys.shownCard else { return }
        model.agentHotkeys.noteShownCard(nil)
        model.agentHotkeys.noteShownCard(card, now: Date.now.addingTimeInterval(-seconds))
    }

    /// The request of this session is answered somewhere else, in its
    /// terminal for one. This is the event the bridge sends then.
    private static func answerElsewhere(_ sessionID: String, on model: AppModel) {
        model.state.apply(.actionableStateResolved(
            ActionableStateResolved(sessionID: sessionID, summary: "Answered in the terminal.", timestamp: .now)
        ))
    }

    /// A model whose cards make no sound.
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

    // MARK: Shortcuts

    @Test
    func theApproveShortcutApprovesTheRequestOnTheCard() {
        let model = AppModel()
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)

        model.handleAgentHotkey(.approve, now: Self.later)

        let after = model.state.session(id: session.id)
        #expect(after?.permissionRequest == nil)
        #expect(after?.phase == .running)
    }

    @Test
    func theDenyShortcutDeniesIt() {
        let model = AppModel()
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)

        model.handleAgentHotkey(.deny, now: Self.later)

        let after = model.state.session(id: session.id)
        #expect(after?.permissionRequest == nil)
        #expect(after?.phase == .completed)
    }

    @Test
    func aPressRightAfterTheCardComesUpDecidesNothing() {
        let model = AppModel()
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)

        model.handleAgentHotkey(.approve, now: .now)

        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)
    }

    @Test
    func aPressWithNothingWaitingDoesNothing() {
        let model = AppModel()
        let session = AgentToolsFixtures.questionSession()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)

        model.handleAgentHotkey(.approve, now: Self.later)

        #expect(model.state.session(id: session.id)?.phase == .waitingForAnswer)
        #expect(model.agentHotkeyContext().waiting.isEmpty)
    }

    @Test
    func withSeveralWaitingOnlyTheOneOnTheCardIsDecided() {
        let model = AppModel()
        let first = AgentToolsFixtures.approvalSession(id: "first")
        let second = AgentToolsFixtures.approvalSession(id: "second")
        model.state = SessionState(sessions: [first, second])
        Self.showCard(for: "second", on: model)

        model.handleAgentHotkey(.approve, now: Self.later)

        #expect(model.state.session(id: "second")?.phase == .running)
        #expect(model.state.session(id: "first")?.phase == .waitingForApproval)
    }

    @Test
    func withTheListOpenTheRequestInItsTopRowIsShownAsACardAndNotDecided() {
        let model = Self.silentModel()
        model.agentHotkeys.activate(registrar: FakeHotkeyRegistrar())
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        Self.showList(on: model)
        defer { model.notchClose() }
        #expect(model.islandListSessions.first?.id == session.id)
        // A row in the list names no keys: a press there decides nothing.
        #expect(model.agentHotkeyHint(for: session) == nil)

        let press = Self.later
        model.handleAgentHotkey(.approve, now: press)

        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)
        #expect(model.notchOpenReason == .notification)
        #expect(model.islandSurface.sessionID == session.id)
        #expect(model.agentHotkeyHint(for: session) != nil)

        // The card only just came up.
        model.handleAgentHotkey(.approve, now: press.addingTimeInterval(0.15))
        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)

        model.handleAgentHotkey(.approve, now: press.addingTimeInterval(2))
        #expect(model.state.session(id: session.id)?.phase == .running)
    }

    @Test
    func aRequestFurtherDownTheListIsShownAsACardAndNotDecided() {
        let model = Self.silentModel()
        var working = AgentToolsFixtures.approvalSession(id: "working", updatedAt: .now)
        working.phase = .running
        working.permissionRequest = nil
        let waiting = AgentToolsFixtures.approvalSession(id: "waiting", updatedAt: .now.addingTimeInterval(-600))
        model.state = SessionState(sessions: [working, waiting])
        Self.showList(on: model)
        defer { model.notchClose() }

        model.handleAgentHotkey(.deny, now: Self.later)

        #expect(model.state.session(id: "waiting")?.phase == .waitingForApproval)
        #expect(model.islandSurface.sessionID == "waiting")
        #expect(model.notchOpenReason == .notification)
    }

    @Test
    func aSecondPressRightAfterAnApprovalDoesNotApproveTheNextSession() {
        let model = Self.silentModel()
        let first = AgentToolsFixtures.approvalSession(id: "first")
        let second = AgentToolsFixtures.approvalSession(id: "second")
        model.state = SessionState(sessions: [first, second])
        Self.showCard(for: "first", on: model)
        defer { model.notchClose() }

        let press = Self.later
        model.handleAgentHotkey(.approve, now: press)
        #expect(model.state.session(id: "first")?.phase == .running)

        // 150 ms later. The other request has waited all along.
        model.handleAgentHotkey(.approve, now: press.addingTimeInterval(0.15))
        #expect(model.state.session(id: "second")?.phase == .waitingForApproval)
        // The press showed it as the card. One right behind it is too soon.
        #expect(model.islandSurface.sessionID == "second")
        model.handleAgentHotkey(.approve, now: press.addingTimeInterval(0.3))
        #expect(model.state.session(id: "second")?.phase == .waitingForApproval)

        model.handleAgentHotkey(.approve, now: press.addingTimeInterval(2))
        #expect(model.state.session(id: "second")?.phase == .running)
    }

    @Test
    func aSecondPressDoesNotApproveACardThatTookTheFirstOnesPlace() {
        let model = Self.silentModel()
        let first = AgentToolsFixtures.approvalSession(id: "first")
        let second = AgentToolsFixtures.approvalSession(id: "second")
        model.state = SessionState(sessions: [first, second])
        Self.showCard(for: "first", on: model)
        defer { model.notchClose() }

        let press = Self.later
        model.handleAgentHotkey(.approve, now: press)
        #expect(model.state.session(id: "first")?.phase == .running)

        // The next request's card comes up by itself, as a waiting card does.
        Self.showCard(for: "second", on: model)
        model.handleAgentHotkey(.approve, now: press.addingTimeInterval(0.15))
        #expect(model.state.session(id: "second")?.phase == .waitingForApproval)
    }

    @Test
    func aCardThatJustCameUpIsNotDecidedHoweverLongItsRequestHasWaited() {
        let model = Self.silentModel()
        // The request arrived 0.7s ago. Its card was held back and is 50 ms old.
        let session = AgentToolsFixtures.approvalSession(updatedAt: .now.addingTimeInterval(-0.7))
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)

        model.handleAgentHotkey(.approve, now: Date.now.addingTimeInterval(0.05))

        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)
    }

    @Test
    func aPressMeantForARequestAnsweredElsewhereDoesNotLandOnTheNextOne() {
        let model = Self.silentModel()
        let first = AgentToolsFixtures.approvalSession(id: "first")
        let second = AgentToolsFixtures.approvalSession(id: "second")
        model.state = SessionState(sessions: [first, second])
        Self.showCard(for: "first", on: model)
        defer { model.notchClose() }

        // "first" is answered in its terminal just before the press.
        Self.answerElsewhere("first", on: model)
        #expect(model.state.session(id: "first")?.phase == .running)
        model.handleAgentHotkey(.approve, now: Self.later)
        #expect(model.state.session(id: "second")?.phase == .waitingForApproval)
        // The press showed "second" as the card and decided nothing.
        #expect(model.islandSurface.sessionID == "second")
    }

    @Test
    func norWhenTheNextCardHasAlreadyTakenItsPlace() {
        let model = Self.silentModel()
        let first = AgentToolsFixtures.approvalSession(id: "first")
        let second = AgentToolsFixtures.approvalSession(id: "second")
        model.state = SessionState(sessions: [first, second])
        Self.showCard(for: "first", on: model)
        Self.backdateCard(on: model, by: 60)

        // "first" is answered in its terminal and the card of "second"
        // takes its place, 50 ms before the press.
        Self.answerElsewhere("first", on: model)
        Self.showCard(for: "second", on: model)
        model.handleAgentHotkey(.approve, now: Date.now.addingTimeInterval(0.05))

        #expect(model.state.session(id: "second")?.phase == .waitingForApproval)
    }

    @Test
    func aNewRequestOnTheSameCardStartsItsOwnTime() {
        let model = Self.silentModel()
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)
        // The card has been up for a minute with the first request.
        Self.backdateCard(on: model, by: 60)

        let next = PermissionRequest(title: "Allow Bash", summary: "Run rm", affectedPath: "/tmp/project")
        model.state.apply(.permissionRequested(
            PermissionRequested(sessionID: session.id, request: next, timestamp: .now)
        ))

        #expect(model.agentHotkeys.shownCard == AgentHotkeyCard(sessionID: session.id, requestID: next.id))
        // A press 50 ms on, meant for the first request, decides nothing.
        model.handleAgentHotkey(.approve, now: Date.now.addingTimeInterval(0.05))
        #expect(model.state.session(id: session.id)?.permissionRequest?.id == next.id)
    }

    @Test
    func aFoldedCardIsNotDecidedAndThePressOpensItAgain() {
        let model = Self.silentModel()
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)
        let tools = model.agentRowTools(for: session)
        let asked = tools.unfoldRequests

        // The user folds the card: its command and buttons are out of sight.
        tools.onApprovalFoldChanged(true)
        model.handleAgentHotkey(.approve, now: Self.later)
        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)
        #expect(model.agentRowTools(for: session).unfoldRequests == asked + 1)

        // Open again: its time starts over.
        tools.onApprovalFoldChanged(false)
        model.handleAgentHotkey(.approve, now: Date.now.addingTimeInterval(0.05))
        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)

        model.handleAgentHotkey(.approve, now: Self.later)
        #expect(model.state.session(id: session.id)?.phase == .running)
    }

    @Test
    func aRequestOffScreenIsShownByTheFirstPressAndDecidedByALaterOne() {
        let model = AppModel()
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        #expect(model.notchStatus == .closed)

        let firstPress = Self.later
        model.handleAgentHotkey(.approve, now: firstPress)
        defer { model.notchClose() }

        // Shown, not decided.
        #expect(model.notchStatus == .opened)
        #expect(model.islandSurface.sessionID == session.id)
        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)

        // A second press in the same breath still decides nothing.
        model.handleAgentHotkey(.approve, now: firstPress.addingTimeInterval(0.1))
        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)

        model.handleAgentHotkey(.approve, now: firstPress.addingTimeInterval(2))
        #expect(model.state.session(id: session.id)?.phase == .running)
    }

    @Test
    func theKeysAreHeldOnlyWhileARequestWaitsAndAPressGoesThroughTheModel() {
        let model = AppModel()
        let registrar = FakeHotkeyRegistrar()
        model.agentHotkeys.activate(registrar: registrar)
        #expect(registrar.registered.isEmpty)

        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        #expect(registrar.registered.count == 2)
        Self.showCard(for: session.id, on: model)

        // The card came up this instant: the press is too soon.
        registrar.press(.approve)
        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)

        // A key that went down before the card came up decides nothing,
        // whenever the app gets to it.
        registrar.press(.approve, at: Date.now.addingTimeInterval(-3))
        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)

        // A press once the card has been up a while. The time of the key
        // going down is what the model judges it by.
        registrar.press(.approve, at: Self.later)
        #expect(model.state.session(id: session.id)?.phase == .running)
    }

    @Test
    func onlyTheCardTheShortcutsActOnNamesTheKeys() {
        let model = AppModel()
        model.agentHotkeys.activate(registrar: FakeHotkeyRegistrar())
        let first = AgentToolsFixtures.approvalSession(id: "first")
        let second = AgentToolsFixtures.approvalSession(id: "second")
        model.state = SessionState(sessions: [first, second])
        Self.showCard(for: "second", on: model)

        #expect(model.agentHotkeyHint(for: second) == AgentHotkeyHint(approve: "⌃⌥Y", deny: "⌃⌥N"))
        #expect(model.agentHotkeyHint(for: first) == nil)
        #expect(model.agentHotkeyHint(for: AgentToolsFixtures.questionSession()) == nil)
    }

    @Test
    func aCardNamesNoKeysTheSystemNeverTook() {
        let model = AppModel()
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)

        // No registrar: the app never asked macOS for the shortcuts.
        #expect(model.agentHotkeyHint(for: session) == nil)
    }

    @Test
    func theKeysAreNotHeldForARequestNoPressCanReach() {
        let model = AppModel()
        let registrar = FakeHotkeyRegistrar()
        model.agentHotkeys.activate(registrar: registrar)

        // A subagent's session is not in the island's list.
        var hidden = AgentToolsFixtures.approvalSession(id: "subagent")
        hidden.claudeMetadata = ClaudeSessionMetadata(transcriptPath: "/tmp/.claude/projects/p/subagents/agent-1.jsonl")
        model.state = SessionState(sessions: [hidden])

        #expect(model.islandListSessions.isEmpty)
        #expect(model.agentHotkeyWaiting().isEmpty)
        #expect(registrar.registered.isEmpty)
    }

    // MARK: Requests the island cannot answer

    /// Hands the model a request the way `applyTrackedEvent` does, minus
    /// its side effects: no card, no sound, nothing saved to disk.
    private static func deliver(_ request: PermissionRequest, sessionID: String, fromAppServer: Bool, to model: AppModel) {
        let event = AgentEvent.permissionRequested(
            PermissionRequested(sessionID: sessionID, request: request, timestamp: .now)
        )
        if fromAppServer { model.noteCodexAppServerEvent(event) }
        model.state.apply(event)
        model.noteAgentToolsEvent(event, ingress: .bridge)
    }

    private static func codexSession(_ id: String) -> AgentSession {
        AgentSession(
            id: id,
            title: "Codex · project",
            tool: .codex,
            attachmentState: .attached,
            phase: .running,
            summary: "Working",
            updatedAt: .now
        )
    }

    @Test
    func aRequestOnlyTheCodexAppServerReportedGetsNoKeysAndNoButtons() throws {
        let model = Self.silentModel()
        let registrar = FakeHotkeyRegistrar()
        model.agentHotkeys.activate(registrar: registrar)
        model.state = SessionState(sessions: [Self.codexSession("codex")])

        let request = PermissionRequest(title: "Approval Required", summary: "Codex is waiting for approval.", affectedPath: "")
        Self.deliver(request, sessionID: "codex", fromAppServer: true, to: model)
        Self.showCard(for: "codex", on: model)

        let session = try #require(model.state.session(id: "codex"))
        #expect(session.phase == .waitingForApproval)
        #expect(model.agentRowTools(for: session).approvalRoute == .agentOnly)
        #expect(model.agentHotkeyHint(for: session) == nil)
        #expect(model.agentHotkeyWaiting().isEmpty)
        #expect(registrar.registered.isEmpty)

        model.handleAgentHotkey(.approve, now: Self.later)
        #expect(model.state.session(id: "codex")?.phase == .waitingForApproval)

        let taller: CGFloat = AgentApprovalMetrics.agentOnlyExtraHeight
        #expect(model.agentApprovalExtraHeight(for: session) == taller)
    }

    @Test
    func aHookRequestForTheSameSessionCanBeAnswered() throws {
        let model = Self.silentModel()
        let registrar = FakeHotkeyRegistrar()
        model.agentHotkeys.activate(registrar: registrar)
        model.state = SessionState(sessions: [Self.codexSession("codex")])

        // The hook asks first, and the bridge holds it open. The app server
        // then reports the same wait with a request of its own.
        let hooked = PermissionRequest(title: "Run Bash command", summary: "Codex wants to run a shell command.", affectedPath: "swift test")
        Self.deliver(hooked, sessionID: "codex", fromAppServer: false, to: model)
        let reported = PermissionRequest(title: "Approval Required", summary: "Codex is waiting for approval.", affectedPath: "")
        Self.deliver(reported, sessionID: "codex", fromAppServer: true, to: model)

        let session = try #require(model.state.session(id: "codex"))
        #expect(session.permissionRequest?.id == reported.id)
        #expect(model.agentRowTools(for: session).approvalRoute == .bridge)
        #expect(registrar.registered.count == 2)
    }

    @Test
    func whatWasNotedAboutARequestGoesWhenItStopsWaiting() {
        let model = Self.silentModel()
        model.state = SessionState(sessions: [Self.codexSession("codex")])
        let request = PermissionRequest(title: "Approval Required", summary: "Codex is waiting for approval.", affectedPath: "")
        Self.deliver(request, sessionID: "codex", fromAppServer: true, to: model)
        #expect(!model.agentApprovals.isEmpty)

        Self.answerElsewhere("codex", on: model)
        #expect(model.agentApprovals.isEmpty)
    }

    // MARK: Answers that did not arrive

    /// Waits for the model's send, which fails at once because this model
    /// never connected its bridge, to run its failure handler.
    private static func waitForNotice(on model: AppModel) async throws {
        for _ in 0..<200 where model.nook.transient == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test
    func anApprovalThatDoesNotReachTheBridgePutsTheRequestBackAndSaysSo() async throws {
        let model = Self.silentModel()
        let session = AgentToolsFixtures.approvalSession()
        let request = try #require(session.permissionRequest)
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)
        defer { model.notchClose() }

        model.approvePermission(for: session.id, action: .allowOnce)
        #expect(model.state.session(id: session.id)?.phase == .running)

        try await Self.waitForNotice(on: model)

        let after = try #require(model.state.session(id: session.id))
        #expect(after.phase == .waitingForApproval)
        #expect(after.permissionRequest?.id == request.id)
        #expect(model.agentRowTools(for: after).approvalWasNotDelivered)
        #expect(model.nook.transient?.text == model.lang.t("approval.notDelivered.notice"))
        // The card is back, and it names what happened.
        #expect(model.islandSurface.sessionID == session.id)
        let noteHeight: CGFloat = AgentApprovalMetrics.notDeliveredHeight
        #expect(model.agentApprovalExtraHeight(for: after) >= noteHeight)
    }

    @Test
    func aLostDenialIsPutBackTheSameWay() async throws {
        let model = Self.silentModel()
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])
        defer { model.notchClose() }

        model.approvePermission(for: session.id, approved: false)
        #expect(model.state.session(id: session.id)?.phase == .completed)

        try await Self.waitForNotice(on: model)

        #expect(model.state.session(id: session.id)?.phase == .waitingForApproval)
    }

    @Test
    func aSessionThatMovedOnIsLeftAloneAndTheLossIsStillSaid() async throws {
        let model = Self.silentModel()
        let session = AgentToolsFixtures.approvalSession()
        model.state = SessionState(sessions: [session])

        model.approvePermission(for: session.id, action: .allowOnce)
        // Something else happens to the session before the send fails.
        model.state.apply(.activityUpdated(
            SessionActivityUpdated(sessionID: session.id, summary: "Running Bash", phase: .running, timestamp: .now)
        ))

        try await Self.waitForNotice(on: model)

        let after = try #require(model.state.session(id: session.id))
        #expect(after.phase == .running)
        #expect(!model.agentRowTools(for: after).approvalWasNotDelivered)
        #expect(model.nook.transient != nil)
    }

    // MARK: Replies

    @Test
    func aReplyThatCouldNotBeSentGoesBackIntoItsField() {
        let model = AppModel()
        var session = AgentToolsFixtures.questionSession(id: "done")
        session.phase = .completed
        session.questionPrompt = nil
        model.state = SessionState(sessions: [session])
        let draft = model.agentRowTools(for: session).completionDraft

        // The field is emptied when the reply is handed over. It went out.
        draft.wrappedValue = ""
        model.agentReplyWasSent("now run the tests", to: session, succeeded: true)
        #expect(draft.wrappedValue == "")
        #expect(model.nook.transient == nil)

        // This one did not: the text is back to be sent again, and the
        // island says what happened.
        model.agentReplyWasSent("now run the tests", to: session, succeeded: false)
        #expect(draft.wrappedValue == "now run the tests")
        #expect(model.nook.transient?.text == model.lang.t("completion.replyNotSent.notice"))

        // Something newer is being typed by then: it is left alone.
        draft.wrappedValue = "and the linter"
        model.agentReplyWasSent("now run the tests", to: session, succeeded: false)
        #expect(draft.wrappedValue == "and the linter")
    }

    @Test
    func aReplyThatCouldNotBeSentIsNotPutBackOnASessionThatWorksAgain() {
        let model = AppModel()
        var session = AgentToolsFixtures.questionSession(id: "done")
        session.phase = .running
        session.questionPrompt = nil
        model.state = SessionState(sessions: [session])

        model.agentReplyWasSent("now run the tests", to: session, succeeded: false)

        #expect(model.agentReplies.isEmpty)
    }

    @Test
    func aHalfTypedAnswerSurvivesTheIslandClosingAndGoesWhenAnswered() {
        let model = AppModel()
        let session = AgentToolsFixtures.questionSession()
        model.state = SessionState(sessions: [session])
        Self.showCard(for: session.id, on: model)

        var draft = AgentQuestionDraft()
        draft.selections["Which database?"] = ["Other"]
        draft.freeformTexts["Which database?|Other"] = "postgres, but only in"
        model.agentRowTools(for: session).questionDraft.wrappedValue = draft

        model.notchStatus = .closed
        model.notchOpenReason = nil
        model.islandSurface = .sessionList()
        #expect(model.agentRowTools(for: session).questionDraft.wrappedValue == draft)

        model.answerQuestion(for: session.id, answer: QuestionPromptResponse(answer: "postgres"))
        #expect(model.agentReplies.isEmpty)
    }

    @Test
    func aHalfTypedReplyToAFinishedAgentSurvivesToo() {
        let model = AppModel()
        var session = AgentToolsFixtures.questionSession(id: "done")
        session.phase = .completed
        session.questionPrompt = nil
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])

        model.agentRowTools(for: session).completionDraft.wrappedValue = "now run the"
        #expect(model.agentRowTools(for: session).completionDraft.wrappedValue == "now run the")

        // The agent starts working again: the reply has nothing to answer.
        model.state.apply(
            .activityUpdated(SessionActivityUpdated(sessionID: "done", summary: "Working", phase: .running, timestamp: .now))
        )
        #expect(model.agentReplies.isEmpty)
    }

    @Test
    func theIslandStaysOpenUnderAReplyBeingTyped() {
        let model = AppModel()
        var session = AgentToolsFixtures.questionSession(id: "done")
        session.phase = .completed
        session.questionPrompt = nil
        session.isProcessAlive = true
        model.state = SessionState(sessions: [session])
        model.notchStatus = .opened
        model.notchOpenReason = .hover
        model.nook.pageOverride = .agents
        #expect(model.shouldAutoCollapseOnMouseLeave)

        model.setAgentReplyEditing(true, sessionID: "done")
        #expect(model.isTypingAgentReply)
        #expect(!model.shouldAutoCollapseOnMouseLeave)
        #expect(model.shouldDeferTimedNotificationAutoCollapse)

        model.setAgentReplyEditing(false, sessionID: "done")
        #expect(!model.isTypingAgentReply)
        #expect(model.shouldAutoCollapseOnMouseLeave)
    }

    @Test
    func typingStopsCountingOnceTheIslandIsClosedOrTheSessionIsGone() {
        let model = AppModel()
        let session = AgentToolsFixtures.questionSession()
        model.state = SessionState(sessions: [session])
        model.notchStatus = .opened
        model.nook.pageOverride = .agents
        model.setAgentReplyEditing(true, sessionID: session.id)
        #expect(model.isTypingAgentReply)

        model.notchStatus = .closed
        #expect(!model.isTypingAgentReply)

        model.notchStatus = .opened
        model.state = SessionState(sessions: [])
        #expect(!model.isTypingAgentReply)
        #expect(model.agentReplyEditingSessionID == nil)
    }

    @Test
    func onlyAgentsTheIslandCanAnswerGetAField() {
        let model = AppModel()
        let claude = AgentToolsFixtures.questionSession(id: "claude", tool: .claudeCode)
        let codex = AgentToolsFixtures.questionSession(
            id: "codex",
            tool: .codex,
            prompt: QuestionPrompt(title: "Codex is waiting for input.", options: [])
        )
        #expect(model.agentRowTools(for: claude).questionRoute == .bridge)
        #expect(model.agentRowTools(for: codex).questionRoute == .terminalOnly)
    }

    // MARK: What it did

    private static func claudeSession(_ id: String) -> AgentSession {
        var session = AgentSession(
            id: id,
            title: "Claude · project",
            tool: .claudeCode,
            origin: .live,
            attachmentState: .attached,
            phase: .completed,
            summary: "Ready",
            updatedAt: .now
        )
        session.isHookManaged = true
        return session
    }

    /// A model that never shows a completion card: every finished session
    /// counts as already in front.
    private static func quietModel() -> AppModel {
        AppModel(isNotificationSessionAlreadyFrontmost: { _ in true })
    }

    /// One prompt, one edit and a finish, 60 seconds apart end to end.
    private static func turnEvents(sessionID: String) -> [AgentEvent] {
        let start = Date.now.addingTimeInterval(-90)
        return [
            .activityUpdated(SessionActivityUpdated(
                sessionID: sessionID,
                summary: "Prompt: fix it",
                phase: .running,
                timestamp: start,
                startsTurn: true
            )),
            .claudeSessionMetadataUpdated(ClaudeSessionMetadataUpdated(
                sessionID: sessionID,
                claudeMetadata: ClaudeSessionMetadata(currentTool: "Edit", currentToolInputPreview: "/repo/a.swift"),
                timestamp: start.addingTimeInterval(10)
            )),
            .activityUpdated(SessionActivityUpdated(
                sessionID: sessionID,
                summary: "Edit finished.",
                phase: .running,
                timestamp: start.addingTimeInterval(12),
                finishedTool: AgentToolFinish(toolName: "Edit", filePath: "/repo/a.swift")
            )),
            .claudeSessionMetadataUpdated(ClaudeSessionMetadataUpdated(
                sessionID: sessionID,
                claudeMetadata: ClaudeSessionMetadata(lastAssistantMessage: "Fixed."),
                timestamp: start.addingTimeInterval(20)
            )),
            .sessionCompleted(SessionCompleted(
                sessionID: sessionID,
                summary: "Fixed.",
                timestamp: start.addingTimeInterval(60)
            )),
        ]
    }

    /// Hands the model the events the way `applyTrackedEvent` does, minus
    /// its side effects: no card, no sound, nothing saved to disk.
    private static func run(
        _ model: AppModel,
        sessionID: String,
        ingress: TrackedEventIngress
    ) {
        for event in turnEvents(sessionID: sessionID) {
            model.state.apply(event)
            model.noteAgentToolsEvent(event, ingress: ingress)
        }
    }

    @Test
    func aFinishedSessionCarriesWhatItDidSinceItsPrompt() throws {
        let model = Self.quietModel()
        model.state = SessionState(sessions: [Self.claudeSession("s")])

        Self.run(model, sessionID: "s", ingress: .bridge)

        let session = try #require(model.state.session(id: "s"))
        let summary = try #require(model.agentTurnSummary(for: session))
        let expectedDuration: TimeInterval = 60
        #expect(summary.duration == expectedDuration)
        #expect(summary.fileEdits == .files(["/repo/a.swift"]))
        #expect(model.agentRowTools(for: session).turnSummary == summary)

        let rowHeight: CGFloat = AgentTurnSummaryMetrics.rowHeight
        #expect(model.agentTurnSummaryRowHeight(for: session, at: .now) == rowHeight)
    }

    @Test
    func theModelsOwnEventPathFeedsTheLedger() throws {
        let model = Self.quietModel()
        model.state = SessionState(sessions: [Self.claudeSession("s")])

        for event in Self.turnEvents(sessionID: "s") {
            model.applyTrackedEvent(event, updateLastActionMessage: false, ingress: .bridge)
        }

        let session = try #require(model.state.session(id: "s"))
        #expect(model.agentTurnSummary(for: session)?.fileEdits == .files(["/repo/a.swift"]))
    }

    @Test
    func aSessionStillWorkingShowsNoSummary() throws {
        let model = Self.quietModel()
        model.state = SessionState(sessions: [Self.claudeSession("s")])
        let prompt = AgentEvent.activityUpdated(SessionActivityUpdated(
            sessionID: "s",
            summary: "Prompt: fix it",
            phase: .running,
            timestamp: .now,
            startsTurn: true
        ))
        model.state.apply(prompt)
        model.noteAgentToolsEvent(prompt, ingress: .bridge)

        let session = try #require(model.state.session(id: "s"))
        #expect(model.agentTurnSummary(for: session) == nil)
        let noHeight: CGFloat = 0
        #expect(model.agentTurnSummaryRowHeight(for: session, at: .now) == noHeight)
    }

    @Test
    func eventsReadBackFromATranscriptAreNotCounted() throws {
        let model = Self.quietModel()
        model.state = SessionState(sessions: [Self.claudeSession("s")])

        Self.run(model, sessionID: "s", ingress: .rollout)

        let session = try #require(model.state.session(id: "s"))
        #expect(model.agentTurnSummary(for: session) == nil)
    }

    @Test
    func aSessionThatGoesAwayTakesItsRecordAlong() {
        let model = Self.quietModel()
        model.state = SessionState(sessions: [Self.claudeSession("s")])
        Self.run(model, sessionID: "s", ingress: .bridge)
        #expect(model.agentTurns.turn(for: "s") != nil)

        model.state = SessionState(sessions: [])
        #expect(model.agentTurns.turn(for: "s") == nil)
    }
}
