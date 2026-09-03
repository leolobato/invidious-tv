import Foundation
import Observation
import SwiftUI
import InvidiousKit

@MainActor
@Observable
final class PlaylistDetailViewModel {
    let playlistID: String
    private let session: ActiveSession
    private let store: PlaylistStore

    private(set) var playlist: Playlist?
    private(set) var entries: [PlaylistVideo] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private var page = 0
    private var reachedEnd = false

    init(playlistID: String, session: ActiveSession, store: PlaylistStore) {
        self.playlistID = playlistID
        self.session = session
        self.store = store
    }

    func load() async {
        page = 0
        reachedEnd = false
        entries = []
        errorMessage = nil
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = page + 1
            let result = try await session.client.playlist(id: playlistID, page: next)
            playlist = result
            let known = Set(entries.map(\.id))
            entries.append(contentsOf: result.videos.filter { !known.contains($0.id) })
            page = next
            if result.videos.count < 100 || entries.count >= result.videoCount {
                reachedEnd = true
            }
        } catch {
            session.handle(error)
            errorMessage = error.localizedDescription
            reachedEnd = true
        }
    }

    func remove(_ entry: PlaylistVideo) async {
        do {
            try await session.client.removeVideo(indexId: entry.indexId, fromPlaylist: playlistID)
            entries.removeAll { $0.id == entry.id }
            playlist?.videoCount = max(0, (playlist?.videoCount ?? 1) - 1)
            store.invalidate()
        } catch {
            session.handle(error)
            errorMessage = error.localizedDescription
        }
    }

    func deletePlaylist() async -> Bool {
        do {
            try await session.client.deletePlaylist(id: playlistID)
            store.invalidate()
            return true
        } catch {
            session.handle(error)
            errorMessage = error.localizedDescription
            return false
        }
    }
}
