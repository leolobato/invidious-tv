import SwiftUI
import InvidiousKit

struct MobileLibraryView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var state: LoadState<[Playlist]> = .idle

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorView(message: message) { Task { await load() } }
            case .loaded(let playlists):
                if playlists.isEmpty {
                    EmptyStateView(title: "No playlists yet", message: "Use Save on a video to add it to Watch Later or a new playlist.", systemImage: "books.vertical")
                } else {
                    List(playlists) { playlist in
                        NavigationLink(value: Route.playlist(id: playlist.playlistId, title: playlist.title)) {
                            HStack(spacing: 14) {
                                cover(playlist)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.title).font(.body.weight(.medium)).lineLimit(2)
                                    Text("\(playlist.videoCount) videos").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .navigationTitle("Library")
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: app.playlists.version) { _, _ in Task { await load() } }
    }

    private func cover(_ playlist: Playlist) -> some View {
        let candidates: [URL] = playlist.videos.prefix(3).flatMap { entry -> [Thumbnail] in
            let thumbs = entry.video.videoThumbnails
            return ["sddefault", "high", "medium"].compactMap { q in thumbs.first { $0.quality == q } }
        }.compactMap { app.active?.client.url(for: $0) }
        return ZStack {
            if let primary = candidates.first {
                RemoteImage(url: primary, fallbacks: Array(candidates.dropFirst()))
            } else {
                Rectangle().fill(Color.secondary.opacity(0.2))
                Image(systemName: PlaylistStore.isWatchLater(playlist) ? "clock" : "list.and.film")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
