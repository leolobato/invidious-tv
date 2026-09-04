import TVServices
import InvidiousKit

/// Shows Continue Watching and the latest subscription uploads on the tvOS home screen.
///
/// The app writes a snapshot into the app group whenever it loads Home or closes the player. When
/// that snapshot is older than `TopShelfSnapshot.refreshInterval`, the extension fetches the
/// subscription feed itself with the profile's credential from the shared keychain, so the shelf
/// stays current even when the app has not been opened for a while.
final class ContentProvider: TVTopShelfContentProvider {
    private static let fetchTimeout: TimeInterval = 8

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "InvidiousAppGroup") as? String else {
            completionHandler(nil)
            return
        }
        let store = TopShelfSnapshotStore(appGroup: appGroup)
        guard let snapshot = store.load() else {
            completionHandler(nil)
            return
        }
        let keychainGroup = (Bundle.main.object(forInfoDictionaryKey: "InvidiousKeychainGroup") as? String)
            .flatMap { $0.isEmpty || $0.hasPrefix(".") ? nil : $0 }

        let handler = CompletionBox(completionHandler)
        Task.detached {
            let refreshed = await ContentProvider.refreshedLatest(for: snapshot, store: store, keychainGroup: keychainGroup)
            handler.call(ContentProvider.makeContent(from: refreshed))
        }
    }

    /// Returns the snapshot with fresh uploads when it is stale and the feed can be fetched in time.
    static func refreshedLatest(for snapshot: TopShelfSnapshot, store: TopShelfSnapshotStore, keychainGroup: String?) async -> TopShelfSnapshot {
        guard Date().timeIntervalSince(snapshot.updatedAt) > TopShelfSnapshot.refreshInterval,
              let account = snapshot.account,
              let credential = try? KeychainSessionStore(accessGroup: keychainGroup).credential(for: account.profileID) else {
            return snapshot
        }
        let client = InvidiousClient(baseURL: account.instanceURL, credential: credential)
        let feed: FeedPage? = await withTimeout(seconds: fetchTimeout) {
            try? await client.feed(page: 1, maxResults: 20)
        }
        guard let feed else { return snapshot }
        var updated = snapshot
        updated.latest = TopShelfSnapshot.latestItems(from: feed.videos, client: client)
        updated.updatedAt = Date()
        store.save(updated)
        return updated
    }

    private static func withTimeout<T: Sendable>(seconds: TimeInterval, _ operation: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func makeContent(from snapshot: TopShelfSnapshot) -> TVTopShelfContent? {
        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []
        if !snapshot.continueWatching.isEmpty {
            let section = TVTopShelfItemCollection(items: snapshot.continueWatching.map(makeItem))
            section.title = "Continue Watching"
            sections.append(section)
        }
        if !snapshot.latest.isEmpty {
            let section = TVTopShelfItemCollection(items: snapshot.latest.map(makeItem))
            section.title = "Latest from Subscriptions"
            sections.append(section)
        }
        guard !sections.isEmpty else { return nil }
        return TVTopShelfSectionedContent(sections: sections)
    }

    private static func makeItem(_ item: TopShelfSnapshot.Item) -> TVTopShelfSectionedItem {
        let shelfItem = TVTopShelfSectionedItem(identifier: item.videoID)
        shelfItem.title = item.title
        shelfItem.imageShape = .hdtv
        if let url = item.imageURL {
            shelfItem.setImageURL(url, for: .screenScale1x)
            shelfItem.setImageURL(url, for: .screenScale2x)
        }
        if let progress = item.progress {
            shelfItem.playbackProgress = progress
        }
        let link = AppLink.video(item.videoID)
        shelfItem.displayAction = TVTopShelfAction(url: link)
        shelfItem.playAction = TVTopShelfAction(url: link)
        return shelfItem
    }
}

/// TVServices hands us a non-Sendable completion handler; it is only invoked once, from the task.
private struct CompletionBox: @unchecked Sendable {
    private let handler: (TVTopShelfContent?) -> Void
    init(_ handler: @escaping (TVTopShelfContent?) -> Void) { self.handler = handler }
    func call(_ content: TVTopShelfContent?) { handler(content) }
}
