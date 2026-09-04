import Foundation

/// A SponsorBlock segment to skip.
public struct SponsorSegment: Codable, Hashable, Identifiable, Sendable {
    public var category: String
    public var actionType: String
    public var segment: [Double]
    public var UUID: String

    public var id: String { UUID }
    public var start: TimeInterval { segment.first ?? 0 }
    public var end: TimeInterval { segment.count > 1 ? segment[1] : start }
    public var isSkippable: Bool { actionType == "skip" && end > start }

    public var categoryLabel: String {
        switch category {
        case "sponsor": return "sponsor"
        case "selfpromo": return "self-promotion"
        case "interaction": return "reminder"
        case "intro": return "intro"
        case "outro": return "outro"
        case "preview": return "preview"
        case "music_offtopic": return "non-music section"
        case "filler": return "filler"
        default: return category
        }
    }
}

public enum SponsorBlockCategory: String, CaseIterable, Sendable, Identifiable {
    case sponsor, selfpromo, interaction, intro, outro, preview, music_offtopic, filler

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .sponsor: return "Sponsors"
        case .selfpromo: return "Self-promotion"
        case .interaction: return "Interaction reminders"
        case .intro: return "Intros"
        case .outro: return "Outros"
        case .preview: return "Previews and recaps"
        case .music_offtopic: return "Non-music sections"
        case .filler: return "Filler"
        }
    }

    public static let defaults: Set<SponsorBlockCategory> = [.sponsor, .selfpromo, .interaction]
}

/// Client for the public SponsorBlock API.
public final class SponsorBlockClient: Sendable {
    public static let defaultBaseURL = URL(string: "https://sponsor.ajay.app")!

    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = SponsorBlockClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Skippable segments for a video. An empty array when SponsorBlock has none (HTTP 404).
    public func segments(videoID: String, categories: Set<SponsorBlockCategory>) async throws -> [SponsorSegment] {
        guard !categories.isEmpty else { return [] }
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/skipSegments"), resolvingAgainstBaseURL: false)!
        let list = categories.map(\.rawValue).sorted().map { "\"\($0)\"" }.joined(separator: ",")
        components.queryItems = [
            URLQueryItem(name: "videoID", value: videoID),
            URLQueryItem(name: "categories", value: "[\(list)]"),
        ]
        guard let url = components.url else { throw InvidiousError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw InvidiousError.invalidResponse }
        if http.statusCode == 404 { return [] }
        guard (200..<300).contains(http.statusCode) else { throw InvidiousError.httpStatus(http.statusCode, nil) }
        return try Self.parse(data)
    }

    public static func parse(_ data: Data) throws -> [SponsorSegment] {
        try JSONDecoder().decode([SponsorSegment].self, from: data)
            .filter(\.isSkippable)
            .sorted { $0.start < $1.start }
    }
}
