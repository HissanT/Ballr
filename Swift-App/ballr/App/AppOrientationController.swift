import UIKit

final class BallrAppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }
}

enum BallrOrientationController {
    private static var activeCameraPresentations = 0
    private static var restoreGeneration = 0

    static func beginCameraPresentation() {
        activeCameraPresentations += 1
        lockDribblingLandscape()
    }

    static func endCameraPresentation() {
        activeCameraPresentations = max(0, activeCameraPresentations - 1)
        restoreDefaultOrientation()
    }

    static func lockDribblingLandscape() {
        restoreGeneration += 1
        update(mask: .landscape, preferredOrientation: .landscapeRight)
    }

    static func restoreDefaultOrientation() {
        restoreGeneration += 1
        let generation = restoreGeneration

        guard activeCameraPresentations == 0 else {
            return
        }

        DispatchQueue.main.async {
            guard activeCameraPresentations == 0, restoreGeneration == generation else {
                return
            }
            update(mask: .portrait, preferredOrientation: .portrait)
        }
    }

    static func cameraInterfaceOrientation() -> UIInterfaceOrientation {
        let sceneOrientation = activeWindowScene()?.interfaceOrientation
        guard activeCameraPresentations > 0 || BallrAppDelegate.orientationLock == .landscape else {
            return sceneOrientation ?? .landscapeRight
        }

        switch sceneOrientation {
        case .landscapeLeft, .landscapeRight:
            return sceneOrientation ?? .landscapeRight
        default:
            return .landscapeRight
        }
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
