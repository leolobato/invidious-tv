import SwiftUI
import InvidiousKit

/// Video page: play or resume, metadata, description, up next.
struct VideoDetailView: View {
    let video: VideoSummary

    @Environment(AppModel.self) private var app
    @State private var details: LoadState<VideoDetails> = .idle
    @State private var isPlaying = false
    @State private var startAt: TimeInterval = 0
    @State private var descriptionExpanded = false
    @State private var playlists: [Playlist] = []
    @State private var saveMessage: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @FocusState private var playFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                hero
                description
                if let recommended = details.value?.recommendedVideos, !recommended.isEmpty {
                    Shelf(title: "Up Next", videos: recommended)
                        .padding(.horizontal, -60)
                }
            }
            .padding(60)
        }
        .navigationBarHidden(true)
        .task(id: video.videoId) {
            await load()
        }
        .onAppear {
            playFocused = true
        }
        .fullScreenCover(isPresented: $isPlaying) {
            if let session = app.active, let loaded = details.value {
                PlayerView(details: loaded, summary: video, startAt: startAt, session: session)
            }
        }
    }

    private var isLive: Bool {
        details.value?.liveNow ?? video.liveNow
    }

    private var resumePoint: TimeInterval? {
        guard let profile = app.active?.profile.id else { return nil }
        return app.resume.resumePoint(for: video.videoId, profile: profile)
    }

    private var hero: some View {
        let client = app.active?.client
        let thumbs = details.value?.videoThumbnails ?? video.videoThumbnails
        let primary = thumbs.first { $0.quality == "maxresdefault" } ?? thumbs.best(maxWidth: 1280)
        let fallbacks = ["sddefault", "high", "medium"].compactMap { q in thumbs.first { $0.quality == q } }
        return HStack(alignment: .top, spacing: 50) {
            RemoteImage(url: primary.flatMap { client?.url(for: $0) }, fallbacks: fallbacks.compactMap { client?.url(for: $0) })
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(width: 880, height: 495)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 24) {
                Text(details.value?.title ?? video.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(3)

                channelRow

                Text(metadata)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 20) {
                    Button {
                        play(from: resumePoint ?? 0)
                    } label: {
                        Label(resumePoint.map { "Resume from \(VideoFormatting.duration(Int($0)))" } ?? "Play", systemImage: "play.fill")
                    }
                    .focused($playFocused)
                    .disabled(details.value == nil || isLive)

                    if resumePoint != nil {
                        Button {
                            play(from: 0)
                        } label: {
                            Label("Start Over", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(details.value == nil)
                    }

                    saveMenu
                }

                if let saveMessage {
                    Label(saveMessage, systemImage: "checkmark.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }

                if isLive {
                    Text("Livestreams are not supported yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if case .failed(let message) = details {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.callout)
                    Button("Try Again") { Task { await load() } }
                } else if details.value == nil {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var saveMenu: some View {
        Menu {
            Button {
                save { try await app.playlists.addToWatchLater(video.videoId, using: $0) }
            } label: {
                Label("Watch Later", systemImage: "clock")
            }
            Button {
                newPlaylistName = ""
                showNewPlaylist = true
            } label: {
                Label("New Playlist…", systemImage: "plus")
            }
            if !playlists.isEmpty {
                Divider()
                ForEach(playlists.filter { !PlaylistStore.isWatchLater($0) }) { playlist in
                    Button(playlist.title) {
                        save { try await app.playlists.add(video.videoId, to: playlist.playlistId, using: $0) }
                    }
                }
            }
        } label: {
            Label("Save", systemImage: "plus.square.on.square")
        }
        .task {
            if let client = app.active?.client {
                playlists = (try? await app.playlists.all(using: client)) ?? []
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create and Save") {
                let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                save { try await app.playlists.createAndAdd(video.videoId, title: name, using: $0) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func save(_ action: @escaping (InvidiousClient) async throws -> Void) {
        guard let client = app.active?.client else { return }
        Task {
            do {
                try await action(client)
                withAnimation { saveMessage = "Saved" }
                playlists = (try? await app.playlists.all(using: client)) ?? playlists
            } catch {
                app.active?.handle(error)
                withAnimation { saveMessage = "Could not save: \(error.localizedDescription)" }
            }
            try? await Task.sleep(for: .seconds(3))
            withAnimation { saveMessage = nil }
        }
    }

    private var channelRow: some View {
        let client = app.active?.client
        let avatarURL = details.value?.authorThumbnails.best(minWidth: 88).flatMap { client?.url(for: $0) }
        return NavigationLink(value: Route.channel(id: video.authorId, name: details.value?.author ?? video.author)) {
            HStack(spacing: 16) {
                ChannelAvatar(channelID: video.authorId, name: video.author, size: 56, url: avatarURL)
                VStack(alignment: .leading, spacing: 2) {
                    Text(details.value?.author ?? video.author)
                        .font(.callout.weight(.medium))
                    if let subs = details.value?.subCountText, !subs.isEmpty {
                        Text("\(subs) subscribers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }

    private var metadata: String {
        var parts: [String] = []
        let loaded = details.value
        if loaded?.liveNow ?? video.liveNow {
            parts.append("Live now")
        }
        if let views = VideoFormatting.viewCount(loaded?.viewCount ?? video.viewCount) {
            parts.append(views)
        }
        if let likes = loaded?.likeCount {
            parts.append("\(VideoFormatting.compact(likes)) likes")
        }
        if let when = loaded?.publishedText ?? video.publishedText ?? VideoFormatting.relativeDate(loaded?.publishedDate ?? video.publishedDate) {
            parts.append(when)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var description: some View {
        if let text = details.value?.description, !text.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Description")
                    .font(.title3.weight(.semibold))
                Button {
                    withAnimation { descriptionExpanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(text)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(descriptionExpanded ? nil : 3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(descriptionExpanded ? "Show less" : "More")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .buttonStyle(.plain)
                .tint(.white)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func load() async {
        guard let client = app.active?.client else { return }
        if details.value == nil { details = .loading }
        do {
            let loaded = try await client.video(id: video.videoId, proxy: app.settings.proxyMedia)
            details = .loaded(loaded)
        } catch {
            app.active?.handle(error)
            details = .failed(error.localizedDescription)
        }
    }

    private func play(from position: TimeInterval) {
        startAt = position
        isPlaying = true
    }
}
