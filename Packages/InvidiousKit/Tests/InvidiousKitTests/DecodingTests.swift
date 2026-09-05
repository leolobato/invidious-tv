import Foundation
import Testing
@testable import InvidiousKit

@Suite("API decoding")
struct DecodingTests {
    @Test func decodesTrending() throws {
        let videos = try Fixtures.decode([VideoSummary].self, "trending")
        #expect(!videos.isEmpty)
        let first = videos[0]
        #expect(!first.videoId.isEmpty)
        #expect(!first.title.isEmpty)
        #expect(!first.videoThumbnails.isEmpty)
    }

    @Test func decodesFeedPage() throws {
        let page = try Fixtures.decode(FeedPage.self, "feed")
        #expect(page.videos.count == 40)
        #expect(page.notifications.isEmpty)
        // Feed is chronological, newest first.
        let published = page.videos.compactMap(\.published)
        #expect(published == published.sorted(by: >))
    }

    @Test func feedPageMergesNotificationsNewestFirst() throws {
        let make = { (id: String, published: Int) in
            VideoSummary(videoId: id, title: id, author: "a", authorId: "c", lengthSeconds: 60, published: published)
        }
        let page = FeedPage(
            notifications: [make("n1", 500), make("n2", 300)],
            videos: [make("v1", 400), make("v2", 200), make("v3", 100)]
        )
        #expect(page.allVideos.map(\.videoId) == ["n1", "v1", "n2", "v2", "v3"])
        #expect(FeedPage(videos: []).allVideos.isEmpty)
    }

    @Test func decodesSubscriptions() throws {
        let subs = try Fixtures.decode([SubscribedChannel].self, "subscriptions")
        #expect(subs.count > 100)
        #expect(subs.allSatisfy { $0.authorId.hasPrefix("UC") })
    }

    @Test func decodesHistory() throws {
        let ids = try Fixtures.decode([String].self, "history")
        #expect(ids.count == 1)
    }

    @Test func decodesVideoDetails() throws {
        let video = try Fixtures.decode(VideoDetails.self, "video")
        #expect(video.videoId == "pE8wVKI79zo")
        #expect(!video.adaptiveFormats.isEmpty)
        #expect(!video.recommendedVideos.isEmpty)
        #expect(video.dashUrl?.hasSuffix("/api/manifest/dash/id/pE8wVKI79zo") == true)
        #expect(video.recommendedVideos[0].published != nil)
        let video1080 = video.adaptiveFormats.first { $0.qualityLabel == "1080p60" && $0.codec == .avc1 }
        #expect(video1080?.height == 1080)
        #expect(video1080?.bitrate ?? 0 > 0)
        #expect(video1080?.isVideo == true)
        #expect(video.adaptiveFormats.contains { $0.isAudio })
    }

    @Test func decodesChannelAndVideos() throws {
        let channel = try Fixtures.decode(Channel.self, "channel")
        #expect(channel.authorId == "UCMNEVbszv8ZyvSXoTn3yhpQ")
        #expect(!channel.authorThumbnails.isEmpty)
        #expect(!channel.authorBanners.isEmpty)
        #expect(channel.subCount ?? 0 > 0)

        let page = try Fixtures.decode(ChannelVideosPage.self, "channel_videos")
        #expect(!page.videos.isEmpty)
        #expect(page.continuation?.isEmpty == false)
    }

    @Test func decodesStoryboardsAndStats() throws {
        let boards = try Fixtures.decode(StoryboardsResponse.self, "storyboards")
        #expect(boards.storyboards.first?.width == 106)
        let stats = try Fixtures.decode(InstanceStats.self, "stats")
        #expect(stats.software.name == "invidious")
    }

    @Test func thumbnailSelection() {
        let thumbs = [
            Thumbnail(quality: "maxres", url: "/a", width: 1280, height: 720),
            Thumbnail(quality: "medium", url: "/b", width: 320, height: 180),
            Thumbnail(quality: "sd", url: "/c", width: 640, height: 480),
        ]
        #expect(thumbs.best(maxWidth: 700)?.url == "/c")
        #expect(thumbs.best(maxWidth: 100)?.url == "/b")
        #expect(thumbs.best(maxWidth: 5000)?.url == "/a")
    }
}
