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
///
/// With an `accessGroup` the items are shared with app extensions (the Top Shelf extension fetches
/// the feed itself). Items saved by earlier versions without a group are migrated on first read.
public struct KeychainSessionStore: SessionStore {
    public let service: String
    public let accessGroup: String?

    public init(service: String = "org.lobato.invidioustv.session", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func sid(for profileID: UUID) throws -> String? {
        if let value = try read(baseQuery(profileID)) {
            return value
        }
        guard accessGroup != nil, let legacy = try read(baseQuery(profileID, includeGroup: false)) else {
            return nil
        }
        // Move the item into the shared group so extensions can see it.
        try? setSID(legacy, for: profileID)
        SecItemDelete(baseQuery(profileID, includeGroup: false) as CFDictionary)
        return legacy
    }

    private func read(_ base: [String: Any]) throws -> String? {
        var query = base
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

    private func baseQuery(_ profileID: UUID, includeGroup: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
        ]
        if includeGroup, let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
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
