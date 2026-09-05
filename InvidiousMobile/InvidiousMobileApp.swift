import SwiftUI
import InvidiousKit
import Nuke

@main
struct InvidiousMobileApp: App {
    @State private var app = AppModel()
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var delegate

    init() {
        ImagePipeline.shared = ImagePipeline(configuration: .withDataCache(name: AppIdentity.label("images"), sizeLimit: 256 * 1024 * 1024))
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environment(app)
        }
    }
}
