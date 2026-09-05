import SwiftUI
import InvidiousKit

/// Video page: play or resume, metadata, description, up next.
struct VideoDetailView: View {
    let video: VideoSummary

    @Environment(AppModel.self) private var app
    @State private var details: LoadState<VideoDetails> = .idle
    @State private var playback: PlaybackRequest?
    @State private var showDescription = false
    @Environment(\.pushRoute) private var pushRoute
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
                if details.value != nil {
                    CommentsSection(videoID: video.videoId)
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
        .fullScreenCover(item: $playback) { request in
            if let session = app.active {
                PlayerView(details: request.details, summary: video, startAt: request.startAt, session: session)
            }
        }
        .fullScreenCover(isPresented: $showDescription) {
            DescriptionSheet(title: details.value?.title ?? video.title, text: details.value?.description ?? "")
        }
        #if DEBUG
        .onChange(of: details.value?.videoId) { _, id in
            // `INVIDIOUS_DEBUG_DESCRIPTION=1` opens the description sheet once the video has loaded.
            if id != nil, ProcessInfo.processInfo.environment["INVIDIOUS_DEBUG_DESCRIPTION"] == "1" {
                showDescription = true
            }
        }
        #endif
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
            ZStack(alignment: .bottomTrailing) {
                RemoteImage(url: primary.flatMap { client?.url(for: $0) }, fallbacks: fallbacks.compactMap { client?.url(for: $0) })
                    .aspectRatio(16 / 9, contentMode: .fill)
                if isLive {
                    durationBadge("LIVE", color: .red)
                } else if let length = details.value?.lengthSeconds ?? (video.lengthSeconds > 0 ? video.lengthSeconds : nil), length > 0 {
                    durationBadge(VideoFormatting.duration(length), color: .black.opacity(0.75))
                }
            }
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

    private func durationBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color, in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.white)
            .padding(16)
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
                // The preview stays three lines tall; a focused button that grew to the full text
                // would scroll the page to its bottom. Selecting it opens the whole description.
                Button {
                    showDescription = true
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(text)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("More")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                }
                .buttonStyle(.plain)
                .tint(.white)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))

                // The remote cannot tap inside the text, so YouTube links become buttons.
                let links = DescriptionLinks.inAppLinks(in: text)
                if !links.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            ForEach(links, id: \.url) { item in
                                Button {
                                    guard let client = app.active?.client else { return }
                                    Task {
                                        if let route = await LinkRouter.route(for: item.link, client: client) {
                                            pushRoute(route)
                                        }
                                    }
                                } label: {
                                    Label(DescriptionLinks.label(for: item.url, link: item.link), systemImage: "link")
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(.vertical, 20)
                    }
                    .scrollClipDisabled()
                }
            }
        }
    }

    private func load() async {
        guard let client = app.active?.client else { return }
        if details.value == nil { details = .loading }
        do {
            let loaded = try await client.video(id: video.videoId, proxy: app.settings.proxyMedia)
            details = .loaded(loaded)
            app.videoMetadata.remember(loaded)
        } catch {
            app.active?.handle(error)
            details = .failed(error.localizedDescription)
        }
    }

    private func play(from position: TimeInterval) {
        guard let loaded = details.value else { return }
        playback = PlaybackRequest(details: loaded, startAt: position)
    }
}

/// Full-screen, scrollable description. Each paragraph is focusable so the remote scrolls through
/// the text; Menu closes the sheet.
struct DescriptionSheet: View {
    let title: String
    let text: String

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedParagraph: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .padding(.bottom, 20)
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph)
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(
                            focusedParagraph == index ? Color.white.opacity(0.1) : .clear,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .focusable()
                        .focused($focusedParagraph, equals: index)
                }
                Text("Press Menu to go back")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            }
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 120)
            .padding(.vertical, 80)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { focusedParagraph = 0 }
    }

    /// Paragraphs of the description; long ones are split at sentence ends so each focus step
    /// moves a readable amount.
    private var paragraphs: [String] {
        Self.paragraphs(of: text)
    }

    static func paragraphs(of text: String, maxLength: Int = 500) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .flatMap { chunk($0, maxLength: maxLength) }
    }

    private static func chunk(_ paragraph: String, maxLength: Int) -> [String] {
        guard paragraph.count > maxLength else { return [paragraph] }
        var result: [String] = []
        var current = ""
        paragraph.enumerateSubstrings(in: paragraph.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            if !current.isEmpty, current.count + sentence.count > maxLength {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            current += sentence
        }
        if !current.isEmpty { result.append(current.trimmingCharacters(in: .whitespaces)) }
        return result.isEmpty ? [paragraph] : result
    }
}
