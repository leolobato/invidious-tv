import Foundation
import Testing
@testable import InvidiousKit

@Suite("Stream selection")
struct StreamSelectorTests {
    let video = try! Fixtures.decode(VideoDetails.self, "video")

    @Test func picksHighestAllowedResolution() {
        let selection = StreamSelector.select(video, preferences: StreamPreferences())
        #expect(selection != nil)
        let best = video.adaptiveFormats.filter(\.isVideo).compactMap(\.height).max()
        #expect(selection?.video.height == best)
        #expect(selection?.audio?.isAudio == true)
    }

    @Test func respectsMaxHeight() {
        let selection = StreamSelector.select(video, preferences: StreamPreferences(maxHeight: 720))
        #expect(selection?.video.height ?? 9999 <= 720)
    }

    @Test func prefersCodecOrderAtSameHeight() {
        let prefs = StreamPreferences(maxHeight: 1080, codecPreference: [.avc1], preferHighFrameRate: false)
        let selection = StreamSelector.select(video, preferences: prefs)
        #expect(selection?.video.codec == .avc1)
        #expect(selection?.video.height == 1080)
    }

    @Test func returnsNilWhenNoCodecMatches() {
        let prefs = StreamPreferences(codecPreference: [.hevc])
        #expect(StreamSelector.select(video, preferences: prefs) == nil)
    }

    @Test func listsAvailableHeightsDescending() {
        let heights = StreamSelector.availableHeights(video, preferences: StreamPreferences())
        #expect(heights == heights.sorted(by: >))
        #expect(heights.contains(1080))
    }

    @Test func prefersAACAudio() {
        let audio = StreamSelector.bestAudio(video.adaptiveFormats)
        #expect(audio?.type.contains("mp4a") == true)
    }
}
