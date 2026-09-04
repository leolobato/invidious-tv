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

        // Finished videos drop out of the UI but stay as tombstones.
        store.save(videoID: "v1", position: 960, duration: 1000, video: video, profile: profile)
        #expect(store.position(for: "v1", profile: profile) == nil)
        #expect(store.resumePoint(for: "v1", profile: profile) == nil)
        #expect(store.continueWatching(profile: profile).isEmpty)
        #expect(store.positions[profile]?["v1"]?.isFinished == true)

        // Persisted across instances and namespaced by profile.
        store.save(videoID: "v3", position: 300, duration: 600, video: nil, profile: profile)
        let reloaded = ResumeStore(directory: dir)
        #expect(reloaded.resumePoint(for: "v3", profile: profile) == 300)
        #expect(reloaded.resumePoint(for: "v3", profile: UUID()) == nil)
    }

    @Test func resumeSyncsBetweenDevicesByAccount() {
        let hub = InMemoryResumeCloud.Hub()
        let key = ResumeStore.accountKey(instanceURL: URL(string: "http://10.0.1.9:3001")!, username: "Leo")
        #expect(key == ResumeStore.accountKey(instanceURL: URL(string: "HTTP://10.0.1.9:3001/")!, username: "leo"))
        #expect(key.utf8.count <= 64)

        let tv = ResumeStore(directory: tempDir(), cloud: InMemoryResumeCloud(hub: hub))
        let tvProfile = UUID()
        tv.setAccountKey(key, for: tvProfile)
        let video = Fixtures.video("v1", length: 1000)
        tv.save(videoID: "v1", position: 400, duration: 1000, video: video, profile: tvProfile, now: Date(timeIntervalSince1970: 100))

        // A phone signing in to the same account picks the position up on registration.
        let phone = ResumeStore(directory: tempDir(), cloud: InMemoryResumeCloud(hub: hub))
        let phoneProfile = UUID()
        phone.setAccountKey(key, for: phoneProfile)
        #expect(phone.resumePoint(for: "v1", profile: phoneProfile) == 400)
        #expect(phone.continueWatching(profile: phoneProfile).first?.video == video)

        // Newer position on the phone reaches the TV through the external-change notification.
        phone.save(videoID: "v1", position: 500, duration: 1000, video: video, profile: phoneProfile, now: Date(timeIntervalSince1970: 200))
        #expect(tv.resumePoint(for: "v1", profile: tvProfile) == 500)

        // An older write on the TV does not roll it back.
        tv.save(videoID: "v1", position: 450, duration: 1000, video: video, profile: tvProfile, now: Date(timeIntervalSince1970: 150))
        #expect(phone.resumePoint(for: "v1", profile: phoneProfile) == 500)

        // Finishing on one device finishes everywhere, and a stale unfinished remote entry loses.
        phone.save(videoID: "v1", position: 990, duration: 1000, video: video, profile: phoneProfile, now: Date(timeIntervalSince1970: 300))
        #expect(tv.resumePoint(for: "v1", profile: tvProfile) == nil)
        #expect(tv.continueWatching(profile: tvProfile).isEmpty)

        // Another account does not see any of it.
        let other = ResumeStore(directory: tempDir(), cloud: InMemoryResumeCloud(hub: hub))
        let otherProfile = UUID()
        other.setAccountKey(ResumeStore.accountKey(instanceURL: URL(string: "http://10.0.1.9:3001")!, username: "someone"), for: otherProfile)
        #expect(other.positions[otherProfile, default: [:]].isEmpty)
    }

    @Test func resumeMergesLocalHistoryWhenSyncTurnsOn() {
        let hub = InMemoryResumeCloud.Hub()
        let key = ResumeStore.accountKey(instanceURL: URL(string: "http://x")!, username: "u")
        let seed = ResumeStore(directory: tempDir(), cloud: InMemoryResumeCloud(hub: hub))
        let seedProfile = UUID()
        seed.setAccountKey(key, for: seedProfile)
        seed.save(videoID: "remote", position: 100, duration: 600, video: nil, profile: seedProfile)

        let local = ResumeStore(directory: tempDir())
        let profile = UUID()
        local.save(videoID: "local", position: 200, duration: 600, video: nil, profile: profile)
        local.setAccountKey(key, for: profile)
        #expect(local.resumePoint(for: "remote", profile: profile) == nil)

        local.cloud = InMemoryResumeCloud(hub: hub)
        #expect(local.resumePoint(for: "remote", profile: profile) == 100)
        #expect(local.resumePoint(for: "local", profile: profile) == 200)
        // And the seed device receives the local entry.
        #expect(seed.resumePoint(for: "local", profile: seedProfile) == 200)
    }

    @Test func resumePrunesOldEntriesAndTrimsSyncedThumbnails() {
        let store = ResumeStore(directory: tempDir())
        let profile = UUID()
        for index in 0..<(ResumeStore.maxEntriesPerAccount + 5) {
            store.save(videoID: "v\(index)", position: 100, duration: 600, video: nil, profile: profile, now: Date(timeIntervalSince1970: TimeInterval(index)))
        }
        let bucket = store.positions[profile] ?? [:]
        #expect(bucket.count == ResumeStore.maxEntriesPerAccount)
        #expect(bucket["v0"] == nil)
        #expect(bucket["v\(ResumeStore.maxEntriesPerAccount + 4)"] != nil)

        var video = Fixtures.video("t")
        video.videoThumbnails = (1...8).map { Thumbnail(quality: "q\($0)", url: "/vi/t/\($0).jpg", width: $0 * 100, height: $0 * 56) }
        let synced = ResumeStore.forSync(["t": ResumePosition(videoID: "t", position: 10, duration: 100, video: video)])
        #expect(synced["t"]?.video?.videoThumbnails.map(\.width) == [800, 700, 600, 500])
        let roundTrip = ResumeStore.decodeBucket(ResumeStore.encodeBucket(synced))
        #expect(roundTrip["t"]?.video?.videoThumbnails.count == 4)
    }

    @Test func credentialsRoundTripThroughSessionStore() throws {
        let store = InMemorySessionStore()
        let id = UUID()
        try store.setCredential(.token("%7B%22session%22%3A%22v1%3Aabc%22%7D"), for: id)
        #expect(try store.credential(for: id) == .token("%7B%22session%22%3A%22v1%3Aabc%22%7D"))
        try store.setSID("plain-sid", for: id)
        #expect(try store.credential(for: id) == .sid("plain-sid"))
        #expect(InvidiousCredential.sid("s").isToken == false)
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
