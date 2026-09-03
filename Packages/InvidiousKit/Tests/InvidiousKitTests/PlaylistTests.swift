import Foundation
import Testing
@testable import InvidiousKit

@Suite("Playlists")
struct PlaylistTests {
    @Test func decodesPlaylistList() throws {
        let playlists = try Fixtures.decode([Playlist].self, "playlists")
        #expect(playlists.count > 10)
        let first = playlists[0]
        #expect(!first.playlistId.isEmpty)
        #expect(!first.title.isEmpty)
        #expect(first.videoCount == first.videos.count || first.videos.count == 100)
        #expect(first.coverThumbnails.isEmpty == first.videos.isEmpty)
    }

    @Test func decodesPlaylistPage() throws {
        let playlist = try Fixtures.decode(Playlist.self, "playlist")
        #expect(playlist.videoCount == 207)
        #expect(playlist.videos.count == 100)
        let entry = playlist.videos[0]
        #expect(entry.index == 0)
        #expect(entry.indexId == "61AFC6B64D41EB7")
        #expect(entry.video.videoId == "NPM3QmDnjIU")
        #expect(entry.id == entry.indexId)
    }
}
