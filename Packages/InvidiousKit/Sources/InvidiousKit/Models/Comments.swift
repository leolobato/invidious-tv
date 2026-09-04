import Foundation

/// Response from `/api/v1/comments/:id`.
public struct CommentsPage: Codable, Hashable, Sendable {
    public var videoId: String
    public var commentCount: Int?
    public var comments: [Comment]
    public var continuation: String?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoId = try c.decodeIfPresent(String.self, forKey: .videoId) ?? ""
        commentCount = try c.decodeIfPresent(Int.self, forKey: .commentCount)
        comments = try c.decodeIfPresent([Comment].self, forKey: .comments) ?? []
        continuation = try c.decodeIfPresent(String.self, forKey: .continuation)
    }
}

public struct Comment: Codable, Hashable, Identifiable, Sendable {
    public struct Replies: Codable, Hashable, Sendable {
        public var replyCount: Int
        public var continuation: String?
    }

    public var commentId: String
    public var author: String
    public var authorId: String
    public var authorThumbnails: [AuthorImage]
    public var content: String
    public var likeCount: Int
    public var published: Int?
    public var publishedText: String?
    public var isPinned: Bool
    public var isEdited: Bool
    public var authorIsChannelOwner: Bool
    public var creatorHeart: Bool
    public var replies: Replies?

    public var id: String { commentId }

    enum CodingKeys: String, CodingKey {
        case commentId, author, authorId, authorThumbnails, content, likeCount, published, publishedText
        case isPinned, isEdited, authorIsChannelOwner, creatorHeart, replies
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        commentId = try c.decodeIfPresent(String.self, forKey: .commentId) ?? UUID().uuidString
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        authorId = try c.decodeIfPresent(String.self, forKey: .authorId) ?? ""
        authorThumbnails = try c.decodeIfPresent([AuthorImage].self, forKey: .authorThumbnails) ?? []
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        published = try c.decodeFlexibleTimestamp(forKey: .published)
        publishedText = try c.decodeIfPresent(String.self, forKey: .publishedText)
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isEdited = try c.decodeIfPresent(Bool.self, forKey: .isEdited) ?? false
        authorIsChannelOwner = try c.decodeIfPresent(Bool.self, forKey: .authorIsChannelOwner) ?? false
        // `creatorHeart` is an object when present.
        creatorHeart = c.contains(.creatorHeart) && !((try? c.decodeNil(forKey: .creatorHeart)) ?? true)
        replies = try c.decodeIfPresent(Replies.self, forKey: .replies)
    }
}
