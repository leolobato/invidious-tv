import SwiftUI
import InvidiousKit

/// Shows the signed-in tabs, or the profile picker when nobody is signed in.
struct MobileRootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let session = app.active {
                MobileTabView(session: session)
                    .id(session.profile.id)
            } else {
                MobileProfilePicker()
            }
        }
        .onOpenURL { url in
            if let id = AppLink.videoID(from: url) {
                open(videoID: id)
            }
        }
        .task {
            if await app.performDebugAutoLoginIfRequested() == false,
               app.active == nil, let profile = app.profiles.lastUsedProfile {
                try? app.activate(profile)
            }
            consumeSharedLink()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumeSharedLink() }
        }
    }

    private func open(videoID: String) {
        app.pendingVideoID = videoID
        if app.active == nil, let profile = app.profiles.lastUsedProfile {
            try? app.activate(profile)
        }
    }

    /// Picks up a link the share extension left in the app group.
    private func consumeSharedLink() {
        if let id = SharedLinkInbox().takeVideoID() {
            open(videoID: id)
        }
    }
}

/// Simple list-based profile picker for iPhone and iPad.
struct MobileProfilePicker: View {
    @Environment(AppModel.self) private var app
    @State private var showLogin = false
    @State private var reauthProfile: Profile?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(app.profiles.profiles) { profile in
                        Button {
                            if (try? app.activate(profile)) == nil {
                                reauthProfile = profile
                            }
                        } label: {
                            HStack(spacing: 16) {
                                ProfileAvatar(profile: profile, size: 48)
                                VStack(alignment: .leading) {
                                    Text(profile.name).font(.headline)
                                    Text(profile.instanceURL.host ?? profile.instanceURL.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { app.removeProfile(profile) }
                        }
                    }
                } header: {
                    Text("Who's watching?")
                }
                Section {
                    Button {
                        showLogin = true
                    } label: {
                        Label("Add Profile", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Invidious")
            .task {
                if app.profiles.profiles.isEmpty { showLogin = true }
            }
            .sheet(isPresented: $showLogin) {
                LoginView(mode: .newProfile)
            }
            .sheet(item: $reauthProfile) { profile in
                LoginView(mode: .reauthenticate(profile))
            }
        }
    }
}

/// Colored circle with initials (shared shape with the tvOS picker).
struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle().fill(ProfilePalette.color(index: profile.colorIndex))
            Text(profile.initials)
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
