import SwiftUI
import InvidiousKit

/// Every subscribed channel, sortable, as a grid or a list.
struct ChannelsView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var model: ChannelsViewModel

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    init(session: ActiveSession) {
        self.session = session
        _model = State(initialValue: ChannelsViewModel(session: session))
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                LoadingView()
            case .failed(let message):
                ErrorView(message: message) { Task { await model.load() } }
            case .loaded(let channels):
                if channels.isEmpty {
                    EmptyStateView(title: "No subscriptions", message: "Channels you subscribe to will be listed here.", systemImage: "person.2")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            toolbar
                            if app.settings.channelLayout == .grid {
                                grid(model.sorted(channels, by: app.settings.channelSort))
                            } else {
                                list(model.sorted(channels, by: app.settings.channelSort))
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 30)
                    }
                }
            }
        }
        .task { await model.load() }
        .task(id: app.settings.channelSort) {
            if app.settings.channelSort == .recentUploads {
                await model.loadRecentUploads()
            }
        }
        .refreshable { await model.load() }
    }

    private var toolbar: some View {
        @Bindable var settings = app.settings
        return HStack(spacing: 20) {
            Menu {
                Picker("Sort", selection: $settings.channelSort) {
                    ForEach(ChannelSortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
            } label: {
                Label("Sort: \(settings.channelSort.label)", systemImage: "arrow.up.arrow.down")
            }

            Button {
                settings.channelLayout = settings.channelLayout.toggled
            } label: {
                Label(settings.channelLayout.toggled.label, systemImage: settings.channelLayout.toggled.systemImage)
            }

            if settings.channelSort == .recentUploads, model.isLoadingRecent {
                ProgressView()
                    .controlSize(.small)
            }

            Spacer()

            Text("\(model.state.value?.count ?? 0) channels")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func grid(_ channels: [SubscribedChannel]) -> some View {
        LazyVGrid(columns: Self.columns, spacing: 40) {
            ForEach(channels) { channel in
                ChannelTile(channel: channel)
            }
        }
        .padding(.vertical, 10)
    }

    private func list(_ channels: [SubscribedChannel]) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(channels) { channel in
                ChannelRow(channel: channel, latestUpload: model.latestUpload[channel.authorId])
            }
        }
        .padding(.vertical, 10)
    }
}

/// Wide row for the list layout.
struct ChannelRow: View {
    let channel: SubscribedChannel
    let latestUpload: Date?

    var body: some View {
        NavigationLink(value: Route.channel(id: channel.authorId, name: channel.author)) {
            HStack(spacing: 24) {
                ChannelAvatar(channelID: channel.authorId, name: channel.author, size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.author)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if let latestUpload, let relative = VideoFormatting.relativeDate(latestUpload) {
                        Text("Last upload \(relative)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
        }
    }
}
