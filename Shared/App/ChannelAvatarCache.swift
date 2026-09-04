import Foundation
import Observation
import InvidiousKit

/// Channel avatar URLs, fetched lazily and remembered on disk.
///
/// The subscriptions endpoint returns names and IDs only, and each channel lookup makes the
/// instance call YouTube, so results are cached across launches.
@MainActor
@Observable
final class ChannelAvatarCache {
    private(set) var urls: [String: URL] = [:]
    private var inFlight: Set<String> = []
    private let file: URL

    init(directory: URL = AppDirectories.applicationSupport()) {
        file = directory.appendingPathComponent("channel-avatars.json")
        if let data = try? Data(contentsOf: file),
           let stored = try? JSONDecoder().decode([String: URL].self, from: data) {
            urls = stored
        }
    }

    func url(for channelID: String) -> URL? {
        urls[channelID]
    }

    func remember(_ url: URL?, for channelID: String) {
        guard let url, urls[channelID] != url else { return }
        urls[channelID] = url
        persist()
    }

    /// Fetches the avatar for a channel unless it is already known or loading.
    func load(channelID: String, using client: InvidiousClient) async {
        guard urls[channelID] == nil, !inFlight.contains(channelID) else { return }
        inFlight.insert(channelID)
        defer { inFlight.remove(channelID) }
        guard let channel = try? await client.channel(ucid: channelID) else { return }
        remember(channel.authorThumbnails.best(minWidth: 176).flatMap(client.url(for:)), for: channelID)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(urls) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
