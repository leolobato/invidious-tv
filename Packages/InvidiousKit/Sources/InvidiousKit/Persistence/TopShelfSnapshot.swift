import Foundation

/// What the Top Shelf extension shows, written by the app into the shared app group container.
public struct TopShelfSnapshot: Codable, Hashable, Sendable {
    public struct Item: Codable, Hashable, Identifiable, Sendable {
        public var videoID: String
        public var title: String
        public var subtitle: String
        public var imageURL: URL?
        /// 0...1 for Continue Watching, nil otherwise.
        public var progress: Double?

        public var id: String { videoID }

        public init(videoID: String, title: String, subtitle: String, imageURL: URL?, progress: Double? = nil) {
            self.videoID = videoID
            self.title = title
            self.subtitle = subtitle
            self.imageURL = imageURL
            self.progress = progress
        }
    }

    /// Which account the extension should refresh the feed for. Its credential lives in the shared keychain.
    public struct Account: Codable, Hashable, Sendable {
        public var profileID: UUID
        public var instanceURL: URL

        public init(profileID: UUID, instanceURL: URL) {
            self.profileID = profileID
            self.instanceURL = instanceURL
        }
    }

    public var profileName: String
    public var continueWatching: [Item]
    public var latest: [Item]
    public var updatedAt: Date
    public var account: Account?

    public init(profileName: String, continueWatching: [Item], latest: [Item], updatedAt: Date = Date(), account: Account? = nil) {
        self.profileName = profileName
        self.continueWatching = continueWatching
        self.latest = latest
        self.updatedAt = updatedAt
        self.account = account
    }

    /// How old a snapshot may be before the extension fetches the feed again.
    public static let refreshInterval: TimeInterval = 15 * 60

    /// Top Shelf item for a video, with the largest thumbnail the instance serves.
    public static func item(for video: VideoSummary, progress: Double?, client: InvidiousClient) -> Item {
        let thumbs = video.videoThumbnails
        let thumb = thumbs.first { $0.quality == "maxresdefault" } ?? thumbs.first { $0.quality == "sddefault" } ?? thumbs.best(maxWidth: 1280)
        return Item(
            videoID: video.videoId,
            title: video.title,
            subtitle: video.author,
            imageURL: thumb.flatMap(client.url(for:)),
            progress: progress
        )
    }

    /// Latest subscription uploads as shelf items, upcoming premieres and live streams left out.
    public static func latestItems(from videos: [VideoSummary], client: InvidiousClient, limit: Int = 12) -> [Item] {
        videos.filter { !$0.isUpcoming && !$0.liveNow }.prefix(limit).map { item(for: $0, progress: nil, client: client) }
    }
}

/// Reads and writes the snapshot in the app group container shared with the Top Shelf extension.
public struct TopShelfSnapshotStore: Sendable {
    public let fileURL: URL?

    public init(appGroup: String) {
        fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("topshelf.json")
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> TopShelfSnapshot? {
        guard let fileURL else { return nil }
        return try? JSONFileStore<TopShelfSnapshot>(url: fileURL).load()
    }

    public func save(_ snapshot: TopShelfSnapshot) {
        guard let fileURL else { return }
        try? JSONFileStore<TopShelfSnapshot>(url: fileURL).save(snapshot)
    }
}

/// Deep links handled by the app, also used by the Top Shelf extension.
public enum AppLink {
    public static let scheme = "invidioustv"

    public static func video(_ id: String) -> URL {
        URL(string: "\(scheme)://video/\(id)")!
    }

    /// Video ID from `invidioustv://video/<id>`, if the URL is one.
    public static func videoID(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "video" else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty ? nil : id
    }
}
