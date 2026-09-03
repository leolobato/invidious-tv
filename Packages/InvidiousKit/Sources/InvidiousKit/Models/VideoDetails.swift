import Foundation

/// Full video response from `/api/v1/videos/:id`.
public struct VideoDetails: Codable, Hashable, Identifiable, Sendable {
    public var videoId: String
    public var title: String
    public var author: String
    public var authorId: String
    public var authorThumbnails: [AuthorImage]
    public var description: String
    public var lengthSeconds: Int
    public var published: Int?
    public var publishedText: String?
    public var viewCount: Int?
    public var likeCount: Int?
    public var subCountText: String?
    public var genre: String?
    public var liveNow: Bool
    public var isUpcoming: Bool
    public var hlsUrl: String?
    public var dashUrl: String?
    public var adaptiveFormats: [AdaptiveFormat]
    public var formatStreams: [FormatStream]
    public var captions: [Caption]
    public var recommendedVideos: [VideoSummary]
    public var videoThumbnails: [Thumbnail]

    public var id: String { videoId }

    public var publishedDate: Date? {
        published.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// The list-style representation of this video.
    public var summary: VideoSummary {
        VideoSummary(
            videoId: videoId, title: title, author: author, authorId: authorId,
            lengthSeconds: lengthSeconds, published: published, publishedText: publishedText,
            viewCount: viewCount, videoThumbnails: videoThumbnails, liveNow: liveNow, isUpcoming: isUpcoming
        )
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try c.decode(String.self, forKey: .videoId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        authorId = try c.decodeIfPresent(String.self, forKey: .authorId) ?? ""
        authorThumbnails = try c.decodeIfPresent([AuthorImage].self, forKey: .authorThumbnails) ?? []
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        lengthSeconds = try c.decodeIfPresent(Int.self, forKey: .lengthSeconds) ?? 0
        published = try c.decodeFlexibleTimestamp(forKey: .published)
        publishedText = try c.decodeIfPresent(String.self, forKey: .publishedText)
        viewCount = try c.decodeIfPresent(Int.self, forKey: .viewCount)
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount)
        subCountText = try c.decodeIfPresent(String.self, forKey: .subCountText)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        liveNow = try c.decodeIfPresent(Bool.self, forKey: .liveNow) ?? false
        isUpcoming = try c.decodeIfPresent(Bool.self, forKey: .isUpcoming) ?? false
        hlsUrl = try c.decodeIfPresent(String.self, forKey: .hlsUrl)
        dashUrl = try c.decodeIfPresent(String.self, forKey: .dashUrl)
        adaptiveFormats = try c.decodeIfPresent([AdaptiveFormat].self, forKey: .adaptiveFormats) ?? []
        formatStreams = try c.decodeIfPresent([FormatStream].self, forKey: .formatStreams) ?? []
        captions = try c.decodeIfPresent([Caption].self, forKey: .captions) ?? []
        recommendedVideos = try c.decodeIfPresent([VideoSummary].self, forKey: .recommendedVideos) ?? []
        videoThumbnails = try c.decodeIfPresent([Thumbnail].self, forKey: .videoThumbnails) ?? []
    }
}

/// One DASH-style stream: video-only or audio-only.
public struct AdaptiveFormat: Codable, Hashable, Sendable {
    public var url: String
    public var itag: String
    public var type: String
    public var bitrate: Int
    public var container: String?
    public var qualityLabel: String?
    public var resolution: String?
    public var fps: Int?
    public var audioQuality: String?
    public var audioSampleRate: Int?
    public var audioChannels: Int?

    public var isVideo: Bool { type.hasPrefix("video/") }
    public var isAudio: Bool { type.hasPrefix("audio/") }

    /// Codec family parsed from the MIME type, e.g. `avc1`, `vp9`, `av01`, `mp4a`, `opus`.
    public var codec: VideoCodec {
        VideoCodec(mimeType: type)
    }

    /// Vertical resolution parsed from `resolution` or `qualityLabel` (e.g. "1080p60" -> 1080).
    public var height: Int? {
        let source = resolution ?? qualityLabel ?? ""
        let digits = source.prefix { $0.isNumber }
        return Int(digits)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        itag = try c.decodeFlexibleString(forKey: .itag) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        bitrate = try c.decodeFlexibleInt(forKey: .bitrate) ?? 0
        container = try c.decodeIfPresent(String.self, forKey: .container)
        qualityLabel = try c.decodeIfPresent(String.self, forKey: .qualityLabel)
        resolution = try c.decodeIfPresent(String.self, forKey: .resolution)
        fps = try c.decodeIfPresent(Int.self, forKey: .fps)
        audioQuality = try c.decodeIfPresent(String.self, forKey: .audioQuality)
        audioSampleRate = try c.decodeFlexibleInt(forKey: .audioSampleRate)
        audioChannels = try c.decodeIfPresent(Int.self, forKey: .audioChannels)
    }
}

/// A muxed (video + audio) progressive stream. Tops out at 720p.
public struct FormatStream: Codable, Hashable, Sendable {
    public var url: String
    public var itag: String
    public var type: String
    public var qualityLabel: String?
    public var container: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        itag = try c.decodeFlexibleString(forKey: .itag) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        qualityLabel = try c.decodeIfPresent(String.self, forKey: .qualityLabel)
        container = try c.decodeIfPresent(String.self, forKey: .container)
    }
}

public struct Caption: Codable, Hashable, Identifiable, Sendable {
    public var label: String
    public var languageCode: String
    public var url: String

    public var id: String { label + "|" + languageCode }

    enum CodingKeys: String, CodingKey {
        case label
        case languageCode = "language_code"
        case url
    }
}

public enum VideoCodec: String, Hashable, Sendable, CaseIterable {
    case avc1, hevc, vp9, av01, unknown

    init(mimeType: String) {
        let lower = mimeType.lowercased()
        if lower.contains("avc1") || lower.contains("h264") {
            self = .avc1
        } else if lower.contains("hev1") || lower.contains("hvc1") || lower.contains("hevc") {
            self = .hevc
        } else if lower.contains("vp9") || lower.contains("vp09") {
            self = .vp9
        } else if lower.contains("av01") || lower.contains("av1") {
            self = .av01
        } else {
            self = .unknown
        }
    }
}
