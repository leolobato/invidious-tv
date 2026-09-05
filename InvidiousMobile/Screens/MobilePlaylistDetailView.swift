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
    @State private var isStartingPlayback = false

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
            if let model, model.isEditable, !(model.playlist.map(PlaylistStore.isWatchLater) ?? false) {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label("Delete Playlist", systemImage: "trash")
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
                header(model)
                    .listRowSeparator(.hidden)
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

    /// Count, owner and description, plus Play All for the whole list.
    private func header(_ model: PlaylistDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(countLine(model))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let description = model.playlist?.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let first = model.entries.first {
                Button {
                    Task { await startPlayback(from: first.video) }
                } label: {
                    Label(isStartingPlayback ? "Loading…" : "Play All", systemImage: "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(isStartingPlayback)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }

    private func countLine(_ model: PlaylistDetailViewModel) -> String {
        var parts = ["\(model.playlist?.videoCount ?? model.entries.count) videos"]
        if let playlist = model.playlist, !playlist.isInvidiousPlaylist, !playlist.author.isEmpty {
            parts.append(playlist.author)
        }
        return parts.joined(separator: " · ")
    }

    private func startPlayback(from video: VideoSummary) async {
        guard let client = app.active?.client, !isStartingPlayback else { return }
        isStartingPlayback = true
        defer { isStartingPlayback = false }
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
        let progress = progress
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: thumb.flatMap { app.active?.client.url(for: $0) })
                    .aspectRatio(16 / 9, contentMode: .fill)
                if video.liveNow {
                    badge("LIVE", color: .red)
                } else if video.isUpcoming {
                    badge("UPCOMING", color: .gray)
                } else if video.lengthSeconds > 0 {
                    badge(VideoFormatting.duration(video.lengthSeconds), color: .black.opacity(0.75))
                }
                if let progress, progress > 0 {
                    VStack {
                        Spacer()
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(.white.opacity(0.3))
                                Rectangle().fill(Color.red).frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
            .frame(width: 140, height: 79)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.subheadline.weight(.medium)).lineLimit(2)
                Text(video.author).font(.caption).foregroundStyle(.secondary)
            }
        }
        .opacity(app.active?.watchedIDs.contains(video.videoId) == true && progress == nil ? 0.6 : 1)
    }

    private var progress: Double? {
        guard let profile = app.active?.profile.id,
              let entry = app.resume.position(for: video.videoId, profile: profile) else { return nil }
        return entry.progress
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            .padding(4)
    }
}
