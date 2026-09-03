import SwiftUI
import InvidiousKit

/// Top-level tabs for a signed-in profile.
struct MainTabView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var showReauth = false
    @State private var debugVideo: VideoDetails?
    @State private var selectedTab: String = ProcessInfo.processInfo.environment["INVIDIOUS_DEBUG_TAB"] ?? "home"
    @State private var homePath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Search", systemImage: "magnifyingglass", value: "search", role: .search) {
                SearchView(session: session)
            }
            Tab("Home", systemImage: "house", value: "home") {
                NavigationStack(path: $homePath) {
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
            Tab("Library", systemImage: "books.vertical", value: "library") {
                NavigationStack {
                    LibraryView(session: session)
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
            // `INVIDIOUS_DEBUG_ROUTE=video:<id>` or `channel:<ucid>` opens that screen on the Home tab.
            if let route = ProcessInfo.processInfo.environment["INVIDIOUS_DEBUG_ROUTE"] {
                let parts = route.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    if parts[0] == "video", let details = try? await session.client.video(id: parts[1]) {
                        homePath.append(Route.video(details.summary))
                    } else if parts[0] == "channel" {
                        homePath.append(Route.channel(id: parts[1], name: ""))
                    } else if parts[0] == "playlist" {
                        homePath.append(Route.playlist(id: parts[1], title: ""))
                    }
                }
            }
            #endif
        }
        .fullScreenCover(item: $debugVideo) { video in
            PlayerView(details: video, summary: video.summary, startAt: 0, session: session)
        }
        .onChange(of: session.sessionExpired) { _, expired in
            showReauth = expired
        }
        .task(id: app.pendingVideoID) {
            guard let id = app.pendingVideoID else { return }
            app.pendingVideoID = nil
            if let details = try? await session.client.video(id: id) {
                selectedTab = "home"
                homePath.append(Route.video(details.summary))
            }
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
            case .playlist(let id, let title):
                PlaylistDetailView(playlistID: id, title: title)
            }
        }
    }
}
