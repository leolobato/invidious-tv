import SwiftUI
import InvidiousKit

/// Collapsible comments list on the video details page.
struct CommentsSection: View {
    let videoID: String

    @Environment(AppModel.self) private var app
    @State private var expanded = false
    @State private var page: CommentsPage?
    @State private var comments: [Comment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if DEBUG
            let _ = debugAutoExpand()
            #endif
            Button {
                withAnimation { expanded.toggle() }
                if expanded && comments.isEmpty { Task { await load() } }
            } label: {
                HStack {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
            }
            .buttonStyle(.plain)
            .tint(.white)

            if expanded {
                if let errorMessage, comments.isEmpty {
                    Text(errorMessage).foregroundStyle(.secondary)
                } else if comments.isEmpty && !isLoading {
                    Text("No comments.").foregroundStyle(.secondary)
                }
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment)
                    }
                    if isLoading {
                        ProgressView().padding(20)
                    } else if page?.continuation != nil {
                        Button("Load more comments") { Task { await load() } }
                    }
                }
            }
        }
    }

    #if DEBUG
    /// `INVIDIOUS_DEBUG_COMMENTS=1` expands comments on appear for screenshots.
    private func debugAutoExpand() {
        guard ProcessInfo.processInfo.environment["INVIDIOUS_DEBUG_COMMENTS"] != nil, !expanded, comments.isEmpty, !isLoading else { return }
        Task { @MainActor in
            expanded = true
            await load()
        }
    }
    #endif

    private var title: String {
        if let count = page?.commentCount {
            return "Comments (\(VideoFormatting.compact(count)))"
        }
        return "Comments"
    }

    private func load() async {
        guard let client = app.active?.client, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let next = try await client.comments(videoID: videoID, continuation: page?.continuation)
            page = next
            let known = Set(comments.map(\.id))
            comments.append(contentsOf: next.comments.filter { !known.contains($0.id) })
        } catch {
            app.active?.handle(error)
            errorMessage = "Comments could not be loaded: \(error.localizedDescription)"
        }
    }
}

struct CommentRow: View {
    let comment: Comment

    @Environment(AppModel.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            ChannelAvatar(
                channelID: comment.authorId,
                name: comment.author.replacingOccurrences(of: "@", with: ""),
                size: 56,
                url: comment.authorThumbnails.best(minWidth: 88).flatMap { app.active?.client.url(for: $0) }
            )
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(comment.author)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(comment.authorIsChannelOwner ? .white : .secondary)
                    if comment.isPinned {
                        Label("Pinned", systemImage: "pin.fill").font(.caption).foregroundStyle(.secondary)
                    }
                    if let when = comment.publishedText {
                        Text(when).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(comment.content)
                    .font(.callout)
                    .lineLimit(focused ? nil : 4)
                HStack(spacing: 16) {
                    Label(VideoFormatting.compact(comment.likeCount), systemImage: "hand.thumbsup")
                    if let replies = comment.replies, replies.replyCount > 0 {
                        Label("\(replies.replyCount) replies", systemImage: "bubble.left")
                    }
                    if comment.creatorHeart {
                        Image(systemName: "heart.fill").foregroundStyle(.red)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color.white.opacity(focused ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 14))
        .focusable()
        .focused($focused)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}
