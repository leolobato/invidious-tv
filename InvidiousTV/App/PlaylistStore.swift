import Foundation
import Observation
import InvidiousKit

/// Caches the account's playlists and owns the Watch Later convention.
///
/// Invidious has no built-in Watch Later, so it is a private playlist named "Watch Later" that is
/// created on first use.
@MainActor
@Observable
final class PlaylistStore {
    static let watchLaterTitle = "Watch Later"

    /// Bumped whenever playlists change so views can reload.
    private(set) var version = 0
    private var cached: [Playlist] = []
    private var cachedAt: Date?

    static func isWatchLater(_ playlist: Playlist) -> Bool {
        playlist.title.caseInsensitiveCompare(watchLaterTitle) == .orderedSame
    }

    /// Playlists, Watch Later first, then most recently updated.
    func all(using client: InvidiousClient, maxAge: TimeInterval = 60) async throws -> [Playlist] {
        if let cachedAt, Date().timeIntervalSince(cachedAt) < maxAge, !cached.isEmpty {
            return cached
        }
        let playlists = try await client.playlists()
        cached = playlists.sorted { lhs, rhs in
            let lw = Self.isWatchLater(lhs), rw = Self.isWatchLater(rhs)
            if lw != rw { return lw }
            return (lhs.updated ?? 0) > (rhs.updated ?? 0)
        }
        cachedAt = Date()
        return cached
    }

    func invalidate() {
        cachedAt = nil
        version += 1
    }

    /// Adds a video to Watch Later, creating the playlist if needed.
    func addToWatchLater(_ videoID: String, using client: InvidiousClient) async throws {
        let playlists = try await all(using: client, maxAge: 0)
        let id: String
        if let existing = playlists.first(where: Self.isWatchLater) {
            id = existing.playlistId
        } else {
            id = try await client.createPlaylist(title: Self.watchLaterTitle, privacy: .private)
        }
        try await client.addVideo(videoID, toPlaylist: id)
        invalidate()
    }

    func add(_ videoID: String, to playlistID: String, using client: InvidiousClient) async throws {
        try await client.addVideo(videoID, toPlaylist: playlistID)
        invalidate()
    }

    /// Creates a playlist and adds the video to it.
    func createAndAdd(_ videoID: String, title: String, using client: InvidiousClient) async throws {
        let id = try await client.createPlaylist(title: title, privacy: .private)
        try await client.addVideo(videoID, toPlaylist: id)
        invalidate()
    }
}
