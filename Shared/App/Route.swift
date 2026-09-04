import Foundation
import SwiftUI
import InvidiousKit

/// Navigation destinations shared by every tab.
enum Route: Hashable {
    case video(VideoSummary)
    case channel(id: String, name: String)
    case playlist(id: String, title: String)
    case history
}

/// Pushes a route onto the enclosing tab's navigation stack.
///
/// Each tab owns a `NavigationPath` and injects this closure, so menus and description links can
/// navigate without `navigationDestination(item:)`, which does not compose with the stack's
/// `navigationDestination(for: Route.self)` and left pushes rendering the wrong screen.
typealias PushRoute = @MainActor @Sendable (Route) -> Void

struct PushRouteKey: EnvironmentKey {
    static let defaultValue: PushRoute = { _ in }
}

extension EnvironmentValues {
    var pushRoute: PushRoute {
        get { self[PushRouteKey.self] }
        set { self[PushRouteKey.self] = newValue }
    }
}
