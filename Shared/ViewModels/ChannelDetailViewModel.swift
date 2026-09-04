import Foundation
import Observation
import SwiftUI
import InvidiousKit

@MainActor
@Observable
final class ChannelDetailViewModel {
    let channelID: String
    private let session: ActiveSession
    private let avatars: ChannelAvatarCache

    private(set) var header: LoadState<Channel> = .idle
    private(set) var videos: [VideoSummary] = []
    private(set) var playlists: [SearchPlaylist] = []
    private(set) var isLoadingMore = false
    private(set) var isLoadingPlaylists = false
    private(set) var isSubscribed = false
    private(set) var isTogglingSubscription = false
    private var continuation: String?
    private var reachedEnd = false
    private var playlistContinuation: String?
    private var reachedPlaylistsEnd = false

    init(channelID: String, session: ActiveSession, avatars: ChannelAvatarCache) {
        self.channelID = channelID
        self.session = session
        self.avatars = avatars
    }

    func load() async {
        header = .loading
        let client = session.client
        async let subs = try? client.subscriptions()
        do {
            let channel = try await client.channel(ucid: channelID)
            header = .loaded(channel)
            avatars.remember(channel.authorThumbnails.best(minWidth: 176).flatMap(client.url(for:)), for: channelID)
        } catch {
            session.handle(error)
            header = .failed(error.localizedDescription)
        }
        if let subs = await subs {
            isSubscribed = subs.contains { $0.authorId == channelID }
        }
        async let playlists: Void = loadMorePlaylists()
        await loadMore()
        await playlists
    }

    /// Next page of the channel's public playlists. A failure leaves the shelf empty; the videos
    /// still show.
    func loadMorePlaylists() async {
        guard !isLoadingPlaylists, !reachedPlaylistsEnd else { return }
        isLoadingPlaylists = true
        defer { isLoadingPlaylists = false }
        do {
            let page = try await session.client.channelPlaylists(ucid: channelID, continuation: playlistContinuation)
            let known = Set(playlists.map(\.playlistId))
            playlists.append(contentsOf: page.playlists.filter { !known.contains($0.playlistId) })
            playlistContinuation = page.continuation
            if page.continuation == nil || page.playlists.isEmpty {
                reachedPlaylistsEnd = true
            }
        } catch {
            reachedPlaylistsEnd = true
        }
    }

    func loadMore() async {
        guard !isLoadingMore, !reachedEnd else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await session.client.channelVideos(ucid: channelID, continuation: continuation)
            let known = Set(videos.map(\.videoId))
            videos.append(contentsOf: page.videos.filter { !known.contains($0.videoId) })
            continuation = page.continuation
            if page.continuation == nil || page.videos.isEmpty {
                reachedEnd = true
            }
        } catch {
            session.handle(error)
            if videos.isEmpty, header.value == nil {
                header = .failed(error.localizedDescription)
            }
            reachedEnd = true
        }
    }

    func toggleSubscription() async {
        isTogglingSubscription = true
        defer { isTogglingSubscription = false }
        do {
            if isSubscribed {
                try await session.client.unsubscribe(ucid: channelID)
            } else {
                try await session.client.subscribe(ucid: channelID)
            }
            isSubscribed.toggle()
        } catch {
            session.handle(error)
        }
    }
}
