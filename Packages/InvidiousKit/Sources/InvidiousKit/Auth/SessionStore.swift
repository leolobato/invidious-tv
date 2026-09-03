import Foundation
import Security

/// Stores Invidious session IDs per profile.
public protocol SessionStore: Sendable {
    func sid(for profileID: UUID) throws -> String?
    func setSID(_ sid: String, for profileID: UUID) throws
    func removeSID(for profileID: UUID) throws
}

public enum SessionStoreError: Error, Sendable {
    case keychain(OSStatus)
}

/// Keychain-backed session storage.
public struct KeychainSessionStore: SessionStore {
    public let service: String

    public init(service: String = "org.lobato.invidioustv.session") {
        self.service = service
    }

    public func sid(for profileID: UUID) throws -> String? {
        var query = baseQuery(profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw SessionStoreError.keychain(status)
        }
    }

    public func setSID(_ sid: String, for profileID: UUID) throws {
        let data = Data(sid.utf8)
        var query = baseQuery(profileID)
        let update: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw SessionStoreError.keychain(status) }
    }

    public func removeSID(for profileID: UUID) throws {
        let status = SecItemDelete(baseQuery(profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SessionStoreError.keychain(status)
        }
    }

    private func baseQuery(_ profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
    }
}

/// In-memory session storage for tests and previews.
public final class InMemorySessionStore: SessionStore, @unchecked Sendable {
    private var storage: [UUID: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func sid(for profileID: UUID) throws -> String? {
        lock.withLock { storage[profileID] }
    }

    public func setSID(_ sid: String, for profileID: UUID) throws {
        lock.withLock { storage[profileID] = sid }
    }

    public func removeSID(for profileID: UUID) throws {
        _ = lock.withLock { storage.removeValue(forKey: profileID) }
    }
}
