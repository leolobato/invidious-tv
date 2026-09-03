import SwiftUI
import InvidiousKit

/// Alphabetical grid of every subscribed channel.
struct ChannelsView: View {
    let session: ActiveSession

    @State private var state: LoadState<[SubscribedChannel]> = .idle

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 40), count: 6)

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                LoadingView()
            case .failed(let message):
                ErrorView(message: message) { Task { await load() } }
            case .loaded(let channels):
                if channels.isEmpty {
                    EmptyStateView(title: "No subscriptions", message: "Channels you subscribe to will be listed here.", systemImage: "person.2")
                } else {
                    ScrollView {
                        LazyVGrid(columns: Self.columns, spacing: 40) {
                            ForEach(channels) { channel in
                                ChannelTile(channel: channel)
                            }
                        }
                        .padding(.horizontal, 60)
                        .padding(.vertical, 40)
                    }
                }
            }
        }
        .navigationTitle("Channels")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let channels = try await session.client.subscriptions()
                .sorted { $0.author.localizedCaseInsensitiveCompare($1.author) == .orderedAscending }
            state = .loaded(channels)
        } catch {
            session.handle(error)
            state = .failed(error.localizedDescription)
        }
    }
}
