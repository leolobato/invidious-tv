import UIKit
import OpenGLES
import QuartzCore
import SwiftUI
import os

private let renderLog = Logger(subsystem: "org.lobato.invidioustv", category: "render")

/// Looks up OpenGL ES entry points for libmpv.
private func mpvGetProcAddress(_ context: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbol = String(cString: name)
    guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengles" as CFString)
        ?? CFBundleCreate(kCFAllocatorDefault, URL(fileURLWithPath: "/System/Library/Frameworks/OpenGLES.framework") as CFURL) else {
        return nil
    }
    return CFBundleGetFunctionPointerForName(bundle, symbol as CFString)
}

/// UIView backed by a CAEAGLLayer that libmpv renders into on a dedicated queue.
final class MPVRenderView: UIView {
    private var player: MPVPlayer?
    private var glContext: EAGLContext?
    private var framebuffer: GLuint = 0
    private var colorRenderbuffer: GLuint = 0
    private var renderWidth: GLint = 0
    private var renderHeight: GLint = 0
    private let renderQueue = DispatchQueue(label: "org.lobato.invidioustv.mpv.render", qos: .userInteractive)
    private var renderScheduled = false
    private let scheduleLock = NSLock()
    private var isTornDown = false
    private var renderedFrames = 0

    override class var layerClass: AnyClass { CAEAGLLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        if let layer = layer as? CAEAGLLayer {
            layer.isOpaque = true
            layer.drawableProperties = [
                kEAGLDrawablePropertyRetainedBacking: false,
                kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8,
            ]
            layer.contentsScale = UIScreen.main.scale
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Creates the GL context, framebuffer and mpv render context.
    func attach(_ player: MPVPlayer) {
        guard self.player == nil else { return }
        self.player = player
        renderQueue.async { [self] in
            guard let context = EAGLContext(api: .openGLES3) ?? EAGLContext(api: .openGLES2) else {
                renderLog.error("EAGLContext creation failed")
                return
            }
            glContext = context
            EAGLContext.setCurrent(context)
            createFramebufferLocked()
            let created = player.createRenderContext(getProcAddress: mpvGetProcAddress)
            EAGLContext.setCurrent(nil)
            renderLog.info("render context created=\(created) framebuffer=\(self.framebuffer) size=\(self.renderWidth)x\(self.renderHeight)")
            player.onRenderUpdate = { [weak self] in
                self?.scheduleRender()
            }
        }
    }

    /// Releases GL and mpv render resources. Safe to call more than once.
    func tearDown() {
        renderQueue.sync { [self] in
            guard !isTornDown else { return }
            isTornDown = true
            player?.onRenderUpdate = nil
            if let glContext {
                EAGLContext.setCurrent(glContext)
                glFinish()
                player?.destroyRenderContext()
                deleteFramebuffer()
                EAGLContext.setCurrent(nil)
            }
            player = nil
            glContext = nil
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard glContext != nil, bounds.width > 0, bounds.height > 0 else { return }
        renderQueue.sync { [self] in
            guard let glContext, !isTornDown else { return }
            EAGLContext.setCurrent(glContext)
            glFinish()
            deleteFramebuffer()
            createFramebufferLocked()
            EAGLContext.setCurrent(nil)
        }
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

    /// Runs on the render queue.
    private func performRender() {
        guard !isTornDown, let player, let glContext, framebuffer != 0 else { return }
        guard player.hasNewFrame() else { return }
        EAGLContext.setCurrent(glContext)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        player.render(fbo: GLint(framebuffer), width: renderWidth, height: renderHeight)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        if glContext.presentRenderbuffer(Int(GL_RENDERBUFFER)) {
            player.reportSwap()
            renderedFrames += 1
            if renderedFrames == 1 || renderedFrames % 300 == 0 {
                renderLog.info("presented frame #\(self.renderedFrames) at \(self.renderWidth)x\(self.renderHeight)")
            }
        } else {
            renderLog.warning("presentRenderbuffer failed")
        }
        EAGLContext.setCurrent(nil)
    }

    /// Requires the GL context to be current. Runs on main (layer access) or render queue.
    private func createFramebufferLocked() {
        guard let glContext, let eaglLayer = layer as? CAEAGLLayer else { return }
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glGenRenderbuffers(1, &colorRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        guard glContext.renderbufferStorage(Int(GL_RENDERBUFFER), from: eaglLayer) else {
            deleteFramebuffer()
            return
        }
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &renderWidth)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &renderHeight)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        if glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) != GLenum(GL_FRAMEBUFFER_COMPLETE) || renderWidth == 0 || renderHeight == 0 {
            renderLog.warning("framebuffer incomplete or empty (\(self.renderWidth)x\(self.renderHeight)), bounds=\(self.bounds.debugDescription)")
            deleteFramebuffer()
            return
        }
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
    }

    private func deleteFramebuffer() {
        if framebuffer != 0 {
            glDeleteFramebuffers(1, &framebuffer)
            framebuffer = 0
        }
        if colorRenderbuffer != 0 {
            glDeleteRenderbuffers(1, &colorRenderbuffer)
            colorRenderbuffer = 0
        }
        renderWidth = 0
        renderHeight = 0
    }
}

/// SwiftUI wrapper for the platform render view: OpenGL ES on devices, CPU rendering in the simulator.
struct MPVVideoView: UIViewRepresentable {
    let player: MPVPlayer

    #if targetEnvironment(simulator)
    typealias RenderView = MPVSoftwareRenderView
    #else
    typealias RenderView = MPVRenderView
    #endif

    func makeUIView(context: Context) -> RenderView {
        let view = RenderView(frame: .zero)
        view.attach(player)
        return view
    }

    func updateUIView(_ uiView: RenderView, context: Context) {}

    static func dismantleUIView(_ uiView: RenderView, coordinator: ()) {
        uiView.tearDown()
    }
}
