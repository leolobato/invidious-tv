import Foundation
import InvidiousKit

/// Navigation destinations shared by every tab.
enum Route: Hashable {
    case video(VideoSummary)
    case channel(id: String, name: String)
    case playlist(id: String, title: String)
}
