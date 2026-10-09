import Foundation
import os

/// Monitors AppModel state changes and relays relevant events to the WatchHTTPEndpoint as SSE pushes.
/// Also handles resolution callbacks from the Watch/iPhone back to the bridge.
public final class WatchNotificationRelay: @unchecked Sendable {
    private static let logger = Logger(subsystem: "app.openisland", category: "WatchNotificationRelay")

    public let endpoint: WatchHTTPEndpoint

    /// Callback to resolve a permission request (sessionID, approved).
    public var onResolvePermission: (@Sendable (_ sessionID: String, _ approved: Bool) -> Void)?

    /// Callback to answer a question (sessionID, answer).
    public var onAnswerQuestion: (@Sendable (_ sessionID: String, _ answer: String) -> Void)?

    /// Provider for looking up session by ID (needed to map requestID → sessionID).
    public var sessionLookup: (@Sendable (_ requestID: String) -> (sessionID: String, kind: PendingRequestKind)?)?

    public enum PendingRequestKind: Sendable {
        case permission
        case question
    }

    /// A request a device may answer.
    private struct PendingRequest {
        var sessionID: String
        var kind: PendingRequestKind
        /// The two button titles the device was sent. It answers with one
        /// of them, lowercased, or with "allow" or "deny".
        var primaryAction: String?
        var secondaryAction: String?
        /// The agent takes the approval only where it runs.
        var requiresTerminalApproval = false
    }

    /// The two answers a permission request has.
    enum PermissionAnswer: Equatable, Sendable {
        case approve
        case deny
    }

    // Maps requestID → the pending request
    private let queue = DispatchQueue(label: "app.openisland.watch.relay")
    private var pendingRequests: [String: PendingRequest] = [:]

    public init(endpoint: WatchHTTPEndpoint = WatchHTTPEndpoint()) {
        self.endpoint = endpoint
        setupResolutionHandler()
    }

    // MARK: - Event Notification

    /// Called by AppModel after applying a tracked event. Filters for events that should
    /// be pushed to the Watch and constructs the appropriate SSE event.
    public func notifyEvent(_ event: AgentEvent, session: AgentSession?) {
        switch event {
        case let .permissionRequested(payload):
            guard let session else { return }
            // The app answers a session's newest request only. An older
            // card still open on a device must not decide this one.
            retirePendingRequests(forSession: payload.sessionID)
            let requestID = payload.request.id.uuidString
            trackPendingRequest(requestID: requestID, PendingRequest(
                sessionID: payload.sessionID,
                kind: .permission,
                primaryAction: payload.request.primaryActionTitle,
                secondaryAction: payload.request.secondaryActionTitle,
                requiresTerminalApproval: payload.request.requiresTerminalApproval
            ))

            let sseEvent = WatchSSEEvent.permissionRequested(WatchPermissionEvent(
                sessionID: payload.sessionID,
                agentTool: session.tool.displayName,
                title: payload.request.title,
                summary: payload.request.summary,
                workingDirectory: session.jumpTarget?.workingDirectory,
                primaryAction: payload.request.primaryActionTitle,
                secondaryAction: payload.request.secondaryActionTitle,
                requestID: requestID,
                requiresTerminalApproval: payload.request.requiresTerminalApproval
            ))
            endpoint.pushEvent(sseEvent)
            Self.logger.info("Pushed permissionRequested for session \(payload.sessionID)")

        case let .questionAsked(payload):
            guard let session else { return }
            retirePendingRequests(forSession: payload.sessionID)
            let requestID = payload.prompt.id.uuidString
            trackPendingRequest(requestID: requestID, PendingRequest(
                sessionID: payload.sessionID,
                kind: .question,
                requiresTerminalApproval: payload.prompt.requiresTerminalAnswer
            ))

            // A question answered only in the terminal goes out with no
            // options: a device then has nothing to send back.
            let sseEvent = WatchSSEEvent.questionAsked(WatchQuestionEvent(
                sessionID: payload.sessionID,
                agentTool: session.tool.displayName,
                title: payload.prompt.title,
                options: payload.prompt.requiresTerminalAnswer ? [] : payload.prompt.options,
                requestID: requestID
            ))
            endpoint.pushEvent(sseEvent)
            Self.logger.info("Pushed questionAsked for session \(payload.sessionID)")

        case let .activityUpdated(payload):
            // An answer given on the Mac moves the session on without an
            // "actionable state resolved" event. The request is over all
            // the same, and its id must stop working on the devices.
            if payload.phase != .waitingForApproval, payload.phase != .waitingForAnswer {
                retirePendingRequests(forSession: payload.sessionID)
            }

        case let .sessionCompleted(payload):
            retirePendingRequests(forSession: payload.sessionID)
            guard let session else { return }
            let sseEvent = WatchSSEEvent.sessionCompleted(WatchCompletionEvent(
                sessionID: payload.sessionID,
                agentTool: session.tool.displayName,
                summary: payload.summary
            ))
            endpoint.pushEvent(sseEvent)
            Self.logger.info("Pushed sessionCompleted for session \(payload.sessionID)")

        case let .actionableStateResolved(payload):
            // Find and remove ALL pending requests for this session, notifying
            // iPhone for each one. A single session can have multiple pending
            // entries when subagents fan out permission/question prompts in
            // parallel; the previous one-at-a-time removal silently leaked
            // every entry past the first and left the watch UI showing stale
            // pending requests.
            let requestIDs = removeAllPendingRequests(forSession: payload.sessionID)
            if requestIDs.isEmpty {
                Self.logger.debug("No pending request found for resolved session \(payload.sessionID)")
            } else {
                for requestID in requestIDs {
                    let resolvedEvent = WatchSSEEvent.actionableStateResolved(WatchResolvedEvent(
                        requestID: requestID,
                        sessionID: payload.sessionID
                    ))
                    endpoint.pushEvent(resolvedEvent)
                }
                Self.logger.info("Pushed actionableStateResolved for \(requestIDs.count) request(s) on session \(payload.sessionID)")
            }

        default:
            break
        }
    }

    // MARK: - Lifecycle

    public func start() {
        endpoint.start()
    }

    public func stop() {
        endpoint.stop()
    }

    // MARK: - Private

    /// Forgets every request still waiting for a session and tells the
    /// devices each one is over.
    private func retirePendingRequests(forSession sessionID: String) {
        for requestID in removeAllPendingRequests(forSession: sessionID) {
            endpoint.pushEvent(.actionableStateResolved(WatchResolvedEvent(
                requestID: requestID,
                sessionID: sessionID
            )))
        }
    }

    private func trackPendingRequest(requestID: String, _ request: PendingRequest) {
        queue.sync {
            pendingRequests[requestID] = request
        }
    }

    /// Reads a device's answer to a permission request. The phone's own
    /// buttons send the title they show, lowercased ("allow once"), and
    /// its notification and the watch send "allow" or "deny". Anything
    /// else is no answer: text this cannot read must never deny a request.
    static func permissionAnswer(
        for action: String,
        primaryAction: String?,
        secondaryAction: String?
    ) -> PermissionAnswer? {
        let action = action.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !action.isEmpty else { return nil }
        func matches(_ title: String?) -> Bool {
            title?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == action
        }
        // The two plain words first: a title can never turn "deny" into
        // an approval.
        if action == "allow" { return .approve }
        if action == "deny" { return .deny }
        if matches(primaryAction) { return .approve }
        if matches(secondaryAction) { return .deny }
        return nil
    }

    /// What to do with a device's answer, and the request it used up. The
    /// request stays waiting unless the answer is taken: an approval this
    /// refuses leaves the device able to deny afterwards.
    func resolve(_ resolution: WatchResolutionRequest) -> WatchResolutionOutcome {
        enum Step {
            case finished(WatchResolutionOutcome)
            case permission(sessionID: String, approved: Bool)
            case question(sessionID: String)
        }

        let known: Step? = queue.sync {
            guard let pending = pendingRequests[resolution.requestID] else { return nil }
            switch pending.kind {
            case .permission:
                guard let answer = Self.permissionAnswer(
                    for: resolution.action,
                    primaryAction: pending.primaryAction,
                    secondaryAction: pending.secondaryAction
                ) else {
                    return .finished(.unknownAction)
                }
                if answer == .approve, pending.requiresTerminalApproval {
                    return .finished(.needsTerminal)
                }
                pendingRequests.removeValue(forKey: resolution.requestID)
                return .permission(sessionID: pending.sessionID, approved: answer == .approve)
            case .question:
                if pending.requiresTerminalApproval { return .finished(.needsTerminal) }
                pendingRequests.removeValue(forKey: resolution.requestID)
                return .question(sessionID: pending.sessionID)
            }
        }

        let step: Step
        if let known {
            step = known
        } else if let found = sessionLookup?(resolution.requestID) {
            // A request this relay never pushed. Nothing is known about
            // its buttons, and only the two plain words are read.
            switch found.kind {
            case .permission:
                guard let answer = Self.permissionAnswer(for: resolution.action, primaryAction: nil, secondaryAction: nil) else {
                    step = .finished(.unknownAction)
                    break
                }
                step = .permission(sessionID: found.sessionID, approved: answer == .approve)
            case .question:
                step = .question(sessionID: found.sessionID)
            }
        } else {
            Self.logger.warning("Resolution for unknown requestID: \(resolution.requestID)")
            return .unknownRequest
        }

        switch step {
        case let .finished(outcome):
            Self.logger.info("Did not take a device's answer for \(resolution.requestID): \(String(describing: outcome), privacy: .public)")
            return outcome
        case let .permission(sessionID, approved):
            Self.logger.info("Resolving permission for session \(sessionID): \(approved ? "approve" : "deny", privacy: .public)")
            onResolvePermission?(sessionID, approved)
            return .accepted
        case let .question(sessionID):
            Self.logger.info("Answering question for session \(sessionID)")
            onAnswerQuestion?(sessionID, resolution.action)
            return .accepted
        }
    }

    /// Removes every pending request belonging to a session and returns
    /// the cleared requestIDs in the order they were originally inserted
    /// (best effort — `Dictionary` iteration order is undefined, so callers
    /// must not rely on order for correctness).
    private func removeAllPendingRequests(forSession sessionID: String) -> [String] {
        queue.sync {
            let matchingKeys = pendingRequests.compactMap { key, value in
                value.sessionID == sessionID ? key : nil
            }
            for key in matchingKeys {
                pendingRequests.removeValue(forKey: key)
            }
            return matchingKeys
        }
    }

    /// Test-only accessor for verifying pending-request cleanup.
    func pendingRequestCountForTests(sessionID: String? = nil) -> Int {
        queue.sync {
            guard let sessionID else { return pendingRequests.count }
            return pendingRequests.values.filter { $0.sessionID == sessionID }.count
        }
    }

    private func setupResolutionHandler() {
        endpoint.onResolution = { [weak self] resolution in
            self?.resolve(resolution) ?? .unknownRequest
        }
    }
}
