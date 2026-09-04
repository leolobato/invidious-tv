import Foundation
import SwiftUI
import InvidiousKit

/// Finds URLs in a plain-text description and decides where they lead.
enum DescriptionLinks {
    /// The text with every URL marked as a tappable link.
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        for (url, range) in matches(in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
        }
        return result
    }

    /// URLs in order of appearance, without duplicates.
    static func urls(in text: String) -> [URL] {
        var seen: Set<URL> = []
        return matches(in: text).map(\.0).filter { seen.insert($0).inserted }
    }

    /// YouTube links the app can open itself.
    static func inAppLinks(in text: String) -> [(url: URL, link: YouTubeLink)] {
        urls(in: text).compactMap { url in YouTubeLink.parse(url.absoluteString).map { (url, $0) } }
    }

    /// Short label for a link button: host plus the interesting part of the path.
    static func label(for url: URL, link: YouTubeLink) -> String {
        switch link {
        case .video: return "Video " + (url.host ?? "") + url.path
        case .channel(let id): return "Channel " + id
        case .playlist(let id): return "Playlist " + id
        }
    }

    private static func matches(in text: String) -> [(URL, Range<String.Index>)] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: nsRange).compactMap { match in
            guard let url = match.url, let range = Range(match.range, in: text) else { return nil }
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
            return (url, range)
        }
    }
}

/// Resolves a YouTube link from a description into a navigation route, fetching video details as needed.
@MainActor
enum LinkRouter {
    static func route(for link: YouTubeLink, client: InvidiousClient) async -> Route? {
        switch link {
        case .video(let id, _):
            guard let details = try? await client.video(id: id) else { return nil }
            return .video(details.summary)
        case .channel(let id):
            return .channel(id: id, name: "")
        case .playlist(let id):
            return .playlist(id: id, title: "")
        }
    }
}
