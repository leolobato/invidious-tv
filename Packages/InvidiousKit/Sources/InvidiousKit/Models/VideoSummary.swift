import Foundation

/// A video as it appears in lists: feed, trending, channel videos, recommendations.
public struct VideoSummary: Codable, Hashable, Identifiable, Sendable {
    public var videoId: String
    public var title: String
    public var author: String
    public var authorId: String
    public var lengthSeconds: Int
    public var published: Int?
    public var publishedText: String?
    public var viewCount: Int?
    public var viewCountText: String?
    public var videoThumbnails: [Thumbnail]
    public var liveNow: Bool
    public var isUpcoming: Bool
    public var premiereTimestamp: Int?

    public var id: String { videoId }

    public var publishedDate: Date? {
        published.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public init(
        videoId: String,
        title: String,
        author: String,
        authorId: String,
        lengthSeconds: Int,
        published: Int? = nil,
        publishedText: String? = nil,
        viewCount: Int? = nil,
        viewCountText: String? = nil,
        videoThumbnails: [Thumbnail] = [],
        liveNow: Bool = false,
        isUpcoming: Bool = false,
        premiereTimestamp: Int? = nil
    ) {
        self.videoId = videoId
        self.title = title
        self.author = author
        self.authorId = authorId
        self.lengthSeconds = lengthSeconds
        self.published = published
        self.publishedText = publishedText
        self.viewCount = viewCount
        self.viewCountText = viewCountText
        self.videoThumbnails = videoThumbnails
        self.liveNow = liveNow
        self.isUpcoming = isUpcoming
        self.premiereTimestamp = premiereTimestamp
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try c.decode(String.self, forKey: .videoId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        authorId = try c.decodeIfPresent(String.self, forKey: .authorId) ?? ""
        lengthSeconds = try c.decodeIfPresent(Int.self, forKey: .lengthSeconds) ?? 0
        published = try c.decodeFlexibleTimestamp(forKey: .published)
        publishedText = try c.decodeIfPresent(String.self, forKey: .publishedText)
        viewCount = try c.decodeIfPresent(Int.self, forKey: .viewCount)
        viewCountText = try c.decodeIfPresent(String.self, forKey: .viewCountText)
        videoThumbnails = try c.decodeIfPresent([Thumbnail].self, forKey: .videoThumbnails) ?? []
        liveNow = try c.decodeIfPresent(Bool.self, forKey: .liveNow) ?? false
        isUpcoming = try c.decodeIfPresent(Bool.self, forKey: .isUpcoming) ?? false
        premiereTimestamp = try c.decodeIfPresent(Int.self, forKey: .premiereTimestamp)
    }
}
