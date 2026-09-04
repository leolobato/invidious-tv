import Foundation

/// Picks the video and audio streams to hand to the player.
public struct StreamSelection: Hashable, Sendable {
    public var video: AdaptiveFormat
    public var audio: AdaptiveFormat?

    public var label: String {
        video.qualityLabel ?? video.resolution ?? "\(video.height ?? 0)p"
    }
}

/// Quality preferences for stream selection.
public struct StreamPreferences: Hashable, Sendable {
    /// Maximum vertical resolution, nil for unlimited.
    public var maxHeight: Int?
    /// Codecs the device can decode, in order of preference.
    public var codecPreference: [VideoCodec]
    /// Prefer higher frame rate over codec preference at the same resolution.
    public var preferHighFrameRate: Bool

    public init(maxHeight: Int? = nil, codecPreference: [VideoCodec] = [.avc1, .hevc, .vp9, .av01], preferHighFrameRate: Bool = true) {
        self.maxHeight = maxHeight
        self.codecPreference = codecPreference
        self.preferHighFrameRate = preferHighFrameRate
    }
}

public enum StreamSelector {
    /// Distinct heights offered by a video, highest first. Used for the quality menu.
    public static func availableHeights(_ details: VideoDetails, preferences: StreamPreferences) -> [Int] {
        let heights = details.adaptiveFormats
            .filter { $0.isVideo && preferences.codecPreference.contains($0.codec) }
            .compactMap(\.height)
        return Array(Set(heights)).sorted(by: >)
    }

    /// Distinct audio languages offered by a video, original first. Empty when nothing is labeled.
    public static func audioTracks(_ formats: [AdaptiveFormat]) -> [AudioTrack] {
        var seen: Set<AudioTrack> = []
        var tracks: [AudioTrack] = []
        for format in formats where format.isAudio {
            guard let track = format.audioTrack, !seen.contains(track) else { continue }
            seen.insert(track)
            tracks.append(track)
        }
        return tracks.sorted { lhs, rhs in
            if lhs.isOriginal != rhs.isOriginal { return lhs.isOriginal }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    /// Best video + audio pair under the given preferences, or nil when no playable video exists.
    /// - Parameter audioTrack: language to play; nil means the original track.
    public static func select(_ details: VideoDetails, preferences: StreamPreferences, audioTrack: AudioTrack? = nil) -> StreamSelection? {
        let videos = details.adaptiveFormats.filter { format in
            guard format.isVideo, let height = format.height else { return false }
            guard preferences.codecPreference.contains(format.codec) else { return false }
            if let maxHeight = preferences.maxHeight, height > maxHeight { return false }
            return true
        }
        guard let video = videos.max(by: { lhs, rhs in rank(lhs, preferences) < rank(rhs, preferences) }) else {
            return nil
        }
        return StreamSelection(video: video, audio: bestAudio(details.adaptiveFormats, track: audioTrack))
    }

    /// Highest-bitrate audio stream for a language, preferring AAC in MP4 for hardware compatibility
    /// and plain over loudness-normalized (DRC) variants.
    ///
    /// With `track` nil the original language wins; auto-dubbed tracks are only used when nothing
    /// else exists. Unlabeled streams (older Invidious responses) are treated as the original.
    public static func bestAudio(_ formats: [AdaptiveFormat], track: AudioTrack? = nil) -> AdaptiveFormat? {
        let audios = formats.filter(\.isAudio)
        guard !audios.isEmpty else { return nil }

        let pool: [AdaptiveFormat]
        if let track {
            let matching = audios.filter { $0.audioTrack == track }
            pool = matching.isEmpty ? audios : matching
        } else {
            let original = audios.filter { $0.audioTrack?.isOriginal ?? false }
            let unlabeled = audios.filter { $0.audioTrack == nil }
            let notDubbed = audios.filter { $0.audioTrack.map { $0.kind != .autoDubbed && $0.kind != .dubbed } ?? true }
            pool = !original.isEmpty ? original : (!unlabeled.isEmpty ? unlabeled : (!notDubbed.isEmpty ? notDubbed : audios))
        }

        let plain = pool.filter { !$0.hasDRC }
        let candidates = plain.isEmpty ? pool : plain
        let aac = candidates.filter { $0.type.lowercased().contains("mp4a") }
        return (aac.isEmpty ? candidates : aac).max { $0.bitrate < $1.bitrate }
    }

    /// Sort key: height, then frame rate or codec preference, then bitrate.
    private static func rank(_ format: AdaptiveFormat, _ preferences: StreamPreferences) -> (Int, Int, Int, Int) {
        let height = format.height ?? 0
        let codecRank = preferences.codecPreference.count - (preferences.codecPreference.firstIndex(of: format.codec) ?? preferences.codecPreference.count)
        let fps = format.fps ?? 30
        if preferences.preferHighFrameRate {
            return (height, fps, codecRank, format.bitrate)
        }
        return (height, codecRank, fps, format.bitrate)
    }
}
