import Foundation

/// Response from `/api/v1/storyboards/:id`.
public struct StoryboardsResponse: Codable, Hashable, Sendable {
    public var storyboards: [StoryboardSpec]
}

/// One storyboard resolution. `url` points at a WebVTT file describing the sprite cues.
public struct StoryboardSpec: Codable, Hashable, Sendable {
    public var url: String
    public var templateUrl: String
    public var width: Int
    public var height: Int
    public var count: Int
    public var interval: Int
    public var storyboardWidth: Int
    public var storyboardHeight: Int
    public var storyboardCount: Int
}

/// A single preview frame: a time range and a crop rectangle inside a sprite image.
public struct StoryboardCue: Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var imageURL: URL
    public var x: Int
    public var y: Int
    public var width: Int
    public var height: Int
}

/// Parsed storyboard track for seek previews.
public struct StoryboardTrack: Hashable, Sendable {
    public var cues: [StoryboardCue]

    public init(cues: [StoryboardCue]) {
        self.cues = cues
    }

    /// The cue covering `time`, or the nearest one when between gaps.
    public func cue(at time: TimeInterval) -> StoryboardCue? {
        guard !cues.isEmpty else { return nil }
        if let exact = cues.first(where: { time >= $0.start && time < $0.end }) {
            return exact
        }
        return cues.min { abs($0.start - time) < abs($1.start - time) }
    }

    /// Parses the WebVTT storyboard format produced by Invidious:
    ///
    /// ```
    /// WEBVTT
    ///
    /// 00:00:00.000 --> 00:00:05.000
    /// https://i.ytimg.com/sb/ID/storyboard3_L1/M0.jpg?sqp=...#xywh=0,0,160,90
    /// ```
    public static func parse(webVTT text: String, relativeTo base: URL?) -> StoryboardTrack {
        var cues: [StoryboardCue] = []
        var pendingRange: (TimeInterval, TimeInterval)?

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line == "WEBVTT" { continue }
            if line.contains("-->") {
                let parts = line.components(separatedBy: "-->").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, let start = parseTimestamp(parts[0]), let end = parseTimestamp(parts[1]) {
                    pendingRange = (start, end)
                }
                continue
            }
            guard let range = pendingRange else { continue }
            pendingRange = nil

            let urlAndFragment = line.components(separatedBy: "#xywh=")
            guard urlAndFragment.count == 2 else { continue }
            let coords = urlAndFragment[1].split(separator: ",").compactMap { Int($0) }
            guard coords.count == 4 else { continue }
            let urlString = urlAndFragment[0]
            let url: URL?
            if urlString.hasPrefix("/") {
                url = base.flatMap { URL(string: urlString, relativeTo: $0)?.absoluteURL }
            } else {
                url = URL(string: urlString)
            }
            guard let imageURL = url else { continue }
            cues.append(StoryboardCue(
                start: range.0, end: range.1, imageURL: imageURL,
                x: coords[0], y: coords[1], width: coords[2], height: coords[3]
            ))
        }
        return StoryboardTrack(cues: cues)
    }

    /// Parses `HH:MM:SS.mmm` or `MM:SS.mmm` into seconds.
    static func parseTimestamp(_ value: String) -> TimeInterval? {
        let parts = value.split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total: TimeInterval = 0
        for part in parts {
            guard let number = Double(part) else { return nil }
            total = total * 60 + number
        }
        return total
    }
}
