import Foundation
import Observation
import InvidiousKit

/// User preferences backed by UserDefaults.
@MainActor
@Observable
final class AppSettings {
    /// Instance offered on first launch, from the `DEFAULT_INSTANCE_URL` build setting (empty by default).
    static let defaultInstance = (Bundle.main.object(forInfoDictionaryKey: "InvidiousDefaultInstance") as? String) ?? ""

    /// Vertical resolutions offered in the quality setting. 0 means unlimited.
    static let qualityOptions: [Int] = [0, 2160, 1440, 1080, 720, 480]
    /// Phones and tablets default to 1080p; the TV plays the best the video offers (up to 4K).
    #if os(iOS)
    static let defaultMaxQuality = 1080
    #else
    static let defaultMaxQuality = 0
    #endif
    static let speedOptions: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private let defaults: UserDefaults

    var instanceURLString: String {
        didSet { defaults.set(instanceURLString, forKey: Keys.instance) }
    }

    var proxyMedia: Bool {
        didSet { defaults.set(proxyMedia, forKey: Keys.proxyMedia) }
    }

    /// 0 means unlimited.
    var maxQuality: Int {
        didSet { defaults.set(maxQuality, forKey: Keys.maxQuality) }
    }

    var defaultSpeed: Double {
        didSet { defaults.set(defaultSpeed, forKey: Keys.defaultSpeed) }
    }

    var sponsorBlockEnabled: Bool {
        didSet { defaults.set(sponsorBlockEnabled, forKey: Keys.sponsorBlockEnabled) }
    }

    var sponsorBlockCategories: Set<SponsorBlockCategory> {
        didSet { defaults.set(sponsorBlockCategories.map(\.rawValue).sorted(), forKey: Keys.sponsorBlockCategories) }
    }

    /// Sync resume positions between this user's devices through iCloud.
    var iCloudSync: Bool {
        didSet { defaults.set(iCloudSync, forKey: Keys.iCloudSync) }
    }

    var autoplayNext: Bool {
        didSet { defaults.set(autoplayNext, forKey: Keys.autoplayNext) }
    }

    var channelSort: ChannelSortOrder {
        didSet { defaults.set(channelSort.rawValue, forKey: Keys.channelSort) }
    }

    var channelLayout: ChannelLayout {
        didSet { defaults.set(channelLayout.rawValue, forKey: Keys.channelLayout) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        instanceURLString = defaults.string(forKey: Keys.instance) ?? Self.defaultInstance
        proxyMedia = defaults.object(forKey: Keys.proxyMedia) as? Bool ?? true
        maxQuality = defaults.object(forKey: Keys.maxQuality) as? Int ?? Self.defaultMaxQuality
        let speed = defaults.double(forKey: Keys.defaultSpeed)
        defaultSpeed = speed > 0 ? speed : 1.0
        autoplayNext = defaults.object(forKey: Keys.autoplayNext) as? Bool ?? true
        iCloudSync = defaults.object(forKey: Keys.iCloudSync) as? Bool ?? true
        sponsorBlockEnabled = defaults.object(forKey: Keys.sponsorBlockEnabled) as? Bool ?? true
        if let stored = defaults.stringArray(forKey: Keys.sponsorBlockCategories) {
            sponsorBlockCategories = Set(stored.compactMap(SponsorBlockCategory.init))
        } else {
            sponsorBlockCategories = SponsorBlockCategory.defaults
        }
        channelSort = defaults.string(forKey: Keys.channelSort).flatMap(ChannelSortOrder.init) ?? .nameAscending
        channelLayout = defaults.string(forKey: Keys.channelLayout).flatMap(ChannelLayout.init) ?? .grid
    }

    var instanceURL: URL? {
        Self.normalizedURL(from: instanceURLString)
    }

    /// Stream preferences for this device, honoring the quality cap.
    var streamPreferences: StreamPreferences {
        #if targetEnvironment(simulator)
        // No hardware decoding in the simulator; keep it light.
        let cap = min(maxQuality == 0 ? 720 : maxQuality, 720)
        return StreamPreferences(maxHeight: cap, codecPreference: [.avc1], preferHighFrameRate: false)
        #else
        return StreamPreferences(maxHeight: maxQuality == 0 ? nil : maxQuality, codecPreference: [.avc1, .hevc, .vp9])
        #endif
    }

    static func normalizedURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
            trimmed = "http://" + trimmed
        }
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed), url.host != nil else { return nil }
        return url
    }

    static func qualityLabel(_ height: Int) -> String {
        switch height {
        case 0: return "Best available"
        case 2160: return "4K (2160p)"
        default: return "\(height)p"
        }
    }

    private enum Keys {
        static let instance = "settings.instanceURL"
        static let proxyMedia = "settings.proxyMedia"
        static let maxQuality = "settings.maxQuality"
        static let defaultSpeed = "settings.defaultSpeed"
        static let autoplayNext = "settings.autoplayNext"
        static let iCloudSync = "settings.iCloudSync"
        static let sponsorBlockEnabled = "settings.sponsorBlockEnabled"
        static let sponsorBlockCategories = "settings.sponsorBlockCategories"
        static let channelSort = "settings.channelSort"
        static let channelLayout = "settings.channelLayout"
    }
}

enum ChannelSortOrder: String, CaseIterable, Identifiable {
    case nameAscending, nameDescending, recentUploads

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nameAscending: return "Name A–Z"
        case .nameDescending: return "Name Z–A"
        case .recentUploads: return "Recent uploads"
        }
    }
}

enum ChannelLayout: String, CaseIterable {
    case grid, list

    var toggled: ChannelLayout { self == .grid ? .list : .grid }
    var label: String { self == .grid ? "Grid" : "List" }
    var systemImage: String { self == .grid ? "square.grid.3x2" : "list.bullet" }
}
