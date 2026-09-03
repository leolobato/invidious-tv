import TVServices
import InvidiousKit

/// Shows Continue Watching and the latest subscription uploads on the tvOS home screen.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        completionHandler(makeContent())
    }

    private func makeContent() -> TVTopShelfContent? {
        guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "InvidiousAppGroup") as? String,
              let snapshot = TopShelfSnapshotStore(appGroup: appGroup).load() else {
            return nil
        }

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

    private func makeItem(_ item: TopShelfSnapshot.Item) -> TVTopShelfSectionedItem {
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
