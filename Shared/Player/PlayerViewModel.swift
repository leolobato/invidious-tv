import Foundation
import Observation
import os
import AVFoundation
import InvidiousKit

private let vmLog = Logger(subsystem: AppIdentity.logSubsystem, category: "player")

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
    /// Audio languages the video offers (empty when YouTube labels none).
    private(set) var audioTracks: [AudioTrack] = []
    /// Language being played; nil until streams load.
    private(set) var selectedAudioTrack: AudioTrack?

    // Captions
    private(set) var selectedCaption: Caption?

    // Scrubbing
    private(set) var scrubTarget: TimeInterval?
    private var scrubCommitTask: Task<Void, Never>?
    private(set) var storyboard: StoryboardTrack?

    // SponsorBlock
    private(set) var sponsorSegments: [SponsorSegment] = []
    private(set) var skipNotice: String?
    private var skippedSegmentIDs: Set<String> = []
    private var skipNoticeTask: Task<Void, Never>?

    // Controls
    private(set) var controlsVisible = true
    private var hideControlsTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var pendingStart: TimeInterval
    private var markedWatched = false
    private var didBeginLoading = false
    private var renderTimeoutTask: Task<Void, Never>?

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

    /// The video autoplay should continue with: the first recommendation not yet watched.
    func nextVideo(excluding watched: Set<String>) -> VideoSummary? {
        let candidates = details.recommendedVideos.filter { !$0.isUpcoming && !$0.liveNow && $0.videoId != details.videoId }
        return candidates.first { !watched.contains($0.videoId) } ?? candidates.first
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
            // Loading must wait for the render view to create mpv's render context, otherwise the
            // video output fails to initialize and the file plays without video.
            player.onRenderContextReady = { [weak self] in
                self?.beginLoadingIfNeeded()
            }
            if player.hasRenderContext {
                beginLoadingIfNeeded()
            }
            renderTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled, !self.didBeginLoading else { return }
                self.errorMessage = "The video renderer could not be started."
            }
            Task { await loadStoryboard() }
            Task { await loadSponsorSegments() }
            startProgressTimer()
            scheduleHideControls()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginLoadingIfNeeded() {
        guard !didBeginLoading else { return }
        didBeginLoading = true
        renderTimeoutTask?.cancel()
        loadStreams(startAt: pendingStart)
    }

    func stop() {
        renderTimeoutTask?.cancel()
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
        audioTracks = StreamSelector.audioTracks(details.adaptiveFormats)
        hasLoaded = false
        videoSize = nil

        if details.liveNow {
            errorMessage = "Livestreams are not supported yet."
            return
        }

        if let chosen = StreamSelector.select(details, preferences: streamPreferences, audioTrack: selectedAudioTrack), let url = try? client.absoluteURL(chosen.video.url) {
            selection = chosen
            selectedAudioTrack = chosen.audio?.audioTrack
            player.load(url: url, startAt: startAt)
            return
        }

        // Fall back to a muxed progressive stream (720p at best).
        if let stream = details.formatStreams.max(by: { ($0.qualityLabel ?? "") < ($1.qualityLabel ?? "") }), let url = try? client.absoluteURL(stream.url) {
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

    /// Switches the audio language without interrupting the video.
    func selectAudioTrack(_ track: AudioTrack) {
        guard track != selectedAudioTrack, var current = selection else { return }
        guard let audio = StreamSelector.bestAudio(details.adaptiveFormats, track: track), let url = try? client.absoluteURL(audio.url) else { return }
        current.audio = audio
        selection = current
        selectedAudioTrack = audio.audioTrack ?? track
        if hasLoaded {
            player?.replaceAudio(url: url)
        }
    }

    // MARK: - Events

    private func handle(_ event: MPVPlayerEvent) {
        switch event {
        case .fileLoaded:
            hasLoaded = true
            // `start` was set as a per-file option; seek as well in case the demuxer ignored it.
            if pendingStart > 1 {
                player?.seek(to: pendingStart)
                pendingStart = 0
            }
            if let audio = selection?.audio, let url = try? client.absoluteURL(audio.url) {
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
            skipSponsorSegmentIfNeeded(at: time)
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

    /// Sets the scrub target directly (slider dragging). Commit with `commitScrub()`.
    func scrub(to time: TimeInterval) {
        scrubCommitTask?.cancel()
        scrubTarget = min(max(time, 0), max(duration - 1, 0))
        showControls(autoHide: false)
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

    // MARK: - SponsorBlock

    private func loadSponsorSegments() async {
        guard settings.sponsorBlockEnabled, !details.liveNow else { return }
        let client = SponsorBlockClient()
        sponsorSegments = (try? await client.segments(videoID: details.videoId, categories: settings.sponsorBlockCategories)) ?? []
        vmLog.info("sponsorblock: \(self.sponsorSegments.count) segments for \(self.details.videoId, privacy: .public)")
    }

    private func skipSponsorSegmentIfNeeded(at time: TimeInterval) {
        guard !isScrubbing, !sponsorSegments.isEmpty else { return }
        // Only skip when entering the segment near its start; a user who seeks into the middle stays.
        guard let segment = sponsorSegments.first(where: { time >= $0.start && time < min($0.end, $0.start + 1.5) }),
              !skippedSegmentIDs.contains(segment.id) else { return }
        skippedSegmentIDs.insert(segment.id)
        let target = min(segment.end, max(duration - 0.5, segment.end))
        currentTime = target
        player?.seek(to: target)
        vmLog.info("sponsorblock: skipped \(segment.categoryLabel, privacy: .public) \(segment.start)-\(segment.end)")
        skipNotice = "Skipped \(segment.categoryLabel)"
        skipNoticeTask?.cancel()
        skipNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.skipNotice = nil
        }
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
