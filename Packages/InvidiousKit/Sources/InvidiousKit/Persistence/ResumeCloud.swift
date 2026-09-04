import Foundation
import CryptoKit

/// Key-value backend that syncs resume buckets between devices.
@MainActor
public protocol ResumeCloud: AnyObject {
    func data(forKey key: String) -> Data?
    func set(_ data: Data?, forKey key: String)
    /// Called with the keys another device changed.
    var onExternalChange: (([String]) -> Void)? { get set }
}

/// iCloud key-value store backend. Without an iCloud account it behaves like a local store.
@MainActor
public final class UbiquitousResumeCloud: ResumeCloud {
    private let store: NSUbiquitousKeyValueStore
    private var observation: Task<Void, Never>?
    public var onExternalChange: (([String]) -> Void)?

    public init(store: NSUbiquitousKeyValueStore = .default) {
        self.store = store
        let notifications = NotificationCenter.default.notifications(
            named: NSUbiquitousKeyValueStore.didChangeExternallyNotification
        )
        observation = Task { [weak self] in
            for await notification in notifications.map({ $0.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? [] }) {
                guard let self else { return }
                self.onExternalChange?(notification)
            }
        }
        store.synchronize()
    }

    deinit {
        observation?.cancel()
    }

    public func data(forKey key: String) -> Data? {
        store.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            store.set(data, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
        store.synchronize()
    }
}

/// In-memory backend for tests. Several stores sharing one `Hub` behave like devices on one account.
@MainActor
public final class InMemoryResumeCloud: ResumeCloud {
    public final class Hub {
        var values: [String: Data] = [:]
        var members: [InMemoryResumeCloud] = []
        public init() {}
    }

    private let hub: Hub
    public var onExternalChange: (([String]) -> Void)?

    public init(hub: Hub = Hub()) {
        self.hub = hub
        hub.members.append(self)
    }

    public func data(forKey key: String) -> Data? {
        hub.values[key]
    }

    public func set(_ data: Data?, forKey key: String) {
        guard hub.values[key] != data else { return }
        hub.values[key] = data
        for member in hub.members where member !== self {
            member.onExternalChange?([key])
        }
    }
}

extension ResumeStore {
    /// Stable key for one Invidious account, shared by every device that signs in to it.
    /// Hashed so it fits the 64-byte key limit of the iCloud key-value store.
    public static func accountKey(instanceURL: URL, username: String) -> String {
        let host = (instanceURL.host ?? "").lowercased()
        let port = instanceURL.port.map { ":\($0)" } ?? ""
        let material = "\(host)\(port)|\(username.lowercased())"
        let digest = SHA256.hash(data: Data(material.utf8))
        let hex = digest.prefix(16).map { String(format: "%02x", $0) }.joined()
        return "resume." + hex
    }
}
