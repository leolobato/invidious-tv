import Foundation

/// A playlist from `/api/v1/auth/playlists` or `/api/v1/auth/playlists/:plid`.
public struct Playlist: Codable, Hashable, Identifiable, Sendable {
    public var playlistId: String
    public var title: String
    public var author: String
    public var description: String
    public var videoCount: Int
    public var updated: Int?
    public var isListed: Bool
    public var videos: [PlaylistVideo]

    public var id: String { playlistId }

    public var updatedDate: Date? {
        updated.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    /// Thumbnail of the first video, for the library card.
    public var coverThumbnails: [Thumbnail] {
        videos.first?.video.videoThumbnails ?? []
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playlistId = try c.decode(String.self, forKey: .playlistId)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        videoCount = try c.decodeIfPresent(Int.self, forKey: .videoCount) ?? 0
        updated = try c.decodeIfPresent(Int.self, forKey: .updated)
        isListed = try c.decodeIfPresent(Bool.self, forKey: .isListed) ?? false
        videos = try c.decodeIfPresent([PlaylistVideo].self, forKey: .videos) ?? []
    }
}

/// A playlist entry: the video plus the entry's own identifier used for removal.
public struct PlaylistVideo: Codable, Hashable, Identifiable, Sendable {
    public var video: VideoSummary
    public var index: Int
    /// Hexadecimal entry ID, passed back to `DELETE .../videos/:index`.
    public var indexId: String

    public var id: String { indexId.isEmpty ? video.videoId : indexId }

    private enum CodingKeys: String, CodingKey { case index, indexId }

    public init(from decoder: Decoder) throws {
        video = try VideoSummary(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        indexId = try c.decodeIfPresent(String.self, forKey: .indexId) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        try video.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(index, forKey: .index)
        try c.encode(indexId, forKey: .indexId)
    }
}

public enum PlaylistPrivacy: String, Sendable, CaseIterable {
    case `private`, unlisted, `public`
}
