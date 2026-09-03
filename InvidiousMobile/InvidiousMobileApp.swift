import SwiftUI
import Nuke

@main
struct InvidiousMobileApp: App {
    @State private var app = AppModel()

    init() {
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: "org.lobato.invidious.images", sizeLimit: 256 * 1024 * 1024))
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environment(app)
        }
    }
}

struct MobileRootView: View {
    var body: some View {
        Text("Invidious")
    }
}
