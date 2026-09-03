import Foundation
import os
import Libmpv

private let mpvLog = Logger(subsystem: "org.lobato.invidioustv", category: "mpv")

/// Events the player reports, delivered on the main thread.
enum MPVPlayerEvent: Sendable {
    case fileLoaded
    case timePosition(Double)
    case duration(Double)
    case paused(Bool)
    case buffering(Bool)
    case coreIdle(Bool)
    case speed(Double)
    case videoSize(width: Int, height: Int)
    case endOfFile
    case error(String)
}

/// Thin wrapper around a libmpv handle: options, commands, property observation and the
/// OpenGL render context. Rendering itself lives in `MPVRenderView`.
final class MPVPlayer: @unchecked Sendable {
    private var handle: OpaquePointer?
    private(set) var renderContext: OpaquePointer?
    private let renderContextLock = NSLock()
    private let commandQueue = DispatchQueue(label: "org.lobato.invidioustv.mpv.commands", qos: .userInitiated)
    private var eventThread: Thread?
    private var isShuttingDown = false
    private let shutdownLock = NSLock()

    /// Called on the main thread for every event.
    var onEvent: (@MainActor (MPVPlayerEvent) -> Void)?
    /// Called on an arbitrary mpv thread whenever a new frame or redraw is needed.
    var onRenderUpdate: (@Sendable () -> Void)?
    /// Called on the main thread once the render context exists and files can be loaded.
    var onRenderContextReady: (@MainActor () -> Void)?

    var hasRenderContext: Bool {
        renderContextLock.lock()
        defer { renderContextLock.unlock() }
        return renderContext != nil
    }

    enum PlayerError: Error, LocalizedError {
        case createFailed
        case initializeFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .createFailed: return "Could not create the video player."
            case .initializeFailed(let code): return "Video player failed to start (\(String(cString: mpv_error_string(code))))."
            }
        }
    }

    init(hardwareDecoding: Bool, userAgent: String) throws {
        guard let mpv = mpv_create() else { throw PlayerError.createFailed }
        handle = mpv

        setOption("vo", "libmpv")
        setOption("keep-open", "yes")
        setOption("pause", "yes")
        setOption("idle", "yes")
        setOption("terminal", "no")
        setOption("msg-level", "all=warn")
        setOption("ytdl", "no")
        setOption("user-agent", userAgent)

        if hardwareDecoding {
            setOption("hwdec", "videotoolbox-copy")
            setOption("hwdec-codecs", "h264,hevc,vp9,av1,prores")
        } else {
            setOption("hwdec", "no")
            setOption("sw-fast", "yes")
        }

        setOption("target-prim", "bt.709")
        setOption("target-trc", "srgb")
        setOption("video-sync", "display-vdrop")
        setOption("framedrop", "decoder+vo")
        setOption("ao", "avfoundation,audiounit")
        setOption("audio-client-name", "Invidious TV")

        setOption("cache", "yes")
        setOption("cache-secs", "30")
        setOption("demuxer-readahead-secs", "20")
        setOption("demuxer-max-bytes", "48MiB")
        setOption("demuxer-max-back-bytes", "16MiB")
        setOption("network-timeout", "15")

        setOption("sub-auto", "no")
        setOption("sub-font-size", "48")
        setOption("sub-border-size", "2.5")
        setOption("sub-margin-y", "60")

        let result = mpv_initialize(mpv)
        guard result >= 0 else {
            mpv_destroy(mpv)
            handle = nil
            throw PlayerError.initializeFailed(result)
        }

        #if DEBUG
        mpv_request_log_messages(mpv, "info")
        #else
        mpv_request_log_messages(mpv, "warn")
        #endif

        observe("time-pos", MPV_FORMAT_DOUBLE)
        observe("duration", MPV_FORMAT_DOUBLE)
        observe("pause", MPV_FORMAT_FLAG)
        observe("paused-for-cache", MPV_FORMAT_FLAG)
        observe("core-idle", MPV_FORMAT_FLAG)
        observe("eof-reached", MPV_FORMAT_FLAG)
        observe("speed", MPV_FORMAT_DOUBLE)
        observe("video-params/w", MPV_FORMAT_INT64)
        observe("video-params/h", MPV_FORMAT_INT64)

        startEventLoop()
    }

    deinit {
        shutdown()
    }

    // MARK: - Playback control

    /// Loads a video URL, starting paused at `startAt`. Call `play()` once ready.
    func load(url: URL, startAt: TimeInterval) {
        // `start` is a per-file option; setting it before loadfile avoids the loadfile argument
        // layout that changed between mpv versions.
        setProperty("start", string: startAt > 1 ? String(Int(startAt)) : "none")
        command(["loadfile", url.absoluteString, "replace"])
    }

    /// Attaches a separate audio stream (used with video-only adaptive formats).
    func addAudio(url: URL) {
        command(["audio-add", url.absoluteString, "select"])
    }

    func play() {
        setProperty("pause", flag: false)
    }

    func pause() {
        setProperty("pause", flag: true)
    }

    func seek(to seconds: TimeInterval) {
        command(["seek", String(format: "%.3f", max(0, seconds)), "absolute+exact"])
    }

    func seek(by seconds: TimeInterval) {
        command(["seek", String(format: "%.1f", seconds), "relative"])
    }

    func setSpeed(_ speed: Double) {
        setProperty("speed", string: String(format: "%.3f", speed))
    }

    /// Loads an external subtitle track, or disables subtitles when nil.
    func setSubtitle(url: URL?) {
        if let url {
            command(["sub-remove"])
            command(["sub-add", url.absoluteString, "select"])
        } else {
            setProperty("sid", string: "no")
        }
    }

    func stop() {
        command(["stop"])
    }

    // MARK: - Render API

    /// Creates the OpenGL render context. The GL context must be current on the calling thread.
    func createRenderContext(getProcAddress: @escaping @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?) -> Bool {
        guard let handle, renderContext == nil else { return false }
        var apiType = MPV_RENDER_API_TYPE_OPENGL
        var initParams = mpv_opengl_init_params(get_proc_address: getProcAddress, get_proc_address_ctx: nil)
        var context: OpaquePointer?
        let result: Int32 = withUnsafeMutablePointer(to: &apiType) { apiPtr in
            withUnsafeMutablePointer(to: &initParams) { initPtr in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                return params.withUnsafeMutableBufferPointer { buffer in
                    mpv_render_context_create(&context, handle, buffer.baseAddress)
                }
            }
        }
        guard result >= 0, let context else { return false }
        renderContextLock.lock()
        renderContext = context
        renderContextLock.unlock()

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        mpv_render_context_set_update_callback(context, { pointer in
            guard let pointer else { return }
            let player = Unmanaged<MPVPlayer>.fromOpaque(pointer).takeUnretainedValue()
            player.onRenderUpdate?()
        }, selfPointer)
        Task { @MainActor [weak self] in
            self?.onRenderContextReady?()
        }
        return true
    }

    /// Creates a CPU render context (used in the simulator, where OpenGL ES is unreliable).
    func createSoftwareRenderContext() -> Bool {
        guard let handle, renderContext == nil else { return false }
        var apiType = MPV_RENDER_API_TYPE_SW
        var context: OpaquePointer?
        let result: Int32 = withUnsafeMutablePointer(to: &apiType) { apiPtr in
            var params: [mpv_render_param] = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiPtr),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return params.withUnsafeMutableBufferPointer { buffer in
                mpv_render_context_create(&context, handle, buffer.baseAddress)
            }
        }
        guard result >= 0, let context else {
            mpvLog.error("software render context failed: \(String(cString: mpv_error_string(result)), privacy: .public)")
            return false
        }
        renderContextLock.lock()
        renderContext = context
        renderContextLock.unlock()
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        mpv_render_context_set_update_callback(context, { pointer in
            guard let pointer else { return }
            let player = Unmanaged<MPVPlayer>.fromOpaque(pointer).takeUnretainedValue()
            player.onRenderUpdate?()
        }, selfPointer)
        Task { @MainActor [weak self] in
            self?.onRenderContextReady?()
        }
        return true
    }

    /// Renders into a CPU buffer of `rgb0` pixels. Returns false when nothing was rendered.
    func renderSoftware(width: Int32, height: Int32, stride: Int, pixels: UnsafeMutableRawPointer) -> Bool {
        renderContextLock.lock()
        defer { renderContextLock.unlock() }
        guard let renderContext else { return false }
        var size: [Int32] = [width, height]
        var strideValue = stride
        let format = strdup("rgb0")
        defer { free(format) }
        let result: Int32 = size.withUnsafeMutableBufferPointer { sizePtr in
            withUnsafeMutablePointer(to: &strideValue) { stridePtr in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_SIZE, data: sizePtr.baseAddress),
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_FORMAT, data: format),
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_STRIDE, data: stridePtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_SW_POINTER, data: pixels),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                return params.withUnsafeMutableBufferPointer { buffer in
                    mpv_render_context_render(renderContext, buffer.baseAddress)
                }
            }
        }
        return result >= 0
    }

    /// Returns true when mpv has a new frame to draw. Call from the render thread.
    func hasNewFrame() -> Bool {
        renderContextLock.lock()
        defer { renderContextLock.unlock() }
        guard let renderContext else { return false }
        let flags = mpv_render_context_update(renderContext)
        return flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0
    }

    /// Renders into the given framebuffer. The GL context must be current.
    func render(fbo: Int32, width: Int32, height: Int32) {
        renderContextLock.lock()
        defer { renderContextLock.unlock() }
        guard let renderContext else { return }
        var framebuffer = mpv_opengl_fbo(fbo: fbo, w: width, h: height, internal_format: 0)
        var flipY: Int32 = 1
        withUnsafeMutablePointer(to: &framebuffer) { fboPtr in
            withUnsafeMutablePointer(to: &flipY) { flipPtr in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                params.withUnsafeMutableBufferPointer { buffer in
                    _ = mpv_render_context_render(renderContext, buffer.baseAddress)
                }
            }
        }
    }

    func reportSwap() {
        renderContextLock.lock()
        defer { renderContextLock.unlock() }
        guard let renderContext else { return }
        mpv_render_context_report_swap(renderContext)
    }

    /// Frees the render context. Must be called on the render thread with the GL context current,
    /// before `shutdown()`.
    func destroyRenderContext() {
        renderContextLock.lock()
        let context = renderContext
        renderContext = nil
        renderContextLock.unlock()
        if let context {
            mpv_render_context_set_update_callback(context, nil, nil)
            mpv_render_context_free(context)
        }
    }

    // MARK: - Shutdown

    func shutdown() {
        shutdownLock.lock()
        if isShuttingDown {
            shutdownLock.unlock()
            return
        }
        isShuttingDown = true
        shutdownLock.unlock()

        onEvent = nil
        onRenderUpdate = nil
        destroyRenderContext()
        commandQueue.sync {
            guard let handle = self.handle else { return }
            mpv_command_string(handle, "quit")
            // Wait briefly for the event thread to observe the shutdown event.
            let deadline = Date().addingTimeInterval(1.0)
            while let thread = self.eventThread, !thread.isFinished, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            mpv_terminate_destroy(handle)
            self.handle = nil
        }
    }

    // MARK: - Internals

    private func setOption(_ name: String, _ value: String) {
        guard let handle else { return }
        mpv_set_option_string(handle, name, value)
    }

    private func setProperty(_ name: String, string value: String) {
        commandQueue.async { [self] in
            guard let handle, !isShutDown else { return }
            mpv_set_property_string(handle, name, value)
        }
    }

    private func setProperty(_ name: String, flag value: Bool) {
        commandQueue.async { [self] in
            guard let handle, !isShutDown else { return }
            var flag: Int32 = value ? 1 : 0
            mpv_set_property(handle, name, MPV_FORMAT_FLAG, &flag)
        }
    }

    private func command(_ arguments: [String]) {
        commandQueue.async { [self] in
            guard let handle, !isShutDown else { return }
            let cStrings = arguments.map { strdup($0) }
            var pointers: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) }
            pointers.append(nil)
            let status = pointers.withUnsafeMutableBufferPointer { buffer in
                mpv_command(handle, buffer.baseAddress)
            }
            if status < 0 {
                mpvLog.error("command \(arguments.first ?? "", privacy: .public) failed: \(String(cString: mpv_error_string(status)), privacy: .public)")
            }
            cStrings.forEach { free($0) }
        }
    }

    private var isShutDown: Bool {
        shutdownLock.lock()
        defer { shutdownLock.unlock() }
        return isShuttingDown
    }

    private func observe(_ name: String, _ format: mpv_format) {
        guard let handle else { return }
        mpv_observe_property(handle, 0, name, format)
    }

    private func startEventLoop() {
        let thread = Thread { [weak self] in
            self?.runEventLoop()
        }
        thread.name = "org.lobato.invidioustv.mpv.events"
        thread.qualityOfService = .userInitiated
        eventThread = thread
        thread.start()
    }

    private func runEventLoop() {
        while true {
            guard let handle, !isShutDown else { return }
            guard let event = mpv_wait_event(handle, 0.1) else { continue }
            let id = event.pointee.event_id
            if id == MPV_EVENT_SHUTDOWN { return }
            if id == MPV_EVENT_NONE { continue }
            if let mapped = map(event.pointee) {
                deliver(mapped)
            }
        }
    }

    private func deliver(_ event: MPVPlayerEvent) {
        Task { @MainActor [weak self] in
            self?.onEvent?(event)
        }
    }

    private func map(_ event: mpv_event) -> MPVPlayerEvent? {
        switch event.event_id {
        case MPV_EVENT_LOG_MESSAGE:
            guard let data = event.data else { return nil }
            let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
            let prefix = String(cString: message.prefix)
            let text = String(cString: message.text).trimmingCharacters(in: .whitespacesAndNewlines)
            switch message.log_level {
            case MPV_LOG_LEVEL_FATAL, MPV_LOG_LEVEL_ERROR:
                mpvLog.error("[\(prefix, privacy: .public)] \(text, privacy: .public)")
            case MPV_LOG_LEVEL_WARN:
                mpvLog.warning("[\(prefix, privacy: .public)] \(text, privacy: .public)")
            default:
                mpvLog.info("[\(prefix, privacy: .public)] \(text, privacy: .public)")
            }
            return nil
        case MPV_EVENT_COMMAND_REPLY:
            if event.error < 0 {
                mpvLog.error("command failed: \(String(cString: mpv_error_string(event.error)), privacy: .public)")
            }
            return nil
        case MPV_EVENT_FILE_LOADED:
            return .fileLoaded
        case MPV_EVENT_END_FILE:
            guard let data = event.data else { return nil }
            let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            switch endFile.reason {
            case MPV_END_FILE_REASON_EOF:
                return .endOfFile
            case MPV_END_FILE_REASON_ERROR:
                return .error(String(cString: mpv_error_string(endFile.error)))
            default:
                return nil
            }
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.data else { return nil }
            let property = data.assumingMemoryBound(to: mpv_event_property.self).pointee
            let name = String(cString: property.name)
            guard let value = property.data else { return nil }
            switch (name, property.format) {
            case ("time-pos", MPV_FORMAT_DOUBLE):
                return .timePosition(value.assumingMemoryBound(to: Double.self).pointee)
            case ("duration", MPV_FORMAT_DOUBLE):
                return .duration(value.assumingMemoryBound(to: Double.self).pointee)
            case ("speed", MPV_FORMAT_DOUBLE):
                return .speed(value.assumingMemoryBound(to: Double.self).pointee)
            case ("pause", MPV_FORMAT_FLAG):
                return .paused(value.assumingMemoryBound(to: Int32.self).pointee != 0)
            case ("paused-for-cache", MPV_FORMAT_FLAG):
                return .buffering(value.assumingMemoryBound(to: Int32.self).pointee != 0)
            case ("core-idle", MPV_FORMAT_FLAG):
                return .coreIdle(value.assumingMemoryBound(to: Int32.self).pointee != 0)
            case ("eof-reached", MPV_FORMAT_FLAG):
                return value.assumingMemoryBound(to: Int32.self).pointee != 0 ? .endOfFile : nil
            case ("video-params/w", MPV_FORMAT_INT64), ("video-params/h", MPV_FORMAT_INT64):
                return videoSizeEvent()
            default:
                return nil
            }
        default:
            return nil
        }
    }

    private func videoSizeEvent() -> MPVPlayerEvent? {
        guard let handle else { return nil }
        var width: Int64 = 0
        var height: Int64 = 0
        guard mpv_get_property(handle, "video-params/w", MPV_FORMAT_INT64, &width) >= 0,
              mpv_get_property(handle, "video-params/h", MPV_FORMAT_INT64, &height) >= 0,
              width > 0, height > 0 else { return nil }
        return .videoSize(width: Int(width), height: Int(height))
    }
}
