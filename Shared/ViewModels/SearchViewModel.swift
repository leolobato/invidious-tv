import Foundation
import Observation
import SwiftUI
import InvidiousKit

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
