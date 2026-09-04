import Foundation
import Observation

/// Persists the list of profiles and remembers the last used one.
@MainActor
@Observable
public final class ProfileStore {
    public private(set) var profiles: [Profile] = []
    public private(set) var lastUsedProfileID: UUID?

    private let fileStore: JSONFileStore<Snapshot>

    private struct Snapshot: Codable {
        var profiles: [Profile]
        var lastUsedProfileID: UUID?
    }

    /// - Parameter directory: where `profiles.json` lives. Defaults to Application Support.
    public init(directory: URL? = nil) {
        let dir = directory ?? AppDirectories.applicationSupport()
        fileStore = JSONFileStore(url: dir.appendingPathComponent("profiles.json"))
        if let snapshot = try? fileStore.load() {
            profiles = snapshot.profiles
            lastUsedProfileID = snapshot.lastUsedProfileID
        }
    }

    public var lastUsedProfile: Profile? {
        guard let lastUsedProfileID else { return nil }
        return profiles.first { $0.id == lastUsedProfileID }
    }

    public func profile(id: UUID) -> Profile? {
        profiles.first { $0.id == id }
    }

    public func add(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        persist()
    }

    public func update(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        persist()
    }

    public func remove(id: UUID) {
        profiles.removeAll { $0.id == id }
        if lastUsedProfileID == id {
            lastUsedProfileID = nil
        }
        persist()
    }

    public func markUsed(id: UUID) {
        lastUsedProfileID = id
        persist()
    }

    /// Next avatar color that is not already in use, cycling when all are taken.
    public func nextColorIndex(paletteSize: Int) -> Int {
        let used = Set(profiles.map(\.colorIndex))
        return (0..<paletteSize).first { !used.contains($0) } ?? (profiles.count % max(paletteSize, 1))
    }

    private func persist() {
        try? fileStore.save(Snapshot(profiles: profiles, lastUsedProfileID: lastUsedProfileID))
    }
}
