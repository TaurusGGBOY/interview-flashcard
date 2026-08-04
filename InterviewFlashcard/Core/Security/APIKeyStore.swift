import Foundation
import Security

protocol APIKeyStore: Sendable {
    func load() throws -> String?
    func save(_ key: String) throws
    func delete() throws
}

enum APIKeyStoreError: Error, Equatable, Sendable {
    case emptyKey
    case invalidEncoding
    case unreadableData
    case keychainStatus(Int32)
}

struct KeychainAPIKeyStore: APIKeyStore {
    static let service = "com.gaoguobin.InterviewFlashcard.deepseek"
    static let account = "api-key"

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw APIKeyStoreError.keychainStatus(status)
        }
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw APIKeyStoreError.unreadableData
        }
        return key
    }

    func save(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIKeyStoreError.emptyKey
        }
        guard let data = key.data(using: .utf8) else {
            throw APIKeyStoreError.invalidEncoding
        }

        let attributes = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError.keychainStatus(updateStatus)
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw APIKeyStoreError.keychainStatus(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError.keychainStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account
        ]
    }
}

final class InMemoryAPIKeyStore: APIKeyStore, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?

    init(key: String? = nil) {
        self.key = key
    }

    func load() throws -> String? {
        lock.withLock { key }
    }

    func save(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw APIKeyStoreError.emptyKey
        }
        lock.withLock { self.key = key }
    }

    func delete() throws {
        lock.withLock { key = nil }
    }
}
