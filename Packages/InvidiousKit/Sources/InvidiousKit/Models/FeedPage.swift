import Foundation

/// One page of the subscriptions feed from `/api/v1/auth/feed`.
public struct FeedPage: Codable, Hashable, Sendable {
    public var notifications: [VideoSummary]
    public var videos: [VideoSummary]

    public init(notifications: [VideoSummary] = [], videos: [VideoSummary]) {
        self.notifications = notifications
        self.videos = videos
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        notifications = try c.decodeIfPresent([VideoSummary].self, forKey: .notifications) ?? []
        videos = try c.decodeIfPresent([VideoSummary].self, forKey: .videos) ?? []
    }
}

/// Response from `/api/v1/stats`.
public struct InstanceStats: Codable, Hashable, Sendable {
    public struct Software: Codable, Hashable, Sendable {
        public var name: String
        public var version: String
        public var branch: String?
    }

    public var software: Software
}
