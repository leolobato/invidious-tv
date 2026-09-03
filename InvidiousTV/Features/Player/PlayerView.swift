import SwiftUI
import InvidiousKit

/// Placeholder until the MPV player lands.
struct PlayerView: View {
    let details: VideoDetails
    let summary: VideoSummary
    let startAt: TimeInterval
    let session: ActiveSession

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text(details.title)
            Text("Player coming soon")
                .foregroundStyle(.secondary)
            Button("Close") { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
