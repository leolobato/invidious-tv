import SwiftUI
import InvidiousKit

/// Thumbnail with title and metadata, YouTube mobile style.
struct MobileVideoCard: View {
    let video: VideoSummary
    var showChannel = true

    @Environment(AppModel.self) private var app

    /// The list entry with length and live state filled in from the cache.
    private var resolved: VideoSummary { app.videoMetadata.resolved(video) }

    var body: some View {
        NavigationLink(value: Route.video(resolved)) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail
                HStack(alignment: .top, spacing: 10) {
                    if showChannel {
                        ChannelAvatar(channelID: video.authorId, name: video.author, size: 36)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(video.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.plain)
        .opacity(app.active?.watchedIDs.contains(video.videoId) == true && progress == nil ? 0.6 : 1)
        .task(id: video.videoId) {
            guard VideoMetadataCache.needsLookup(video), let client = app.active?.client else { return }
            await app.videoMetadata.load(videoID: video.videoId, using: client)
        }
    }

    private var progress: Double? {
        guard let profile = app.active?.profile.id,
              let entry = app.resume.position(for: video.videoId, profile: profile) else { return nil }
        return entry.progress
    }

    private var thumbnail: some View {
        let client = app.active?.client
        let thumbs = video.videoThumbnails
        let primary = thumbs.first { $0.quality == "maxresdefault" } ?? thumbs.best(maxWidth: 1280)
        let fallbacks = ["sddefault", "high", "medium"].compactMap { q in thumbs.first { $0.quality == q } }
        return ZStack(alignment: .bottomTrailing) {
            RemoteImage(url: primary.flatMap { client?.url(for: $0) }, fallbacks: fallbacks.compactMap { client?.url(for: $0) })
                .aspectRatio(16 / 9, contentMode: .fill)
                .clipped()
            let resolved = resolved
            if resolved.liveNow {
                badge("LIVE", color: .red)
            } else if resolved.isUpcoming {
                badge("UPCOMING", color: .gray)
            } else if resolved.lengthSeconds > 0 {
                badge(VideoFormatting.duration(resolved.lengthSeconds), color: .black.opacity(0.75))
            }
            if let progress, progress > 0 {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.3))
                            Rectangle().fill(Color.red).frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                }
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
            .padding(8)
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

/// Adaptive grid: one column on iPhone portrait, more on iPad and landscape.
struct MobileVideoList: View {
    let videos: [VideoSummary]
    var showChannel = true
    var onReachEnd: (() -> Void)? = nil

    @Environment(AppModel.self) private var app

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320, maximum: 520), spacing: 16, alignment: .top)], alignment: .leading, spacing: 24) {
            ForEach(videos) { video in
                MobileVideoCard(video: video, showChannel: showChannel)
                    .onAppear {
                        if video.id == videos.last?.id { onReachEnd?() }
                    }
            }
        }
        .padding(.horizontal, 16)
    }
}

/// Horizontal shelf of compact cards.
struct MobileShelf: View {
    let title: String
    let videos: [VideoSummary]

    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(videos) { video in
                        MobileVideoCard(video: video, showChannel: false)
                            .frame(width: 260)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
