import SwiftUI
import InvidiousKit

/// Full-screen player with custom controls.
struct PlayerView: View {
    let details: VideoDetails
    let summary: VideoSummary
    let startAt: TimeInterval
    let session: ActiveSession

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayerViewModel?
    @State private var surface = PlayerSurfaceHandle()
    @State private var optionsVisible = false
    @FocusState private var optionFocus: OptionFocus?

    enum OptionFocus: Hashable {
        case speed, captions, quality, close
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let model {
                    if let player = model.player {
                        MPVVideoView(player: player)
                            .ignoresSafeArea()
                    }

                    PlayerSurface(handle: surface, handlesMenu: { true }) { action in
                        handle(action, model: model, width: geo.size.width)
                    }
                    .ignoresSafeArea()

                    overlay(model)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            if model == nil {
                let vm = PlayerViewModel(details: details, summary: summary, startAt: startAt, session: session, settings: app.settings, resume: app.resume)
                model = vm
                vm.start()
            }
        }
        .onDisappear {
            model?.stop()
        }
        .onChange(of: model?.finished ?? false) { _, finished in
            if finished { dismiss() }
        }
        .onChange(of: optionFocus) { _, focus in
            if focus != nil {
                model?.showControls(autoHide: false)
            }
        }
    }

    // MARK: - Remote handling

    private func handle(_ action: PlayerSurfaceAction, model: PlayerViewModel, width: CGFloat) {
        switch action {
        case .select:
            if model.isScrubbing {
                model.commitScrub()
            } else {
                model.togglePause()
            }
        case .playPause:
            if model.isScrubbing { model.commitScrub() }
            model.togglePause()
        case .skipBackward:
            model.skip(-1)
        case .skipForward:
            model.skip(1)
        case .down:
            model.showControls(autoHide: false)
            optionsVisible = true
            optionFocus = .speed
        case .up:
            if model.controlsVisible {
                model.hideControls()
            } else {
                model.showControls()
            }
        case .menu:
            if model.isScrubbing {
                model.cancelScrub()
            } else if optionsVisible {
                closeOptions(model)
            } else if model.controlsVisible && !model.isPaused {
                model.hideControls()
            } else {
                dismiss()
            }
        case .panChanged(let deltaX):
            model.handlePan(deltaX: deltaX, surfaceWidth: width)
        case .panEnded:
            model.handlePanEnded()
        }
    }

    private func closeOptions(_ model: PlayerViewModel) {
        optionsVisible = false
        optionFocus = nil
        surface.focus()
        model.showControls()
    }

    // MARK: - Overlay

    @ViewBuilder
    private func overlay(_ model: PlayerViewModel) -> some View {
        ZStack {
            if let error = model.errorMessage {
                errorState(error, model: model)
            } else if !model.hasLoaded || model.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }

            if model.controlsVisible || model.isPaused || optionsVisible {
                controls(model)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.controlsVisible)
        .animation(.easeInOut(duration: 0.2), value: optionsVisible)
    }

    private func controls(_ model: PlayerViewModel) -> some View {
        VStack(spacing: 0) {
            // Top: title
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                    Text(model.author)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                if !model.qualityLabel.isEmpty {
                    Text(model.qualityLabel)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal, 80)
            .padding(.top, 60)
            .padding(.bottom, 30)
            .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            // Bottom: progress and options
            VStack(spacing: 24) {
                if model.isPaused && model.hasLoaded && !model.isScrubbing {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 44))
                        .padding(.bottom, 10)
                }
                ProgressBarView(model: model, surfaceWidth: 1920 - 160)
                if optionsVisible {
                    optionsRow(model)
                }
            }
            .padding(.horizontal, 80)
            .padding(.top, 120)
            .padding(.bottom, 60)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        }
        .foregroundStyle(.white)
    }

    private func optionsRow(_ model: PlayerViewModel) -> some View {
        HStack(spacing: 24) {
            Menu {
                ForEach(AppSettings.speedOptions, id: \.self) { value in
                    Button {
                        model.setSpeed(value)
                    } label: {
                        Label(speedLabel(value), systemImage: model.speed == value ? "checkmark" : "")
                    }
                }
            } label: {
                Label("Speed \(speedLabel(model.speed))", systemImage: "gauge.with.dots.needle.67percent")
            }
            .focused($optionFocus, equals: .speed)

            if !model.captions.isEmpty {
                Menu {
                    Button {
                        model.selectCaption(nil)
                    } label: {
                        Label("Off", systemImage: model.selectedCaption == nil ? "checkmark" : "")
                    }
                    ForEach(model.captions) { caption in
                        Button {
                            model.selectCaption(caption)
                        } label: {
                            Label(caption.label, systemImage: model.selectedCaption == caption ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label(model.selectedCaption?.label ?? "Captions", systemImage: "captions.bubble")
                }
                .focused($optionFocus, equals: .captions)
            }

            if model.availableHeights.count > 1 {
                Menu {
                    Button {
                        model.setQuality(nil)
                    } label: {
                        Label("Auto", systemImage: model.qualityOverride == nil ? "checkmark" : "")
                    }
                    ForEach(model.availableHeights, id: \.self) { height in
                        Button {
                            model.setQuality(height)
                        } label: {
                            Label("\(height)p", systemImage: model.qualityOverride == height ? "checkmark" : "")
                        }
                    }
                } label: {
                    Label(model.qualityOverride.map { "\($0)p" } ?? "Quality", systemImage: "4k.tv")
                }
                .focused($optionFocus, equals: .quality)
            }

            Button {
                closeOptions(model)
            } label: {
                Label("Done", systemImage: "chevron.up")
            }
            .focused($optionFocus, equals: .close)
        }
        .onExitCommand {
            closeOptions(model)
        }
        .onMoveCommand { direction in
            if direction == .up {
                closeOptions(model)
            }
        }
    }

    private func speedLabel(_ value: Double) -> String {
        value == 1 ? "Normal" : String(format: "%g×", value)
    }

    private func errorState(_ message: String, model: PlayerViewModel) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
            Text(message)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 900)
            Button("Close") { dismiss() }
        }
        .foregroundStyle(.white)
        .padding(60)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Progress bar with a scrubber, time labels and a storyboard preview while scrubbing.
struct ProgressBarView: View {
    let model: PlayerViewModel
    let surfaceWidth: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let width = geo.size.width
                let x = width * model.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3)).frame(height: 8)
                    Capsule().fill(Color.accentColor).frame(width: x, height: 8)
                    Circle()
                        .fill(.white)
                        .frame(width: model.isScrubbing ? 26 : 18, height: model.isScrubbing ? 26 : 18)
                        .offset(x: x - (model.isScrubbing ? 13 : 9))
                        .animation(.easeOut(duration: 0.1), value: model.isScrubbing)

                    if model.isScrubbing {
                        SeekPreviewView(model: model)
                            .frame(width: 320, height: 180 + 40)
                            .offset(x: min(max(x - 160, 0), width - 320), y: -150)
                    }
                }
                .frame(height: 26)
            }
            .frame(height: 26)

            HStack {
                Text(VideoFormatting.duration(Int(model.displayTime)))
                Spacer()
                if model.details.liveNow {
                    Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(.red)
                } else {
                    Text("-" + VideoFormatting.duration(max(0, Int(model.duration - model.displayTime))))
                }
            }
            .font(.callout.monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
        }
    }
}

/// Storyboard frame for the scrub position.
struct SeekPreviewView: View {
    let model: PlayerViewModel

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
            .frame(width: 320, height: 180)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.7), lineWidth: 2))
            Text(VideoFormatting.duration(Int(model.displayTime)))
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
