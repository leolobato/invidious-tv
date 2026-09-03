import Foundation
import Testing
@testable import InvidiousKit

@Suite("Search decoding")
struct SearchTests {
    @Test func decodesMixedResults() throws {
        let items = try Fixtures.decode([SearchItem].self, "search")
        #expect(items.count == 20)
        let videos = items.compactMap(\.video)
        let channels = items.compactMap(\.channel)
        #expect(videos.count == 18)
        #expect(channels.count == 1)
        #expect(channels.first?.author == "Every Frame a Painting")
        #expect(channels.first?.subCount ?? 0 > 1_000_000)
        #expect(!(channels.first?.authorThumbnails.isEmpty ?? true))
        let hasPlaylist = items.contains { item in
            if case .playlist(let playlist) = item { return !playlist.playlistId.isEmpty }
            return false
        }
        #expect(hasPlaylist)
    }

    @Test func unknownTypesDoNotFail() throws {
        let json = ##"[{"type":"hashtag","title":"#x"},{"type":"video","videoId":"abc","title":"T"}]"##
        let items = try InvidiousDecoder.make().decode([SearchItem].self, from: Data(json.utf8))
        #expect(items.count == 2)
        #expect(items[1].video?.videoId == "abc")
        guard case .unsupported(let type) = items[0] else {
            Issue.record("expected unsupported")
            return
        }
        #expect(type == "hashtag")
    }

    @Test func decodesSuggestions() throws {
        let response = try Fixtures.decode(SearchSuggestions.self, "search_suggestions")
        #expect(response.query == "every fra")
        #expect(response.suggestions.first == "every frame a painting")
    }
}
