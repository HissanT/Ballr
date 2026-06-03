import AVFoundation
import Combine
import Foundation
import UIKit
import Vision

struct JugglingFrame {
    let ballOverlayState: BallTrackerOverlayState
    let bodyOverlayState: JugglingBodyOverlayState
    let timestamp: Date
    let framePixelSize: CGSize
}

enum JugglingBodyJoint: CaseIterable, Hashable {
    case nose
    case neck
    case leftShoulder
    case rightShoulder
    case leftElbow
    case rightElbow
    case leftWrist
    case rightWrist
    case leftAnkle
    case rightAnkle
    case leftKnee
    case rightKnee
    case leftHip
    case rightHip

    var jointName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .nose:
            return .nose
        case .neck:
            return .neck
        case .leftShoulder:
            return .leftShoulder
        case .rightShoulder:
            return .rightShoulder
        case .leftElbow:
            return .leftElbow
        case .rightElbow:
            return .rightElbow
        case .leftWrist:
            return .leftWrist
        case .rightWrist:
            return .rightWrist
        case .leftAnkle:
            return .leftAnkle
        case .rightAnkle:
            return .rightAnkle
        case .leftKnee:
            return .leftKnee
        case .rightKnee:
            return .rightKnee
        case .leftHip:
            return .leftHip
        case .rightHip:
            return .rightHip
        }
    }

    var isLowerBodyContactJoint: Bool {
        switch self {
        case .leftAnkle, .rightAnkle, .leftKnee, .rightKnee, .leftHip, .rightHip:
            return true
        case .nose, .neck, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist:
            return false
        }
    }
}

struct JugglingBodyPointOverlayState {
    let joint: JugglingBodyJoint
    let normalizedPoint: CGPoint
    let confidence: Double
}

struct JugglingBodyOverlayState {
    let points: [JugglingBodyPointOverlayState]
    let normalizedEnvelopeRect: CGRect?
    let confidence: Double
    let isTracking: Bool
    let candidateCount: Int

    static let idle = JugglingBodyOverlayState(
        points: [],
        normalizedEnvelopeRect: nil,
        confidence: 0,
        isTracking: false,
        candidateCount: 0
    )
}

final class JugglingCameraController: NSObject, ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var isStarting = true

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    var onTrackingFrame: ((JugglingFrame) -> Void)?
    var publishesTrackingFramesToSwiftUI = true

    private let sessionQueue = DispatchQueue(label: "ballr.juggling.session")
    private let videoOutputQueue = DispatchQueue(label: "ballr.juggling.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingSemaphore = DispatchSemaphore(value: 1)
    private let ballTracker = BallTrackerEngine()
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private let minPointConfidence: VNConfidence = 0.22
    private let pointBlendAmount: CGFloat = 0.36
    private let maxTrackedBodyMisses = 2
    private let bodyRequestStride = 3
    private let cachedBodyMaxAge: TimeInterval = 0.35

    private var ballRequest: VNCoreMLRequest?
    private var resources: BallTrackerResources?
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isObservingOrientationChanges = false
    private var currentFramePixelSize: CGSize = .zero
    private var trackedBody: TrackedJugglingBody?
    private var processedFrameIndex = 0
    private var cachedBodyOverlayState: JugglingBodyOverlayState = .idle
    private var cachedBodyTimestamp: Date?
    #if DEBUG
    private var processedFrameCount = 0
    private var droppedFrameCount = 0
    private var bodyRequestCount = 0
    private var totalVisionDuration: TimeInterval = 0
    private var lastDiagnosticsLogTimestamp = Date()
    #endif

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
                        $0.errorMessage = JugglingCameraError.cameraPermissionDenied.localizedDescription
                        $0.isStarting = false
                    }
                }
            }
        case .denied, .restricted:
            publish {
                $0.permissionDenied = true
                $0.errorMessage = JugglingCameraError.cameraPermissionDenied.localizedDescription
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
            ballTracker.reset()
            trackedBody = nil
            cachedBodyOverlayState = .idle
            cachedBodyTimestamp = nil
            processedFrameIndex = 0
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
            throw JugglingCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw JugglingCameraError.configurationFailed("Unable to add the front camera input.")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw JugglingCameraError.configurationFailed("Unable to add the video output.")
        }
        session.addOutput(videoOutput)

        self.resources = resources
        self.ballRequest = request
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
        bodyObservations: [VNHumanBodyPoseObservation]?,
        timestamp: Date
    ) {
        guard let resources else {
            return
        }

        let framePixelSize = currentFramePixelSize
        let ballOverlayState = ballTracker.process(
            observations: ballObservations,
            frameSize: framePixelSize,
            timestamp: timestamp,
            config: resources.config
        )
        if let bodyObservations {
            let processedBodyState = processBody(observations: bodyObservations)
            if processedBodyState.isTracking {
                cachedBodyOverlayState = processedBodyState
                cachedBodyTimestamp = timestamp
            }
        }
        let bodyOverlayState = cachedBodyState(at: timestamp)

        let frame = JugglingFrame(
            ballOverlayState: ballOverlayState,
            bodyOverlayState: bodyOverlayState,
            timestamp: timestamp,
            framePixelSize: framePixelSize
        )
        deliverTrackingFrame(frame)
    }

    private func cachedBodyState(at timestamp: Date) -> JugglingBodyOverlayState {
        guard
            let cachedBodyTimestamp,
            timestamp.timeIntervalSince(cachedBodyTimestamp) <= cachedBodyMaxAge
        else {
            return .idle
        }
        return cachedBodyOverlayState
    }

    private func processBody(observations: [VNHumanBodyPoseObservation]) -> JugglingBodyOverlayState {
        let candidates = observations.compactMap(bodyCandidate(from:))
        guard let candidate = candidates.max(by: { $0.confidence < $1.confidence }) else {
            if var trackedBody, trackedBody.misses < maxTrackedBodyMisses {
                trackedBody.misses += 1
                trackedBody.confidence *= 0.76
                self.trackedBody = trackedBody
                return overlayState(from: trackedBody, candidateCount: 0)
            }

            trackedBody = nil
            return .idle
        }

        let resolvedBody: TrackedJugglingBody
        if let previous = trackedBody {
            var resolvedPoints: [JugglingBodyJoint: TrackedJugglingPoint] = [:]
            for (joint, point) in candidate.points {
                if let previousPoint = previous.points[joint] {
                    resolvedPoints[joint] = TrackedJugglingPoint(
                        normalizedPoint: blendPoint(
                            from: previousPoint.normalizedPoint,
                            to: point.normalizedPoint,
                            amount: pointBlendAmount
                        ),
                        confidence: previousPoint.confidence * Double(1 - pointBlendAmount) + point.confidence * Double(pointBlendAmount)
                    )
                } else {
                    resolvedPoints[joint] = point
                }
            }

            for (joint, previousPoint) in previous.points where resolvedPoints[joint] == nil {
                resolvedPoints[joint] = TrackedJugglingPoint(
                    normalizedPoint: previousPoint.normalizedPoint,
                    confidence: previousPoint.confidence * 0.72
                )
            }
            resolvedBody = TrackedJugglingBody(
                points: resolvedPoints,
                confidence: previous.confidence * Double(1 - pointBlendAmount) + candidate.confidence * Double(pointBlendAmount),
                misses: 0
            )
        } else {
            resolvedBody = TrackedJugglingBody(
                points: candidate.points,
                confidence: candidate.confidence,
                misses: 0
            )
        }

        trackedBody = resolvedBody
        return overlayState(from: resolvedBody, candidateCount: candidates.count)
    }

    private func bodyCandidate(from observation: VNHumanBodyPoseObservation) -> JugglingBodyCandidate? {
        var points: [JugglingBodyJoint: TrackedJugglingPoint] = [:]
        for joint in JugglingBodyJoint.allCases {
            guard let recognizedPoint = recognizedPoint(for: joint.jointName, observation: observation) else {
                continue
            }
            points[joint] = TrackedJugglingPoint(
                normalizedPoint: swiftUINormalizedPoint(fromVisionPoint: recognizedPoint.location),
                confidence: Double(recognizedPoint.confidence)
            )
        }

        let lowerBodyPointCount = points.keys.filter(\.isLowerBodyContactJoint).count
        let upperBodyPointCount = points.count - lowerBodyPointCount
        let hasUsefulLowerBody =
            (points[.leftAnkle] != nil && points[.leftKnee] != nil)
            || (points[.rightAnkle] != nil && points[.rightKnee] != nil)
            || (points[.leftKnee] != nil && points[.leftHip] != nil)
            || (points[.rightKnee] != nil && points[.rightHip] != nil)

        guard points.count >= 5, lowerBodyPointCount >= 3, upperBodyPointCount >= 1, hasUsefulLowerBody else {
            return nil
        }

        let confidence = points.values.reduce(0.0) { $0 + $1.confidence } / Double(points.count)
        return JugglingBodyCandidate(points: points, confidence: confidence)
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

    private func overlayState(
        from trackedBody: TrackedJugglingBody,
        candidateCount: Int
    ) -> JugglingBodyOverlayState {
        let points = trackedBody.points.map { joint, point in
            JugglingBodyPointOverlayState(
                joint: joint,
                normalizedPoint: point.normalizedPoint,
                confidence: point.confidence
            )
        }
        let envelope = boundingRect(for: trackedBody.points.values.map(\.normalizedPoint))?
            .insetBy(dx: -0.035, dy: -0.035)
            .standardized
            .intersection(unitRect)

        return JugglingBodyOverlayState(
            points: points,
            normalizedEnvelopeRect: envelope,
            confidence: trackedBody.confidence,
            isTracking: trackedBody.misses == 0,
            candidateCount: candidateCount
        )
    }

    private func swiftUINormalizedPoint(fromVisionPoint point: CGPoint) -> CGPoint {
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

    private func blendPoint(from previous: CGPoint, to current: CGPoint, amount: CGFloat) -> CGPoint {
        CGPoint(
            x: previous.x + (current.x - previous.x) * amount,
            y: previous.y + (current.y - previous.y) * amount
        )
    }

    private func deliverTrackingFrame(_ frame: JugglingFrame) {
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

    private func publish(_ updates: @escaping (JugglingCameraController) -> Void) {
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

    private static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        BallrOrientationController.cameraInterfaceOrientation()
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

extension JugglingCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard processingSemaphore.wait(timeout: .now()) == .success else {
            logDroppedFrameIfNeeded()
            return
        }
        defer { processingSemaphore.signal() }

        guard let ballRequest, resources != nil else {
            return
        }

        let startedAt = Date()
        let orientation = imageOrientation(for: connection.videoOrientation)
        currentFramePixelSize = framePixelSize(from: sampleBuffer, videoOrientation: connection.videoOrientation)
        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: orientation,
            options: [:]
        )
        let shouldRunBodyRequest = processedFrameIndex.isMultiple(of: bodyRequestStride) || cachedBodyTimestamp == nil
        processedFrameIndex += 1
        let requests: [VNRequest] = shouldRunBodyRequest ? [ballRequest, bodyRequest] : [ballRequest]

        do {
            try handler.perform(requests)
            let ballObservations = (ballRequest.results as? [VNRecognizedObjectObservation]) ?? []
            let bodyObservations = shouldRunBodyRequest ? (bodyRequest.results ?? []) : nil
            handleTrackingResults(
                ballObservations: ballObservations,
                bodyObservations: bodyObservations,
                timestamp: Date()
            )
            logVisionDurationIfNeeded(Date().timeIntervalSince(startedAt), didRunBodyRequest: shouldRunBodyRequest)
        } catch {
            publish {
                $0.errorMessage = "Juggling tracking failed: \(error.localizedDescription)"
            }
        }
    }

    private func logDroppedFrameIfNeeded() {
        #if DEBUG
        droppedFrameCount += 1
        logTrackingDiagnosticsIfNeeded()
        #endif
    }

    private func logVisionDurationIfNeeded(_ duration: TimeInterval, didRunBodyRequest: Bool) {
        #if DEBUG
        processedFrameCount += 1
        if didRunBodyRequest {
            bodyRequestCount += 1
        }
        totalVisionDuration += duration
        logTrackingDiagnosticsIfNeeded()
        #endif
    }

    private func logTrackingDiagnosticsIfNeeded() {
        #if DEBUG
        let now = Date()
        guard now.timeIntervalSince(lastDiagnosticsLogTimestamp) >= 2.0 else {
            return
        }

        let averageVisionDuration = processedFrameCount > 0
            ? totalVisionDuration / Double(processedFrameCount)
            : 0
        let cachedBodyAge = cachedBodyTimestamp.map { now.timeIntervalSince($0) } ?? -1
        print(
            "Juggling tracking diagnostics: processed=\(processedFrameCount) " +
            "dropped=\(droppedFrameCount) bodyRequests=\(bodyRequestCount) " +
            "avgVisionMs=\(String(format: "%.1f", averageVisionDuration * 1000)) " +
            "cachedBodyAge=\(String(format: "%.2f", cachedBodyAge))"
        )
        processedFrameCount = 0
        droppedFrameCount = 0
        bodyRequestCount = 0
        totalVisionDuration = 0
        lastDiagnosticsLogTimestamp = now
        #endif
    }
}

private struct TrackedJugglingPoint {
    let normalizedPoint: CGPoint
    let confidence: Double
}

private struct TrackedJugglingBody {
    let points: [JugglingBodyJoint: TrackedJugglingPoint]
    var confidence: Double
    var misses: Int
}

private struct JugglingBodyCandidate {
    let points: [JugglingBodyJoint: TrackedJugglingPoint]
    let confidence: Double
}

private enum JugglingCameraError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to count juggles."
        case .cameraUnavailable:
            return "The front camera is unavailable on this device."
        case .configurationFailed(let message):
            return message
        }
    }
}
