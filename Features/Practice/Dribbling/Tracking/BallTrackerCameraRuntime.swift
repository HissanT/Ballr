import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit
import Vision

final class BallTrackerCameraController: NSObject, ObservableObject {
    @Published private(set) var overlayState: BallTrackerOverlayState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var isStarting = true

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "ballr.dribbling.session")
    private let videoOutputQueue = DispatchQueue(label: "ballr.dribbling.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let tracker = BallTrackerEngine()
    private let processingSemaphore = DispatchSemaphore(value: 1)

    private var resources: BallTrackerResources?
    private var request: VNCoreMLRequest?
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isObservingOrientationChanges = false

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init()
        previewLayer.videoGravity = .resizeAspectFill
    }

    deinit {
        stop()
    }

    func start() {
        publish {
            $0.errorMessage = nil
            $0.permissionDenied = false
            $0.isStarting = true
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.configureAndStartSession()
                } else {
                    self.publish {
                        $0.permissionDenied = true
                        $0.errorMessage = BallTrackerCameraError.cameraPermissionDenied.localizedDescription
                        $0.isStarting = false
                    }
                }
            }
        case .denied, .restricted:
            publish {
                $0.permissionDenied = true
                $0.errorMessage = BallTrackerCameraError.cameraPermissionDenied.localizedDescription
                $0.isStarting = false
            }
        @unknown default:
            publish {
                $0.errorMessage = "Unable to determine the current camera permission state."
                $0.isStarting = false
            }
        }
    }

    func stop() {
        stopObservingOrientationChanges()

        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.tracker.reset()
        }

        publish {
            $0.overlayState = .idle
            $0.isStarting = false
        }
    }

    func displayRect(for trackerNormalizedRect: CGRect) -> CGRect? {
        guard !previewLayer.bounds.isEmpty else {
            return nil
        }

        let metadataRect = previewMetadataRect(fromTrackerRect: trackerNormalizedRect)
        guard !metadataRect.isNull, !metadataRect.isEmpty else {
            return nil
        }

        let displayRect = previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
        guard !displayRect.isNull, !displayRect.isEmpty else {
            return nil
        }
        return displayRect
    }

    private func previewMetadataRect(fromTrackerRect trackerRect: CGRect) -> CGRect {
        var rect = trackerRect
            .standardized
            .intersection(unitRect)

        guard !rect.isNull, !rect.isEmpty else {
            return .null
        }

        // Tracker rects are normalized with a top-left origin. SwiftUI uses top-left
        // layer points, and AVCaptureVideoPreviewLayer handles the aspect-fill scale.
        // The analysis output is intentionally not mirrored, but the front preview is,
        // so flip x only at the display boundary.
        if
            resources?.config.frontendNotes.mirrorPreviewOnly == true,
            previewLayer.connection?.isVideoMirrored == true
        {
            rect.origin.x = 1.0 - rect.origin.x - rect.width
            rect = rect.standardized.intersection(unitRect)
        }

        return rect
    }

    private var unitRect: CGRect {
        CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    @objc
    private func handleDeviceOrientationDidChange() {
        sessionQueue.async {
            self.applyConnectionPreferences()
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async {
            do {
                try self.configureIfNeeded()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                self.applyConnectionPreferences()
                self.startObservingOrientationChanges()
                self.publish {
                    $0.isStarting = false
                }
            } catch {
                self.publish {
                    $0.errorMessage = error.localizedDescription
                    $0.isStarting = false
                }
            }
        }
    }

    private func configureIfNeeded() throws {
        guard !isConfigured else {
            return
        }

        let resources = try BallTrackerConfig.load()
        let visionModel = try resources.makeVisionModel()
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            self?.handleVisionResult(request: request, error: error)
        }
        request.imageCropAndScaleOption = resources.config.visionCropAndScaleOption

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = preferredSessionPreset()

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else {
            throw BallTrackerCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw BallTrackerCameraError.configurationFailed("Unable to add the front camera input.")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw BallTrackerCameraError.configurationFailed("Unable to add the video output.")
        }
        session.addOutput(videoOutput)

        self.resources = resources
        self.request = request
        isConfigured = true
    }

    private func preferredSessionPreset() -> AVCaptureSession.Preset {
        if session.canSetSessionPreset(.hd1920x1080) {
            return .hd1920x1080
        }
        if session.canSetSessionPreset(.hd1280x720) {
            return .hd1280x720
        }
        if session.canSetSessionPreset(.high) {
            return .high
        }
        return session.sessionPreset
    }

    private func applyConnectionPreferences() {
        let interfaceOrientation = Self.currentInterfaceOrientation()
        guard let videoOrientation = AVCaptureVideoOrientation(interfaceOrientation: interfaceOrientation) else {
            return
        }

        if let previewConnection = previewLayer.connection {
            if previewConnection.isVideoOrientationSupported {
                previewConnection.videoOrientation = videoOrientation
            }
            if previewConnection.isVideoMirroringSupported {
                previewConnection.automaticallyAdjustsVideoMirroring = false
                previewConnection.isVideoMirrored = true
            }
        }

        if let outputConnection = videoOutput.connection(with: .video) {
            if outputConnection.isVideoOrientationSupported {
                outputConnection.videoOrientation = videoOrientation
            }
            if outputConnection.isVideoMirroringSupported {
                outputConnection.automaticallyAdjustsVideoMirroring = false
                outputConnection.isVideoMirrored = false
            }
        }
    }

    private func handleVisionResult(request: VNRequest, error: Error?) {
        if let error {
            publish {
                $0.errorMessage = "Ball tracking failed: \(error.localizedDescription)"
            }
            return
        }

        guard let resources else {
            return
        }

        let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []
        let overlayState = tracker.process(observations: observations, config: resources.config)
        logFilteredObservationsIfNeeded(observations, overlayState: overlayState, config: resources.config)

        publish {
            $0.errorMessage = nil
            $0.overlayState = overlayState
        }
    }

    private func startObservingOrientationChanges() {
        DispatchQueue.main.async {
            guard !self.isObservingOrientationChanges else {
                return
            }

            self.isObservingOrientationChanges = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleDeviceOrientationDidChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
        }
    }

    private func stopObservingOrientationChanges() {
        DispatchQueue.main.async {
            guard self.isObservingOrientationChanges else {
                return
            }

            self.isObservingOrientationChanges = false
            NotificationCenter.default.removeObserver(
                self,
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    private func publish(_ updates: @escaping (BallTrackerCameraController) -> Void) {
        DispatchQueue.main.async {
            updates(self)
        }
    }

    private func logFilteredObservationsIfNeeded(
        _ observations: [VNRecognizedObjectObservation],
        overlayState: BallTrackerOverlayState,
        config: BallTrackerConfig
    ) {
        #if DEBUG
        guard overlayState.candidateCount == 0, !observations.isEmpty else {
            return
        }

        let labels = observations.prefix(4).map { observation in
            observation.labels.prefix(3)
                .map { "\($0.identifier):\(String(format: "%.2f", $0.confidence))" }
                .joined(separator: ",")
        }
        print(
            "BallTracker filtered \(observations.count) Vision observations. " +
            "Accepted labels: \(config.acceptedBallLabels.sorted()). Top labels: \(labels)"
        )
        #endif
    }

    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation ?? .landscapeRight
    }
}

extension BallTrackerCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let request, let resources else {
            return
        }

        guard processingSemaphore.wait(timeout: .now()) == .success else {
            return
        }
        defer { processingSemaphore.signal() }

        let orientation = resources.config.frontendNotes.passCaptureOrientation
            ? CGImagePropertyOrientation(videoOrientation: connection.videoOrientation)
            : .up
        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: orientation,
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            publish {
                $0.errorMessage = "Vision request failed: \(error.localizedDescription)"
            }
        }
    }
}

struct BallTrackerPreviewLayerView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> BallTrackerPreviewHostingView {
        BallTrackerPreviewHostingView(previewLayer: previewLayer)
    }

    func updateUIView(_ uiView: BallTrackerPreviewHostingView, context: Context) {
        uiView.update(previewLayer: previewLayer)
    }
}

final class BallTrackerPreviewHostingView: UIView {
    private var attachedPreviewLayer: AVCaptureVideoPreviewLayer

    init(previewLayer: AVCaptureVideoPreviewLayer) {
        attachedPreviewLayer = previewLayer
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(previewLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(previewLayer: AVCaptureVideoPreviewLayer) {
        guard attachedPreviewLayer !== previewLayer else {
            setNeedsLayout()
            return
        }

        attachedPreviewLayer.removeFromSuperlayer()
        attachedPreviewLayer = previewLayer
        layer.addSublayer(previewLayer)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        attachedPreviewLayer.frame = bounds
    }
}

private enum BallTrackerCameraError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to test dribbling ball tracking."
        case .cameraUnavailable:
            return "The front camera is unavailable on this device."
        case .configurationFailed(let message):
            return message
        }
    }
}

private extension AVCaptureVideoOrientation {
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        default:
            return nil
        }
    }
}

private extension CGImagePropertyOrientation {
    init(videoOrientation: AVCaptureVideoOrientation) {
        switch videoOrientation {
        case .portrait:
            self = .right
        case .portraitUpsideDown:
            self = .left
        case .landscapeRight:
            self = .up
        case .landscapeLeft:
            self = .down
        @unknown default:
            self = .up
        }
    }
}
