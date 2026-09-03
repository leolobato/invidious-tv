import Foundation
import Observation
import SwiftUI
import InvidiousKit

@MainActor
@Observable
final class ChannelsViewModel {
    private let session: ActiveSession
    private(set) var state: LoadState<[SubscribedChannel]> = .idle
    /// Most recent upload per channel, derived from the subscription feed.
    private(set) var latestUpload: [String: Date] = [:]
    private(set) var isLoadingRecent = false
    private var recentLoadedAt: Date?

    /// Feed pages scanned for the recent-uploads sort.
    static let recentFeedPages = 5

    init(session: ActiveSession) {
        self.session = session
    }

    func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await session.client.subscriptions())
        } catch {
            session.handle(error)
            state = .failed(error.localizedDescription)
        }
    }

    func loadRecentUploads() async {
        if let recentLoadedAt, Date().timeIntervalSince(recentLoadedAt) < 10 * 60 { return }
        guard !isLoadingRecent else { return }
        isLoadingRecent = true
        defer { isLoadingRecent = false }
        var latest = latestUpload
        for page in 1...Self.recentFeedPages {
            guard let feed = try? await session.client.feed(page: page, maxResults: 40) else { break }
            for video in feed.videos {
                guard let date = video.publishedDate else { continue }
                if let known = latest[video.authorId], known >= date { continue }
                latest[video.authorId] = date
            }
            latestUpload = latest
            if feed.videos.count < 40 { break }
        }
        recentLoadedAt = Date()
    }

    func sorted(_ channels: [SubscribedChannel], by order: ChannelSortOrder) -> [SubscribedChannel] {
        switch order {
        case .nameAscending:
            return channels.sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
        case .nameDescending:
            return channels.sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedDescending }
        case .recentUploads:
            return channels.sorted { lhs, rhs in
                switch (latestUpload[lhs.authorId], latestUpload[rhs.authorId]) {
                case let (l?, r?) where l != r:
                    return l > r
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                default:
                    return lhs.author.localizedCaseInsensitiveCompare(rhs.author) == .orderedAscending
                }
            }
        }
    }
}
