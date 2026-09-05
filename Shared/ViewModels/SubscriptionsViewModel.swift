import Foundation
import Observation
import SwiftUI
import InvidiousKit

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
            let pageVideos = result.allVideos
            let known = Set(videos.map(\.videoId))
            let fresh = pageVideos.filter { !known.contains($0.videoId) }
            videos.append(contentsOf: fresh)
            page = next
            if pageVideos.count < Self.pageSize || fresh.isEmpty {
                reachedEnd = true
            }
            state = .loaded(())
        } catch {
            session.handle(error)
            state = .failed(error.localizedDescription)
        }
    }
}
