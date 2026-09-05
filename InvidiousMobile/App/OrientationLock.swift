import SwiftUI
import UIKit

/// The orientations the app allows right now. With auto-rotate off the interface is held in portrait
/// and the player in landscape; the change of mask is what turns the device view.
@MainActor
enum OrientationLock {
    private(set) static var mask: UIInterfaceOrientationMask = .all

    /// Orientation for the regular interface under the given setting.
    static func interfaceMask(autoRotate: Bool) -> UIInterfaceOrientationMask {
        autoRotate ? .all : .portrait
    }

    /// Orientation for the player under the given setting.
    static func playerMask(autoRotate: Bool) -> UIInterfaceOrientationMask {
        autoRotate ? .all : .landscape
    }

    static func apply(_ mask: UIInterfaceOrientationMask) {
        guard mask != self.mask else { return }
        self.mask = mask
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

/// Lets `OrientationLock` decide which orientations the windows support.
final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
