import SwiftUI
import InvidiousKit

/// Thumbnail grid tile, in the style of the YouTube TV app.
struct VideoCard: View {
    let video: VideoSummary
    var progress: Double? = nil
    var watched: Bool = false
    var showChannel: Bool = true

    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink(value: Route.video(video)) {
            VStack(alignment: .leading, spacing: 10) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2, reservesSpace: true)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.card)
        .opacity(watched && progress == nil ? 0.55 : 1)
    }

    private var thumbnail: some View {
        let client = app.active?.client
        let thumbs = video.videoThumbnails
        let primary = thumbs.first { $0.quality == "maxresdefault" } ?? thumbs.best(maxWidth: 1280)
        let fallbacks = ["sddefault", "high", "medium"].compactMap { q in thumbs.first { $0.quality == q } }
        return ZStack(alignment: .bottomTrailing) {
            RemoteImage(
                url: primary.flatMap { client?.url(for: $0) },
                fallbacks: fallbacks.compactMap { client?.url(for: $0) }
            )
            .aspectRatio(16 / 9, contentMode: .fill)
            .clipped()

            if video.liveNow {
                badge("LIVE", color: .red)
            } else if video.isUpcoming {
                badge("UPCOMING", color: .gray)
            } else if video.lengthSeconds > 0 {
                badge(VideoFormatting.duration(video.lengthSeconds), color: .black.opacity(0.75))
            }

            if let progress, progress > 0 {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.3))
                            Rectangle().fill(Color.accentColor)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.white)
            .padding(10)
    }

    private var subtitle: String {
        var parts: [String] = []
        if showChannel, !video.author.isEmpty { parts.append(video.author) }
        if let views = VideoFormatting.viewCount(video.viewCount) {
            parts.append(views)
        } else if let text = video.viewCountText, !text.isEmpty {
            parts.append(text.contains("views") ? text : "\(text) views")
        }
        if let when = video.publishedText ?? VideoFormatting.relativeDate(video.publishedDate) {
            parts.append(when)
        }
        return parts.joined(separator: " · ")
    }
}
