import SwiftUI
import InvidiousKit

/// Library tab: the account's playlists, Watch Later first.
struct LibraryView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var state: LoadState<[Playlist]> = .idle

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                LoadingView()
            case .failed(let message):
                ErrorView(message: message) { Task { await load() } }
            case .loaded(let playlists):
                ScrollView {
                    LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 48) {
                        HistoryCard()
                        ForEach(playlists) { playlist in
                            PlaylistCard(playlist: playlist)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 40)
                    if playlists.isEmpty {
                        Text("No playlists yet. Use Save on a video to add it to Watch Later or a new playlist.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 60)
                    }
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: app.playlists.version) { _, _ in
            Task { await load() }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await app.playlists.all(using: session.client))
        } catch {
            session.handle(error)
            state = .failed(error.localizedDescription)
        }
    }
}

/// Playlist tile with the first video's thumbnail and the count.
struct PlaylistCard: View {
    let playlist: Playlist

    @Environment(AppModel.self) private var app

    var body: some View {
        // Try the first few videos so a removed first video does not leave the card blank.
        let covers: [URL] = playlist.videos.prefix(3).flatMap { entry -> [Thumbnail] in
            let thumbs = entry.video.videoThumbnails
            return ["maxresdefault", "sddefault", "high"].compactMap { q in thumbs.first { $0.quality == q } }
        }.compactMap { app.active?.client.url(for: $0) }
        PlaylistTile(
            title: playlist.title,
            subtitle: subtitle,
            videoCount: playlist.videoCount,
            covers: covers,
            placeholder: PlaylistStore.isWatchLater(playlist) ? "clock" : "list.and.film",
            route: .playlist(id: playlist.playlistId, title: playlist.title)
        )
    }

    private var subtitle: String {
        var parts = ["\(playlist.videoCount) video\(playlist.videoCount == 1 ? "" : "s")"]
        if let when = VideoFormatting.relativeDate(playlist.updatedDate) { parts.append("updated \(when)") }
        return parts.joined(separator: " · ")
    }
}

/// Tile for one of a channel's public playlists.
struct ChannelPlaylistCard: View {
    let playlist: SearchPlaylist

    @Environment(AppModel.self) private var app

    var body: some View {
        // The cover is a YouTube thumbnail; load it through the instance like every other image.
        // `maxres.jpg` makes the instance pick the largest size that exists (missing sizes 404 slowly).
        let covers: [URL] = (playlist.coverVideoID.map { id in
            ["maxres", "mqdefault"].compactMap { try? app.active?.client.absoluteURL("/vi/\(id)/\($0).jpg") }
        } ?? []) + (playlist.playlistThumbnail.flatMap(URL.init(string:)).map { [$0] } ?? [])
        // Invidious reports -1 when YouTube does not say how many videos a list has.
        let count = playlist.videoCount.flatMap { $0 >= 0 ? $0 : nil }
        PlaylistTile(
            title: playlist.title,
            subtitle: count.map { "\($0) video\($0 == 1 ? "" : "s")" } ?? "Playlist",
            videoCount: count,
            covers: covers,
            placeholder: "list.and.film",
            route: .playlist(id: playlist.playlistId, title: playlist.title)
        )
    }
}

/// Card shared by the library and channel playlists: cover, count badge, title and subtitle.
struct PlaylistTile: View {
    let title: String
    let subtitle: String
    /// Shown as a badge on the cover; nil hides it.
    let videoCount: Int?
    let covers: [URL]
    let placeholder: String
    let route: Route

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    if let primary = covers.first {
                        RemoteImage(url: primary, fallbacks: Array(covers.dropFirst()))
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .clipped()
                    } else {
                        ZStack {
                            Rectangle().fill(Color.white.opacity(0.08))
                            Image(systemName: placeholder)
                                .font(.system(size: 60, weight: .light))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    if let videoCount {
                        HStack(spacing: 6) {
                            Image(systemName: "list.bullet")
                            Text("\(videoCount)")
                        }
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                        .padding(10)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2, reservesSpace: true)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .buttonStyle(.card)
    }
}

/// Library tile that opens the account's watch history.
struct HistoryCard: View {
    var body: some View {
        NavigationLink(value: Route.history) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.08))
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Watch History")
                        .font(.callout.weight(.medium))
                        .lineLimit(2, reservesSpace: true)
                    Text("Videos you have watched")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .buttonStyle(.card)
    }
}
