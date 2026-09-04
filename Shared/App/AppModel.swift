import Foundation
import Observation
import InvidiousKit

/// Top-level dependency container and the currently active profile.
@MainActor
@Observable
final class AppModel {
    let profiles: ProfileStore
    let resume: ResumeStore
    let settings: AppSettings
    let channelAvatars: ChannelAvatarCache
    let playlists = PlaylistStore()
    let topShelf = TopShelfSnapshotStore(appGroup: Bundle.main.object(forInfoDictionaryKey: "InvidiousAppGroup") as? String ?? "")
    private let sessions: any SessionStore
    /// Video requested through a deep link (Top Shelf), consumed by the tab view.
    var pendingVideoID: String?

    private(set) var active: ActiveSession?

    /// Keychain group shared with the Top Shelf extension (tvOS only; empty on other platforms).
    static var sharedKeychainGroup: String? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "InvidiousKeychainGroup") as? String,
              !group.isEmpty, !group.hasPrefix(".") else { return nil }
        return group
    }

    private var latestForTopShelf: [VideoSummary] = []

    init(
        profiles: ProfileStore = ProfileStore(),
        resume: ResumeStore = ResumeStore(),
        settings: AppSettings = AppSettings(),
        sessions: any SessionStore = KeychainSessionStore(accessGroup: AppModel.sharedKeychainGroup)
    ) {
        self.profiles = profiles
        self.resume = resume
        self.settings = settings
        self.sessions = sessions
        self.channelAvatars = ChannelAvatarCache()
        for profile in profiles.profiles {
            resume.setAccountKey(Self.accountKey(for: profile), for: profile.id)
        }
        applyCloudSyncSetting()
    }

    /// Turns iCloud sync of resume positions on or off to match the setting.
    func applyCloudSyncSetting() {
        if settings.iCloudSync {
            if resume.cloud == nil { resume.cloud = UbiquitousResumeCloud() }
        } else {
            resume.cloud = nil
        }
    }

    private static func accountKey(for profile: Profile) -> String {
        ResumeStore.accountKey(instanceURL: profile.instanceURL, username: profile.username)
    }

    /// Makes `profile` the active one. Fails when its session is missing.
    func activate(_ profile: Profile) throws {
        guard let credential = try sessions.credential(for: profile.id) else {
            throw InvidiousError.unauthorized
        }
        let client = InvidiousClient(baseURL: profile.instanceURL, credential: credential)
        active = ActiveSession(profile: profile, client: client)
        profiles.markUsed(id: profile.id)
    }

    /// Returns to the profile picker without removing anything.
    func deactivate() {
        active = nil
    }

    /// Signs in, stores the session and creates the profile.
    func addProfile(name: String, username: String, password: String, instanceURL: URL) async throws -> Profile {
        let client = InvidiousClient(baseURL: instanceURL)
        let sid = try await client.login(username: username, password: password)
        let displayName = name.trimmingCharacters(in: .whitespaces)
        let profile = Profile(
            name: displayName.isEmpty ? username : displayName,
            username: username,
            instanceURL: instanceURL,
            colorIndex: profiles.nextColorIndex(paletteSize: ProfilePalette.colors.count)
        )
        try sessions.setSID(sid, for: profile.id)
        profiles.add(profile)
        resume.setAccountKey(Self.accountKey(for: profile), for: profile.id)
        return profile
    }

    /// Finishes a phone (token) sign-in. Checks the token against the instance first.
    ///
    /// When `existing` is given, or a profile for the same account already exists, that profile
    /// gets the new credential instead of a duplicate being created.
    func completeTokenLogin(_ result: TokenLogin.Result, instanceURL: URL, name: String = "", existing: Profile? = nil) async throws -> Profile {
        let client = InvidiousClient(baseURL: instanceURL, credential: result.credential)
        do {
            _ = try await client.feed(page: 1, maxResults: 1)
        } catch InvidiousError.unauthorized {
            throw InvidiousError.tokenRejected
        }
        let username = result.username ?? existing?.username ?? ""
        let match = existing
            ?? profiles.profiles.first { $0.instanceURL == instanceURL && !username.isEmpty && $0.username == username }
        if let match {
            try sessions.setCredential(result.credential, for: match.id)
            var updated = match
            if updated.username.isEmpty { updated.username = username }
            profiles.update(updated)
            if active?.profile.id == match.id {
                active = ActiveSession(profile: updated, client: client)
            }
            resume.setAccountKey(Self.accountKey(for: updated), for: updated.id)
            return updated
        }
        let displayName = name.trimmingCharacters(in: .whitespaces)
        let profile = Profile(
            name: displayName.isEmpty ? (username.isEmpty ? "Apple TV" : username) : displayName,
            username: username,
            instanceURL: instanceURL,
            colorIndex: profiles.nextColorIndex(paletteSize: ProfilePalette.colors.count)
        )
        try sessions.setCredential(result.credential, for: profile.id)
        profiles.add(profile)
        if !username.isEmpty {
            resume.setAccountKey(Self.accountKey(for: profile), for: profile.id)
        }
        return profile
    }

    /// Re-authenticates an existing profile after its session expired.
    func reauthenticate(_ profile: Profile, password: String) async throws {
        let client = InvidiousClient(baseURL: profile.instanceURL)
        let sid = try await client.login(username: profile.username, password: password)
        try sessions.setSID(sid, for: profile.id)
        if active?.profile.id == profile.id {
            active = ActiveSession(profile: profile, client: client.authenticated(sid: sid))
        }
    }

    func rename(_ profile: Profile, to name: String) {
        var updated = profile
        updated.name = name
        profiles.update(updated)
        if active?.profile.id == profile.id {
            active?.profile = updated
        }
    }

    func removeProfile(_ profile: Profile) {
        if case .token? = try? sessions.credential(for: profile.id) {
            // Best effort: revoke the token on the instance so it does not linger in the token manager.
            let client = InvidiousClient(baseURL: profile.instanceURL, credential: try? sessions.credential(for: profile.id))
            Task { try? await client.unregisterToken() }
        }
        try? sessions.removeSID(for: profile.id)
        resume.removeAll(profile: profile.id)
        profiles.remove(id: profile.id)
        if active?.profile.id == profile.id {
            active = nil
        }
    }

    /// Refreshes what the Top Shelf extension shows for the active profile.
    func updateTopShelf(latest: [VideoSummary]) {
        latestForTopShelf = latest
        refreshTopShelf()
    }

    /// Rewrites the Top Shelf snapshot from the current resume positions and the last known uploads.
    /// The extension refreshes the uploads itself when the snapshot gets old.
    func refreshTopShelf() {
        guard let session = active else { return }
        let client = session.client
        let continueWatching = resume.continueWatching(profile: session.profile.id, limit: 10)
            .compactMap { entry in entry.video.map { TopShelfSnapshot.item(for: $0, progress: entry.progress, client: client) } }
        let existing = topShelf.load()
        let latestItems = latestForTopShelf.isEmpty
            ? (existing?.latest ?? [])
            : TopShelfSnapshot.latestItems(from: latestForTopShelf, client: client)
        topShelf.save(TopShelfSnapshot(
            profileName: session.profile.name,
            continueWatching: continueWatching,
            latest: latestItems,
            updatedAt: latestForTopShelf.isEmpty ? (existing?.updatedAt ?? .distantPast) : Date(),
            account: TopShelfSnapshot.Account(profileID: session.profile.id, instanceURL: session.profile.instanceURL)
        ))
    }

    func hasSession(_ profile: Profile) -> Bool {
        (try? sessions.sid(for: profile.id)) != nil
    }

    /// Debug builds only: signs in from `INVIDIOUS_AUTOLOGIN_USER` / `INVIDIOUS_AUTOLOGIN_PASSWORD`
    /// (and optionally `INVIDIOUS_AUTOLOGIN_INSTANCE`) so the simulator can skip the keyboard.
    /// Returns true when a profile became active.
    func performDebugAutoLoginIfRequested() async -> Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let user = env["INVIDIOUS_AUTOLOGIN_USER"], let password = env["INVIDIOUS_AUTOLOGIN_PASSWORD"] else {
            return false
        }
        let instance = AppSettings.normalizedURL(from: env["INVIDIOUS_AUTOLOGIN_INSTANCE"] ?? settings.instanceURLString)
        guard let instance else { return false }
        if let existing = profiles.profiles.first(where: { $0.username == user && $0.instanceURL == instance }) {
            if (try? activate(existing)) != nil { return true }
            do {
                try await reauthenticate(existing, password: password)
                try activate(existing)
                return true
            } catch {
                return false
            }
        }
        do {
            let profile = try await addProfile(name: "", username: user, password: password, instanceURL: instance)
            try activate(profile)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}

/// The signed-in profile plus its API client and account state.
@MainActor
@Observable
final class ActiveSession {
    var profile: Profile
    let client: InvidiousClient
    /// Set when a request came back 401/403; the UI then prompts for the password.
    var sessionExpired = false
    /// Video IDs the account has watched, used to dim cards and seed Home.
    private(set) var watchedIDs: Set<String> = []
    private(set) var recentHistory: [String] = []

    init(profile: Profile, client: InvidiousClient) {
        self.profile = profile
        self.client = client
    }

    func refreshHistory() async {
        do {
            let ids = try await client.history(page: 1, maxResults: 100)
            recentHistory = ids
            watchedIDs = Set(ids)
        } catch {
            handle(error)
        }
    }

    func markWatched(_ videoID: String) async {
        watchedIDs.insert(videoID)
        recentHistory.removeAll { $0 == videoID }
        recentHistory.insert(videoID, at: 0)
        do {
            try await client.markWatched(videoID: videoID)
        } catch {
            handle(error)
        }
    }

    /// Removes one video from the account history.
    func unmarkWatched(_ videoID: String) async throws {
        try await client.unmarkWatched(videoID: videoID)
        watchedIDs.remove(videoID)
        recentHistory.removeAll { $0 == videoID }
    }

    /// Wipes the account history.
    func clearHistory() async throws {
        try await client.clearHistory()
        watchedIDs = []
        recentHistory = []
    }

    /// Flags expired sessions; other errors are left to the caller to display.
    func handle(_ error: Error) {
        if let invidious = error as? InvidiousError, invidious.isSessionExpired {
            sessionExpired = true
        }
    }
}
