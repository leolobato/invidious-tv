import SwiftUI
import InvidiousKit

/// Full-screen touch player: tap for controls, slider to scrub, menus for speed, captions and quality.
struct MobilePlayerView: View {
    let details: VideoDetails
    let summary: VideoSummary
    let startAt: TimeInterval
    let session: ActiveSession
    var queue: [VideoSummary] = []

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayerViewModel?
    @State private var sliderValue: Double = 0
    @State private var isSliding = false
    @State private var upNext: VideoSummary?
    @State private var countdown = 8
    @State private var countdownTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                if let player = model.player {
                    MPVVideoView(player: player)
                        .id(ObjectIdentifier(player))
                        .ignoresSafeArea()
                }
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        if model.controlsVisible { model.hideControls() } else { model.showControls() }
                    }
                overlay(model)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            if model == nil {
                let vm = PlayerViewModel(details: details, summary: summary, startAt: startAt, session: session, settings: app.settings, resume: app.resume)
                model = vm
                vm.start()
            }
        }
        .onDisappear { model?.stop() }
        .onChange(of: model?.finished ?? false) { _, finished in
            guard finished, let model else { return }
            if let next = queuedNext(after: model.details.videoId) ?? (app.settings.autoplayNext ? model.nextVideo(excluding: session.watchedIDs) : nil) {
                startCountdown(next)
            } else {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func overlay(_ model: PlayerViewModel) -> some View {
        if let error = model.errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                Text(error).multilineTextAlignment(.center)
                Button("Close") { dismiss() }.buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
            .padding(24)
        } else if !model.hasLoaded || model.isBuffering {
            ProgressView().tint(.white).controlSize(.large)
        }

        if model.controlsVisible || model.isPaused {
            controls(model).transition(.opacity)
        }

        if let notice = model.skipNotice {
            VStack { Spacer(); HStack { Label(notice, systemImage: "forward.fill").font(.footnote.weight(.semibold)).padding(8).background(.black.opacity(0.7), in: Capsule()).foregroundStyle(.white).padding(.leading, 20).padding(.bottom, 100); Spacer() } }
        }

        if let upNext {
            upNextCard(upNext)
        }
    }

    private func controls(_ model: PlayerViewModel) -> some View {
        VStack {
            HStack(alignment: .top) {
                Button { dismiss() } label: { Image(systemName: "chevron.down").font(.title2).padding(10) }
                VStack(alignment: .leading) {
                    Text(model.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(model.author).font(.caption).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                Menu {
                    Menu("Speed") {
                        ForEach(AppSettings.speedOptions, id: \.self) { value in
                            Button { model.setSpeed(value) } label: { Label(value == 1 ? "Normal" : String(format: "%g×", value), systemImage: model.speed == value ? "checkmark" : "") }
                        }
                    }
                    if !model.captions.isEmpty {
                        Menu("Captions") {
                            Button { model.selectCaption(nil) } label: { Label("Off", systemImage: model.selectedCaption == nil ? "checkmark" : "") }
                            ForEach(model.captions) { caption in
                                Button { model.selectCaption(caption) } label: { Label(caption.label, systemImage: model.selectedCaption == caption ? "checkmark" : "") }
                            }
                        }
                    }
                    if model.audioTracks.count > 1 {
                        Menu("Audio") {
                            ForEach(model.audioTracks) { track in
                                Button { model.selectAudioTrack(track) } label: { Label(track.displayName, systemImage: model.selectedAudioTrack == track ? "checkmark" : "") }
                            }
                        }
                    }
                    if model.availableHeights.count > 1 {
                        Menu("Quality") {
                            Button { model.setQuality(nil) } label: { Label("Auto", systemImage: model.qualityOverride == nil ? "checkmark" : "") }
                            ForEach(model.availableHeights, id: \.self) { height in
                                Button { model.setQuality(height) } label: { Label("\(height)p", systemImage: model.qualityOverride == height ? "checkmark" : "") }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title2).padding(10)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .background(LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom))

            Spacer()

            HStack(spacing: 48) {
                Button { model.skip(-1) } label: { Image(systemName: "gobackward.10").font(.system(size: 34)) }
                Button { model.togglePause() } label: { Image(systemName: model.isPaused ? "play.fill" : "pause.fill").font(.system(size: 52)) }
                Button { model.skip(1) } label: { Image(systemName: "goforward.10").font(.system(size: 34)) }
            }

            Spacer()

            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { isSliding ? sliderValue : model.displayTime },
                        set: { value in
                            sliderValue = value
                            model.scrub(to: value)
                        }
                    ),
                    in: 0...max(model.duration, 1),
                    onEditingChanged: { editing in
                        isSliding = editing
                        if !editing { model.commitScrub() }
                    }
                )
                .tint(.red)
                HStack {
                    Text(VideoFormatting.clockTime(Int(model.displayTime)))
                    Spacer()
                    Text(model.qualityLabel).foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("-" + VideoFormatting.clockTime(max(0, Int(model.duration - model.displayTime))))
                }
                .font(.caption.monospacedDigit())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
        }
        .foregroundStyle(.white)
    }

    private func upNextCard(_ next: VideoSummary) -> some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Up next in \(countdown)").font(.caption).foregroundStyle(.secondary)
                    Text(next.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                }
                Spacer()
                Button("Cancel") { countdownTask?.cancel(); upNext = nil; dismiss() }.buttonStyle(.bordered)
                Button("Play") { countdownTask?.cancel(); Task { await playNext() } }.buttonStyle(.borderedProminent)
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(16)
        }
    }

    private func queuedNext(after videoID: String) -> VideoSummary? {
        guard let index = queue.firstIndex(where: { $0.videoId == videoID }) else { return nil }
        return queue.dropFirst(index + 1).first { !$0.isUpcoming && !$0.liveNow }
    }

    private func startCountdown(_ next: VideoSummary) {
        upNext = next
        countdown = 8
        countdownTask?.cancel()
        countdownTask = Task {
            while countdown > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                countdown -= 1
            }
            await playNext()
        }
    }

    private func playNext() async {
        guard let next = upNext else { return }
        do {
            let nextDetails = try await session.client.video(id: next.videoId, proxy: app.settings.proxyMedia)
            model?.stop()
            let resumeAt = app.resume.resumePoint(for: next.videoId, profile: session.profile.id) ?? 0
            let vm = PlayerViewModel(details: nextDetails, summary: next, startAt: resumeAt, session: session, settings: app.settings, resume: app.resume)
            model = vm
            upNext = nil
            vm.start()
        } catch {
            session.handle(error)
            dismiss()
        }
    }
}
