import SwiftUI
import InvidiousKit

/// Watch history list with swipe-to-remove and a Clear History action.
struct MobileHistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var model: HistoryViewModel?
    @State private var confirmClear = false

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Watch History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let model, !model.videos.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", role: .destructive) { confirmClear = true }
                }
            }
        }
        .alert("Clear watch history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { Task { await model?.clear() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every video from your Invidious account's history. Home recommendations will start over.")
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
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ErrorView(message: message) { Task { await model.load(force: true) } }
        case .loaded:
            if model.videos.isEmpty {
                EmptyStateView(title: "No history yet", message: "Videos you watch will show up here.", systemImage: "clock.arrow.circlepath")
            } else {
                List {
                    ForEach(model.videos) { video in
                        NavigationLink(value: Route.video(video)) {
                            HistoryRow(video: video)
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { Task { await model.remove(video) } }
                        }
                        .onAppear {
                            if video.id == model.videos.last?.id { Task { await model.loadMore() } }
                        }
                    }
                    if model.isLoadingMore {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if let error = model.actionError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.load(force: true) }
            }
        }
    }
}

private struct HistoryRow: View {
    let video: VideoSummary

    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(video.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var thumbnail: some View {
        let client = app.active?.client
        let thumbs = video.videoThumbnails
        let primary = thumbs.first { $0.quality == "medium" } ?? thumbs.best(maxWidth: 640)
        let fallbacks = ["sddefault", "high"].compactMap { q in thumbs.first { $0.quality == q } }
        return ZStack(alignment: .bottomTrailing) {
            RemoteImage(url: primary.flatMap { client?.url(for: $0) }, fallbacks: fallbacks.compactMap { client?.url(for: $0) })
                .aspectRatio(16 / 9, contentMode: .fill)
            if video.lengthSeconds > 0 {
                Text(VideoFormatting.duration(video.lengthSeconds))
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.white)
                    .padding(5)
            }
            if let profile = app.active?.profile.id, let entry = app.resume.position(for: video.videoId, profile: profile) {
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        Rectangle().fill(.red).frame(width: geo.size.width * entry.progress, height: 3)
                    }
                    .frame(height: 3)
                }
            }
        }
        .frame(width: 140, height: 79)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
