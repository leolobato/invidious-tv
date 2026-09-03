import SwiftUI
import NukeUI

/// Cached network image with a placeholder and an optional fallback URL.
struct RemoteImage: View {
    let url: URL?
    var fallback: URL? = nil
    var contentMode: ContentMode = .fill

    @State private var useFallback = false

    var body: some View {
        LazyImage(url: useFallback ? fallback : url) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if state.error != nil, fallback != nil, !useFallback {
                Color.clear.onAppear { useFallback = true }
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
