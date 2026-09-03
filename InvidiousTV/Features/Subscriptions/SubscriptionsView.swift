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

@MainActor
@Observable
final class SubscriptionsViewModel {
    private let session: ActiveSession
    private(set) var videos: [VideoSummary] = []
    private(set) var state: LoadState<Void> = .idle
    private var page = 0
    private var reachedEnd = false

    static let pageSize = 40

    init(session: ActiveSession) {
        self.session = session
    }

    func loadIfNeeded() async {
        guard videos.isEmpty, !state.isLoading else { return }
        await loadMore()
    }

    func reload() async {
        page = 0
        reachedEnd = false
        videos = []
        await loadMore()
    }

    func loadMore() async {
        guard !state.isLoading, !reachedEnd else { return }
        state = .loading
        do {
            let next = page + 1
            let result = try await session.client.feed(page: next, maxResults: Self.pageSize)
            let known = Set(videos.map(\.videoId))
            let fresh = result.videos.filter { !known.contains($0.videoId) }
            videos.append(contentsOf: fresh)
            page = next
            if result.videos.count < Self.pageSize || fresh.isEmpty {
                reachedEnd = true
            }
            state = .loaded(())
        } catch {
            session.handle(error)
            state = .failed(error.localizedDescription)
        }
    }
}
