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
    private let sessions: any SessionStore

    private(set) var active: ActiveSession?

    init(
        profiles: ProfileStore = ProfileStore(),
        resume: ResumeStore = ResumeStore(),
        settings: AppSettings = AppSettings(),
        sessions: any SessionStore = KeychainSessionStore()
    ) {
        self.profiles = profiles
        self.resume = resume
        self.settings = settings
        self.sessions = sessions
        self.channelAvatars = ChannelAvatarCache()
    }

    /// Makes `profile` the active one. Fails when its session is missing.
    func activate(_ profile: Profile) throws {
        guard let sid = try sessions.sid(for: profile.id) else {
            throw InvidiousError.unauthorized
        }
        let client = InvidiousClient(baseURL: profile.instanceURL, sid: sid)
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
        try? sessions.removeSID(for: profile.id)
        resume.removeAll(profile: profile.id)
        profiles.remove(id: profile.id)
        if active?.profile.id == profile.id {
            active = nil
        }
    }

    func hasSession(_ profile: Profile) -> Bool {
        (try? sessions.sid(for: profile.id)) != nil
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

    /// Flags expired sessions; other errors are left to the caller to display.
    func handle(_ error: Error) {
        if let invidious = error as? InvidiousError, invidious.isSessionExpired {
            sessionExpired = true
        }
    }
}
