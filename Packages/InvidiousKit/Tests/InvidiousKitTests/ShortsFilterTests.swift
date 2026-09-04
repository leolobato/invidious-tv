import Foundation
import Testing
@testable import InvidiousKit

@Suite("Shorts filter")
struct ShortsFilterTests {
    @Test func detectsByLengthAndTag() {
        #expect(ShortsFilter.isLikelyShort(Fixtures.video("a", length: 45)))
        #expect(!ShortsFilter.isLikelyShort(Fixtures.video("b", length: 600)))
        var tagged = Fixtures.video("c", length: 120)
        tagged.title = "Cool trick #shorts"
        #expect(ShortsFilter.isLikelyShort(tagged))
        var live = Fixtures.video("d", length: 0)
        live.liveNow = true
        #expect(!ShortsFilter.isLikelyShort(live))
        // Unknown length (0) without a tag is not a Short.
        #expect(!ShortsFilter.isLikelyShort(Fixtures.video("e", length: 0)))
    }

    @Test func filtersList() {
        let list = [Fixtures.video("a", length: 30), Fixtures.video("b", length: 300)]
        #expect(ShortsFilter.removingShorts(list).map(\.videoId) == ["b"])
    }
}
