import SwiftUI
import InvidiousKit

/// Top-level tabs for a signed-in profile.
struct MainTabView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var showReauth = false

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    HomeView(session: session)
                        .withRoutes()
                }
            }
            Tab("Subscriptions", systemImage: "rectangle.stack") {
                NavigationStack {
                    SubscriptionsView(session: session)
                        .withRoutes()
                }
            }
            Tab("Channels", systemImage: "person.2") {
                NavigationStack {
                    ChannelsView(session: session)
                        .withRoutes()
                }
            }
            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    SettingsView(session: session)
                        .withRoutes()
                }
            }
        }
        .task {
            await session.refreshHistory()
        }
        .onChange(of: session.sessionExpired) { _, expired in
            showReauth = expired
        }
        .fullScreenCover(isPresented: $showReauth) {
            LoginView(mode: .reauthenticate(session.profile))
        }
    }
}

extension View {
    /// Registers the navigation destinations used across all tabs.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .video(let video):
                VideoDetailView(video: video)
            case .channel(let id, let name):
                ChannelDetailView(channelID: id, channelName: name)
            }
        }
    }
}
