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

    private func audio(_ itag: String, bitrate: Int, mime: String = "audio/mp4; codecs=\"mp4a.40.2\"", xtags: String?) throws -> AdaptiveFormat {
        var url = "https://rr1.googlevideo.com/videoplayback?itag=\(itag)&id=abc"
        if let xtags { url += "&xtags=" + xtags.addingPercentEncoding(withAllowedCharacters: .alphanumerics)! }
        let json = """
        {"url": "\(url)", "itag": "\(itag)", "type": "\(mime.replacingOccurrences(of: "\"", with: "\\\""))", "bitrate": "\(bitrate)"}
        """
        return try JSONDecoder().decode(AdaptiveFormat.self, from: Data(json.utf8))
    }

    @Test func parsesAudioTracksFromXtags() throws {
        let original = try audio("140", bitrate: 130_000, xtags: "acont=original:lang=en-US")
        #expect(original.audioTrack == AudioTrack(languageCode: "en-US", kind: .original))
        #expect(original.hasDRC == false)
        let drc = try audio("140", bitrate: 130_100, xtags: "acont=original:drc=1:lang=en-US")
        #expect(drc.audioTrack == original.audioTrack)
        #expect(drc.hasDRC)
        let dubbed = try audio("140", bitrate: 130_600, xtags: "acont=dubbed-auto:lang=pt-BR")
        #expect(dubbed.audioTrack?.kind == .autoDubbed)
        #expect(dubbed.audioTrack?.displayName.contains("auto-dubbed") == true)
        let plain = try audio("140", bitrate: 130_000, xtags: nil)
        #expect(plain.audioTrack == nil)
    }

    @Test func defaultAudioIsTheOriginalLanguageNotTheLoudestDub() throws {
        let formats = [
            try audio("140", bitrate: 130_600, xtags: "acont=dubbed-auto:lang=pt-BR"),
            try audio("140", bitrate: 130_559, xtags: "acont=original:drc=1:lang=en-US"),
            try audio("140", bitrate: 130_450, xtags: "acont=original:lang=en-US"),
            try audio("251", bitrate: 140_000, mime: "audio/webm; codecs=\"opus\"", xtags: "acont=original:lang=en-US"),
            try audio("140", bitrate: 130_700, xtags: "acont=dubbed-auto:lang=de-DE"),
        ]
        let chosen = try #require(StreamSelector.bestAudio(formats))
        #expect(chosen.audioTrack?.isOriginal == true)
        #expect(chosen.hasDRC == false)
        #expect(chosen.type.contains("mp4a"))

        let german = try #require(StreamSelector.bestAudio(formats, track: AudioTrack(languageCode: "de-DE", kind: .autoDubbed)))
        #expect(german.audioTrack?.languageCode == "de-DE")

        let tracks = StreamSelector.audioTracks(formats)
        #expect(tracks.count == 3)
        #expect(tracks.first?.isOriginal == true)
    }

    @Test func unlabeledAudioStillPlays() throws {
        let formats = [try audio("140", bitrate: 100, xtags: nil), try audio("251", bitrate: 200, mime: "audio/webm; codecs=\"opus\"", xtags: nil)]
        #expect(StreamSelector.bestAudio(formats)?.itag == "140")
        #expect(StreamSelector.audioTracks(formats).isEmpty)
    }
}
