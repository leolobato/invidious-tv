import SwiftUI
import NukeUI

/// Cached network image with a placeholder and an ordered list of fallback URLs.
struct RemoteImage: View {
    let url: URL?
    var fallbacks: [URL] = []
    var contentMode: ContentMode = .fill

    @State private var attempt = 0

    private var candidates: [URL] {
        ([url].compactMap { $0 } + fallbacks)
    }

    private var currentURL: URL? {
        let list = candidates
        guard attempt < list.count else { return nil }
        return list[attempt]
    }

    var body: some View {
        LazyImage(url: currentURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if state.error != nil, attempt + 1 < candidates.count {
                Color.clear.onAppear { attempt += 1 }
            } else {
                placeholder
            }
        }
        .id(url)
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.08))
            Image(systemName: "play.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
        }
    }
}

extension RemoteImage {
    /// Convenience for the common single-fallback case.
    init(url: URL?, fallback: URL?, contentMode: ContentMode = .fill) {
        self.init(url: url, fallbacks: [fallback].compactMap { $0 }, contentMode: contentMode)
    }
}
