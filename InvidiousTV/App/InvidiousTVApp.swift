import SwiftUI
import InvidiousKit
import Nuke

@main
struct InvidiousTVApp: App {
    @State private var app = AppModel()

    init() {
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: AppIdentity.label("images"), sizeLimit: 512 * 1024 * 1024))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
        }
    }
}
