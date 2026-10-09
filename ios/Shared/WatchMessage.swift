import Foundation

/// iPhone -> Watch
enum WatchMessage: Codable, Sendable {
    case permissionRequest(PermissionPayload)
    case question(QuestionPayload)
    case sessionCompleted(CompletionPayload)
    case resolved(requestID: String)  // Mac 侧已处理，通知 Watch 清理 UI

    struct PermissionPayload: Codable, Sendable {
        let requestID: String
        let sessionID: String
        let agentTool: String
        let title: String
        let summary: String
        let workingDirectory: String?
        /// The agent takes an approval of this request only in its
        /// terminal on the Mac. Nil from a phone app that does not send it.
        var requiresTerminalApproval: Bool? = nil
    }

    struct QuestionPayload: Codable, Sendable {
        let requestID: String
        let sessionID: String
        let agentTool: String
        let title: String
        let options: [String]
    }

    struct CompletionPayload: Codable, Sendable {
        let sessionID: String
        let agentTool: String
        let summary: String
    }
}

/// Watch -> iPhone
enum WatchResponse: Codable, Sendable {
    case resolution(requestID: String, action: String)
}
