import SwiftUI
import InvidiousKit

/// Home: continue watching, recommendations, latest subscriptions.
struct HomeView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var model: HomeViewModel

    init(session: ActiveSession) {
        self.session = session
        _model = State(initialValue: HomeViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                let continueWatching = app.resume.continueWatching(profile: session.profile.id).compactMap(\.video)
                if !continueWatching.isEmpty {
                    Shelf(title: "Continue Watching", videos: continueWatching)
                }

                switch model.recommended {
                case .idle, .loading:
                    if continueWatching.isEmpty {
                        LoadingView().frame(height: 400)
                    } else {
                        ProgressView().padding(60)
                    }
                case .failed(let message):
                    ErrorView(message: message) { Task { await model.load(force: true) } }
                        .frame(height: 400)
                case .loaded(let videos):
                    if videos.isEmpty {
                        EmptyStateView(title: "Nothing to recommend yet", message: "Watch a few videos and recommendations will appear here.", systemImage: "sparkles")
                            .frame(height: 300)
                    } else {
                        Shelf(title: "Recommended", videos: videos)
                    }
                }

                if let latest = model.latest.value, !latest.isEmpty {
                    Shelf(title: "Latest from Subscriptions", videos: latest)
                }
            }
            .padding(.vertical, 30)
        }
        .task {
            model.onLatestLoaded = { videos in app.updateTopShelf(latest: videos) }
            await model.load(force: false)
        }
        .refreshable {
            await model.load(force: true)
        }
    }
}

@MainActor
@Observable
final class HomeViewModel {
    private let session: ActiveSession
    var recommended: LoadState<[VideoSummary]> = .idle
    var latest: LoadState<[VideoSummary]> = .idle
    private var loadedAt: Date?

    static let cacheLifetime: TimeInterval = 30 * 60
    static let seedCount = 10

    init(session: ActiveSession) {
        self.session = session
    }

    func load(force: Bool) async {
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < Self.cacheLifetime, recommended.value != nil {
            return
        }
        if recommended.value == nil { recommended = .loading }
        let client = session.client

        async let latestTask: FeedPage? = try? client.feed(page: 1, maxResults: 20)
        async let trendingTask: [VideoSummary] = (try? client.trending()) ?? []

        do {
            if session.recentHistory.isEmpty {
                await session.refreshHistory()
            }
            let seedIDs = Array(session.recentHistory.prefix(Self.seedCount))
            let seeds: [[VideoSummary]] = await withTaskGroup(of: (Int, [VideoSummary]).self) { group in
                for (index, id) in seedIDs.enumerated() {
                    group.addTask {
                        let details = try? await client.video(id: id)
                        return (index, details?.recommendedVideos ?? [])
                    }
                }
                var results = Array(repeating: [VideoSummary](), count: seedIDs.count)
                for await (index, list) in group {
                    results[index] = list
                }
                return results
            }
            let trending = await trendingTask
            let feed = HomeFeedBuilder.build(seeds: seeds, watched: session.watchedIDs, fallback: trending)
            recommended = .loaded(feed)
            loadedAt = Date()
        }

        if let page = await latestTask {
            latest = .loaded(page.videos)
            onLatestLoaded?(page.videos)
        }
    }

    /// Lets the app publish the latest uploads to the Top Shelf extension.
    var onLatestLoaded: (([VideoSummary]) -> Void)?
}
