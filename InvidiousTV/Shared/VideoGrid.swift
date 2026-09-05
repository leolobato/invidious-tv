import SwiftUI
import InvidiousKit

/// Four-column grid of video cards with optional infinite scrolling.
struct VideoGrid: View {
    let videos: [VideoSummary]
    var showChannel: Bool = true
    var onReachEnd: (() -> Void)? = nil
    /// When set, long-pressing a card offers this destructive action.
    var removeTitle: String = "Remove"
    var onRemove: ((VideoSummary) -> Void)? = nil

    @Environment(AppModel.self) private var app

    static let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 4)

    var body: some View {
        LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 48) {
            ForEach(videos) { video in
                card(video)
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

    @ViewBuilder
    private func card(_ video: VideoSummary) -> some View {
        let card = VideoCard(
            video: video,
            progress: progress(for: video),
            watched: app.active?.watchedIDs.contains(video.videoId) ?? false,
            showChannel: showChannel
        )
        if let onRemove {
            card.contextMenu {
                Button(removeTitle, systemImage: "trash", role: .destructive) { onRemove(video) }
            }
        } else {
            card
        }
    }

    private func progress(for video: VideoSummary) -> Double? {
        guard let profile = app.active?.profile.id,
              let entry = app.resume.position(for: video.videoId, profile: profile) else { return nil }
        return entry.progress
    }
}
