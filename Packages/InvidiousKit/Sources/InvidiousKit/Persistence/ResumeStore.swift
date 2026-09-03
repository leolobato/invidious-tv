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

    public init(videoID: String, position: TimeInterval, duration: TimeInterval, updatedAt: Date = Date(), video: VideoSummary? = nil) {
        self.videoID = videoID
        self.position = position
        self.duration = duration
        self.updatedAt = updatedAt
        self.video = video
    }
}

/// Local resume positions, namespaced per profile.
@MainActor
@Observable
public final class ResumeStore {
    /// A video is finished once this fraction has been watched.
    public static let finishedThreshold = 0.95
    /// Videos below this fraction are not offered for resume.
    public static let minimumResumeFraction = 0.05
    /// Nothing shorter than this is worth resuming.
    public static let minimumResumeSeconds: TimeInterval = 10

    public private(set) var positions: [UUID: [String: ResumePosition]] = [:]

    private let fileStore: JSONFileStore<[UUID: [String: ResumePosition]]>

    public init(directory: URL? = nil) {
        let dir = directory ?? AppDirectories.applicationSupport()
        fileStore = JSONFileStore(url: dir.appendingPathComponent("resume.json"))
        positions = (try? fileStore.load()) ?? [:]
    }

    public func position(for videoID: String, profile: UUID) -> ResumePosition? {
        positions[profile]?[videoID]
    }

    /// Position to offer as "Resume", or nil when the video should start from the beginning.
    public func resumePoint(for videoID: String, profile: UUID) -> TimeInterval? {
        guard let entry = position(for: videoID, profile: profile) else { return nil }
        guard entry.position >= Self.minimumResumeSeconds else { return nil }
        guard entry.progress >= Self.minimumResumeFraction, entry.progress < Self.finishedThreshold else { return nil }
        return entry.position
    }

    /// Records progress. Finished videos are removed so they leave Continue Watching.
    public func save(videoID: String, position: TimeInterval, duration: TimeInterval, video: VideoSummary?, profile: UUID, now: Date = Date()) {
        guard duration > 0 else { return }
        var bucket = positions[profile] ?? [:]
        if position / duration >= Self.finishedThreshold {
            bucket.removeValue(forKey: videoID)
        } else {
            bucket[videoID] = ResumePosition(videoID: videoID, position: position, duration: duration, updatedAt: now, video: video)
        }
        positions[profile] = bucket
        persist()
    }

    public func remove(videoID: String, profile: UUID) {
        positions[profile]?.removeValue(forKey: videoID)
        persist()
    }

    public func removeAll(profile: UUID) {
        positions.removeValue(forKey: profile)
        persist()
    }

    /// Unfinished videos, most recently watched first.
    public func continueWatching(profile: UUID, limit: Int = 20) -> [ResumePosition] {
        (positions[profile] ?? [:]).values
            .filter { $0.progress >= Self.minimumResumeFraction && $0.progress < Self.finishedThreshold && $0.position >= Self.minimumResumeSeconds }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }

    private func persist() {
        try? fileStore.save(positions)
    }
}
