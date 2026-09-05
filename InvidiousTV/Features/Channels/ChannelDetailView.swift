import SwiftUI
import InvidiousKit

/// Channel header plus its videos, newest first.
struct ChannelDetailView: View {
    let channelID: String
    let channelName: String

    @Environment(AppModel.self) private var app
    @State private var model: ChannelDetailViewModel?

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                LoadingView()
            }
        }
        .navigationBarHidden(true)
        .task {
            guard model == nil, let session = app.active else { return }
            let vm = ChannelDetailViewModel(channelID: channelID, session: session, avatars: app.channelAvatars)
            model = vm
            await vm.load()
        }
    }

    @ViewBuilder
    private func content(_ model: ChannelDetailViewModel) -> some View {
        switch model.header {
        case .failed(let message) where model.videos.isEmpty:
            ErrorView(message: message) { Task { await model.load() } }
        case .idle, .loading where model.videos.isEmpty && model.header.value == nil:
            LoadingView()
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(model)
                    if !model.playlists.isEmpty {
                        playlistShelf(model)
                        Text("Videos")
                            .font(.title3.weight(.semibold))
                            .padding(.horizontal, 60)
                            .padding(.top, 20)
                    }
                    VideoGrid(videos: model.videos, showChannel: false) {
                        Task { await model.loadMore() }
                    }
                    if model.isLoadingMore {
                        ProgressView().padding(40)
                    }
                }
            }
        }
    }

    private func playlistShelf(_ model: ChannelDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Playlists")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 60)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(model.playlists) { playlist in
                        ChannelPlaylistCard(playlist: playlist)
                            .frame(width: 400)
                            .onAppear {
                                if playlist.id == model.playlists.last?.id {
                                    Task { await model.loadMorePlaylists() }
                                }
                            }
                    }
                }
                .padding(.horizontal, 60)
                .padding(.vertical, 30)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func header(_ model: ChannelDetailViewModel) -> some View {
        let channel = model.header.value
        let client = app.active?.client
        VStack(alignment: .leading, spacing: 0) {
            if let banner = channel?.authorBanners.best(minWidth: 1920), let url = client?.url(for: banner) {
                Color.clear
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .overlay { RemoteImage(url: url) }
                    .clipped()
            }
            HStack(alignment: .center, spacing: 30) {
                ChannelAvatar(
                    channelID: channelID,
                    name: channel?.author ?? channelName,
                    size: 140,
                    url: channel?.authorThumbnails.best(minWidth: 176).flatMap { client?.url(for: $0) }
                )
                VStack(alignment: .leading, spacing: 8) {
                    Text(channel?.author ?? channelName)
                        .font(.title.weight(.semibold))
                    if let count = channel?.subCount {
                        Text("\(VideoFormatting.compact(count)) subscribers")
                            .foregroundStyle(.secondary)
                    }
                    if let description = channel?.description, !description.isEmpty {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .frame(maxWidth: 1000, alignment: .leading)
                    }
                }
                Spacer()
                Button {
                    Task { await model.toggleSubscription() }
                } label: {
                    Label(model.isSubscribed ? "Subscribed" : "Subscribe", systemImage: model.isSubscribed ? "checkmark" : "plus")
                }
                .disabled(model.isTogglingSubscription)
            }
            .padding(.horizontal, 60)
            .padding(.top, 30)
            // Whole header is a focus target, so "up" from any thumbnail reaches the Subscribe
            // button, and one more "up" reaches the tab bar.
            .focusSection()
        }
    }
}
