import SwiftUI
import InvidiousKit

struct MobileChannelDetailView: View {
    let channelID: String
    let channelName: String

    @Environment(AppModel.self) private var app
    @State private var model: ChannelDetailViewModel?
    @State private var descriptionExpanded = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(model?.header.value?.author ?? channelName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard model == nil, let session = app.active else { return }
            let vm = ChannelDetailViewModel(channelID: channelID, session: session, avatars: app.channelAvatars)
            model = vm
            await vm.load()
        }
    }

    @ViewBuilder
    private func content(_ model: ChannelDetailViewModel) -> some View {
        if case .failed(let message) = model.header, model.videos.isEmpty {
            ErrorView(message: message) { Task { await model.load() } }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(model)
                    if !model.playlists.isEmpty {
                        playlistShelf(model)
                        Text("Videos")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 16)
                    }
                    MobileVideoList(videos: model.videos, showChannel: false) {
                        Task { await model.loadMore() }
                    }
                    if model.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity).padding()
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func header(_ model: ChannelDetailViewModel) -> some View {
        let channel = model.header.value
        let client = app.active?.client
        return VStack(alignment: .leading, spacing: 12) {
            if let banner = channel?.authorBanners.best(minWidth: 1280), let url = client?.url(for: banner) {
                // The image fills a fixed-size box and is clipped to it. Sizing the image itself
                // would let a wide banner report its own width and push the page past the screen.
                Color.clear
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .overlay { RemoteImage(url: url) }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
            }
            HStack(spacing: 14) {
                ChannelAvatar(
                    channelID: channelID,
                    name: channel?.author ?? channelName,
                    size: 64,
                    url: channel?.authorThumbnails.best(minWidth: 176).flatMap { client?.url(for: $0) }
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel?.author ?? channelName).font(.title3.weight(.semibold))
                    if let count = channel?.subCount {
                        Text("\(VideoFormatting.compact(count)) subscribers").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                subscribeButton(model)
            }
            .padding(.horizontal, 16)
            if let description = channel?.description, !description.isEmpty {
                ExpandableText(
                    text: Text(description).font(.footnote).foregroundStyle(.secondary),
                    expanded: $descriptionExpanded
                )
                .padding(.horizontal, 16)
            }
        }
    }

    /// Subscribe is filled with the accent color; once subscribed it becomes a quiet outlined button,
    /// so its label stays readable in both light and dark mode.
    @ViewBuilder
    private func subscribeButton(_ model: ChannelDetailViewModel) -> some View {
        let label = Text(model.isSubscribed ? "Subscribed" : "Subscribe").font(.subheadline.weight(.semibold))
        if model.isSubscribed {
            Button { Task { await model.toggleSubscription() } } label: { label }
                .buttonStyle(.bordered)
                .disabled(model.isTogglingSubscription)
        } else {
            Button { Task { await model.toggleSubscription() } } label: { label }
                .buttonStyle(.borderedProminent)
                .disabled(model.isTogglingSubscription)
        }
    }

    private func playlistShelf(_ model: ChannelDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Playlists")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(model.playlists) { playlist in
                        MobileChannelPlaylistCard(playlist: playlist)
                            .frame(width: 220)
                            .onAppear {
                                if playlist.id == model.playlists.last?.id {
                                    Task { await model.loadMorePlaylists() }
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

/// Card for one of a channel's public playlists: cover, count badge, title.
struct MobileChannelPlaylistCard: View {
    let playlist: SearchPlaylist

    @Environment(AppModel.self) private var app

    var body: some View {
        // The cover is a YouTube thumbnail; load it through the instance like every other image.
        // `maxres.jpg` makes the instance pick the largest size that exists.
        let covers: [URL] = (playlist.coverVideoID.map { id in
            ["maxres", "mqdefault"].compactMap { try? app.active?.client.absoluteURL("/vi/\(id)/\($0).jpg") }
        } ?? []) + (playlist.playlistThumbnail.flatMap(URL.init(string:)).map { [$0] } ?? [])
        // Invidious reports -1 when YouTube does not say how many videos a list has.
        let count = playlist.videoCount.flatMap { $0 >= 0 ? $0 : nil }
        NavigationLink(value: Route.playlist(id: playlist.playlistId, title: playlist.title)) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    if let primary = covers.first {
                        RemoteImage(url: primary, fallbacks: Array(covers.dropFirst()))
                            .aspectRatio(16 / 9, contentMode: .fill)
                            .clipped()
                    } else {
                        ZStack {
                            Rectangle().fill(Color.secondary.opacity(0.2))
                            Image(systemName: "list.and.film").font(.title).foregroundStyle(.secondary)
                        }
                    }
                    if let count {
                        Label("\(count)", systemImage: "list.bullet")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(.white)
                            .padding(8)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(playlist.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(count.map { "\($0) video\($0 == 1 ? "" : "s")" } ?? "Playlist")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
