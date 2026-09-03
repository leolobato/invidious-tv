import Foundation

/// Builds a YouTube-like home feed from Invidious's per-video recommendations.
///
/// Invidious has no personalized feed. This takes the recommended videos of each recently
/// watched "seed" video, removes duplicates and already-watched items, and interleaves the
/// lists so no single seed dominates the top of the page.
public enum HomeFeedBuilder {
    /// - Parameters:
    ///   - seeds: recommendation lists, one per seed video, most recent seed first.
    ///   - watched: video IDs to exclude (account history).
    ///   - fallback: videos used to pad the result (trending).
    ///   - minimum: pad with fallback until at least this many items.
    ///   - limit: maximum items returned.
    public static func build(
        seeds: [[VideoSummary]],
        watched: Set<String>,
        fallback: [VideoSummary],
        minimum: Int = 24,
        limit: Int = 60
    ) -> [VideoSummary] {
        var seen = watched
        var result: [VideoSummary] = []

        // Round-robin across seed lists.
        var indices = Array(repeating: 0, count: seeds.count)
        var progressed = true
        while progressed && result.count < limit {
            progressed = false
            for seedIndex in seeds.indices {
                let list = seeds[seedIndex]
                while indices[seedIndex] < list.count {
                    let candidate = list[indices[seedIndex]]
                    indices[seedIndex] += 1
                    if candidate.isUpcoming { continue }
                    if seen.insert(candidate.videoId).inserted {
                        result.append(candidate)
                        progressed = true
                        break
                    }
                }
                if result.count >= limit { break }
            }
        }

        if result.count < minimum {
            for candidate in fallback where result.count < minimum {
                if candidate.isUpcoming { continue }
                if seen.insert(candidate.videoId).inserted {
                    result.append(candidate)
                }
            }
        }

        return Array(result.prefix(limit))
    }
}
