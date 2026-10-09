import Foundation
import Security

/// Where the integration token lives. The app uses the Keychain; tests use
/// an in-memory store.
protocol NotionTokenStoring: Sendable {
    func read() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

/// Carries only the Security status code, never the secret.
struct NotionKeychainError: Error, Equatable, Sendable {
    let status: OSStatus
}

/// Generic-password Keychain item scoped to the app's bundle identifier.
struct NotionKeychain: NotionTokenStoring {
    static let fallbackBundleID = "app.openisland.dev"
    static let serviceSuffix = ".nook.todo.notion"
    static let defaultAccount = "integration-token"

    let service: String
    let account: String

    init(
        service: String = (Bundle.main.bundleIdentifier ?? NotionKeychain.fallbackBundleID) + NotionKeychain.serviceSuffix,
        account: String = NotionKeychain.defaultAccount
    ) {
        self.service = service
        self.account = account
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
            throw NotionKeychainError(status: status)
        }
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw NotionKeychainError(status: update) }
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let add = SecItemAdd(attributes as CFDictionary, nil)
        guard add == errSecSuccess else { throw NotionKeychainError(status: add) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NotionKeychainError(status: status)
        }
    }
}
