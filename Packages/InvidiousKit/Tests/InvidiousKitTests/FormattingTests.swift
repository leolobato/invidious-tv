import Foundation
import Testing
@testable import InvidiousKit

@Suite("Formatting")
struct FormattingTests {
    @Test func durations() {
        #expect(VideoFormatting.duration(65) == "1:05")
        #expect(VideoFormatting.duration(3661) == "1:01:01")
        #expect(VideoFormatting.duration(0) == "")
    }

    @Test func compactCounts() {
        #expect(VideoFormatting.compact(987) == "987")
        #expect(VideoFormatting.compact(43_000) == "43K")
        #expect(VideoFormatting.compact(1_250_000) == "1.3M")
        #expect(VideoFormatting.viewCount(nil) == nil)
        #expect(VideoFormatting.viewCount(2_000) == "2K views")
    }
}
