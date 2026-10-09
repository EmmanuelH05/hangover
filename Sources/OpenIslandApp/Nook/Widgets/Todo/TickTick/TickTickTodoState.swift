import Foundation

/// What the TickTick source is doing or why it cannot show live tasks. Each
/// case has its own user-facing sentence.
enum TickTickTodoState: Equatable, Sendable {
    /// TickTick is not the selected source. Nothing runs.
    case inactive
    case connecting
    case noToken
    /// The Keychain refused to read, save or delete the token.
    case keychainUnavailable
    /// 401: the token is wrong or was revoked.
    case invalidToken
    /// A new token could not be checked: TickTick was reached and did not
    /// answer the question. Nothing retries a connect.
    case connectFailed
    /// 404: the list was deleted.
    case listUnavailable
    /// Another 4xx: TickTick would not take the request.
    case rejected
    /// 403 on a read: the token may not open this list.
    case forbidden
    case rateLimited
    case offline
    case serverError
    case ready

    /// Failures that pass on their own. Cached tasks stay on screen.
    var isTransientFailure: Bool {
        switch self {
        case .rateLimited, .offline, .serverError: true
        default: false
        }
    }

    /// States where the last known tasks may still be shown.
    var allowsItems: Bool {
        switch self {
        case .ready, .connecting: true
        default: isTransientFailure
        }
    }

    var messageKey: String {
        switch self {
        case .inactive: "nook.todo.ticktick.state.inactive"
        case .connecting: "nook.todo.ticktick.state.connecting"
        case .noToken: "nook.todo.ticktick.state.noToken"
        case .keychainUnavailable: "nook.todo.ticktick.state.keychain"
        case .invalidToken: "nook.todo.ticktick.state.invalidToken"
        case .connectFailed: "nook.todo.ticktick.state.connectFailed"
        case .listUnavailable: "nook.todo.ticktick.state.listUnavailable"
        case .rejected: "nook.todo.ticktick.state.rejected"
        case .forbidden: "nook.todo.ticktick.state.forbidden"
        case .rateLimited: "nook.todo.ticktick.state.rateLimited"
        case .offline: "nook.todo.ticktick.state.offline"
        case .serverError: "nook.todo.ticktick.state.serverError"
        case .ready: "nook.todo.ticktick.state.ready"
        }
    }
}

/// A write that failed for a reason that may not repeat.
enum TickTickTodoActionError: Equatable, Sendable {
    case addFailed
    case completeFailed
    case notesFailed
    case rateLimited

    var concernsNotes: Bool { self == .notesFailed }

    var messageKey: String {
        switch self {
        case .addFailed: "nook.todo.ticktick.error.addFailed"
        case .completeFailed: "nook.todo.ticktick.error.completeFailed"
        case .notesFailed: "nook.todo.ticktick.error.notesFailed"
        case .rateLimited: "nook.todo.ticktick.state.rateLimited"
        }
    }
}

/// One entry of the list picker.
struct TickTickListChoice: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    /// Shared with the user as read or comment only.
    var isReadOnly = false
}

/// One full read of a list.
struct TickTickTodoLoad: Equatable, Sendable {
    /// The list's name as TickTick has it. Nil for the inbox.
    let listName: String?
    /// A shared list the user may not change.
    let isReadOnly: Bool
    /// The inbox's real ID, when this load was of the inbox and showed it.
    let inboxProjectID: String?
    let rows: [TickTickRow]
}

/// Runs off the main actor: one request plus decoding and sorting.
enum TickTickTodoLoader {
    static func load(
        client: TickTickClient,
        listID: String,
        listName: String,
        limit: Int
    ) async -> Result<TickTickTodoLoad, TickTickAPIError> {
        let data: TickTickProjectData
        do {
            data = try await client.projectData(id: listID)
        } catch {
            return .failure(TickTickClient.classify(error))
        }
        let isInbox = listID == TickTickClient.inboxID
        let liveName = isInbox ? nil : data.project.flatMap { $0.name.isEmpty ? nil : $0.name }
        let rows = TickTickTaskMapper.rows(
            from: data.tasks, listID: listID, listName: liveName ?? listName, limit: limit
        )
        return .success(TickTickTodoLoad(
            listName: liveName,
            isReadOnly: data.project?.isReadOnly ?? false,
            inboxProjectID: isInbox ? (data.tasks.compactMap(\.projectID).first ?? data.project?.id) : nil,
            rows: rows
        ))
    }
}
