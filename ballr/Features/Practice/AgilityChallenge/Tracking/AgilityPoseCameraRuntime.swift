import AVFoundation
import Combine
import Foundation
import UIKit
import Vision

struct AgilityChallengeFrame {
    let overlayState: AgilityChallengeOverlayState
    let timestamp: Date
    let framePixelSize: CGSize
}

struct AgilityTrackedBodyOverlayState {
    let normalizedCenter: CGPoint
    let normalizedSpan: CGFloat
    let confidence: Double
}

struct AgilityChallengeOverlayState {
    let trackedBody: AgilityTrackedBodyOverlayState?
    let statusText: String
    let isTracking: Bool
    let candidateCount: Int

    static let idle = AgilityChallengeOverlayState(
        trackedBody: nil,
        statusText: "Searching",
        isTracking: false,
        candidateCount: 0
    )
}

final class AgilityPoseCameraController: NSObject, ObservableObject {
    @Published private(set) var overlayState: AgilityChallengeOverlayState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var isStarting = true

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    var onTrackingFrame: ((AgilityChallengeFrame) -> Void)?
    var publishesTrackingFramesToSwiftUI = true

    private let sessionQueue = DispatchQueue(label: "ballr.agility.session")
    private let videoOutputQueue = DispatchQueue(label: "ballr.agility.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingSemaphore = DispatchSemaphore(value: 1)
    private let throttledTrackingPublishInterval: TimeInterval = 0.15
    private let request = VNDetectHumanBodyPoseRequest()

    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isObservingOrientationChanges = false
    private var lastTrackingPublishTimestamp = Date.distantPast
    private var lastPublishedTrackingStatus: Bool?
    private var currentFramePixelSize: CGSize = .zero
    private var trackedBody: TrackedAgilityBody?

    private let minPointConfidence: VNConfidence = 0.25
    private let maxTrackedBodyMisses = 2
    private let blendAmount: CGFloat = 0.24

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init()
        previewLayer.videoGravity = .resizeAspectFill
    }

    deinit {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        NotificationCenter.default.removeObserver(self)
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
                        $0.errorMessage = AgilityPoseCameraError.cameraPermissionDenied.localizedDescription
                        $0.isStarting = false
                    }
                }
            }
        case .denied, .restricted:
            publish {
                $0.permissionDenied = true
                $0.errorMessage = AgilityPoseCameraError.cameraPermissionDenied.localizedDescription
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

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if session.isRunning {
                session.stopRunning()
            }
            trackedBody = nil
        }

        publish {
            $0.overlayState = .idle
            $0.isStarting = false
            $0.onTrackingFrame = nil
            $0.publishesTrackingFramesToSwiftUI = true
        }
    }

    func displayPoint(for normalizedPoint: CGPoint) -> CGPoint? {
        let probeRect = CGRect(
            x: normalizedPoint.x - 0.0005,
            y: normalizedPoint.y - 0.0005,
            width: 0.001,
            height: 0.001
        )
        guard let displayRect = displayRect(for: probeRect) else {
            return nil
        }
        return CGPoint(x: displayRect.midX, y: displayRect.midY)
    }

    private func displayRect(for normalizedRect: CGRect) -> CGRect? {
        guard !previewLayer.bounds.isEmpty else {
            return nil
        }

        let metadataRect = previewMetadataRect(fromNormalizedRect: normalizedRect)
        guard !metadataRect.isNull, !metadataRect.isEmpty else {
            return nil
        }

        let displayRect = previewLayer.layerRectConverted(fromMetadataOutputRect: metadataRect)
        guard !displayRect.isNull, !displayRect.isEmpty else {
            return nil
        }
        return displayRect
    }

    private func previewMetadataRect(fromNormalizedRect normalizedRect: CGRect) -> CGRect {
        var rect = normalizedRect.standardized.intersection(unitRect)

        guard !rect.isNull, !rect.isEmpty else {
            return .null
        }

        if previewLayer.connection?.isVideoMirrored == true {
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

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = preferredSessionPreset()

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else {
            throw AgilityPoseCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw AgilityPoseCameraError.configurationFailed("Unable to add the front camera input.")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw AgilityPoseCameraError.configurationFailed("Unable to add the video output.")
        }
        session.addOutput(videoOutput)

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
        let interfaceOrientation = currentInterfaceOrientation()
        guard let videoOrientation = videoOrientation(for: interfaceOrientation) else {
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

    private func handleBodyPoseResults(_ observations: [VNHumanBodyPoseObservation]) {
        let timestamp = Date()
        let framePixelSize = currentFramePixelSize
        let overlayState = process(observations: observations)
        let frame = AgilityChallengeFrame(
            overlayState: overlayState,
            timestamp: timestamp,
            framePixelSize: framePixelSize
        )
        deliverTrackingFrame(frame)

        if shouldPublishTrackingFrameToSwiftUI(frame) {
            publish {
                $0.errorMessage = nil
                $0.overlayState = overlayState
            }
        }
    }

    private func process(observations: [VNHumanBodyPoseObservation]) -> AgilityChallengeOverlayState {
        let candidates = observations.compactMap(bodyCandidate(from:))
        let strongestCandidate = candidates.max(by: { $0.confidence < $1.confidence })

        if let strongestCandidate {
            if let trackedBody {
                self.trackedBody = TrackedAgilityBody(
                    normalizedCenter: CGPoint(
                        x: trackedBody.normalizedCenter.x + (strongestCandidate.normalizedCenter.x - trackedBody.normalizedCenter.x) * blendAmount,
                        y: trackedBody.normalizedCenter.y + (strongestCandidate.normalizedCenter.y - trackedBody.normalizedCenter.y) * blendAmount
                    ),
                    normalizedSpan: trackedBody.normalizedSpan + (strongestCandidate.normalizedSpan - trackedBody.normalizedSpan) * blendAmount,
                    confidence: trackedBody.confidence * Double(1 - blendAmount) + strongestCandidate.confidence * Double(blendAmount),
                    misses: 0
                )
            } else {
                trackedBody = TrackedAgilityBody(
                    normalizedCenter: strongestCandidate.normalizedCenter,
                    normalizedSpan: strongestCandidate.normalizedSpan,
                    confidence: strongestCandidate.confidence,
                    misses: 0
                )
            }
        } else if let trackedBody, trackedBody.misses < maxTrackedBodyMisses {
            self.trackedBody = TrackedAgilityBody(
                normalizedCenter: trackedBody.normalizedCenter,
                normalizedSpan: trackedBody.normalizedSpan,
                confidence: trackedBody.confidence * 0.84,
                misses: trackedBody.misses + 1
            )
        } else {
            trackedBody = nil
        }

        let overlayTrackedBody = trackedBody.map {
            AgilityTrackedBodyOverlayState(
                normalizedCenter: $0.normalizedCenter,
                normalizedSpan: $0.normalizedSpan,
                confidence: $0.confidence
            )
        }

        return AgilityChallengeOverlayState(
            trackedBody: overlayTrackedBody,
            statusText: overlayTrackedBody == nil ? "Searching" : "Body Found",
            isTracking: overlayTrackedBody != nil,
            candidateCount: candidates.count
        )
    }

    private func bodyCandidate(from observation: VNHumanBodyPoseObservation) -> AgilityBodyCandidate? {
        let leftHip = recognizedPoint(for: .leftHip, observation: observation)
        let rightHip = recognizedPoint(for: .rightHip, observation: observation)
        let leftShoulder = recognizedPoint(for: .leftShoulder, observation: observation)
        let rightShoulder = recognizedPoint(for: .rightShoulder, observation: observation)

        let primaryPair: (VNRecognizedPoint, VNRecognizedPoint)?
        if let leftHip, let rightHip {
            primaryPair = (leftHip, rightHip)
        } else if let leftShoulder, let rightShoulder {
            primaryPair = (leftShoulder, rightShoulder)
        } else {
            primaryPair = nil
        }

        guard let pair = primaryPair else {
            return nil
        }

        let leftPoint = swiftUINormalizedPoint(fromVisionPoint: pair.0.location)
        let rightPoint = swiftUINormalizedPoint(fromVisionPoint: pair.1.location)
        let center = CGPoint(
            x: (leftPoint.x + rightPoint.x) * 0.5,
            y: (leftPoint.y + rightPoint.y) * 0.5
        )
        let span = max(abs(rightPoint.x - leftPoint.x), 0.12)
        let confidence = Double(pair.0.confidence + pair.1.confidence) * 0.5

        return AgilityBodyCandidate(
            normalizedCenter: clampToUnitPoint(center),
            normalizedSpan: min(max(span, 0.12), 0.36),
            confidence: confidence
        )
    }

    private func recognizedPoint(
        for jointName: VNHumanBodyPoseObservation.JointName,
        observation: VNHumanBodyPoseObservation
    ) -> VNRecognizedPoint? {
        guard
            let point = try? observation.recognizedPoint(jointName),
            point.confidence >= minPointConfidence
        else {
            return nil
        }
        return point
    }

    private func clampToUnitPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    private func swiftUINormalizedPoint(fromVisionPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    private func deliverTrackingFrame(_ frame: AgilityChallengeFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.onTrackingFrame?(frame)
        }
    }

    private func shouldPublishTrackingFrameToSwiftUI(_ frame: AgilityChallengeFrame) -> Bool {
        guard !publishesTrackingFramesToSwiftUI else {
            lastTrackingPublishTimestamp = frame.timestamp
            lastPublishedTrackingStatus = frame.overlayState.isTracking
            return true
        }

        let statusChanged = lastPublishedTrackingStatus != frame.overlayState.isTracking
        let publishIntervalElapsed = frame.timestamp.timeIntervalSince(lastTrackingPublishTimestamp) >= throttledTrackingPublishInterval
        guard statusChanged || publishIntervalElapsed else {
            return false
        }

        lastTrackingPublishTimestamp = frame.timestamp
        lastPublishedTrackingStatus = frame.overlayState.isTracking
        return true
    }

    private func startObservingOrientationChanges() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !isObservingOrientationChanges else {
                return
            }

            isObservingOrientationChanges = true
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
        DispatchQueue.main.async { [weak self] in
            guard let self, isObservingOrientationChanges else {
                return
            }

            isObservingOrientationChanges = false
            NotificationCenter.default.removeObserver(
                self,
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    private func publish(_ updates: @escaping (AgilityPoseCameraController) -> Void) {
        if Thread.isMainThread {
            updates(self)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updates(self)
        }
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        BallrOrientationController.cameraInterfaceOrientation()
    }

    private func videoOrientation(for interfaceOrientation: UIInterfaceOrientation) -> AVCaptureVideoOrientation? {
        switch interfaceOrientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        default:
            return nil
        }
    }

    private func imageOrientation(for videoOrientation: AVCaptureVideoOrientation) -> CGImagePropertyOrientation {
        switch videoOrientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeRight:
            return .up
        case .landscapeLeft:
            return .down
        @unknown default:
            return .up
        }
    }
}

extension AgilityPoseCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard processingSemaphore.wait(timeout: .now()) == .success else {
            return
        }

        defer { processingSemaphore.signal() }
        let orientation = imageOrientation(for: connection.videoOrientation)
        currentFramePixelSize = framePixelSize(from: sampleBuffer, videoOrientation: connection.videoOrientation)
        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: orientation,
            options: [:]
        )

        do {
            try handler.perform([request])
            let observations = request.results ?? []
            handleBodyPoseResults(observations)
        } catch {
            publish {
                $0.errorMessage = error.localizedDescription
            }
        }
    }

    private func framePixelSize(
        from sampleBuffer: CMSampleBuffer,
        videoOrientation: AVCaptureVideoOrientation
    ) -> CGSize {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return .zero
        }

        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        switch videoOrientation {
        case .portrait, .portraitUpsideDown:
            return CGSize(width: height, height: width)
        case .landscapeLeft, .landscapeRight:
            return CGSize(width: width, height: height)
        @unknown default:
            return CGSize(width: width, height: height)
        }
    }
}

private struct AgilityBodyCandidate {
    let normalizedCenter: CGPoint
    let normalizedSpan: CGFloat
    let confidence: Double
}

private struct TrackedAgilityBody {
    let normalizedCenter: CGPoint
    let normalizedSpan: CGFloat
    let confidence: Double
    let misses: Int
}

private enum AgilityPoseCameraError: LocalizedError {
    case cameraUnavailable
    case cameraPermissionDenied
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "The front camera is unavailable on this device."
        case .cameraPermissionDenied:
            return "Camera access is required to use this drill."
        case let .configurationFailed(message):
            return message
        }
    }
}
