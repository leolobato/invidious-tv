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
