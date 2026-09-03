import SwiftUI
import InvidiousKit

/// Top-level tabs for a signed-in profile.
struct MainTabView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var showReauth = false
    @State private var debugVideo: VideoDetails?
    @State private var selectedTab: String = ProcessInfo.processInfo.environment["INVIDIOUS_DEBUG_TAB"] ?? "home"

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: "home") {
                NavigationStack {
                    HomeView(session: session)
                        .withRoutes()
                }
            }
            Tab("Subscriptions", systemImage: "rectangle.stack", value: "subscriptions") {
                NavigationStack {
                    SubscriptionsView(session: session)
                        .withRoutes()
                }
            }
            Tab("Channels", systemImage: "person.2", value: "channels") {
                NavigationStack {
                    ChannelsView(session: session)
                        .withRoutes()
                }
            }
            Tab("Settings", systemImage: "gearshape", value: "settings") {
                NavigationStack {
                    SettingsView(session: session)
                        .withRoutes()
                }
            }
        }
        .task {
            await session.refreshHistory()
            #if DEBUG
            if let id = ProcessInfo.processInfo.environment["INVIDIOUS_AUTOPLAY_VIDEO"], debugVideo == nil {
                debugVideo = try? await session.client.video(id: id, proxy: app.settings.proxyMedia)
            }
            #endif
        }
        .fullScreenCover(item: $debugVideo) { video in
            PlayerView(details: video, summary: video.summary, startAt: 0, session: session)
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
