import SwiftUI
import InvidiousKit

/// A titled horizontal row of video cards.
struct Shelf: View {
    let title: String
    let videos: [VideoSummary]
    var showChannel: Bool = true

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(app.settings.filtered(videos)) { video in
                        VideoCard(
                            video: video,
                            progress: progress(for: video),
                            watched: app.active?.watchedIDs.contains(video.videoId) ?? false,
                            showChannel: showChannel
                        )
                        .frame(width: 400)
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
    }

    private func progress(for video: VideoSummary) -> Double? {
        guard let profile = app.active?.profile.id,
              let entry = app.resume.position(for: video.videoId, profile: profile) else { return nil }
        return entry.progress
    }
}
