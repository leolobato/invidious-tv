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
///
/// Swipes on the touch surface do not arrive as arrow presses on a real Siri Remote (only clicks on
/// the clickpad edges do, and only on remotes that have one), so the pan recognizer also decides
/// whether a gesture is a horizontal scrub or a vertical swipe and reports `.up` / `.down` itself.
final class PlayerSurfaceUIView: UIView {
    var onAction: ((PlayerSurfaceAction) -> Void)?
    /// When false, Menu is passed to the system (dismisses the player).
    var handlesMenu: () -> Bool = { false }

    /// False while the options row or the autoplay card is up: the surface then cannot hold focus,
    /// so UIKit has to move it onto those SwiftUI buttons instead of leaving it here, where
    /// left/right would keep scrubbing.
    var focusEnabled = true {
        didSet {
            guard focusEnabled != oldValue else { return }
            setNeedsFocusUpdate()
            updateFocusIfNeeded()
        }
    }

    private enum PanAxis { case undecided, horizontal, vertical }

    private var lastPanX: CGFloat = 0
    private var panAxis: PanAxis = .undecided
    /// Movement before the gesture commits to an axis. The touch surface maps to roughly the
    /// screen's points, so this is a small fraction of a swipe.
    private static let axisThreshold: CGFloat = 40
    /// Vertical travel that counts as a swipe up or down.
    private static let swipeThreshold: CGFloat = 120

    override init(frame: CGRect) {
        super.init(frame: frame)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFocused: Bool { focusEnabled }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            requestFocus()
        }
    }

    func requestFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.focusEnabled else { return }
            UIFocusSystem.focusSystem(for: self)?.requestFocusUpdate(to: self)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isFocused else { return }
        let translation = gesture.translation(in: self)
        switch gesture.state {
        case .began:
            panAxis = .undecided
            lastPanX = 0
        case .changed:
            if panAxis == .undecided, hypot(translation.x, translation.y) >= Self.axisThreshold {
                panAxis = abs(translation.x) >= abs(translation.y) ? .horizontal : .vertical
            }
            guard panAxis == .horizontal else { return }
            // Includes the movement accumulated while the axis was still undecided.
            let delta = translation.x - lastPanX
            lastPanX = translation.x
            onAction?(.panChanged(deltaX: delta))
        case .ended, .cancelled, .failed:
            switch panAxis {
            case .horizontal:
                onAction?(.panEnded)
            case .vertical where gesture.state == .ended && abs(translation.y) >= Self.swipeThreshold:
                onAction?(translation.y > 0 ? .down : .up)
            default:
                break
            }
            panAxis = .undecided
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
    var focusEnabled = true
    let onAction: (PlayerSurfaceAction) -> Void

    func makeUIView(context: Context) -> PlayerSurfaceUIView {
        let view = PlayerSurfaceUIView(frame: .zero)
        view.backgroundColor = .clear
        view.onAction = onAction
        view.handlesMenu = handlesMenu
        view.focusEnabled = focusEnabled
        handle.view = view
        return view
    }

    func updateUIView(_ uiView: PlayerSurfaceUIView, context: Context) {
        uiView.onAction = onAction
        uiView.handlesMenu = handlesMenu
        uiView.focusEnabled = focusEnabled
    }
}
