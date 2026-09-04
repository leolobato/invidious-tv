import Foundation
import Observation
import InvidiousKit

/// The account's watch history, newest first. Invidious only returns video IDs, so each page is
/// resolved to video summaries a few at a time, reusing resume snapshots when available.
@MainActor
@Observable
final class HistoryViewModel {
    static let pageSize = 20
    private static let concurrentFetches = 4

    private(set) var videos: [VideoSummary] = []
    private(set) var state: LoadState<Void> = .idle
    private(set) var isLoadingMore = false
    private(set) var hasMore = true
    private(set) var actionError: String?

    private let session: ActiveSession
    private let resume: ResumeStore
    private var nextPage = 1
    /// IDs the server returned that could not be resolved (deleted or private videos).
    private var unresolved: Set<String> = []
    private var cache: [String: VideoSummary] = [:]

    init(session: ActiveSession, resume: ResumeStore) {
        self.session = session
        self.resume = resume
    }

    func load(force: Bool) async {
        if !force, state.value != nil { return }
        if videos.isEmpty { state = .loading }
        nextPage = 1
        hasMore = true
        do {
            let page = try await fetchPage(1)
            videos = page
            nextPage = 2
            state = .loaded(())
        } catch {
            session.handle(error)
            state = .failed(error.localizedDescription)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, state.value != nil else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await fetchPage(nextPage)
            let known = Set(videos.map(\.videoId))
            videos.append(contentsOf: page.filter { !known.contains($0.videoId) })
            nextPage += 1
        } catch {
            session.handle(error)
            actionError = error.localizedDescription
        }
    }

    func remove(_ video: VideoSummary) async {
        videos.removeAll { $0.videoId == video.videoId }
        do {
            try await session.unmarkWatched(video.videoId)
        } catch {
            actionError = error.localizedDescription
            await load(force: true)
        }
    }

    func clear() async {
        do {
            try await session.clearHistory()
            videos = []
            hasMore = false
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Fetching

    private func fetchPage(_ page: Int) async throws -> [VideoSummary] {
        let ids = try await session.client.history(page: page, maxResults: Self.pageSize)
        if ids.count < Self.pageSize { hasMore = false }
        let pending = ids.filter { cache[$0] == nil && !unresolved.contains($0) }
        for id in pending {
            if let snapshot = resume.positions[session.profile.id]?[id]?.video {
                cache[id] = snapshot
            }
        }
        let toFetch = pending.filter { cache[$0] == nil }
        let client = session.client
        let fetched: [(String, VideoSummary?)] = await withTaskGroup(of: (String, VideoSummary?).self) { group in
            var results: [(String, VideoSummary?)] = []
            var iterator = toFetch.makeIterator()
            var inFlight = 0
            func addNext() {
                guard let id = iterator.next() else { return }
                inFlight += 1
                group.addTask { (id, try? await client.video(id: id).summary) }
            }
            for _ in 0..<Self.concurrentFetches { addNext() }
            while inFlight > 0, let result = await group.next() {
                inFlight -= 1
                results.append(result)
                addNext()
            }
            return results
        }
        for (id, summary) in fetched {
            if let summary { cache[id] = summary } else { unresolved.insert(id) }
        }
        return ids.compactMap { cache[$0] }
    }
}
