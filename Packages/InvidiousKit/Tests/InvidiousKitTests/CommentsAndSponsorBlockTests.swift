import Foundation
import Testing
@testable import InvidiousKit

@Suite("Comments and SponsorBlock")
struct CommentsAndSponsorBlockTests {
    @Test func decodesComments() throws {
        let page = try Fixtures.decode(CommentsPage.self, "comments")
        #expect(page.commentCount == 3532)
        #expect(page.comments.count == 20)
        #expect(page.continuation?.isEmpty == false)
        let first = page.comments[0]
        #expect(first.author.hasPrefix("@"))
        #expect(first.likeCount == 20000)
        #expect(first.replies?.replyCount == 55)
        #expect(!first.content.isEmpty)
    }

    @Test func parsesSegmentsSortedAndSkippableOnly() throws {
        let json = """
        [{"category":"outro","actionType":"skip","segment":[576.3,596.1],"UUID":"b"},
         {"category":"intro","actionType":"skip","segment":[0,0.259],"UUID":"a"},
         {"category":"sponsor","actionType":"mute","segment":[10,20],"UUID":"c"}]
        """
        let segments = try SponsorBlockClient.parse(Data(json.utf8))
        #expect(segments.map(\.UUID) == ["a", "b"])
        #expect(segments[1].end == 596.1)
        #expect(segments[0].categoryLabel == "intro")
    }
}
