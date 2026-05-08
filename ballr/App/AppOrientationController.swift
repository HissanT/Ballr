import UIKit

final class BallrAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .allButUpsideDown

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

enum BallrOrientationController {
    static func lockDribblingLandscape() {
        update(mask: .landscape, preferredOrientation: .landscapeRight)
    }

    static func restoreDefaultOrientation() {
        update(mask: .portrait, preferredOrientation: .portrait)
    }

    private static func update(
        mask: UIInterfaceOrientationMask,
        preferredOrientation: UIInterfaceOrientation?
    ) {
        BallrAppDelegate.orientationLock = mask

        guard let windowScene = activeWindowScene() else {
            return
        }

        windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in
            // Ignore geometry update failures and still attempt device rotation.
        }

        if let preferredOrientation {
            UIDevice.current.setValue(
                preferredOrientation.deviceOrientation.rawValue,
                forKey: "orientation"
            )
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }
}

private extension UIInterfaceOrientation {
    var deviceOrientation: UIDeviceOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return .unknown
        }
    }
}
