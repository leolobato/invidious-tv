import SwiftUI
import InvidiousKit

/// Search tab: system keyboard with live suggestions, results as channel shelf plus video grid.
struct SearchView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var model: SearchViewModel
    @State private var path = NavigationPath()

    init(session: ActiveSession) {
        self.session = session
        _model = State(initialValue: SearchViewModel(session: session))
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            ScrollView {
                content
            }
            .searchable(text: $model.query, prompt: "Search videos and channels, or paste a YouTube link")
            .searchSuggestions {
                ForEach(model.suggestions, id: \.self) { suggestion in
                    Text(suggestion).searchCompletion(suggestion)
                }
            }
            .onSubmit(of: .search) {
                Task { await submit() }
            }
            .withRoutes()
        }
        .task(id: model.query) {
            await model.queryChanged()
        }
        .onAppear {
            #if DEBUG
            if let query = ProcessInfo.processInfo.environment["INVIDIOUS_DEBUG_SEARCH"], model.query.isEmpty {
                model.query = query
            }
            #endif
        }
    }

    /// Submit opens a pasted link directly, otherwise runs the search.
    private func submit() async {
        if let link = model.link {
            switch link {
            case .video:
                if let video = await model.resolveLinkedVideo() {
                    path.append(Route.video(video))
                }
            case .channel(let id):
                path.append(Route.channel(id: id, name: ""))
            case .playlist:
                await model.search()
            }
        } else {
            await model.search()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let link = model.link {
            linkContent(link)
        } else if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyStateView(title: "Search Invidious", message: "Find videos and channels on YouTube through your instance.", systemImage: "magnifyingglass")
                .frame(minHeight: 500)
        } else if model.isSearching && model.videos.isEmpty && model.channels.isEmpty {
            LoadingView().frame(minHeight: 500)
        } else if let error = model.errorMessage, model.videos.isEmpty {
            ErrorView(message: error) { Task { await model.search() } }
                .frame(minHeight: 500)
        } else if model.videos.isEmpty && model.channels.isEmpty && model.hasSearched {
            EmptyStateView(title: "No results", message: "Nothing matched \"\(model.query)\".", systemImage: "magnifyingglass")
                .frame(minHeight: 500)
        } else {
            LazyVStack(alignment: .leading, spacing: 30) {
                if !model.channels.isEmpty {
                    channelShelf
                }
                VideoGrid(videos: model.videos) {
                    Task { await model.loadMore() }
                }
                if model.isSearching {
                    ProgressView().padding(40)
                }
            }
        }
    }

    @ViewBuilder
    private func linkContent(_ link: YouTubeLink) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Open link")
                .font(.title3.weight(.semibold))
            switch link {
            case .video:
                if let video = model.linkedVideo {
                    VideoCard(video: video)
                        .frame(width: 440)
                } else if let error = model.linkError {
                    Text(error).foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .task { _ = await model.resolveLinkedVideo() }
                }
            case .channel(let id):
                NavigationLink(value: Route.channel(id: id, name: "")) {
                    Label("Open channel", systemImage: "person.crop.rectangle")
                }
            case .playlist:
                Text("Playlists are not supported yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 40)
    }

    private var channelShelf: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Channels")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(model.channels) { channel in
                        SearchChannelCard(channel: channel)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }
}

/// Channel result with avatar, name and counts.
struct SearchChannelCard: View {
    let channel: SearchChannel

    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink(value: Route.channel(id: channel.authorId, name: channel.author)) {
            VStack(spacing: 14) {
                ChannelAvatar(
                    channelID: channel.authorId,
                    name: channel.author,
                    size: 140,
                    url: channel.authorThumbnails.best(minWidth: 176).flatMap { app.active?.client.url(for: $0) }
                )
                Text(channel.author)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 300)
            .padding(.vertical, 20)
            .padding(.horizontal, 10)
        }
        .buttonStyle(.card)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let subs = channel.subCount { parts.append("\(VideoFormatting.compact(subs)) subscribers") }
        if let count = channel.videoCount, count > 0 { parts.append("\(VideoFormatting.compact(count)) videos") }
        return parts.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class SearchViewModel {
    private let session: ActiveSession

    var query = ""
    private(set) var suggestions: [String] = []
    private(set) var videos: [VideoSummary] = []
    private(set) var channels: [SearchChannel] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false
    private(set) var errorMessage: String?

    /// Set when the query is a YouTube link rather than a search term.
    var link: YouTubeLink? { YouTubeLink.parse(query) }
    private(set) var linkedVideo: VideoSummary?
    private(set) var linkError: String?

    private var searchedQuery = ""
    private var page = 0
    private var reachedEnd = false
    private var searchTask: Task<Void, Never>?

    static let suggestionDelay: Duration = .milliseconds(250)
    static let searchDelay: Duration = .milliseconds(700)

    init(session: ActiveSession) {
        self.session = session
    }

    /// Called whenever the text changes: refresh suggestions, then search after a pause in typing.
    func queryChanged() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        linkedVideo = nil
        linkError = nil
        guard !text.isEmpty, link == nil else {
            suggestions = []
            clearResults()
            return
        }
        try? await Task.sleep(for: Self.suggestionDelay)
        guard !Task.isCancelled else { return }
        if let fetched = try? await session.client.searchSuggestions(query: text) {
            suggestions = Array(fetched.prefix(8))
        }
        try? await Task.sleep(for: Self.searchDelay)
        guard !Task.isCancelled, text != searchedQuery else { return }
        await search()
    }

    func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        searchTask?.cancel()
        searchedQuery = text
        page = 0
        reachedEnd = false
        videos = []
        channels = []
        errorMessage = nil
        await loadMore()
        hasSearched = true
    }

    func loadMore() async {
        guard !isSearching, !reachedEnd, !searchedQuery.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        let next = page + 1
        do {
            let items = try await session.client.search(query: searchedQuery, page: next)
            let knownVideos = Set(videos.map(\.videoId))
            let knownChannels = Set(channels.map(\.authorId))
            let newVideos = items.compactMap(\.video).filter { !knownVideos.contains($0.videoId) }
            let newChannels = items.compactMap(\.channel).filter { !knownChannels.contains($0.authorId) }
            videos.append(contentsOf: newVideos)
            channels.append(contentsOf: newChannels)
            page = next
            if items.isEmpty || (newVideos.isEmpty && newChannels.isEmpty) {
                reachedEnd = true
            }
        } catch {
            session.handle(error)
            errorMessage = error.localizedDescription
            reachedEnd = true
        }
    }

    /// Loads the video behind a pasted link so it can be shown and opened.
    func resolveLinkedVideo() async -> VideoSummary? {
        guard case .video(let id, _) = link else { return nil }
        if let linkedVideo, linkedVideo.videoId == id { return linkedVideo }
        do {
            let details = try await session.client.video(id: id)
            linkedVideo = details.summary
            return details.summary
        } catch {
            linkError = "Could not open that link: \(error.localizedDescription)"
            return nil
        }
    }

    private func clearResults() {
        searchTask?.cancel()
        searchedQuery = ""
        videos = []
        channels = []
        hasSearched = false
        errorMessage = nil
    }
}
