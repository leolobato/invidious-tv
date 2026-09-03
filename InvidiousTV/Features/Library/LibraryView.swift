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
                if playlists.isEmpty {
                    EmptyStateView(title: "No playlists yet", message: "Use Save on a video to add it to Watch Later or a new playlist.", systemImage: "books.vertical")
                } else {
                    ScrollView {
                        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 48) {
                            ForEach(playlists) { playlist in
                                PlaylistCard(playlist: playlist)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 40)
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
        NavigationLink(value: Route.playlist(id: playlist.playlistId, title: playlist.title)) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    // Try the first few videos so a removed first video does not leave the card blank.
                    let candidates: [URL] = playlist.videos.prefix(3).flatMap { entry -> [Thumbnail] in
                        let thumbs = entry.video.videoThumbnails
                        return ["maxresdefault", "sddefault", "high"].compactMap { q in thumbs.first { $0.quality == q } }
                    }.compactMap { app.active?.client.url(for: $0) }
                    if let primary = candidates.first {
                        RemoteImage(url: primary, fallbacks: Array(candidates.dropFirst()))
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .clipped()
                    } else {
                        ZStack {
                            Rectangle().fill(Color.white.opacity(0.08))
                            Image(systemName: PlaylistStore.isWatchLater(playlist) ? "clock" : "list.and.film")
                                .font(.system(size: 60, weight: .light))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "list.bullet")
                        Text("\(playlist.videoCount)")
                    }
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                    .padding(10)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(playlist.title)
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

    private var subtitle: String {
        var parts = ["\(playlist.videoCount) video\(playlist.videoCount == 1 ? "" : "s")"]
        if let when = VideoFormatting.relativeDate(playlist.updatedDate) { parts.append("updated \(when)") }
        return parts.joined(separator: " · ")
    }
}
