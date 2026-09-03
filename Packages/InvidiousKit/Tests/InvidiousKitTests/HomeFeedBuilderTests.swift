import Foundation
import Testing
@testable import InvidiousKit

@Suite("Home feed builder")
struct HomeFeedBuilderTests {
    @Test func interleavesSeedsAndDropsDuplicatesAndWatched() {
        let seedA = ["a1", "a2", "shared", "a3"].map { Fixtures.video($0) }
        let seedB = ["b1", "shared", "watched", "b2"].map { Fixtures.video($0) }
        let result = HomeFeedBuilder.build(seeds: [seedA, seedB], watched: ["watched"], fallback: [], minimum: 0)
        #expect(result.map(\.videoId) == ["a1", "b1", "a2", "shared", "a3", "b2"])
    }

    @Test func padsWithFallbackWhenShort() {
        let seed = [Fixtures.video("a1")]
        let trending = ["t1", "a1", "t2", "t3"].map { Fixtures.video($0) }
        let result = HomeFeedBuilder.build(seeds: [seed], watched: [], fallback: trending, minimum: 3)
        #expect(result.map(\.videoId) == ["a1", "t1", "t2"])
    }

    @Test func emptySeedsUsesFallbackOnly() {
        let trending = ["t1", "t2"].map { Fixtures.video($0) }
        let result = HomeFeedBuilder.build(seeds: [], watched: ["t1"], fallback: trending, minimum: 5)
        #expect(result.map(\.videoId) == ["t2"])
    }

    @Test func skipsUpcomingAndRespectsLimit() {
        let seed = [Fixtures.video("up", upcoming: true)] + (1...10).map { Fixtures.video("v\($0)") }
        let result = HomeFeedBuilder.build(seeds: [seed], watched: [], fallback: [], minimum: 0, limit: 4)
        #expect(result.map(\.videoId) == ["v1", "v2", "v3", "v4"])
    }
}
