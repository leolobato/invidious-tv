import Foundation
import Observation
import InvidiousKit

/// Lengths and live state for videos whose list entry does not say.
///
/// The subscriptions feed comes from the instance's database, which records a stream the moment it
/// is found: length 0 and no live flag, even long after it ended. Cards ask here so a finished stream
/// shows its duration and a running one shows LIVE. Lengths are kept on disk; live and upcoming
/// state changes, so it only lasts the session.
@MainActor
@Observable
final class VideoMetadataCache {
    struct Entry: Hashable {
        var lengthSeconds: Int
        var liveNow: Bool
        var isUpcoming: Bool
    }

    private(set) var entries: [String: Entry] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private let file: URL

    init(directory: URL = AppDirectories.applicationSupport()) {
        file = directory.appendingPathComponent("video-lengths.json")
        if let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode([String: Int].self, from: data) {
            entries = stored.mapValues { Entry(lengthSeconds: $0, liveNow: false, isUpcoming: false) }
        }
    }

    /// True when a list entry lacks what a card needs to label it.
    static func needsLookup(_ video: VideoSummary) -> Bool {
        video.lengthSeconds == 0 && !video.liveNow && !video.isUpcoming
    }

    /// The summary with the cached length and live state filled in.
    func resolved(_ video: VideoSummary) -> VideoSummary {
        guard Self.needsLookup(video), let entry = entries[video.videoId] else { return video }
        var copy = video
        copy.lengthSeconds = entry.lengthSeconds
        copy.liveNow = entry.liveNow
        copy.isUpcoming = entry.isUpcoming
        return copy
    }

    /// Records what a video page reported, so lists opened later need no lookup.
    func remember(_ details: VideoDetails) {
        let entry = Entry(lengthSeconds: details.lengthSeconds, liveNow: details.liveNow, isUpcoming: details.isUpcoming)
        guard entries[details.videoId] != entry else { return }
        entries[details.videoId] = entry
        if entry.lengthSeconds > 0, !entry.liveNow {
            persist()
        }
    }

    /// Fetches the video page for a list entry unless it is known, loading, or failed before.
    func load(videoID: String, using client: InvidiousClient) async {
        guard entries[videoID] == nil, !inFlight.contains(videoID), !failed.contains(videoID) else { return }
        inFlight.insert(videoID)
        defer { inFlight.remove(videoID) }
        guard let details = try? await client.video(id: videoID) else {
            failed.insert(videoID)
            return
        }
        remember(details)
    }

    private func persist() {
        let lengths = entries.compactMapValues { $0.lengthSeconds > 0 && !$0.liveNow ? $0.lengthSeconds : nil }
        guard let data = try? JSONEncoder().encode(lengths) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
