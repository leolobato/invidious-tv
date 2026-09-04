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
        #expect(entry.indexId == "9357DBC5AE5C614")
        #expect(entry.video.videoId == "EAB9807C27D")
        #expect(entry.id == entry.indexId)
        #expect(playlist.isInvidiousPlaylist)
    }

    @Test func decodesChannelPlaylists() throws {
        let page = try Fixtures.decode(ChannelPlaylistsPage.self, "channel_playlists")
        #expect(page.playlists.count == 2)
        #expect(page.continuation == "4qmFsgKsample")
        let first = page.playlists[0]
        #expect(first.title == "Sample Series")
        #expect(first.videoCount == 143)
        #expect(first.coverVideoID == "EAB9807C27D")
        #expect(page.playlists[1].coverVideoID == nil)
    }

    @Test func youTubePlaylistIsReadOnly() throws {
        let json = #"{"type":"playlist","title":"Series","playlistId":"PLabc","author":"Channel","videoCount":3,"isListed":true,"videos":[]}"#
        let playlist = try InvidiousDecoder.make().decode(Playlist.self, from: Data(json.utf8))
        #expect(!playlist.isInvidiousPlaylist)
    }
}
