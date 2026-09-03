import SwiftUI

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
    }
}
