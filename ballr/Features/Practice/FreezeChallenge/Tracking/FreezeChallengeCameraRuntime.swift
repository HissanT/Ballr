import AVFoundation
import Combine
import Foundation
import UIKit
import Vision

struct FreezeChallengeFrame {
    let ballOverlayState: BallTrackerOverlayState
    let bodyOverlayState: FreezeChallengeBodyOverlayState?
    let timestamp: Date
    let framePixelSize: CGSize
}

enum FreezeBodyAnchor: String, CaseIterable, Hashable {
    case leftAnkle
    case rightAnkle
    case leftHip
    case rightHip
    case leftWrist
    case rightWrist
    case leftShoulder
    case rightShoulder

    var jointName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .leftAnkle:
            return .leftAnkle
        case .rightAnkle:
            return .rightAnkle
        case .leftHip:
            return .leftHip
        case .rightHip:
            return .rightHip
        case .leftWrist:
            return .leftWrist
        case .rightWrist:
            return .rightWrist
        case .leftShoulder:
            return .leftShoulder
        case .rightShoulder:
            return .rightShoulder
        }
    }

    var isLowerBody: Bool {
        switch self {
        case .leftAnkle, .rightAnkle, .leftHip, .rightHip:
            return true
        case .leftWrist, .rightWrist, .leftShoulder, .rightShoulder:
            return false
        }
    }
}

struct FreezeBodyAnchorOverlayState {
    let anchor: FreezeBodyAnchor
    let normalizedPoint: CGPoint
    let confidence: Double
}

struct FreezeChallengeBodyOverlayState {
    let normalizedEnvelopeRect: CGRect
    let normalizedCenter: CGPoint
    let normalizedSpan: CGFloat
    let anchors: [FreezeBodyAnchorOverlayState]
    let confidence: Double
    let lowerBodyCount: Int
    let upperBodyCount: Int
}

final class FreezeChallengeCameraController: NSObject, ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var isStarting = true

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    var onTrackingFrame: ((FreezeChallengeFrame) -> Void)?
    var publishesTrackingFramesToSwiftUI = true

    private let sessionQueue = DispatchQueue(label: "ballr.freeze.session")
    private let videoOutputQueue = DispatchQueue(label: "ballr.freeze.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingSemaphore = DispatchSemaphore(value: 1)
    private let ballTracker = BallTrackerEngine()
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let minPointConfidence: VNConfidence = 0.25
    private let rectBlendAmount: CGFloat = 0.28
    private let pointBlendAmount: CGFloat = 0.30
    private let maxTrackedBodyMisses = 2

    private var ballRequest: VNCoreMLRequest?
    private var resources: BallTrackerResources?
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isObservingOrientationChanges = false
    private var currentFramePixelSize: CGSize = .zero
    private var trackedBody: TrackedFreezeBody?

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
                    configureAndStartSession()
                } else {
                    publish {
                        $0.permissionDenied = true
                        $0.errorMessage = FreezeChallengeCameraError.cameraPermissionDenied.localizedDescription
                        $0.isStarting = false
                    }
                }
            }
        case .denied, .restricted:
            publish {
                $0.permissionDenied = true
                $0.errorMessage = FreezeChallengeCameraError.cameraPermissionDenied.localizedDescription
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
            ballTracker.reset()
            trackedBody = nil
        }

        publish {
            $0.isStarting = false
            $0.onTrackingFrame = nil
            $0.publishesTrackingFramesToSwiftUI = true
        }
    }

    func displayRect(for normalizedRect: CGRect) -> CGRect? {
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

        let resources = try BallTrackerConfig.load()
        let visionModel = try resources.makeVisionModel()
        let request = VNCoreMLRequest(model: visionModel) { _, _ in }
        request.imageCropAndScaleOption = resources.config.visionCropAndScaleOption

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = preferredSessionPreset()

        guard
            let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        else {
            throw FreezeChallengeCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw FreezeChallengeCameraError.configurationFailed("Unable to add the front camera input.")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw FreezeChallengeCameraError.configurationFailed("Unable to add the video output.")
        }
        session.addOutput(videoOutput)

        self.resources = resources
        ballRequest = request
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

    private func handleTrackingResults(
        ballObservations: [VNRecognizedObjectObservation],
        bodyObservations: [VNHumanBodyPoseObservation]
    ) {
        guard let resources else {
            return
        }

        let timestamp = Date()
        let framePixelSize = currentFramePixelSize
        let ballOverlayState = ballTracker.process(
            observations: ballObservations,
            frameSize: framePixelSize,
            timestamp: timestamp,
            config: resources.config
        )
        let bodyOverlayState = processBody(observations: bodyObservations)

        let frame = FreezeChallengeFrame(
            ballOverlayState: ballOverlayState,
            bodyOverlayState: bodyOverlayState,
            timestamp: timestamp,
            framePixelSize: framePixelSize
        )
        deliverTrackingFrame(frame)
    }

    private func processBody(observations: [VNHumanBodyPoseObservation]) -> FreezeChallengeBodyOverlayState? {
        let candidates = observations.compactMap(bodyCandidate(from:))
        let strongestCandidate = candidates.max(by: { $0.confidence < $1.confidence })

        if let strongestCandidate {
            if let trackedBody {
                var blendedAnchors: [FreezeBodyAnchor: CGPoint] = [:]
                for (anchor, point) in strongestCandidate.anchors {
                    if let previousPoint = trackedBody.anchors[anchor] {
                        blendedAnchors[anchor] = blendPoint(from: previousPoint, to: point, amount: pointBlendAmount)
                    } else {
                        blendedAnchors[anchor] = point
                    }
                }

                self.trackedBody = TrackedFreezeBody(
                    normalizedEnvelopeRect: blendRect(
                        from: trackedBody.normalizedEnvelopeRect,
                        to: strongestCandidate.normalizedEnvelopeRect,
                        amount: rectBlendAmount
                    ),
                    normalizedCenter: blendPoint(
                        from: trackedBody.normalizedCenter,
                        to: strongestCandidate.normalizedCenter,
                        amount: pointBlendAmount
                    ),
                    normalizedSpan: trackedBody.normalizedSpan + (strongestCandidate.normalizedSpan - trackedBody.normalizedSpan) * rectBlendAmount,
                    anchors: blendedAnchors,
                    confidence: trackedBody.confidence * Double(1 - rectBlendAmount) + strongestCandidate.confidence * Double(rectBlendAmount),
                    lowerBodyCount: strongestCandidate.lowerBodyCount,
                    upperBodyCount: strongestCandidate.upperBodyCount,
                    misses: 0
                )
            } else {
                trackedBody = TrackedFreezeBody(
                    normalizedEnvelopeRect: strongestCandidate.normalizedEnvelopeRect,
                    normalizedCenter: strongestCandidate.normalizedCenter,
                    normalizedSpan: strongestCandidate.normalizedSpan,
                    anchors: strongestCandidate.anchors,
                    confidence: strongestCandidate.confidence,
                    lowerBodyCount: strongestCandidate.lowerBodyCount,
                    upperBodyCount: strongestCandidate.upperBodyCount,
                    misses: 0
                )
            }
        } else if let trackedBody, trackedBody.misses < maxTrackedBodyMisses {
            self.trackedBody = TrackedFreezeBody(
                normalizedEnvelopeRect: trackedBody.normalizedEnvelopeRect,
                normalizedCenter: trackedBody.normalizedCenter,
                normalizedSpan: trackedBody.normalizedSpan,
                anchors: trackedBody.anchors,
                confidence: trackedBody.confidence * 0.84,
                lowerBodyCount: trackedBody.lowerBodyCount,
                upperBodyCount: trackedBody.upperBodyCount,
                misses: trackedBody.misses + 1
            )
        } else {
            trackedBody = nil
        }

        guard let trackedBody else {
            return nil
        }

        return FreezeChallengeBodyOverlayState(
            normalizedEnvelopeRect: trackedBody.normalizedEnvelopeRect,
            normalizedCenter: trackedBody.normalizedCenter,
            normalizedSpan: trackedBody.normalizedSpan,
            anchors: FreezeBodyAnchor.allCases.compactMap { anchor in
                guard let point = trackedBody.anchors[anchor] else {
                    return nil
                }
                return FreezeBodyAnchorOverlayState(anchor: anchor, normalizedPoint: point, confidence: trackedBody.confidence)
            },
            confidence: trackedBody.confidence,
            lowerBodyCount: trackedBody.lowerBodyCount,
            upperBodyCount: trackedBody.upperBodyCount
        )
    }

    private func bodyCandidate(from observation: VNHumanBodyPoseObservation) -> FreezeBodyCandidate? {
        var anchors: [FreezeBodyAnchor: CGPoint] = [:]
        var confidences: [Double] = []
        var lowerBodyCount = 0
        var upperBodyCount = 0

        for anchor in FreezeBodyAnchor.allCases {
            guard let point = recognizedPoint(for: anchor.jointName, observation: observation) else {
                continue
            }

            let normalizedPoint = swiftUINormalizedPoint(fromVisionPoint: point.location)
            anchors[anchor] = normalizedPoint
            confidences.append(Double(point.confidence))
            if anchor.isLowerBody {
                lowerBodyCount += 1
            } else {
                upperBodyCount += 1
            }
        }

        guard lowerBodyCount >= 2, upperBodyCount >= 1 else {
            return nil
        }

        guard let envelopeRect = expandedBodyEnvelope(for: Array(anchors.values)) else {
            return nil
        }

        let center = CGPoint(x: envelopeRect.midX, y: envelopeRect.midY)
        let span = max(envelopeRect.width, envelopeRect.height)
        let confidence = confidences.reduce(0, +) / Double(max(confidences.count, 1))

        return FreezeBodyCandidate(
            normalizedEnvelopeRect: envelopeRect,
            normalizedCenter: clampToUnitPoint(center),
            normalizedSpan: clamp(span, minValue: 0.18, maxValue: 0.85),
            anchors: anchors,
            confidence: confidence,
            lowerBodyCount: lowerBodyCount,
            upperBodyCount: upperBodyCount
        )
    }

    private func expandedBodyEnvelope(for points: [CGPoint]) -> CGRect? {
        guard let baseRect = boundingRect(for: points)?.standardized.intersection(unitRect), !baseRect.isEmpty else {
            return nil
        }

        let expandedWidth = max(baseRect.width * 1.22, 0.18)
        let expandedHeight = max(baseRect.height * 1.16, 0.30)
        let expandedRect = CGRect(
            x: baseRect.midX - expandedWidth * 0.5,
            y: baseRect.midY - expandedHeight * 0.5,
            width: expandedWidth,
            height: expandedHeight
        )
        return expandedRect.standardized.intersection(unitRect)
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

    private func swiftUINormalizedPoint(fromVisionPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    private func clampToUnitPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    private func boundingRect(for points: [CGPoint]) -> CGRect? {
        guard
            let minX = points.map(\.x).min(),
            let maxX = points.map(\.x).max(),
            let minY = points.map(\.y).min(),
            let maxY = points.map(\.y).max()
        else {
            return nil
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func blendRect(from previous: CGRect, to current: CGRect, amount: CGFloat) -> CGRect {
        CGRect(
            x: previous.origin.x + (current.origin.x - previous.origin.x) * amount,
            y: previous.origin.y + (current.origin.y - previous.origin.y) * amount,
            width: previous.size.width + (current.size.width - previous.size.width) * amount,
            height: previous.size.height + (current.size.height - previous.size.height) * amount
        )
    }

    private func blendPoint(from previous: CGPoint, to current: CGPoint, amount: CGFloat) -> CGPoint {
        CGPoint(
            x: previous.x + (current.x - previous.x) * amount,
            y: previous.y + (current.y - previous.y) * amount
        )
    }

    private func clamp(_ value: CGFloat, minValue: CGFloat, maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    private func deliverTrackingFrame(_ frame: FreezeChallengeFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.onTrackingFrame?(frame)
        }
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

    private func publish(_ updates: @escaping (FreezeChallengeCameraController) -> Void) {
        if Thread.isMainThread {
            updates(self)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            updates(self)
        }
    }

    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation ?? .landscapeRight
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

extension FreezeChallengeCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard processingSemaphore.wait(timeout: .now()) == .success else {
            return
        }
        defer { processingSemaphore.signal() }

        guard let ballRequest else {
            return
        }

        let orientation = imageOrientation(for: connection.videoOrientation)
        currentFramePixelSize = framePixelSize(from: sampleBuffer, videoOrientation: connection.videoOrientation)
        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: orientation,
            options: [:]
        )

        do {
            try handler.perform([ballRequest, bodyRequest])
            let ballObservations = (ballRequest.results as? [VNRecognizedObjectObservation]) ?? []
            let bodyObservations = (bodyRequest.results as? [VNHumanBodyPoseObservation]) ?? []
            handleTrackingResults(ballObservations: ballObservations, bodyObservations: bodyObservations)
        } catch {
            publish {
                $0.errorMessage = "Freeze Challenge tracking failed: \(error.localizedDescription)"
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

private struct FreezeBodyCandidate {
    let normalizedEnvelopeRect: CGRect
    let normalizedCenter: CGPoint
    let normalizedSpan: CGFloat
    let anchors: [FreezeBodyAnchor: CGPoint]
    let confidence: Double
    let lowerBodyCount: Int
    let upperBodyCount: Int
}

private struct TrackedFreezeBody {
    let normalizedEnvelopeRect: CGRect
    let normalizedCenter: CGPoint
    let normalizedSpan: CGFloat
    let anchors: [FreezeBodyAnchor: CGPoint]
    let confidence: Double
    let lowerBodyCount: Int
    let upperBodyCount: Int
    let misses: Int
}

private enum FreezeChallengeCameraError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to use Freeze Challenge."
        case .cameraUnavailable:
            return "The front camera is unavailable on this device."
        case let .configurationFailed(message):
            return message
        }
    }
}
