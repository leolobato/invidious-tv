import SwiftUI
import InvidiousKit

/// Watch history grid with a Clear History action.
struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var model: HistoryViewModel?
    @State private var confirmClear = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                LoadingView()
            }
        }
        .task {
            guard model == nil, let session = app.active else { return }
            let model = HistoryViewModel(session: session, resume: app.resume)
            self.model = model
            await model.load(force: false)
        }
    }

    @ViewBuilder
    private func content(_ model: HistoryViewModel) -> some View {
        switch model.state {
        case .idle, .loading:
            LoadingView()
        case .failed(let message):
            ErrorView(message: message) { Task { await model.load(force: true) } }
        case .loaded:
            if model.videos.isEmpty {
                EmptyStateView(title: "No history yet", message: "Videos you watch will show up here.", systemImage: "clock.arrow.circlepath")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 30) {
                        HStack {
                            Text("Watch History")
                                .font(.title2.weight(.semibold))
                            Spacer()
                            Button("Clear History", role: .destructive) { confirmClear = true }
                        }
                        .focusSection()
                        VideoGrid(videos: model.videos) {
                            Task { await model.loadMore() }
                        }
                        if model.isLoadingMore {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 40)
                }
                .alert("Clear watch history?", isPresented: $confirmClear) {
                    Button("Clear", role: .destructive) { Task { await model.clear() } }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes every video from your Invidious account's history. Home recommendations will start over.")
                }
            }
        }
    }
}
