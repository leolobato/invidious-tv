import SwiftUI
import InvidiousKit

struct MobileHomeView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var model: HomeViewModel

    init(session: ActiveSession) {
        self.session = session
        _model = State(initialValue: HomeViewModel(session: session))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                let continueWatching = app.resume.continueWatching(profile: session.profile.id).compactMap(\.video)
                if !continueWatching.isEmpty {
                    MobileShelf(title: "Continue Watching", videos: continueWatching)
                }
                switch model.recommended {
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                case .failed(let message):
                    ErrorView(message: message) { Task { await model.load(force: true) } }
                        .frame(height: 300)
                case .loaded(let videos):
                    if !videos.isEmpty {
                        Text("Recommended")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 16)
                        MobileVideoList(videos: videos)
                    }
                }
                if let latest = model.latest.value, !latest.isEmpty {
                    MobileShelf(title: "Latest from Subscriptions", videos: latest)
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Home")
        .profileToolbar(session: session)
        .task {
            model.onLatestLoaded = { videos in app.updateTopShelf(latest: videos) }
            await model.load(force: false)
        }
        .refreshable { await model.load(force: true) }
    }
}
