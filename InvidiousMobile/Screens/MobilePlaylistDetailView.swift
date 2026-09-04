import SwiftUI
import InvidiousKit

struct MobilePlaylistDetailView: View {
    let playlistID: String
    let title: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlaylistDetailViewModel?
    @State private var playing: VideoDetails?
    @State private var confirmDelete = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model?.playlist?.title ?? title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let model {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let first = model.entries.first {
                            Button {
                                Task { await startPlayback(from: first.video) }
                            } label: {
                                Label("Play All", systemImage: "play.fill")
                            }
                        }
                        if model.isEditable, !(model.playlist.map(PlaylistStore.isWatchLater) ?? false) {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                Label("Delete Playlist", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete this playlist?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                Task { if await model?.deletePlaylist() == true { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(item: $playing) { details in
            if let session = app.active, let model {
                MobilePlayerView(
                    details: details,
                    summary: details.summary,
                    startAt: app.resume.resumePoint(for: details.videoId, profile: session.profile.id) ?? 0,
                    session: session,
                    queue: model.entries.map(\.video)
                )
            }
        }
        .task {
            guard model == nil, let session = app.active else { return }
            let vm = PlaylistDetailViewModel(playlistID: playlistID, session: session, store: app.playlists)
            model = vm
            await vm.load()
        }
    }

    @ViewBuilder
    private func content(_ model: PlaylistDetailViewModel) -> some View {
        if let error = model.errorMessage, model.entries.isEmpty {
            ErrorView(message: error) { Task { await model.load() } }
        } else if model.entries.isEmpty && !model.isLoading {
            EmptyStateView(title: "Empty playlist", message: "Videos you save here will show up in this list.", systemImage: "list.and.film")
        } else {
            List {
                ForEach(model.entries) { entry in
                    NavigationLink(value: Route.video(entry.video)) {
                        MobileVideoRow(video: entry.video)
                    }
                    .swipeActions {
                        if model.isEditable {
                            Button(role: .destructive) {
                                Task { await model.remove(entry) }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    .onAppear {
                        if entry.id == model.entries.last?.id { Task { await model.loadMore() } }
                    }
                }
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .listStyle(.plain)
        }
    }

    private func startPlayback(from video: VideoSummary) async {
        guard let client = app.active?.client else { return }
        if let details = try? await client.video(id: video.videoId, proxy: app.settings.proxyMedia) {
            playing = details
        }
    }
}

/// Compact row: small thumbnail, title, channel.
struct MobileVideoRow: View {
    let video: VideoSummary

    @Environment(AppModel.self) private var app

    var body: some View {
        let thumbs = video.videoThumbnails
        let thumb = thumbs.first { $0.quality == "medium" } ?? thumbs.best(maxWidth: 480)
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: thumb.flatMap { app.active?.client.url(for: $0) })
                    .aspectRatio(16 / 9, contentMode: .fill)
                    .frame(width: 140, height: 79)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if video.lengthSeconds > 0 {
                    Text(VideoFormatting.duration(video.lengthSeconds))
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.subheadline.weight(.medium)).lineLimit(2)
                Text(video.author).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
