import Foundation

/// Recognizes pasted YouTube links and bare video IDs.
public enum YouTubeLink: Hashable, Sendable {
    case video(id: String, startAt: TimeInterval?)
    case channel(id: String)
    case playlist(id: String)

    private static let videoIDPattern = "^[A-Za-z0-9_-]{11}$"

    /// Parses URLs such as `https://youtu.be/ID?t=42`, `https://www.youtube.com/watch?v=ID`,
    /// `/shorts/ID`, `/live/ID`, `/embed/ID`, `/channel/UC...`, `/playlist?list=PL...`,
    /// Invidious instance links of the same shapes, and bare 11-character video IDs.
    public static func parse(_ text: String) -> YouTubeLink? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.range(of: videoIDPattern, options: .regularExpression) != nil, trimmed.contains(where: { $0.isNumber || $0 == "_" || $0 == "-" || $0.isUppercase }) {
            return .video(id: trimmed, startAt: nil)
        }

        if !trimmed.contains("://") {
            trimmed = "https://" + trimmed
        }
        guard let components = URLComponents(string: trimmed), let host = components.host?.lowercased() else { return nil }
        let isYouTube = host == "youtu.be" || host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
        let path = components.path.split(separator: "/").map(String.init)
        let start = query["t"].flatMap(parseStart) ?? query["start"].flatMap(parseStart)

        if host == "youtu.be", let id = path.first, isVideoID(id) {
            return .video(id: id, startAt: start)
        }
        if let list = query["list"], components.path.hasPrefix("/playlist") {
            return .playlist(id: list)
        }
        if let id = query["v"], isVideoID(id) {
            return .video(id: id, startAt: start)
        }
        if path.count >= 2, ["shorts", "live", "embed", "v", "w"].contains(path[0]), isVideoID(path[1]) {
            return .video(id: path[1], startAt: start)
        }
        if path.count >= 2, path[0] == "channel", path[1].hasPrefix("UC") {
            return .channel(id: path[1])
        }
        // Invidious instances mirror YouTube paths; accept any host for those shapes.
        if !isYouTube, path.count == 1, isVideoID(path[0]), query["v"] == nil {
            return nil
        }
        return nil
    }

    static func isVideoID(_ value: String) -> Bool {
        value.range(of: videoIDPattern, options: .regularExpression) != nil
    }

    /// `42`, `42s`, `1m30s`, `1h2m3s`.
    static func parseStart(_ value: String) -> TimeInterval? {
        if let seconds = Double(value) { return seconds }
        var total: TimeInterval = 0
        var number = ""
        var matched = false
        for character in value {
            if character.isNumber {
                number.append(character)
            } else {
                guard let n = Double(number) else { return nil }
                switch character {
                case "h": total += n * 3600
                case "m": total += n * 60
                case "s": total += n
                default: return nil
                }
                matched = true
                number = ""
            }
        }
        if let n = Double(number) { total += n; matched = true }
        return matched ? total : nil
    }
}
