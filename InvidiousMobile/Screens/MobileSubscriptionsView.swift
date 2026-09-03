import SwiftUI
import InvidiousKit

struct MobileSubscriptionsView: View {
    let session: ActiveSession

    @State private var model: SubscriptionsViewModel

    init(session: ActiveSession) {
        self.session = session
        _model = State(initialValue: SubscriptionsViewModel(session: session))
    }

    var body: some View {
        Group {
            if model.videos.isEmpty, model.state.isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if case .failed(let message) = model.state, model.videos.isEmpty {
                ErrorView(message: message) { Task { await model.reload() } }
            } else if model.videos.isEmpty {
                EmptyStateView(title: "No videos yet", message: "Subscribe to channels on your Invidious instance and their uploads will show up here.", systemImage: "rectangle.stack")
            } else {
                ScrollView {
                    MobileVideoList(videos: model.videos) {
                        Task { await model.loadMore() }
                    }
                    .padding(.vertical, 12)
                    if model.state.isLoading {
                        ProgressView().padding()
                    }
                }
            }
        }
        .navigationTitle("Subscriptions")
        .task { await model.loadIfNeeded() }
        .refreshable { await model.reload() }
    }
}
