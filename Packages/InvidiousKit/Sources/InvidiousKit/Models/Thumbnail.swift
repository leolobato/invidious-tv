import Foundation

/// A video thumbnail as returned by Invidious. URLs may be relative to the instance.
public struct Thumbnail: Codable, Hashable, Sendable {
    public var quality: String?
    public var url: String
    public var width: Int
    public var height: Int

    public init(quality: String? = nil, url: String, width: Int, height: Int) {
        self.quality = quality
        self.url = url
        self.width = width
        self.height = height
    }
}

/// A channel avatar or banner image.
public struct AuthorImage: Codable, Hashable, Sendable {
    public var url: String
    public var width: Int
    public var height: Int

    public init(url: String, width: Int, height: Int) {
        self.url = url
        self.width = width
        self.height = height
    }
}

extension Array where Element == Thumbnail {
    /// Best thumbnail whose width does not exceed `maxWidth`, falling back to the smallest available.
    public func best(maxWidth: Int) -> Thumbnail? {
        let sorted = self.sorted { $0.width > $1.width }
        return sorted.first { $0.width <= maxWidth } ?? sorted.last
    }
}

extension Array where Element == AuthorImage {
    /// Smallest image whose width is at least `minWidth`, falling back to the largest available.
    public func best(minWidth: Int) -> AuthorImage? {
        let sorted = self.sorted { $0.width < $1.width }
        return sorted.first { $0.width >= minWidth } ?? sorted.last
    }
}
