import Foundation
import OpenIslandCore
import OSLog
import SwiftUI

private let agentToolsLog = Logger(subsystem: "app.openisland", category: "agentTools")

/// What the agent tools hand one session row: the shortcut keys to print,
/// where an approval and a typed answer go, the drafts being typed, and
/// what the session did since its last prompt.
struct AgentRowTools {
    var hotkeyHint: AgentHotkeyHint?
    /// Whether an approval given here reaches the agent at all.
    var approvalRoute: AgentApprovalRoute
    /// The last answer to this request was sent and did not arrive.
    var approvalWasNotDelivered: Bool
    /// Goes up when a shortcut asks the folded card to open again.
    var unfoldRequests: Int
    /// The card reports its buttons being folded away and opened again.
    var onApprovalFoldChanged: (Bool) -> Void
    var questionRoute: AgentQuestionReplyRoute
    var questionDraft: Binding<AgentQuestionDraft>
    var completionDraft: Binding<String>
    var turnSummary: AgentTurnSummary?
    var onReplyEditingChanged: (Bool) -> Void
}

/// Glue between `AppModel` and the agent tools: approve and deny from the
/// keyboard, replies in progress, and the "what it did" card. The rules
/// live in `AgentHotkeyRules`, `AgentReplyDraftStore` and `AgentTurnLedger`.
extension AppModel {
    func configureAgentTools() {
        agentHotkeys.onPress = { [weak self] action, pressedAt in
            self?.handleAgentHotkey(action, now: pressedAt)
        }
    }

    // MARK: - Keeping up with the sessions

    /// Runs after every change to `state`.
    func agentToolsStateDidChange() {
        let waitingSessions = state.sessionsByID.values.filter {
            $0.phase == .waitingForApproval && $0.permissionRequest != nil
        }
        if !agentApprovals.isEmpty {
            var pruned = agentApprovals
            pruned.prune(toWaiting: waitingSessions)
            if pruned != agentApprovals { agentApprovals = pruned }
        }
        refreshAgentHotkeyArming(hasWaitingSession: !waitingSessions.isEmpty)
        refreshAgentHotkeyCard()

        // Written back only when something changed, which keeps views that
        // read them from redrawing on every event.
        if !agentReplies.isEmpty {
            var pruned = agentReplies
            pruned.prune(to: Array(state.sessionsByID.values))
            if pruned != agentReplies { agentReplies = pruned }
        }
        if agentTurns.turns.keys.contains(where: { state.sessionsByID[$0] == nil }) {
            agentTurns.prune(keeping: Set(state.sessionsByID.keys))
        }
        if let editingID = agentReplyEditingSessionID, state.sessionsByID[editingID] == nil {
            agentReplyEditingSessionID = nil
        }
    }

    /// Feeds the ledger and notes where a request came from. Only hook
    /// events count: the transcript watchers report the same tools a second
    /// time and under other names.
    func noteAgentToolsEvent(_ event: AgentEvent, ingress: TrackedEventIngress) {
        guard ingress == .bridge else { return }
        if case let .permissionRequested(payload) = event {
            agentApprovals.noteRequest(sessionID: payload.sessionID, requestID: payload.request.id)
            // Where a request came from decides whether a press can reach it.
            refreshAgentHotkeyArming(hasWaitingSession: true)
        }
        var ledger = agentTurns
        ledger.record(event)
        if ledger != agentTurns { agentTurns = ledger }
    }

    /// Runs for every event of the Codex app server, before it is applied.
    /// The app server only says that a thread waits for approval, and the
    /// app has no call to answer one through it.
    func noteCodexAppServerEvent(_ event: AgentEvent) {
        if case let .permissionRequested(payload) = event {
            agentApprovals.noteAppServerRequest(payload.request.id)
        }
    }

    // MARK: - Shortcuts

    /// The keys are held only while a press has a request to decide or to
    /// show: the same list a press reads. `hasWaitingSession` false skips
    /// building that list, which is the usual case.
    func refreshAgentHotkeyArming(hasWaitingSession: Bool) {
        agentHotkeys.setArmed(agentsEnabled && hasWaitingSession && !agentHotkeyWaiting().isEmpty)
    }

    /// The requests a press can decide or show: waiting, in the island's
    /// list, and with a way for the answer to reach the agent. One the
    /// agent wants approved where it runs is listed as deny only.
    func agentHotkeyWaiting() -> [AgentHotkeyCandidate] {
        islandListSessions.compactMap { session in
            guard session.phase == .waitingForApproval, let request = session.permissionRequest else {
                return nil
            }
            let route = agentApprovals.route(for: session)
            guard route != .agentOnly else { return nil }
            return AgentHotkeyCandidate(sessionID: session.id, requestID: request.id, canApprove: route.canApprove)
        }
    }

    /// The request the island shows as its single card right now.
    var agentHotkeyLiveCard: AgentHotkeyCard? {
        guard agentsEnabled,
              notchStatus == .opened,
              notchOpenReason == .notification,
              let sessionID = islandSurface.sessionID,
              let session = state.session(id: sessionID),
              session.phase == .waitingForApproval,
              let request = session.permissionRequest else {
            return nil
        }
        return AgentHotkeyCard(sessionID: sessionID, requestID: request.id)
    }

    /// Runs whenever the card on screen may have changed: the island
    /// opened, closed or swapped its card, or a session changed. A new
    /// card is stamped with the time it came on screen.
    func refreshAgentHotkeyCard(now: Date = .now) {
        agentHotkeys.noteShownCard(agentHotkeyLiveCard, now: now)
    }

    func agentHotkeyContext(now: Date = .now) -> AgentHotkeyContext {
        let shown = agentHotkeys.shownCard
        let isCard = shown != nil && shown == agentHotkeyLiveCard
        let isFolded = shown == agentHotkeys.foldedCard
        return AgentHotkeyContext(
            card: isCard && !isFolded ? shown : nil,
            foldedCard: isCard && isFolded ? shown : nil,
            cardShownAt: agentHotkeys.cardShownAt,
            lastDecisionAt: agentHotkeys.lastDecisionAt,
            waiting: agentHotkeyWaiting(),
            now: now
        )
    }

    /// A press of an agent shortcut. It decides a request only when that
    /// request is the single card on screen and has been for a moment. Any
    /// other waiting request is shown as the card first, and only a later
    /// press decides it. `now` is when the key went down, which can be a
    /// moment before the app gets to it. The approve key decides nothing
    /// for a request the agent wants approved where it runs. Its card says
    /// where to approve, and no notice is shown: notices live on the closed
    /// island, and this card is open.
    func handleAgentHotkey(_ action: AgentHotkeyAction, now: Date = .now) {
        guard agentsEnabled else { return }
        // A change of card the app did not see happen starts its time now.
        refreshAgentHotkeyCard(now: now)

        switch AgentHotkeyRules.decision(for: action, in: agentHotkeyContext(now: now)) {
        case .ignore, .tooSoon, .needsTerminal:
            return
        case let .reveal(sessionID):
            if let folded = agentHotkeys.foldedCard, folded == agentHotkeys.shownCard, folded.sessionID == sessionID {
                // The request is the card already, with its buttons folded
                // away. Opening them again restarts its time.
                agentHotkeys.requestUnfold()
                return
            }
            notchOpen(reason: .notification, surface: .sessionList(actionableSessionID: sessionID))
            agentHotkeys.noteRevealed(now: now)
        case let .act(sessionID, requestID):
            guard state.session(id: sessionID)?.permissionRequest?.id == requestID else { return }
            agentHotkeys.lastDecisionAt = now
            approvePermission(for: sessionID, action: action == .approve ? .allowOnce : .deny)
        }
    }

    /// The keys to print on this session's approval card. Only the card a
    /// press would decide carries them: a row in the list never does, and
    /// neither does a request the island cannot answer.
    func agentHotkeyHint(for session: AgentSession) -> AgentHotkeyHint? {
        guard session.phase == .waitingForApproval, let request = session.permissionRequest else { return nil }
        // Most rows are not the card. Leave before the list is built.
        guard let shown = agentHotkeys.shownCard,
              shown.sessionID == session.id, shown.requestID == request.id else {
            return nil
        }
        var hint = agentHotkeys.hint
        // The approve key does nothing for a request the island can only deny.
        if !agentApprovals.route(for: session).canApprove { hint.approve = nil }
        guard !hint.isEmpty,
              AgentHotkeyRules.isOnCard(sessionID: session.id, requestID: request.id, in: agentHotkeyContext()) else {
            return nil
        }
        return hint
    }

    /// Height the approval area takes beyond its command box and buttons:
    /// the line of keys, the note about a lost answer, or the taller text
    /// that stands in for buttons the island cannot back.
    func agentApprovalExtraHeight(for session: AgentSession) -> CGFloat {
        let route = agentApprovals.route(for: session)
        if route == .agentOnly {
            return AgentApprovalMetrics.agentOnlyExtraHeight
        }
        var height: CGFloat = route == .denyOnly ? AgentApprovalMetrics.denyOnlyExtraHeight : 0
        if agentHotkeyHint(for: session) != nil { height += AgentHotkeyHint.lineHeight }
        if agentApprovals.wasNotDelivered(session.permissionRequest?.id) {
            height += AgentApprovalMetrics.notDeliveredHeight
        }
        return height
    }

    // MARK: - Answers that did not arrive

    /// The answer to a request was sent and never reached the bridge. The
    /// request goes back on screen when nothing else has happened to the
    /// session since, and the island says that the answer was lost.
    func agentApprovalWasNotDelivered(waiting: AgentSession, resolved: AgentSession?, error: any Error) {
        // An answer cut off by the agents switch going off is no news.
        guard agentsEnabled else { return }
        agentToolsLog.error(
            "An approval answer for session \(waiting.id, privacy: .public) did not reach the agent: \(error.localizedDescription, privacy: .public)"
        )
        nook.showTransient(
            symbol: "exclamationmark.triangle.fill",
            text: lang.t("approval.notDelivered.notice"),
            tint: .orange
        )

        guard let request = waiting.permissionRequest,
              let resolved, state.session(id: waiting.id) == resolved else {
            return
        }
        agentApprovals.noteUndelivered(request.id)
        state.apply(.permissionRequested(
            PermissionRequested(sessionID: waiting.id, request: request, timestamp: .now)
        ))
        overlay.presentNotificationSurface(.sessionList(actionableSessionID: waiting.id))
    }

    /// A reply typed to a finished session went out, or failed to. The
    /// field is emptied when the reply is handed over. A reply that could
    /// not be sent goes back into it, unless something newer is being
    /// typed there, and the island says that it was not sent.
    func agentReplyWasSent(_ text: String, to session: AgentSession, succeeded: Bool) {
        guard !succeeded, agentsEnabled else { return }
        agentToolsLog.error("A reply to session \(session.id, privacy: .public) could not be sent to its terminal")
        nook.showTransient(
            symbol: "exclamationmark.triangle.fill",
            text: lang.t("completion.replyNotSent.notice"),
            tint: .orange
        )
        guard state.session(id: session.id)?.phase == .completed,
              agentReplies.completionDraft(sessionID: session.id).isEmpty else {
            return
        }
        agentReplies.setCompletionDraft(text, sessionID: session.id)
    }

    // MARK: - Replies

    /// True while a reply is being typed in the open island. The island
    /// does not close under it.
    var isTypingAgentReply: Bool {
        guard notchStatus == .opened, !showsNookPage, let sessionID = agentReplyEditingSessionID else {
            return false
        }
        return state.session(id: sessionID) != nil
    }

    func setAgentReplyEditing(_ isEditing: Bool, sessionID: String) {
        if isEditing {
            agentReplyEditingSessionID = sessionID
        } else if agentReplyEditingSessionID == sessionID {
            agentReplyEditingSessionID = nil
        }
    }

    // MARK: - What it did

    /// What the session did since the user's last prompt. Nil while it
    /// works, and for a session whose prompt the app never saw.
    func agentTurnSummary(for session: AgentSession) -> AgentTurnSummary? {
        guard session.phase == .completed, let record = agentTurns.turn(for: session.id) else { return nil }
        return AgentTurnSummary.make(from: record, tool: session.tool)
    }

    /// Height the summary line adds to this session's row in the list. The
    /// row shows it with its other detail lines, which a row that has gone
    /// quiet folds away.
    func agentTurnSummaryRowHeight(for session: AgentSession, at date: Date) -> CGFloat {
        guard session.islandPresence(at: date) != .inactive,
              !session.isStaleCompletedForIsland(at: date, threshold: completedStaleThreshold.seconds),
              agentTurnSummary(for: session) != nil else {
            return 0
        }
        return AgentTurnSummaryMetrics.rowHeight
    }

    // MARK: - Rows

    func agentRowTools(for session: AgentSession) -> AgentRowTools {
        let sessionID = session.id
        let promptID = session.questionPrompt?.id
        let requestID = session.permissionRequest?.id
        return AgentRowTools(
            hotkeyHint: agentHotkeyHint(for: session),
            approvalRoute: agentApprovals.route(for: session),
            approvalWasNotDelivered: agentApprovals.wasNotDelivered(requestID),
            unfoldRequests: agentHotkeys.unfoldRequests,
            onApprovalFoldChanged: { [weak self] isFolded in
                guard let self, let requestID else { return }
                self.agentHotkeys.noteCard(
                    AgentHotkeyCard(sessionID: sessionID, requestID: requestID),
                    isFolded: isFolded
                )
            },
            questionRoute: .route(for: session),
            questionDraft: Binding(
                get: { [weak self] in
                    guard let self, let promptID else { return AgentQuestionDraft() }
                    return self.agentReplies.questionDraft(sessionID: sessionID, promptID: promptID)
                },
                set: { [weak self] draft in
                    guard let self, let promptID else { return }
                    self.agentReplies.setQuestionDraft(draft, sessionID: sessionID, promptID: promptID)
                }
            ),
            completionDraft: Binding(
                get: { [weak self] in self?.agentReplies.completionDraft(sessionID: sessionID) ?? "" },
                set: { [weak self] text in self?.agentReplies.setCompletionDraft(text, sessionID: sessionID) }
            ),
            turnSummary: agentTurnSummary(for: session),
            onReplyEditingChanged: { [weak self] isEditing in
                self?.setAgentReplyEditing(isEditing, sessionID: sessionID)
            }
        )
    }
}
