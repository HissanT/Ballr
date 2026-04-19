import AVFoundation
import Combine
import Foundation
import UIKit
import Vision

struct HandPoseFrame {
    let overlayState: HandPoseOverlayState
    let timestamp: Date
    let framePixelSize: CGSize
}

struct HandOverlayState: Identifiable {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let confidence: Double
}

struct HandPoseOverlayState {
    let hands: [HandOverlayState]
    let statusText: String
    let isTracking: Bool
    let candidateCount: Int

    static let idle = HandPoseOverlayState(
        hands: [],
        statusText: "Searching",
        isTracking: false,
        candidateCount: 0
    )
}

final class HandPoseCameraController: NSObject, ObservableObject {
    @Published private(set) var overlayState: HandPoseOverlayState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var isStarting = true

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    var onTrackingFrame: ((HandPoseFrame) -> Void)?
    var publishesTrackingFramesToSwiftUI = true

    private let sessionQueue = DispatchQueue(label: "ballr.hand-target.session")
    private let videoOutputQueue = DispatchQueue(label: "ballr.hand-target.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingSemaphore = DispatchSemaphore(value: 1)
    private let throttledTrackingPublishInterval: TimeInterval = 0.15
    private let request = VNDetectHumanHandPoseRequest()

    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isObservingOrientationChanges = false
    private var lastTrackingPublishTimestamp = Date.distantPast
    private var lastPublishedTrackingStatus: Bool?
    private var currentFramePixelSize: CGSize = .zero
    private var trackedHands: [TrackedHand] = []
    private var nextHandID = 0

    private let minPointConfidence: VNConfidence = 0.25
    private let minRequiredPoints = 4
    private let maxTrackedHandMisses = 1
    private let matchDistanceThreshold: CGFloat = 0.22
    private let rectBlendAmount: CGFloat = 0.42

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init()
        previewLayer.videoGravity = .resizeAspectFill
        request.maximumHandCount = 2
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
                        $0.errorMessage = HandPoseCameraError.cameraPermissionDenied.localizedDescription
                        $0.isStarting = false
                    }
                }
            }
        case .denied, .restricted:
            publish {
                $0.permissionDenied = true
                $0.errorMessage = HandPoseCameraError.cameraPermissionDenied.localizedDescription
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
            guard let self else {
                return
            }

            if session.isRunning {
                session.stopRunning()
            }
            trackedHands = []
        }

        publish {
            $0.overlayState = .idle
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
        var rect = normalizedRect
            .standardized
            .intersection(unitRect)

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
            throw HandPoseCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw HandPoseCameraError.configurationFailed("Unable to add the front camera input.")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw HandPoseCameraError.configurationFailed("Unable to add the video output.")
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

    private func handleHandPoseResults(_ observations: [VNHumanHandPoseObservation]) {
        let timestamp = Date()
        let framePixelSize = currentFramePixelSize
        let overlayState = process(observations: observations)
        let frame = HandPoseFrame(
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

    private func process(observations: [VNHumanHandPoseObservation]) -> HandPoseOverlayState {
        let candidates = observations
            .compactMap(handCandidate(from:))
            .sorted(by: { $0.confidence > $1.confidence })
            .prefix(2)

        var unmatchedPrevious = trackedHands
        var resolvedHands: [TrackedHand] = []

        for candidate in candidates {
            if let matchIndex = bestMatchIndex(for: candidate, in: unmatchedPrevious) {
                let previous = unmatchedPrevious.remove(at: matchIndex)
                let blendedRect = blendRect(from: previous.normalizedRect, to: candidate.normalizedRect, amount: rectBlendAmount)
                let blendedConfidence = Double(previous.confidence * Double(1 - rectBlendAmount) + candidate.confidence * Double(rectBlendAmount))
                resolvedHands.append(
                    TrackedHand(
                        id: previous.id,
                        normalizedRect: blendedRect,
                        normalizedPoints: candidate.normalizedPoints,
                        confidence: blendedConfidence,
                        misses: 0
                    )
                )
            } else {
                resolvedHands.append(
                    TrackedHand(
                        id: nextHandID,
                        normalizedRect: candidate.normalizedRect,
                        normalizedPoints: candidate.normalizedPoints,
                        confidence: candidate.confidence,
                        misses: 0
                    )
                )
                nextHandID += 1
            }
        }

        for previous in unmatchedPrevious where previous.misses < maxTrackedHandMisses {
            resolvedHands.append(
                TrackedHand(
                    id: previous.id,
                    normalizedRect: previous.normalizedRect,
                    normalizedPoints: previous.normalizedPoints,
                    confidence: previous.confidence * 0.82,
                    misses: previous.misses + 1
                )
            )
        }

        trackedHands = Array(
            resolvedHands
                .sorted(by: { $0.confidence > $1.confidence })
                .prefix(2)
        )

        let hands = trackedHands.map {
            HandOverlayState(
                id: $0.id,
                normalizedRect: $0.normalizedRect,
                normalizedPoints: $0.normalizedPoints,
                confidence: $0.confidence
            )
        }

        let statusText: String
        if hands.isEmpty {
            statusText = "Searching"
        } else if hands.count == 1 {
            statusText = "Hand Found"
        } else {
            statusText = "Hands Found"
        }

        return HandPoseOverlayState(
            hands: hands,
            statusText: statusText,
            isTracking: !hands.isEmpty,
            candidateCount: candidates.count
        )
    }

    private func handCandidate(from observation: VNHumanHandPoseObservation) -> HandCandidate? {
        guard let points = try? observation.recognizedPoints(.all) else {
            return nil
        }

        let jointNames: [VNHumanHandPoseObservation.JointName] = [
            .wrist,
            .thumbCMC,
            .thumbMP,
            .thumbIP,
            .thumbTip,
            .indexMCP,
            .indexPIP,
            .indexDIP,
            .indexTip,
            .middleMCP,
            .middlePIP,
            .middleDIP,
            .middleTip,
            .ringMCP,
            .ringPIP,
            .ringDIP,
            .ringTip,
            .littleMCP,
            .littlePIP,
            .littleDIP,
            .littleTip,
        ]

        let validPoints = jointNames.compactMap { jointName -> VNRecognizedPoint? in
            guard let point = points[jointName], point.confidence >= minPointConfidence else {
                return nil
            }
            return point
        }

        guard validPoints.count >= minRequiredPoints else {
            return nil
        }

        let normalizedPoints = validPoints.map { swiftUINormalizedPoint(fromVisionPoint: $0.location) }

        let minX = normalizedPoints.map(\.x).min() ?? 0
        let maxX = normalizedPoints.map(\.x).max() ?? 0
        let minY = normalizedPoints.map(\.y).min() ?? 0
        let maxY = normalizedPoints.map(\.y).max() ?? 0
        let averageConfidence = validPoints.reduce(0.0) { $0 + Double($1.confidence) } / Double(validPoints.count)

        let rawWidth = max(maxX - minX, 0.035)
        let rawHeight = max(maxY - minY, 0.045)
        let horizontalPadding = max(rawWidth * 0.10, 0.018)
        let verticalPadding = max(rawHeight * 0.10, 0.018)

        let paddedRect = CGRect(
            x: minX - horizontalPadding,
            y: minY - verticalPadding,
            width: rawWidth + horizontalPadding * 2,
            height: rawHeight + verticalPadding * 2
        )

        let normalizedRect = expandedToMinimumSize(
            rect: paddedRect.standardized.intersection(unitRect),
            minimumWidth: 0.075,
            minimumHeight: 0.09
        )

        guard !normalizedRect.isNull, !normalizedRect.isEmpty else {
            return nil
        }

        return HandCandidate(
            normalizedRect: normalizedRect,
            normalizedPoints: normalizedPoints,
            confidence: averageConfidence
        )
    }

    private func bestMatchIndex(for candidate: HandCandidate, in previousHands: [TrackedHand]) -> Int? {
        let candidateCenter = CGPoint(x: candidate.normalizedRect.midX, y: candidate.normalizedRect.midY)

        return previousHands.enumerated()
            .filter { _, previous in
                let previousCenter = CGPoint(x: previous.normalizedRect.midX, y: previous.normalizedRect.midY)
                return hypot(previousCenter.x - candidateCenter.x, previousCenter.y - candidateCenter.y) <= matchDistanceThreshold
            }
            .min { lhs, rhs in
                let lhsCenter = CGPoint(x: lhs.element.normalizedRect.midX, y: lhs.element.normalizedRect.midY)
                let rhsCenter = CGPoint(x: rhs.element.normalizedRect.midX, y: rhs.element.normalizedRect.midY)
                return hypot(lhsCenter.x - candidateCenter.x, lhsCenter.y - candidateCenter.y)
                    < hypot(rhsCenter.x - candidateCenter.x, rhsCenter.y - candidateCenter.y)
            }?
            .offset
    }

    private func blendRect(from previous: CGRect, to current: CGRect, amount: CGFloat) -> CGRect {
        CGRect(
            x: previous.origin.x + (current.origin.x - previous.origin.x) * amount,
            y: previous.origin.y + (current.origin.y - previous.origin.y) * amount,
            width: previous.width + (current.width - previous.width) * amount,
            height: previous.height + (current.height - previous.height) * amount
        )
        .standardized
        .intersection(unitRect)
    }

    private func expandedToMinimumSize(
        rect: CGRect,
        minimumWidth: CGFloat,
        minimumHeight: CGFloat
    ) -> CGRect {
        guard !rect.isNull, !rect.isEmpty else {
            return .null
        }

        let width = max(rect.width, minimumWidth)
        let height = max(rect.height, minimumHeight)
        let adjustedRect = CGRect(
            x: rect.midX - width * 0.5,
            y: rect.midY - height * 0.5,
            width: width,
            height: height
        )
        return adjustedRect.standardized.intersection(unitRect)
    }

    private func swiftUINormalizedPoint(fromVisionPoint point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }

    private func deliverTrackingFrame(_ frame: HandPoseFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.onTrackingFrame?(frame)
        }
    }

    private func shouldPublishTrackingFrameToSwiftUI(_ frame: HandPoseFrame) -> Bool {
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

    private func publish(_ updates: @escaping (HandPoseCameraController) -> Void) {
        if Thread.isMainThread {
            updates(self)
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            updates(self)
        }
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?
            .interfaceOrientation ?? .landscapeRight
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

extension HandPoseCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
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
            let observations = (request.results as? [VNHumanHandPoseObservation]) ?? []
            handleHandPoseResults(observations)
        } catch {
            publish {
                $0.errorMessage = "Hand tracking failed: \(error.localizedDescription)"
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

private struct HandCandidate {
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let confidence: Double
}

private struct TrackedHand {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let confidence: Double
    let misses: Int
}

private enum HandPoseCameraError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to test hand targets."
        case .cameraUnavailable:
            return "The front camera is unavailable on this device."
        case .configurationFailed(let message):
            return message
        }
    }
}
