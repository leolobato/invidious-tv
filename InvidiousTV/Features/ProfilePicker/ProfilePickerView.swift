import SwiftUI
import InvidiousKit

/// Launch screen: who is watching?
struct ProfilePickerView: View {
    @Environment(AppModel.self) private var app
    @State private var showLogin = false
    @State private var reauthProfile: Profile?
    @State private var errorMessage: String?
    @FocusState private var focusedProfile: UUID?

    var body: some View {
        VStack(spacing: 60) {
            Text("Who's watching?")
                .font(.largeTitle.weight(.semibold))

            HStack(alignment: .top, spacing: 60) {
                ForEach(app.profiles.profiles) { profile in
                    Button {
                        select(profile)
                    } label: {
                        VStack(spacing: 20) {
                            ProfileAvatar(profile: profile, size: 200)
                            Text(profile.name)
                                .font(.title3)
                                .lineLimit(1)
                        }
                        .frame(width: 240)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedProfile, equals: profile.id)
                    .scaleEffect(focusedProfile == profile.id ? 1.1 : 1)
                    .animation(.easeOut(duration: 0.15), value: focusedProfile)
                    .contextMenu {
                        Button("Sign in again") { reauthProfile = profile }
                        Button("Remove profile", role: .destructive) { app.removeProfile(profile) }
                    }
                }

                Button {
                    showLogin = true
                } label: {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.12))
                            Image(systemName: "plus")
                                .font(.system(size: 80, weight: .light))
                        }
                        .frame(width: 200, height: 200)
                        Text("Add Profile")
                            .font(.title3)
                    }
                    .frame(width: 240)
                }
                .buttonStyle(.plain)
                .focused($focusedProfile, equals: Self.addID)
                .scaleEffect(focusedProfile == Self.addID ? 1.1 : 1)
                .animation(.easeOut(duration: 0.15), value: focusedProfile)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onAppear {
            if app.profiles.profiles.isEmpty {
                showLogin = true
            }
            focusedProfile = app.profiles.lastUsedProfileID ?? app.profiles.profiles.first?.id ?? Self.addID
        }
        .fullScreenCover(isPresented: $showLogin) {
            LoginView(mode: .newProfile)
        }
        .fullScreenCover(item: $reauthProfile) { profile in
            LoginView(mode: .reauthenticate(profile))
        }
    }

    private static let addID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    private func select(_ profile: Profile) {
        do {
            try app.activate(profile)
            errorMessage = nil
        } catch {
            reauthProfile = profile
        }
    }
}

/// Colored circle with initials.
struct ProfileAvatar: View {
    let profile: Profile
    var size: CGFloat = 120

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
