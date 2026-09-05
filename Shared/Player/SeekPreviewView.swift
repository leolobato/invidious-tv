import SwiftUI
import InvidiousKit

/// Storyboard frame for the scrub position.
struct SeekPreviewView: View {
    let model: PlayerViewModel
    /// Width of the frame; the height follows 16:9.
    var width: CGFloat = 320

    @State private var image: UIImage?
    @State private var loadedCue: StoryboardCue?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.8))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .frame(width: width, height: width * 9 / 16)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.7), lineWidth: 2))
            Text(VideoFormatting.clockTime(Int(model.displayTime)))
                .font(.callout.weight(.semibold).monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.black.opacity(0.7), in: Capsule())
        }
        .task(id: cueKey) {
            await loadCue()
        }
    }

    private var currentCue: StoryboardCue? {
        model.storyboard?.cue(at: model.displayTime)
    }

    private var cueKey: String {
        guard let cue = currentCue else { return "" }
        return "\(cue.imageURL.absoluteString)|\(cue.x)|\(cue.y)"
    }

    private func loadCue() async {
        guard let cue = currentCue, cue != loadedCue else { return }
        guard let sprite = await SpriteCache.shared.image(for: cue.imageURL) else { return }
        let scale = sprite.scale
        let rect = CGRect(x: CGFloat(cue.x) * scale, y: CGFloat(cue.y) * scale, width: CGFloat(cue.width) * scale, height: CGFloat(cue.height) * scale)
        guard let cg = sprite.cgImage?.cropping(to: rect) else { return }
        image = UIImage(cgImage: cg)
        loadedCue = cue
    }
}

/// Small in-memory cache of storyboard sprite sheets.
actor SpriteCache {
    static let shared = SpriteCache()
    private var images: [URL: UIImage] = [:]
    private var order: [URL] = []

    func image(for url: URL) async -> UIImage? {
        if let cached = images[url] { return cached }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let image = UIImage(data: data) else { return nil }
        images[url] = image
        order.append(url)
        if order.count > 12, let oldest = order.first {
            order.removeFirst()
            images.removeValue(forKey: oldest)
        }
        return image
    }
}
