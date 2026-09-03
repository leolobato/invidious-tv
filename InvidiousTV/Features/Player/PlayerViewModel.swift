import Foundation
import Observation
import AVFoundation
import InvidiousKit

/// Drives one playback session: stream selection, MPV control, progress saving, scrubbing.
@MainActor
@Observable
final class PlayerViewModel {
    let details: VideoDetails
    let summary: VideoSummary
    private let session: ActiveSession
    private let settings: AppSettings
    private let resume: ResumeStore

    private(set) var player: MPVPlayer?
    private(set) var errorMessage: String?

    // Playback state
    private(set) var isPaused = true
    private(set) var isBuffering = false
    private(set) var hasLoaded = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval
    private(set) var speed: Double = 1
    private(set) var videoSize: (width: Int, height: Int)?
    private(set) var finished = false

    // Streams
    private(set) var selection: StreamSelection?
    private(set) var availableHeights: [Int] = []
    /// nil means automatic (best allowed).
    var qualityOverride: Int?

    // Captions
    private(set) var selectedCaption: Caption?

    // Scrubbing
    private(set) var scrubTarget: TimeInterval?
    private var scrubCommitTask: Task<Void, Never>?
    private(set) var storyboard: StoryboardTrack?

    // Controls
    private(set) var controlsVisible = true
    private var hideControlsTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var pendingStart: TimeInterval
    private var markedWatched = false

    static let skipInterval: TimeInterval = 10
    static let controlsTimeout: TimeInterval = 4
    static let scrubCommitDelay: TimeInterval = 3

    init(details: VideoDetails, summary: VideoSummary, startAt: TimeInterval, session: ActiveSession, settings: AppSettings, resume: ResumeStore) {
        self.details = details
        self.summary = summary
        self.session = session
        self.settings = settings
        self.resume = resume
        self.duration = TimeInterval(details.lengthSeconds)
        self.pendingStart = startAt
        self.currentTime = startAt
    }

    var client: InvidiousClient { session.client }
    var title: String { details.title }
    var author: String { details.author }
    var captions: [Caption] { details.captions }

    var displayTime: TimeInterval { scrubTarget ?? currentTime }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(displayTime / duration, 0), 1)
    }

    var isScrubbing: Bool { scrubTarget != nil }

    var qualityLabel: String {
        if let videoSize {
            return "\(videoSize.height)p"
        }
        return selection?.label ?? ""
    }

    // MARK: - Lifecycle

    func start() {
        guard player == nil else { return }
        configureAudioSession()
        do {
            #if targetEnvironment(simulator)
            let hardware = false
            #else
            let hardware = true
            #endif
            let player = try MPVPlayer(hardwareDecoding: hardware, userAgent: "InvidiousTV/1.0")
            player.onEvent = { [weak self] event in
                self?.handle(event)
            }
            self.player = player
            player.setSpeed(settings.defaultSpeed)
            speed = settings.defaultSpeed
            loadStreams(startAt: pendingStart)
            Task { await loadStoryboard() }
            startProgressTimer()
            scheduleHideControls()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        hideControlsTask?.cancel()
        scrubCommitTask?.cancel()
        saveProgress()
        player?.shutdown()
        player = nil
    }

    private func configureAudioSession() {
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .moviePlayback)
        try? audio.setActive(true)
    }

    // MARK: - Streams

    private var streamPreferences: StreamPreferences {
        var prefs = settings.streamPreferences
        if let qualityOverride {
            prefs.maxHeight = qualityOverride
        }
        return prefs
    }

    private func loadStreams(startAt: TimeInterval) {
        guard let player else { return }
        availableHeights = StreamSelector.availableHeights(details, preferences: settings.streamPreferences)
        hasLoaded = false
        videoSize = nil

        if details.liveNow, let hls = details.hlsUrl, let url = try? client.absoluteURL(hls) {
            selection = nil
            player.load(url: url, startAt: 0)
            return
        }

        if let chosen = StreamSelector.select(details, preferences: streamPreferences), let url = URL(string: chosen.video.url) {
            selection = chosen
            player.load(url: url, startAt: startAt)
            return
        }

        // Fall back to a muxed progressive stream (720p at best).
        if let stream = details.formatStreams.max(by: { ($0.qualityLabel ?? "") < ($1.qualityLabel ?? "") }), let url = URL(string: stream.url) {
            selection = nil
            player.load(url: url, startAt: startAt)
            return
        }

        errorMessage = "No playable stream was found for this video."
    }

    /// Reloads at the current position with a different quality cap.
    func setQuality(_ height: Int?) {
        guard qualityOverride != height else { return }
        qualityOverride = height
        pendingStart = currentTime
        loadStreams(startAt: currentTime)
    }

    // MARK: - Events

    private func handle(_ event: MPVPlayerEvent) {
        switch event {
        case .fileLoaded:
            hasLoaded = true
            if let audio = selection?.audio, let url = URL(string: audio.url) {
                player?.addAudio(url: url)
            }
            if let selectedCaption, let url = client.captionURL(selectedCaption) {
                player?.setSubtitle(url: url)
            }
            player?.play()
            if !markedWatched {
                markedWatched = true
                Task { await session.markWatched(details.videoId) }
            }
        case .timePosition(let time):
            currentTime = time
        case .duration(let value):
            if value > 0 { duration = value }
        case .paused(let paused):
            isPaused = paused
            if paused { saveProgress() }
        case .buffering(let buffering):
            isBuffering = buffering
        case .coreIdle:
            break
        case .speed(let value):
            speed = value
        case .videoSize(let width, let height):
            videoSize = (width, height)
        case .endOfFile:
            guard hasLoaded, !finished else { return }
            finished = true
            currentTime = duration
            saveProgress()
        case .error(let message):
            errorMessage = "Playback failed: \(message)"
        }
    }

    // MARK: - Controls

    func togglePause() {
        guard let player else { return }
        if isPaused {
            player.play()
        } else {
            player.pause()
        }
        showControls()
    }

    func skip(_ direction: Int) {
        let delta = Self.skipInterval * Double(direction)
        if isScrubbing {
            moveScrub(by: delta)
        } else {
            let target = min(max(currentTime + delta, 0), max(duration - 1, 0))
            currentTime = target
            player?.seek(to: target)
            showControls()
        }
    }

    func handlePan(deltaX: CGFloat, surfaceWidth: CGFloat) {
        guard duration > 0 else { return }
        let width = max(surfaceWidth, 1)
        // A full-width swipe covers a quarter of the video, at least a minute and at most 10 minutes.
        let secondsPerSweep = min(max(duration * 0.25, 60), 600)
        let delta = Double(deltaX / width) * secondsPerSweep
        moveScrub(by: delta)
    }

    func handlePanEnded() {
        scheduleScrubCommit()
    }

    private func moveScrub(by delta: TimeInterval) {
        let base = scrubTarget ?? currentTime
        scrubTarget = min(max(base + delta, 0), max(duration - 1, 0))
        showControls(autoHide: false)
        scheduleScrubCommit()
    }

    /// Seeks to the scrub target.
    func commitScrub() {
        scrubCommitTask?.cancel()
        guard let target = scrubTarget else { return }
        scrubTarget = nil
        currentTime = target
        player?.seek(to: target)
        showControls()
    }

    func cancelScrub() {
        scrubCommitTask?.cancel()
        scrubTarget = nil
        showControls()
    }

    private func scheduleScrubCommit() {
        scrubCommitTask?.cancel()
        scrubCommitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.scrubCommitDelay))
            guard !Task.isCancelled else { return }
            self?.commitScrub()
        }
    }

    func setSpeed(_ value: Double) {
        player?.setSpeed(value)
        speed = value
    }

    func selectCaption(_ caption: Caption?) {
        selectedCaption = caption
        if let caption, let url = client.captionURL(caption) {
            player?.setSubtitle(url: url)
        } else {
            player?.setSubtitle(url: nil)
        }
    }

    func showControls(autoHide: Bool = true) {
        controlsVisible = true
        hideControlsTask?.cancel()
        if autoHide {
            scheduleHideControls()
        }
    }

    func hideControls() {
        hideControlsTask?.cancel()
        controlsVisible = false
    }

    private func scheduleHideControls() {
        hideControlsTask?.cancel()
        hideControlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.controlsTimeout))
            guard !Task.isCancelled, let self else { return }
            if !self.isPaused && !self.isScrubbing {
                self.controlsVisible = false
            }
        }
    }

    // MARK: - Progress

    private func startProgressTimer() {
        progressTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveProgress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func saveProgress() {
        guard hasLoaded, duration > 0, !details.liveNow else { return }
        resume.save(
            videoID: details.videoId,
            position: currentTime,
            duration: duration,
            video: details.summary,
            profile: session.profile.id
        )
    }

    // MARK: - Storyboards

    private func loadStoryboard() async {
        guard !details.liveNow else { return }
        do {
            let response = try await client.storyboards(videoID: details.videoId)
            let specs = response.storyboards.filter { $0.count != -1 }
            guard let spec = specs.first(where: { $0.width >= 160 }) ?? specs.last else { return }
            storyboard = try await client.storyboardTrack(spec: spec)
        } catch {
            // Previews are optional.
        }
    }
}
