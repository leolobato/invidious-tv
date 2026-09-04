import Foundation
import InvidiousKit

/// What the video page asks the player to play. Carried by the presentation itself so the start
/// position can never be read stale.
struct PlaybackRequest: Identifiable {
    let details: VideoDetails
    let startAt: TimeInterval

    var id: String { "\(details.videoId)@\(Int(startAt))" }
}
