import Foundation

/// What the Notion source is doing or why it cannot show live tasks. Each
/// case has its own user-facing sentence.
enum NotionTodoState: Equatable, Sendable {
    /// Notion is not the selected source. Nothing runs.
    case inactive
    case connecting
    case noToken
    /// The Keychain refused to read, save or delete the token.
    case keychainUnavailable
    /// 401: the token is wrong or was revoked.
    case invalidToken
    case noDatabase
    /// The mapping no longer fits the database schema.
    case needsAttention(NotionMappingIssue)
    /// 404: the database was deleted or is not shared with the integration.
    case databaseUnavailable
    /// 403 on a read: the integration lacks the read content capability.
    case missingReadCapability
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
        case .inactive: "nook.todo.notion.state.inactive"
        case .connecting: "nook.todo.notion.state.connecting"
        case .noToken: "nook.todo.notion.state.noToken"
        case .keychainUnavailable: "nook.todo.notion.state.keychain"
        case .invalidToken: "nook.todo.notion.state.invalidToken"
        case .noDatabase: "nook.todo.notion.state.noDatabase"
        case .needsAttention(let issue): "nook.todo.notion.issue.\(issue.rawValue)"
        case .databaseUnavailable: "nook.todo.notion.state.databaseUnavailable"
        case .missingReadCapability: "nook.todo.notion.state.missingRead"
        case .rateLimited: "nook.todo.notion.state.rateLimited"
        case .offline: "nook.todo.notion.state.offline"
        case .serverError: "nook.todo.notion.state.serverError"
        case .ready: "nook.todo.notion.state.ready"
        }
    }
}

/// A write that failed for a reason that may not repeat.
enum NotionTodoActionError: Equatable, Sendable {
    case addFailed
    case completeFailed
    case notesFailed
    case notesTooLong
    case rateLimited

    var concernsNotes: Bool { self == .notesFailed || self == .notesTooLong }

    var messageKey: String {
        switch self {
        case .notesFailed: "nook.todo.notion.error.notesFailed"
        case .notesTooLong: "nook.todo.notion.error.notesTooLong"
        case .addFailed: "nook.todo.notion.error.addFailed"
        case .completeFailed: "nook.todo.notion.error.completeFailed"
        case .rateLimited: "nook.todo.notion.state.rateLimited"
        }
    }
}

struct NotionDatabaseChoice: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

/// One full read of a database: schema, checked mapping and open tasks.
struct NotionTodoLoad: Equatable, Sendable {
    let schema: NotionDataSource
    let resolved: NotionResolvedMapping
    let items: [NookTodoItem]
}

enum NotionTodoLoadError: Error, Equatable, Sendable {
    case api(NotionAPIError)
    /// The schema loaded but the saved mapping does not fit it.
    case mapping(NotionMappingIssue, schema: NotionDataSource)
}

/// Runs off the main actor: two requests plus decoding and sorting.
enum NotionTodoLoader {
    static func load(
        client: NotionClient,
        dataSourceID: String,
        mapping: NotionTodoMapping,
        limit: Int
    ) async -> Result<NotionTodoLoad, NotionTodoLoadError> {
        let schema: NotionDataSource
        do {
            schema = try await client.dataSource(id: dataSourceID)
        } catch {
            return .failure(.api(NotionClient.classify(error)))
        }
        let resolved: NotionResolvedMapping
        switch NotionTodoMapper.resolve(mapping, schema: schema) {
        case .success(let value): resolved = value
        case .failure(let issue): return .failure(.mapping(issue, schema: schema))
        }
        do {
            let pages = try await client.queryPages(
                dataSourceID: dataSourceID,
                filter: NotionTodoMapper.queryFilter(resolved),
                sorts: NotionTodoMapper.sorts(resolved),
                limit: limit
            )
            let items = NotionTodoMapper.items(from: pages, resolved: resolved, listName: schema.title)
            return .success(NotionTodoLoad(schema: schema, resolved: resolved, items: items))
        } catch {
            let failure = NotionClient.classify(error)
            if case .badRequest = failure {
                // The schema fits on paper but Notion refused the filter or sort.
                return .failure(.mapping(.queryRejected, schema: schema))
            }
            return .failure(.api(failure))
        }
    }
}
