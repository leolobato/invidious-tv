import Foundation

/// Heuristic detection of YouTube Shorts. The API does not flag them outside a channel's Shorts tab.
public enum ShortsFilter {
    /// Anything at or under this length is treated as a Short.
    public static let maxShortSeconds = 60

    public static func isLikelyShort(_ video: VideoSummary) -> Bool {
        if video.liveNow || video.isUpcoming { return false }
        if video.lengthSeconds > 0 && video.lengthSeconds <= maxShortSeconds { return true }
        let title = video.title.lowercased()
        return title.contains("#shorts") || title.contains("#short ") || title.hasSuffix("#short")
    }

    public static func removingShorts(_ videos: [VideoSummary]) -> [VideoSummary] {
        videos.filter { !isLikelyShort($0) }
    }
}
