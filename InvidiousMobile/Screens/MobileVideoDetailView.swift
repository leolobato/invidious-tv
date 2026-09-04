import SwiftUI
import InvidiousKit

struct MobileVideoDetailView: View {
    let video: VideoSummary

    @Environment(AppModel.self) private var app
    @State private var details: LoadState<VideoDetails> = .idle
    @State private var playback: PlaybackRequest?
    @State private var descriptionExpanded = false
    @State private var linkedRoute: Route?
    @State private var playlists: [Playlist] = []
    @State private var saveMessage: String?
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                VStack(alignment: .leading, spacing: 12) {
                    Text(details.value?.title ?? video.title)
                        .font(.title3.weight(.semibold))
                    Text(metadata)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    channelRow
                    actions
                    if let saveMessage {
                        Label(saveMessage, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.secondary)
                    }
                    if case .failed(let message) = details {
                        Text(message).foregroundStyle(.red).font(.footnote)
                        Button("Try Again") { Task { await load() } }
                    }
                    description
                }
                .padding(.horizontal, 16)

                if let recommended = details.value?.recommendedVideos, !recommended.isEmpty {
                    Text("Up Next").font(.title3.weight(.semibold)).padding(.horizontal, 16)
                    MobileVideoList(videos: recommended)
                }
                if details.value != nil {
                    CommentsSection(videoID: video.videoId)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: video.videoId) { await load() }
        .fullScreenCover(item: $playback) { request in
            if let session = app.active {
                MobilePlayerView(details: request.details, summary: video, startAt: request.startAt, session: session)
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

    private var isLive: Bool { details.value?.liveNow ?? video.liveNow }

    private var resumePoint: TimeInterval? {
        guard let profile = app.active?.profile.id else { return nil }
        return app.resume.resumePoint(for: video.videoId, profile: profile)
    }

    private var hero: some View {
        let client = app.active?.client
        let thumbs = details.value?.videoThumbnails ?? video.videoThumbnails
        let primary = thumbs.first { $0.quality == "maxresdefault" } ?? thumbs.best(maxWidth: 1280)
        let fallbacks = ["sddefault", "high", "medium"].compactMap { q in thumbs.first { $0.quality == q } }
        return Button {
            play(from: resumePoint ?? 0)
        } label: {
            ZStack {
                RemoteImage(url: primary.flatMap { client?.url(for: $0) }, fallbacks: fallbacks.compactMap { client?.url(for: $0) })
                    .aspectRatio(16 / 9, contentMode: .fill)
                if details.value == nil {
                    ProgressView().tint(.white)
                } else if isLive {
                    Text("Livestreams are not supported yet.")
                        .font(.footnote.weight(.semibold))
                        .padding(8)
                        .background(.black.opacity(0.7), in: Capsule())
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 8)
                }
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .disabled(details.value == nil || isLive)
    }

    private var channelRow: some View {
        let client = app.active?.client
        return NavigationLink(value: Route.channel(id: video.authorId, name: details.value?.author ?? video.author)) {
            HStack(spacing: 12) {
                ChannelAvatar(channelID: video.authorId, name: video.author, size: 40,
                                   url: details.value?.authorThumbnails.best(minWidth: 88).flatMap { client?.url(for: $0) })
                VStack(alignment: .leading, spacing: 2) {
                    Text(details.value?.author ?? video.author).font(.subheadline.weight(.medium))
                    if let subs = details.value?.subCountText, !subs.isEmpty {
                        Text("\(subs) subscribers").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                play(from: resumePoint ?? 0)
            } label: {
                Label(resumePoint.map { "Resume \(VideoFormatting.duration(Int($0)))" } ?? "Play", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(details.value == nil || isLive)
            if resumePoint != nil {
                Button { play(from: 0) } label: { Label("Start Over", systemImage: "arrow.counterclockwise") }
                    .buttonStyle(.bordered)
            }
            Menu {
                Button { save { try await app.playlists.addToWatchLater(video.videoId, using: $0) } } label: { Label("Watch Later", systemImage: "clock") }
                Button { newPlaylistName = ""; showNewPlaylist = true } label: { Label("New Playlist…", systemImage: "plus") }
                if !playlists.isEmpty {
                    Divider()
                    ForEach(playlists.filter { !PlaylistStore.isWatchLater($0) }) { playlist in
                        Button(playlist.title) { save { try await app.playlists.add(video.videoId, to: playlist.playlistId, using: $0) } }
                    }
                }
            } label: {
                Label("Save", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.bordered)
            .task {
                if let client = app.active?.client { playlists = (try? await app.playlists.all(using: client)) ?? [] }
            }
            ShareLink(item: URL(string: "https://www.youtube.com/watch?v=\(video.videoId)")!) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
        .labelStyle(.titleAndIcon)
        .font(.footnote)
    }

    private var metadata: String {
        var parts: [String] = []
        let loaded = details.value
        if loaded?.liveNow ?? video.liveNow { parts.append("Live now") }
        if let views = VideoFormatting.viewCount(loaded?.viewCount ?? video.viewCount) { parts.append(views) }
        if let likes = loaded?.likeCount { parts.append("\(VideoFormatting.compact(likes)) likes") }
        if let when = loaded?.publishedText ?? video.publishedText ?? VideoFormatting.relativeDate(loaded?.publishedDate ?? video.publishedDate) { parts.append(when) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var description: some View {
        if let text = details.value?.description, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                // Links stay tappable because the text is not wrapped in the expand button.
                Text(DescriptionLinks.attributed(text))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .lineLimit(descriptionExpanded ? nil : 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.openURL, OpenURLAction { url in
                        guard let link = YouTubeLink.parse(url.absoluteString), let client = app.active?.client else {
                            return .systemAction
                        }
                        Task {
                            if let route = await LinkRouter.route(for: link, client: client) {
                                linkedRoute = route
                            }
                        }
                        return .handled
                    })
                Button {
                    withAnimation { descriptionExpanded.toggle() }
                } label: {
                    Text(descriptionExpanded ? "Show less" : "More")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .navigationDestination(item: $linkedRoute) { route in
                MobileRouteDestination(route: route)
            }
        }
    }

    private func load() async {
        guard let client = app.active?.client else { return }
        if details.value == nil { details = .loading }
        do {
            details = .loaded(try await client.video(id: video.videoId, proxy: app.settings.proxyMedia))
        } catch {
            app.active?.handle(error)
            details = .failed(error.localizedDescription)
        }
    }

    private func play(from position: TimeInterval) {
        guard let loaded = details.value else { return }
        playback = PlaybackRequest(details: loaded, startAt: position)
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
}
