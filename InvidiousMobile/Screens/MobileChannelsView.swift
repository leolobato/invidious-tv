import SwiftUI
import InvidiousKit

struct MobileChannelsView: View {
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @State private var model: ChannelsViewModel
    @State private var filter = ""

    init(session: ActiveSession) {
        self.session = session
        _model = State(initialValue: ChannelsViewModel(session: session))
    }

    var body: some View {
        @Bindable var settings = app.settings
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                ErrorView(message: message) { Task { await model.load() } }
            case .loaded(let channels) where channels.isEmpty:
                EmptyStateView(title: "No subscriptions", message: "Channels you subscribe to will be listed here.", systemImage: "person.2")
            case .loaded(let channels):
                let shown = model.sorted(ChannelsViewModel.filtered(channels, query: filter), by: settings.channelSort)
                List {
                    if shown.isEmpty, !filter.isEmpty {
                        Text("No channels match \u{201C}\(filter)\u{201D}.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shown) { channel in
                        NavigationLink(value: Route.channel(id: channel.authorId, name: channel.author)) {
                            HStack(spacing: 14) {
                                ChannelAvatar(channelID: channel.authorId, name: channel.author, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(channel.author).font(.body)
                                    if let date = model.latestUpload[channel.authorId], let relative = VideoFormatting.relativeDate(date) {
                                        Text("Last upload \(relative)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Channels")
        .searchable(text: $filter, prompt: "Filter by name")
        .textInputAutocapitalization(.never)
        .profileToolbar(session: session)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort", selection: $settings.channelSort) {
                        ForEach(ChannelSortOrder.allCases) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .task { await model.load() }
        .task(id: settings.channelSort) {
            if settings.channelSort == .recentUploads { await model.loadRecentUploads() }
        }
        .refreshable { await model.load() }
    }
}
