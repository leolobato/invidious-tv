import Foundation

/// One entry from `/api/v1/search`, distinguished by its `type` field.
public enum SearchItem: Hashable, Identifiable, Sendable, Decodable {
    case video(VideoSummary)
    case channel(SearchChannel)
    case playlist(SearchPlaylist)
    /// Types this app does not render (hashtags, categories, ...).
    case unsupported(String)

    public var id: String {
        switch self {
        case .video(let video): return "video:\(video.videoId)"
        case .channel(let channel): return "channel:\(channel.authorId)"
        case .playlist(let playlist): return "playlist:\(playlist.playlistId)"
        case .unsupported(let type): return "unsupported:\(type):\(UUID().uuidString)"
        }
    }

    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "video":
            self = .video(try VideoSummary(from: decoder))
        case "channel":
            self = .channel(try SearchChannel(from: decoder))
        case "playlist":
            self = .playlist(try SearchPlaylist(from: decoder))
        default:
            self = .unsupported(type)
        }
    }

    public var video: VideoSummary? {
        if case .video(let video) = self { return video }
        return nil
    }

    public var channel: SearchChannel? {
        if case .channel(let channel) = self { return channel }
        return nil
    }
}

public struct SearchChannel: Codable, Hashable, Identifiable, Sendable {
    public var author: String
    public var authorId: String
    public var authorThumbnails: [AuthorImage]
    public var subCount: Int?
    public var videoCount: Int?
    public var description: String
    public var channelHandle: String?

    public var id: String { authorId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        authorId = try c.decode(String.self, forKey: .authorId)
        authorThumbnails = try c.decodeIfPresent([AuthorImage].self, forKey: .authorThumbnails) ?? []
        subCount = try c.decodeIfPresent(Int.self, forKey: .subCount)
        videoCount = try c.decodeIfPresent(Int.self, forKey: .videoCount)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        channelHandle = try c.decodeIfPresent(String.self, forKey: .channelHandle)
    }

    /// The subscriptions-list shape of this channel.
    public var subscribed: SubscribedChannel {
        SubscribedChannel(author: author, authorId: authorId)
    }
}

public struct SearchPlaylist: Codable, Hashable, Identifiable, Sendable {
    public var title: String
    public var playlistId: String
    public var author: String
    public var authorId: String
    public var videoCount: Int?
    public var playlistThumbnail: String?

    public var id: String { playlistId }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        playlistId = try c.decode(String.self, forKey: .playlistId)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        authorId = try c.decodeIfPresent(String.self, forKey: .authorId) ?? ""
        videoCount = try c.decodeIfPresent(Int.self, forKey: .videoCount)
        playlistThumbnail = try c.decodeIfPresent(String.self, forKey: .playlistThumbnail)
    }
}

/// Response from `/api/v1/search/suggestions`.
public struct SearchSuggestions: Codable, Hashable, Sendable {
    public var query: String
    public var suggestions: [String]
}

public enum SearchType: String, Sendable, CaseIterable {
    case all, video, channel, playlist
}
