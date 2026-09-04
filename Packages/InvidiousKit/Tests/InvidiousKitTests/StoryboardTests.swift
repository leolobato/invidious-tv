import Foundation
import Testing
@testable import InvidiousKit

@Suite("Storyboards")
struct StoryboardTests {
    let vtt = """
    WEBVTT

    00:00:00.000 --> 00:00:05.000
    https://i.ytimg.com/sb/ID/M0.jpg?sqp=x#xywh=0,0,160,90

    00:00:05.000 --> 00:00:10.000
    https://i.ytimg.com/sb/ID/M0.jpg?sqp=x#xywh=160,0,160,90

    01:00:10.000 --> 01:00:15.000
    /sb/ID/M1.jpg#xywh=0,90,160,90
    """

    @Test func parsesCues() {
        let track = StoryboardTrack.parse(webVTT: vtt, relativeTo: URL(string: "http://192.168.1.10:3000"))
        #expect(track.cues.count == 3)
        #expect(track.cues[1].x == 160)
        #expect(track.cues[2].start == 3610)
        #expect(track.cues[2].imageURL.absoluteString == "http://192.168.1.10:3000/sb/ID/M1.jpg")
    }

    @Test func findsCueForTime() {
        let track = StoryboardTrack.parse(webVTT: vtt, relativeTo: URL(string: "http://192.168.1.10:3000"))
        #expect(track.cue(at: 7)?.x == 160)
        #expect(track.cue(at: 0)?.x == 0)
        #expect(track.cue(at: 3000)?.start == 3610)
    }

    @Test func parsesTimestamps() {
        #expect(StoryboardTrack.parseTimestamp("00:01:02.500") == 62.5)
        #expect(StoryboardTrack.parseTimestamp("01:02.000") == 62)
        #expect(StoryboardTrack.parseTimestamp("bad") == nil)
    }
}
