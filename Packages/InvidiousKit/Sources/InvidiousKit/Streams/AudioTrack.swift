import Foundation

/// One language variant of a video's audio, as YouTube labels it in the stream URL's `xtags`
/// (`acont=original:lang=en-US`, `acont=dubbed-auto:lang=pt-BR`, sometimes with `drc=1`).
/// Invidious does not expose this as a field, so it is parsed from the URL.
public struct AudioTrack: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case original
        case dubbed
        case autoDubbed
        case unknown
    }

    public var languageCode: String?
    public var kind: Kind

    public var id: String { "\(kind.rawValue):\(languageCode ?? "")" }

    public init(languageCode: String?, kind: Kind) {
        self.languageCode = languageCode
        self.kind = kind
    }

    /// The track to play when the user has no preference.
    public var isOriginal: Bool { kind == .original }

    /// "Portuguese (Brazil) · auto-dubbed", "English (original)".
    public var displayName: String {
        let language = languageCode.flatMap { Locale.current.localizedString(forIdentifier: $0) }
            ?? languageCode
            ?? "Unknown"
        switch kind {
        case .original: return "\(language) (original)"
        case .autoDubbed: return "\(language) · auto-dubbed"
        case .dubbed: return "\(language) · dubbed"
        case .unknown: return language
        }
    }

    /// Parses the `xtags` query value of a stream URL. Returns nil when the URL carries none.
    /// The `drc` flag (loudness-normalized variant) is reported separately by ``AdaptiveFormat/hasDRC``.
    public static func parse(xtags: String) -> AudioTrack? {
        var language: String?
        var kind: Kind = .unknown
        var sawTag = false
        for pair in xtags.split(separator: ":") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "lang":
                language = parts[1]
                sawTag = true
            case "acont":
                sawTag = true
                switch parts[1] {
                case "original": kind = .original
                case "dubbed-auto": kind = .autoDubbed
                case "dubbed": kind = .dubbed
                default: kind = .unknown
                }
            default:
                break
            }
        }
        return sawTag ? AudioTrack(languageCode: language, kind: kind) : nil
    }
}

extension AdaptiveFormat {
    /// Query parameters of the stream URL. Works for direct googlevideo URLs and instance-proxied ones.
    var urlQuery: [String: String] {
        guard let components = URLComponents(string: url) else { return [:] }
        return Dictionary((components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    /// Language variant of an audio stream, when YouTube labels it.
    public var audioTrack: AudioTrack? {
        guard isAudio, let xtags = urlQuery["xtags"] else { return nil }
        return AudioTrack.parse(xtags: xtags)
    }

    /// Loudness-normalized ("dynamic range compression") variant of the same track.
    public var hasDRC: Bool {
        urlQuery["xtags"]?.split(separator: ":").contains("drc=1") ?? false
    }
}
