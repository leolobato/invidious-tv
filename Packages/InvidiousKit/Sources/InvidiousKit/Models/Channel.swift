import Foundation

/// Channel response from `/api/v1/channels/:ucid`.
public struct Channel: Codable, Hashable, Identifiable, Sendable {
    public var author: String
    public var authorId: String
    public var authorThumbnails: [AuthorImage]
    public var authorBanners: [AuthorImage]
    public var subCount: Int?
    public var description: String
    public var latestVideos: [VideoSummary]

    public var id: String { authorId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        authorId = try c.decode(String.self, forKey: .authorId)
        authorThumbnails = try c.decodeIfPresent([AuthorImage].self, forKey: .authorThumbnails) ?? []
        authorBanners = try c.decodeIfPresent([AuthorImage].self, forKey: .authorBanners) ?? []
        subCount = try c.decodeIfPresent(Int.self, forKey: .subCount)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        latestVideos = try c.decodeIfPresent([VideoSummary].self, forKey: .latestVideos) ?? []
    }
}

/// One page of a channel's videos, with a continuation token for the next page.
public struct ChannelVideosPage: Codable, Hashable, Sendable {
    public var videos: [VideoSummary]
    public var continuation: String?

    public init(videos: [VideoSummary], continuation: String? = nil) {
        self.videos = videos
        self.continuation = continuation
    }
}

/// A channel entry from `/api/v1/auth/subscriptions`.
public struct SubscribedChannel: Codable, Hashable, Identifiable, Sendable {
    public var author: String
    public var authorId: String

    public var id: String { authorId }

    public init(author: String, authorId: String) {
        self.author = author
        self.authorId = authorId
    }
}
