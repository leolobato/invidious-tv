import SwiftUI
import InvidiousKit

/// Chronological feed of subscribed channels.
struct SubscriptionsView: View {
    let session: ActiveSession

    @State private var model: SubscriptionsViewModel

    init(session: ActiveSession) {
        self.session = session
        _model = State(initialValue: SubscriptionsViewModel(session: session))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading where model.videos.isEmpty:
                LoadingView()
            case .failed(let message) where model.videos.isEmpty:
                ErrorView(message: message) { Task { await model.reload() } }
            default:
                if model.videos.isEmpty {
                    EmptyStateView(title: "No videos yet", message: "Subscribe to channels on your Invidious instance and their uploads will show up here.", systemImage: "rectangle.stack")
                } else {
                    ScrollView {
                        VideoGrid(videos: model.videos) {
                            Task { await model.loadMore() }
                        }
                        if model.state.isLoading {
                            ProgressView().padding(40)
                        }
                    }
                }
            }
        }
        .task { await model.loadIfNeeded() }
        .refreshable { await model.reload() }
    }
}
