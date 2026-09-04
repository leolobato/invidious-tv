import SwiftUI
import InvidiousKit

struct MobileSearchView: View {
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
            .navigationTitle("Search")
            .searchable(text: $model.query, prompt: "Search, or paste a YouTube link")
            .searchSuggestions {
                ForEach(model.suggestions, id: \.self) { suggestion in
                    Text(suggestion).searchCompletion(suggestion)
                }
            }
            .onSubmit(of: .search) { Task { await submit() } }
            .withMobileRoutes()
        }
        .environment(\.pushRoute) { path.append($0) }
        .task(id: model.query) { await model.queryChanged() }
        .onAppear {
            #if DEBUG
            if let query = ProcessInfo.processInfo.environment["INVIDIOUS_DEBUG_SEARCH"], model.query.isEmpty {
                model.query = query
            }
            #endif
        }
    }

    private func submit() async {
        if let link = model.link {
            switch link {
            case .video:
                if let video = await model.resolveLinkedVideo() { path.append(Route.video(video)) }
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
            VStack(alignment: .leading, spacing: 12) {
                Text("Open link").font(.headline)
                switch link {
                case .video:
                    if let video = model.linkedVideo {
                        MobileVideoCard(video: video)
                    } else if let error = model.linkError {
                        Text(error).foregroundStyle(.secondary)
                    } else {
                        ProgressView().task { _ = await model.resolveLinkedVideo() }
                    }
                case .channel(let id):
                    NavigationLink(value: Route.channel(id: id, name: "")) { Label("Open channel", systemImage: "person.crop.rectangle") }
                case .playlist:
                    Text("Playlists are not supported yet.").foregroundStyle(.secondary)
                }
            }
            .padding(16)
        } else if model.query.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView("Search Invidious", systemImage: "magnifyingglass", description: Text("Find videos and channels, or paste a YouTube link."))
                .padding(.top, 80)
        } else if model.isSearching && model.videos.isEmpty && model.channels.isEmpty {
            ProgressView().padding(40)
        } else if model.videos.isEmpty && model.channels.isEmpty && model.hasSearched {
            ContentUnavailableView.search(text: model.query)
        } else {
            LazyVStack(alignment: .leading, spacing: 20) {
                if !model.channels.isEmpty {
                    ForEach(model.channels) { channel in
                        NavigationLink(value: Route.channel(id: channel.authorId, name: channel.author)) {
                            HStack(spacing: 14) {
                                ChannelAvatar(channelID: channel.authorId, name: channel.author, size: 56,
                                                   url: channel.authorThumbnails.best(minWidth: 176).flatMap { app.active?.client.url(for: $0) })
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(channel.author).font(.body.weight(.medium))
                                    if let subs = channel.subCount {
                                        Text("\(VideoFormatting.compact(subs)) subscribers").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
                MobileVideoList(videos: model.videos) { Task { await model.loadMore() } }
                if model.isSearching { ProgressView().frame(maxWidth: .infinity).padding() }
            }
            .padding(.vertical, 12)
        }
    }
}
