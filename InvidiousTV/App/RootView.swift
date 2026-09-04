import SwiftUI
import InvidiousKit

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if let session = app.active {
                MainTabView(session: session)
                    .id(session.profile.id)
            } else {
                ProfilePickerView()
            }
        }
        .animation(.default, value: app.active?.profile.id)
        .onOpenURL { url in
            if let id = AppLink.videoID(from: url) {
                app.pendingVideoID = id
                if app.active == nil, let profile = app.profiles.lastUsedProfile {
                    try? app.activate(profile)
                }
            }
        }
    }
}
