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

    public var profileName: String
    public var continueWatching: [Item]
    public var latest: [Item]
    public var updatedAt: Date

    public init(profileName: String, continueWatching: [Item], latest: [Item], updatedAt: Date = Date()) {
        self.profileName = profileName
        self.continueWatching = continueWatching
        self.latest = latest
        self.updatedAt = updatedAt
    }
}

/// Reads and writes the snapshot in the app group container shared with the Top Shelf extension.
public struct TopShelfSnapshotStore: Sendable {
    public let fileURL: URL?

    public init(appGroup: String) {
        fileURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("topshelf.json")
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
