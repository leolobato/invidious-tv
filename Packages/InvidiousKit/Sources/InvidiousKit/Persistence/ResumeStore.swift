import Foundation
import Observation

/// Where a viewer stopped in a video.
public struct ResumePosition: Codable, Hashable, Sendable {
    public var videoID: String
    public var position: TimeInterval
    public var duration: TimeInterval
    public var updatedAt: Date
    /// Snapshot of the video so Continue Watching can render without a network call.
    public var video: VideoSummary?

    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// Finished entries stay stored as tombstones so a finish on one device wins over an older
    /// position synced from another.
    public var isFinished: Bool {
        progress >= ResumeStore.finishedThreshold
    }

    public init(videoID: String, position: TimeInterval, duration: TimeInterval, updatedAt: Date = Date(), video: VideoSummary? = nil) {
        self.videoID = videoID
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.video = video
    }
}

/// Resume positions, namespaced per profile, persisted locally and optionally synced through iCloud.
///
/// Sync is keyed by Invidious account (``accountKey(instanceURL:username:)``) rather than by the
/// local profile ID, so the same account on another device shares one bucket. Per video, the newest
/// `updatedAt` wins.
@MainActor
@Observable
public final class ResumeStore {
    /// A video is finished once this fraction has been watched.
    nonisolated public static let finishedThreshold = 0.95
    /// Videos below this fraction are not offered for resume.
    nonisolated public static let minimumResumeFraction = 0.05
    /// Nothing shorter than this is worth resuming.
    nonisolated public static let minimumResumeSeconds: TimeInterval = 10
    /// Cap per account so a bucket stays well under the key-value store's size limits.
    nonisolated public static let maxEntriesPerAccount = 60
    /// Thumbnails kept in the synced snapshot (the widest ones).
    nonisolated static let maxSyncedThumbnails = 4

    /// Includes finished tombstones; use ``position(for:profile:)`` for what the UI should show.
    public private(set) var positions: [UUID: [String: ResumePosition]] = [:]

    private let fileStore: JSONFileStore<[UUID: [String: ResumePosition]]>
    private var accountKeys: [UUID: String] = [:]

    /// Sync backend. Setting it pulls every registered account and pushes local changes.
    public var cloud: (any ResumeCloud)? {
        didSet {
            oldValue?.onExternalChange = nil
            cloud?.onExternalChange = { [weak self] keys in
                self?.mergeFromCloud(keys: keys)
            }
            for (profile, key) in accountKeys {
                syncAccount(key: key, profile: profile)
            }
        }
    }

    public init(directory: URL? = nil, cloud: (any ResumeCloud)? = nil) {
        let dir = directory ?? AppDirectories.applicationSupport()
        fileStore = JSONFileStore(url: dir.appendingPathComponent("resume.json"))
        positions = (try? fileStore.load()) ?? [:]
        self.cloud = cloud
        cloud?.onExternalChange = { [weak self] keys in
            self?.mergeFromCloud(keys: keys)
        }
    }

    // MARK: - Accounts

    /// Ties a profile to its account bucket in the cloud (pass nil to stop syncing it).
    public func setAccountKey(_ key: String?, for profile: UUID) {
        if let key {
            accountKeys[profile] = key
            syncAccount(key: key, profile: profile)
        } else {
            accountKeys.removeValue(forKey: profile)
        }
    }

    // MARK: - Reading

    /// The unfinished position for a video, or nil.
    public func position(for videoID: String, profile: UUID) -> ResumePosition? {
        guard let entry = positions[profile]?[videoID], !entry.isFinished else { return nil }
        return entry
    }

    /// Position to offer as "Resume", or nil when the video should start from the beginning.
    public func resumePoint(for videoID: String, profile: UUID) -> TimeInterval? {
        guard let entry = position(for: videoID, profile: profile) else { return nil }
        guard entry.position >= Self.minimumResumeSeconds else { return nil }
        guard entry.progress >= Self.minimumResumeFraction else { return nil }
        return entry.position
    }

    /// Unfinished videos, most recently watched first.
    public func continueWatching(profile: UUID, limit: Int = 20) -> [ResumePosition] {
        (positions[profile] ?? [:]).values
            .filter { !$0.isFinished && $0.progress >= Self.minimumResumeFraction && $0.position >= Self.minimumResumeSeconds }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Writing

    /// Records progress. Finished videos leave Continue Watching and are kept as tombstones.
    public func save(videoID: String, position: TimeInterval, duration: TimeInterval, video: VideoSummary?, profile: UUID, now: Date = Date()) {
        guard duration > 0 else { return }
        var bucket = positions[profile] ?? [:]
        let finished = position / duration >= Self.finishedThreshold
        bucket[videoID] = ResumePosition(
            videoID: videoID,
            position: finished ? duration : position,
            duration: duration,
            // Whole seconds: the synced copy is ISO 8601 without fractions and must compare equal.
            updatedAt: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)),
            video: finished ? nil : video
        )
        positions[profile] = Self.pruned(bucket)
        persist()
        pushToCloud(profile: profile)
    }

    /// Drops a video from Continue Watching everywhere by marking it finished.
    public func remove(videoID: String, profile: UUID, now: Date = Date()) {
        guard let entry = positions[profile]?[videoID] else { return }
        save(videoID: videoID, position: entry.duration, duration: entry.duration, video: nil, profile: profile, now: now)
    }

    /// Forgets a profile's positions on this device only; the account bucket in the cloud is untouched.
    public func removeAll(profile: UUID) {
        positions.removeValue(forKey: profile)
        accountKeys.removeValue(forKey: profile)
        persist()
    }

    // MARK: - Sync

    private func syncAccount(key: String, profile: UUID) {
        guard let cloud else { return }
        let remoteData = cloud.data(forKey: key)
        let remote = Self.decodeBucket(remoteData)
        let local = positions[profile] ?? [:]
        let merged = Self.pruned(Self.merge(local, remote))
        if merged != local {
            positions[profile] = merged
            persist()
        }
        let encoded = Self.encodeBucket(merged)
        if encoded != remoteData {
            cloud.set(encoded, forKey: key)
        }
    }

    private func pushToCloud(profile: UUID) {
        guard let cloud, let key = accountKeys[profile] else { return }
        // Other local profiles on the same account see the change too.
        for (otherProfile, otherKey) in accountKeys where otherKey == key && otherProfile != profile {
            positions[otherProfile] = positions[profile]
        }
        cloud.set(Self.encodeBucket(positions[profile] ?? [:]), forKey: key)
    }

    private func mergeFromCloud(keys: [String]) {
        let changed = Set(keys)
        for (profile, key) in accountKeys where changed.contains(key) {
            syncAccount(key: key, profile: profile)
        }
    }

    /// Per video, the entry updated most recently wins.
    static func merge(_ a: [String: ResumePosition], _ b: [String: ResumePosition]) -> [String: ResumePosition] {
        var result = a
        for (id, entry) in b {
            if let existing = result[id], existing.updatedAt >= entry.updatedAt { continue }
            result[id] = entry
        }
        return result
    }

    /// Keeps the most recent entries, unfinished ones first so tombstones are the first to go.
    static func pruned(_ bucket: [String: ResumePosition]) -> [String: ResumePosition] {
        guard bucket.count > maxEntriesPerAccount else { return bucket }
        let kept = bucket.values
            .sorted { lhs, rhs in
                if lhs.isFinished != rhs.isFinished { return !lhs.isFinished }
                return lhs.updatedAt > rhs.updatedAt
            }
            .prefix(maxEntriesPerAccount)
        return Dictionary(uniqueKeysWithValues: kept.map { ($0.videoID, $0) })
    }

    /// The bucket as it goes to the cloud: same entries, snapshots trimmed to a few thumbnails.
    static func forSync(_ bucket: [String: ResumePosition]) -> [String: ResumePosition] {
        bucket.mapValues { entry in
            var copy = entry
            if var video = copy.video, video.videoThumbnails.count > maxSyncedThumbnails {
                video.videoThumbnails = Array(video.videoThumbnails.sorted { $0.width > $1.width }.prefix(maxSyncedThumbnails))
                copy.video = video
            }
            return copy
        }
    }

    static func encodeBucket(_ bucket: [String: ResumePosition]) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(forSync(bucket))
    }

    static func decodeBucket(_ data: Data?) -> [String: ResumePosition] {
        guard let data else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: ResumePosition].self, from: data)) ?? [:]
    }

    private func persist() {
        try? fileStore.save(positions)
    }
}
