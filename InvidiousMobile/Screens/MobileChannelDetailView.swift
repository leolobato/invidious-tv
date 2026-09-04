import SwiftUI
import InvidiousKit

struct MobileChannelDetailView: View {
    let channelID: String
    let channelName: String

    @Environment(AppModel.self) private var app
    @State private var model: ChannelDetailViewModel?

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
                RemoteImage(url: url)
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipped()
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
                Button {
                    Task { await model.toggleSubscription() }
                } label: {
                    Text(model.isSubscribed ? "Subscribed" : "Subscribe")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isSubscribed ? .secondary : .primary)
                .disabled(model.isTogglingSubscription)
            }
            .padding(.horizontal, 16)
            if let description = channel?.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 16)
            }
        }
    }
}
