import Foundation
import Testing
@testable import InvidiousKit

@Suite("Stores")
@MainActor
struct StoreTests {
    func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func profileStoreRoundTrips() {
        let dir = tempDir()
        let store = ProfileStore(directory: dir)
        let profile = Profile(name: "Leo Lobato", username: "leo", instanceURL: URL(string: "http://10.0.1.9:3001")!, colorIndex: 2, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        store.add(profile)
        store.markUsed(id: profile.id)

        let reloaded = ProfileStore(directory: dir)
        #expect(reloaded.profiles == [profile])
        #expect(reloaded.lastUsedProfile == profile)
        #expect(profile.initials == "LL")

        reloaded.remove(id: profile.id)
        #expect(reloaded.profiles.isEmpty)
        #expect(reloaded.lastUsedProfileID == nil)
    }

    @Test func nextColorSkipsUsedOnes() {
        let store = ProfileStore(directory: tempDir())
        store.add(Profile(name: "A", username: "a", instanceURL: URL(string: "http://x")!, colorIndex: 0))
        #expect(store.nextColorIndex(paletteSize: 3) == 1)
    }

    @Test func resumeStoreTracksProgressAndFinish() {
        let dir = tempDir()
        let store = ResumeStore(directory: dir)
        let profile = UUID()
        let video = Fixtures.video("v1", length: 1000)

        store.save(videoID: "v1", position: 400, duration: 1000, video: video, profile: profile)
        #expect(store.resumePoint(for: "v1", profile: profile) == 400)
        #expect(store.continueWatching(profile: profile).map(\.videoID) == ["v1"])

        // Too early to resume.
        store.save(videoID: "v2", position: 8, duration: 1000, video: nil, profile: profile)
        #expect(store.resumePoint(for: "v2", profile: profile) == nil)

        // Finished videos drop out.
        store.save(videoID: "v1", position: 960, duration: 1000, video: video, profile: profile)
        #expect(store.position(for: "v1", profile: profile) == nil)
        #expect(store.continueWatching(profile: profile).isEmpty)

        // Persisted across instances and namespaced by profile.
        store.save(videoID: "v3", position: 300, duration: 600, video: nil, profile: profile)
        let reloaded = ResumeStore(directory: dir)
        #expect(reloaded.resumePoint(for: "v3", profile: profile) == 300)
        #expect(reloaded.resumePoint(for: "v3", profile: UUID()) == nil)
    }

    @Test func inMemorySessionStore() throws {
        let store = InMemorySessionStore()
        let id = UUID()
        #expect(try store.sid(for: id) == nil)
        try store.setSID("abc", for: id)
        #expect(try store.sid(for: id) == "abc")
        try store.removeSID(for: id)
        #expect(try store.sid(for: id) == nil)
    }
}
