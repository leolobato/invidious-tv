import Foundation
import Testing
@testable import InvidiousKit

@Suite("YouTube links")
struct YouTubeLinkTests {
    @Test func parsesVideoLinks() {
        #expect(YouTubeLink.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ") == .video(id: "dQw4w9WgXcQ", startAt: nil))
        #expect(YouTubeLink.parse("https://youtu.be/dQw4w9WgXcQ?t=42") == .video(id: "dQw4w9WgXcQ", startAt: 42))
        #expect(YouTubeLink.parse("youtube.com/shorts/dQw4w9WgXcQ") == .video(id: "dQw4w9WgXcQ", startAt: nil))
        #expect(YouTubeLink.parse("https://m.youtube.com/watch?feature=share&v=dQw4w9WgXcQ&t=1m30s") == .video(id: "dQw4w9WgXcQ", startAt: 90))
        #expect(YouTubeLink.parse("http://10.0.1.9:3001/watch?v=dQw4w9WgXcQ") == .video(id: "dQw4w9WgXcQ", startAt: nil))
        #expect(YouTubeLink.parse("dQw4w9WgXcQ") == .video(id: "dQw4w9WgXcQ", startAt: nil))
    }

    @Test func parsesChannelsAndPlaylists() {
        #expect(YouTubeLink.parse("https://www.youtube.com/channel/UCjFqcJQXGZ6T6sxyFB-5i6A") == .channel(id: "UCjFqcJQXGZ6T6sxyFB-5i6A"))
        #expect(YouTubeLink.parse("https://www.youtube.com/playlist?list=PL123") == .playlist(id: "PL123"))
    }

    @Test func rejectsPlainQueries() {
        #expect(YouTubeLink.parse("every frame a painting") == nil)
        #expect(YouTubeLink.parse("lego") == nil)
        #expect(YouTubeLink.parse("") == nil)
        #expect(YouTubeLink.parse("https://example.com/page") == nil)
    }

    @Test func parsesStartTimes() {
        #expect(YouTubeLink.parseStart("90") == 90)
        #expect(YouTubeLink.parseStart("1h2m3s") == 3723)
        #expect(YouTubeLink.parseStart("2m") == 120)
        #expect(YouTubeLink.parseStart("abc") == nil)
    }
}
