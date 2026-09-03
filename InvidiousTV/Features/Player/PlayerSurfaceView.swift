import SwiftUI
import UIKit

/// Remote input the player surface reports.
enum PlayerSurfaceAction {
    case select
    case playPause
    case skipBackward
    case skipForward
    case up
    case down
    case menu
    case panChanged(deltaX: CGFloat)
    case panEnded
}

/// Focusable UIKit view that turns Siri Remote presses and touch-surface pans into actions.
final class PlayerSurfaceUIView: UIView {
    var onAction: ((PlayerSurfaceAction) -> Void)?
    /// When false, Menu is passed to the system (dismisses the player).
    var handlesMenu: () -> Bool = { false }

    private var lastPanX: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFocused: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            requestFocus()
        }
    }

    func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            UIFocusSystem.focusSystem(for: self)?.requestFocusUpdate(to: self)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isFocused else { return }
        switch gesture.state {
        case .began:
            lastPanX = gesture.translation(in: self).x
        case .changed:
            let x = gesture.translation(in: self).x
            let delta = x - lastPanX
            lastPanX = x
            onAction?(.panChanged(deltaX: delta))
        case .ended, .cancelled, .failed:
            onAction?(.panEnded)
        default:
            break
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            switch press.type {
            case .select:
                onAction?(.select)
            case .playPause:
                onAction?(.playPause)
            case .leftArrow:
                onAction?(.skipBackward)
            case .rightArrow:
                onAction?(.skipForward)
            case .upArrow:
                onAction?(.up)
            case .downArrow:
                onAction?(.down)
            case .menu:
                if handlesMenu() {
                    onAction?(.menu)
                } else {
                    unhandled.insert(press)
                }
            default:
                unhandled.insert(press)
            }
        }
        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let passthrough = presses.filter { $0.type == .menu && !handlesMenu() }
        if !passthrough.isEmpty {
            super.pressesEnded(Set(passthrough), with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        super.pressesCancelled(presses, with: event)
    }
}

/// Holds a reference to the live surface so SwiftUI can hand focus back to it.
@MainActor
final class PlayerSurfaceHandle {
    weak var view: PlayerSurfaceUIView?

    func focus() {
        view?.requestFocus()
    }
}

struct PlayerSurface: UIViewRepresentable {
    let handle: PlayerSurfaceHandle
    let handlesMenu: () -> Bool
    let onAction: (PlayerSurfaceAction) -> Void

    func makeUIView(context: Context) -> PlayerSurfaceUIView {
        let view = PlayerSurfaceUIView(frame: .zero)
        view.backgroundColor = .clear
        view.onAction = onAction
        view.handlesMenu = handlesMenu
        handle.view = view
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceUIView, context: Context) {
        uiView.onAction = onAction
        uiView.handlesMenu = handlesMenu
    }
}
