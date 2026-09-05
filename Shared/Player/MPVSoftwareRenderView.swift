import UIKit
import InvidiousKit
import os

private let swLog = Logger(subsystem: AppIdentity.logSubsystem, category: "render")

/// CPU-rendered video view for the simulator, where OpenGL ES is not dependable.
/// mpv writes `rgb0` pixels into a buffer that is shown as the layer contents.
final class MPVSoftwareRenderView: UIView {
    private var player: MPVPlayer?
    private let renderQueue = DispatchQueue(label: AppIdentity.label("mpv.swrender"), qos: .userInteractive)
    private var pixelBuffer: PixelBuffer?
    private var buffer: UnsafeMutableRawPointer? { pixelBuffer?.pointer }
    private var bufferWidth = 0
    private var bufferHeight = 0
    private var bufferStride = 0
    private var renderScheduled = false
    private let scheduleLock = NSLock()
    private var isTornDown = false
    private var renderedFrames = 0
    /// Set when the view changed size, so a paused video is redrawn at the new size.
    private var needsRedraw = false

    /// Keeps the CPU path affordable.
    private static let maxWidth = 1280

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.contentsGravity = .resizeAspect
        layer.isOpaque = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func attach(_ player: MPVPlayer) {
        guard self.player == nil else { return }
        self.player = player
        renderQueue.async { [self] in
            let created = player.createSoftwareRenderContext()
            swLog.info("software render context created=\(created)")
            player.onRenderUpdate = { [weak self] in
                self?.scheduleRender()
            }
        }
    }

    func tearDown() {
        renderQueue.sync { [self] in
            guard !isTornDown else { return }
            isTornDown = true
            player?.onRenderUpdate = nil
            player?.destroyRenderContext()
            player = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        renderQueue.async { [self] in needsRedraw = true }
        scheduleRender()
    }

    private func scheduleRender() {
        scheduleLock.lock()
        if renderScheduled {
            scheduleLock.unlock()
            return
        }
        renderScheduled = true
        scheduleLock.unlock()
        renderQueue.async { [self] in
            scheduleLock.lock()
            renderScheduled = false
            scheduleLock.unlock()
            performRender()
        }
    }

    private func performRender() {
        guard !isTornDown, let player else { return }
        let hasNewFrame = player.hasNewFrame()
        guard hasNewFrame || needsRedraw else { return }
        needsRedraw = false
        let targetSize = DispatchQueue.main.sync { bounds.size }
        guard targetSize.width > 0, targetSize.height > 0 else { return }
        ensureBuffer(for: targetSize)
        guard let buffer else { return }
        guard player.renderSoftware(width: Int32(bufferWidth), height: Int32(bufferHeight), stride: bufferStride, pixels: buffer) else { return }
        player.reportSwap()
        guard let image = makeImage() else { return }
        renderedFrames += 1
        if renderedFrames == 1 {
            swLog.info("software frame #1 at \(self.bufferWidth)x\(self.bufferHeight)")
        }
        DispatchQueue.main.async { [weak self] in
            self?.layer.contents = image
        }
    }

    private func ensureBuffer(for size: CGSize) {
        var width = Int(size.width)
        var height = Int(size.height)
        if width > Self.maxWidth {
            height = height * Self.maxWidth / max(width, 1)
            width = Self.maxWidth
        }
        width = max(width & ~1, 2)
        height = max(height & ~1, 2)
        guard width != bufferWidth || height != bufferHeight || pixelBuffer == nil else { return }
        bufferWidth = width
        bufferHeight = height
        bufferStride = ((width * 4 + 63) / 64) * 64
        pixelBuffer = PixelBuffer(byteCount: bufferStride * height)
    }

    private func makeImage() -> CGImage? {
        guard let buffer else { return nil }
        let data = Data(bytes: buffer, count: bufferStride * bufferHeight)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: bufferWidth,
            height: bufferHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bufferStride,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

/// Owns a zeroed pixel buffer and frees it when released.
final class PixelBuffer {
    let pointer: UnsafeMutableRawPointer
    let byteCount: Int

    init(byteCount: Int) {
        self.byteCount = byteCount
        pointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 64)
        pointer.initializeMemory(as: UInt8.self, repeating: 0, count: byteCount)
    }

    deinit {
        pointer.deallocate()
    }
}
