import SwiftUI
import InvidiousKit

struct MobileTabView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var selectedTab: String = ProcessInfo.processInfo.environment["INVIDIOUS_DEBUG_TAB"] ?? "home"
    @State private var homePath = NavigationPath()
    @State private var showReauth = false
    @State private var debugVideo: VideoDetails?

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: "home") {
                NavigationStack(path: $homePath) {
                    MobileHomeView(session: session)
                        .withMobileRoutes()
                }
            }
            Tab("Subscriptions", systemImage: "rectangle.stack", value: "subscriptions") {
                NavigationStack {
                    MobileSubscriptionsView(session: session)
                        .withMobileRoutes()
                }
            }
            Tab("Channels", systemImage: "person.2", value: "channels") {
                NavigationStack {
                    MobileChannelsView(session: session)
                        .withMobileRoutes()
                }
            }
            Tab("Library", systemImage: "books.vertical", value: "library") {
                NavigationStack {
                    MobileLibraryView(session: session)
                        .withMobileRoutes()
                }
            }
            Tab("Settings", systemImage: "gearshape", value: "settings") {
                NavigationStack {
                    SettingsView(session: session)
                }
            }
            Tab("Search", systemImage: "magnifyingglass", value: "search", role: .search) {
                MobileSearchView(session: session)
            }
        }
        .task {
            await session.refreshHistory()
            #if DEBUG
            if let id = ProcessInfo.processInfo.environment["INVIDIOUS_AUTOPLAY_VIDEO"], debugVideo == nil {
                debugVideo = try? await session.client.video(id: id, proxy: app.settings.proxyMedia)
            }
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
        .task(id: app.pendingVideoID) {
            // Clearing the ID changes this task's identity and would cancel the fetch, so clear it last.
            guard let id = app.pendingVideoID else { return }
            if let details = try? await session.client.video(id: id) {
                selectedTab = "home"
                homePath.append(Route.video(details.summary))
            }
            app.pendingVideoID = nil
        }
        .onChange(of: session.sessionExpired) { _, expired in
            showReauth = expired
        }
        .sheet(isPresented: $showReauth) {
            LoginView(mode: .reauthenticate(session.profile))
        }
        .fullScreenCover(item: $debugVideo) { video in
            MobilePlayerView(details: video, summary: video.summary, startAt: 0, session: session)
        }
    }
}

extension View {
    func withMobileRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .video(let video):
                MobileVideoDetailView(video: video)
            case .channel(let id, let name):
                MobileChannelDetailView(channelID: id, channelName: name)
            case .playlist(let id, let title):
                MobilePlaylistDetailView(playlistID: id, title: title)
            }
        }
    }
}
