import SwiftUI
import InvidiousKit

/// Four-column grid of video cards with optional infinite scrolling.
struct VideoGrid: View {
    let videos: [VideoSummary]
    var showChannel: Bool = true
    var onReachEnd: (() -> Void)? = nil

    @Environment(AppModel.self) private var app

    static let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)

    var body: some View {
        let videos = app.settings.filtered(videos)
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 48) {
            ForEach(videos) { video in
                VideoCard(
                    video: video,
                    progress: progress(for: video),
                    watched: app.active?.watchedIDs.contains(video.videoId) ?? false,
                    showChannel: showChannel
                )
                .onAppear {
                    if video.id == videos.last?.id {
                        onReachEnd?()
                    }
                }
            }
        }
        .padding(.horizontal, 60)
        .padding(.vertical, 40)
    }

    private func progress(for video: VideoSummary) -> Double? {
        guard let profile = app.active?.profile.id,
              let entry = app.resume.position(for: video.videoId, profile: profile) else { return nil }
        return entry.progress
    }
}
