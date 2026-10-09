import Foundation
import OpenIslandCore

/// How an approval given in the island reaches the agent that asked.
enum AgentApprovalRoute: Equatable, Sendable {
    /// A hook of the agent holds its request open, and the bridge hands
    /// the island's answer back through it.
    case bridge
    /// Nothing carries an answer from the island to this agent. The
    /// request is approved where the agent runs.
    case agentOnly
    /// The bridge carries an answer, and the agent only takes a denial
    /// from it. Claude Code does this for a call one of its ask rules
    /// matches: it keeps its own prompt for the approval.
    case denyOnly

    /// Whether an approval sent from the island would be taken.
    var canApprove: Bool { self == .bridge }
}

enum AgentApprovalMetrics {
    /// Height the note about a lost answer adds above the buttons.
    static let notDeliveredHeight: CGFloat = 36
    /// How much taller the text and the one button are than the row of
    /// buttons they stand in for.
    static let agentOnlyExtraHeight: CGFloat = 38
    /// Height the line about approving in the terminal adds above the
    /// two buttons of a request the island can only deny.
    static let denyOnlyExtraHeight: CGFloat = 38
}

/// Where each waiting request came from, and which answers did not arrive.
/// It holds only what the app saw happen during the current wait.
struct AgentApprovalTracker: Equatable, Sendable {
    /// Requests the Codex app server reported. It only says that a thread
    /// waits, and the app has no call to answer one through it.
    private(set) var appServerRequestIDs: Set<UUID> = []
    /// Sessions for which a hook raised a request during this wait. The
    /// bridge holds that hook open and can answer it.
    private(set) var hookSessionIDs: Set<String> = []
    /// Requests whose answer was sent and did not reach the bridge. They
    /// are back on screen to be answered again.
    private(set) var undeliveredRequestIDs: Set<UUID> = []

    var isEmpty: Bool {
        appServerRequestIDs.isEmpty && hookSessionIDs.isEmpty && undeliveredRequestIDs.isEmpty
    }

    mutating func noteAppServerRequest(_ requestID: UUID) {
        appServerRequestIDs.insert(requestID)
    }

    /// A request that reached the app. One the app server reported is not
    /// a hook's.
    mutating func noteRequest(sessionID: String, requestID: UUID) {
        guard !appServerRequestIDs.contains(requestID) else { return }
        hookSessionIDs.insert(sessionID)
    }

    mutating func noteUndelivered(_ requestID: UUID) {
        undeliveredRequestIDs.insert(requestID)
    }

    /// Forgets everything about requests that no longer wait.
    mutating func prune(toWaiting sessions: [AgentSession]) {
        guard !isEmpty else { return }
        let requestIDs = Set(sessions.compactMap { $0.permissionRequest?.id })
        let sessionIDs = Set(sessions.map(\.id))
        appServerRequestIDs.formIntersection(requestIDs)
        undeliveredRequestIDs.formIntersection(requestIDs)
        hookSessionIDs.formIntersection(sessionIDs)
    }

    /// The island cannot answer a request only when it is proven to have
    /// no way there: the app server reported it, and no hook raised one
    /// for the session during this wait. Every other request goes through
    /// the bridge, which can only deny one the agent wants approved where
    /// it runs.
    func route(for session: AgentSession) -> AgentApprovalRoute {
        guard session.phase == .waitingForApproval, let request = session.permissionRequest else {
            return .bridge
        }
        let isAppServerOnly = appServerRequestIDs.contains(request.id) && !hookSessionIDs.contains(session.id)
        if isAppServerOnly { return .agentOnly }
        return request.requiresTerminalApproval ? .denyOnly : .bridge
    }

    func wasNotDelivered(_ requestID: UUID?) -> Bool {
        requestID.map(undeliveredRequestIDs.contains) ?? false
    }
}
