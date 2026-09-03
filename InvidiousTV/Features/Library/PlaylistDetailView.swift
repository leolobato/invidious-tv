import SwiftUI
import InvidiousKit

/// One playlist: header and its videos, with removal via long press.
struct PlaylistDetailView: View {
    let playlistID: String
    let title: String

    @Environment(AppModel.self) private var app
    @State private var model: PlaylistDetailViewModel?
    @State private var confirmDelete = false
    @State private var playing: VideoDetails?
    @State private var isStartingPlayback = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                LoadingView()
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(item: $playing) { details in
            if let session = app.active, let model {
                PlayerView(
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
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(model)
                    if model.entries.isEmpty && !model.isLoading {
                        EmptyStateView(title: "Empty playlist", message: "Videos you save here will show up in this list.", systemImage: "list.and.film")
                            .frame(height: 400)
                    } else {
                        LazyVGrid(columns: VideoGrid.columns, alignment: .leading, spacing: 48) {
                            ForEach(model.entries) { entry in
                                VideoCard(
                                    video: entry.video,
                                    progress: progress(for: entry.video),
                                    watched: app.active?.watchedIDs.contains(entry.video.videoId) ?? false
                                )
                                .contextMenu {
                                    Button("Remove from playlist", systemImage: "trash", role: .destructive) {
                                        Task { await model.remove(entry) }
                                    }
                                }
                                .onAppear {
                                    if entry.id == model.entries.last?.id {
                                        Task { await model.loadMore() }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 40)
                    }
                    if model.isLoading {
                        ProgressView().padding(40)
                    }
                }
            }
        }
    }

    private func header(_ model: PlaylistDetailViewModel) -> some View {
        HStack(alignment: .center, spacing: 30) {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.playlist?.title ?? title)
                    .font(.title.weight(.semibold))
                Text("\(model.playlist?.videoCount ?? model.entries.count) videos")
                    .foregroundStyle(.secondary)
                if let description = model.playlist?.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if let first = model.entries.first {
                Button {
                    Task { await startPlayback(from: first.video) }
                } label: {
                    Label(isStartingPlayback ? "Loading…" : "Play All", systemImage: "play.fill")
                }
                .disabled(isStartingPlayback)
            }
            if !(model.playlist.map(PlaylistStore.isWatchLater) ?? false) {
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .alert("Delete \"\(model.playlist?.title ?? title)\"?", isPresented: $confirmDelete) {
                    Button("Delete", role: .destructive) {
                        Task {
                            if await model.deletePlaylist() { dismiss() }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }
        }
        .padding(.horizontal, 60)
        .padding(.top, 40)
        .focusSection()
    }

    /// Loads the first video and opens the player with the whole playlist queued.
    private func startPlayback(from video: VideoSummary) async {
        guard let client = app.active?.client, !isStartingPlayback else { return }
        isStartingPlayback = true
        defer { isStartingPlayback = false }
        if let details = try? await client.video(id: video.videoId, proxy: app.settings.proxyMedia) {
            playing = details
        }
    }

    private func progress(for video: VideoSummary) -> Double? {
        guard let profile = app.active?.profile.id,
              let entry = app.resume.position(for: video.videoId, profile: profile) else { return nil }
        return entry.progress
    }
}

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
