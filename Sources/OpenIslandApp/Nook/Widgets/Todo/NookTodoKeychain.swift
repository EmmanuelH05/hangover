import Foundation
import Security

/// Where a task source's token lives. The app uses the Keychain; tests use
/// an in-memory store.
protocol NookTodoTokenStoring: Sendable {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

/// Carries only the Security status code, never the secret.
struct NookTodoKeychainError: Error, Equatable, Sendable {
    let status: OSStatus
}

/// Generic-password Keychain item scoped to the app's bundle identifier.
/// Each task source has its own item.
struct NookTodoKeychain: NookTodoTokenStoring {
    static let fallbackBundleID = "app.openisland.dev"
    static let notionServiceSuffix = ".nook.todo.notion"
    static let tickTickServiceSuffix = ".nook.todo.ticktick"

    /// The Notion integration token. The item keeps the name it had before
    /// a second source existed, which keeps a saved token readable.
    static var notion: NookTodoKeychain {
        NookTodoKeychain(serviceSuffix: notionServiceSuffix, account: "integration-token")
    }

    /// The TickTick API token.
    static var tickTick: NookTodoKeychain {
        NookTodoKeychain(serviceSuffix: tickTickServiceSuffix, account: "api-token")
    }

    let service: String
    let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    init(serviceSuffix: String, account: String) {
        self.init(
            service: (Bundle.main.bundleIdentifier ?? Self.fallbackBundleID) + serviceSuffix,
            account: account
        )
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8), !token.isEmpty else {
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw NookTodoKeychainError(status: status)
        }
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw NookTodoKeychainError(status: update) }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else { throw NookTodoKeychainError(status: add) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NookTodoKeychainError(status: status)
        }
    }
}
