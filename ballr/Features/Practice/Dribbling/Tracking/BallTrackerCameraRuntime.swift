import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit
import Vision

struct BallTrackerFrame {
    let overlayState: BallTrackerOverlayState
    let handOverlayState: HandPoseOverlayState
    let bodyOverlayState: AgilityChallengeOverlayState
    let timestamp: Date
    let framePixelSize: CGSize
}

final class BallTrackerCameraController: NSObject, ObservableObject {
    @Published private(set) var overlayState: BallTrackerOverlayState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var isStarting = true

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    var onTrackingFrame: ((BallTrackerFrame) -> Void)?
    var publishesTrackingFramesToSwiftUI = true
    var detectsHands = false
    var detectsBody = false
    var trackingProfile: BallTrackerTrackingProfile = .standard

    private let sessionQueue = DispatchQueue(label: "ballr.dribbling.session")
    private let videoOutputQueue = DispatchQueue(label: "ballr.dribbling.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let tracker = BallTrackerEngine()
    private let processingSemaphore = DispatchSemaphore(value: 1)
    private let throttledTrackingPublishInterval: TimeInterval = 0.15

    private var resources: BallTrackerResources?
    private var request: VNCoreMLRequest?
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let bodyRequest = VNDetectHumanBodyPoseRequest()
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isObservingOrientationChanges = false
    private var lastTrackingPublishTimestamp = Date.distantPast
    private var lastPublishedTrackingStatus: Bool?
    private var currentFramePixelSize: CGSize = .zero
    private var currentHandOverlayState: HandPoseOverlayState = .idle
    private var currentBodyOverlayState: AgilityChallengeOverlayState = .idle
    private var trackedHands: [BallTrackerTrackedHand] = []
    private var trackedBody: BallTrackerTrackedBody?
    private var nextHandID = 0
    private let minHandPointConfidence: VNConfidence = 0.25
    private let minRequiredHandPoints = 4
    private let maxTrackedHandMisses = 1
    private let handMatchDistanceThreshold: CGFloat = 0.22
    private let handRectBlendAmount: CGFloat = 0.42
    private let minBodyPointConfidence: VNConfidence = 0.25
    private let maxTrackedBodyMisses = 2
    private let bodyBlendAmount: CGFloat = 0.24
    #if DEBUG
    private var processedFrameCount = 0
    private var droppedFrameCount = 0
    private var totalVisionDuration: TimeInterval = 0
    private var lastDiagnosticsLogTimestamp = Date()
    #endif

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init()
        previewLayer.videoGravity = .resizeAspectFill
        handRequest.maximumHandCount = 2
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

        sessionQueue.async { [weak self] in
            guard let self else {
                return
            }

            if session.isRunning {
                session.stopRunning()
            }
            tracker.reset()
            trackedHands = []
            trackedBody = nil
            currentHandOverlayState = .idle
            currentBodyOverlayState = .idle
        }

        publish {
            $0.overlayState = .idle
            $0.isStarting = false
            $0.onTrackingFrame = nil
            $0.publishesTrackingFramesToSwiftUI = true
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

    func displayPoint(forTrackerPoint point: CGPoint) -> CGPoint? {
        let rect = CGRect(
            x: point.x - 0.0005,
            y: point.y - 0.0005,
            width: 0.001,
            height: 0.001
        )
        guard let displayRect = displayRect(for: rect) else {
            return nil
        }
        return CGPoint(x: displayRect.midX, y: displayRect.midY)
    }

    func trackerPoint(forDisplayPoint point: CGPoint) -> CGPoint? {
        guard !previewLayer.bounds.isEmpty else {
            return nil
        }

        let probeRect = CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)
        var metadataRect = previewLayer.metadataOutputRectConverted(fromLayerRect: probeRect)
            .standardized
            .intersection(unitRect)
        guard !metadataRect.isNull, !metadataRect.isEmpty else {
            return nil
        }

        var normalizedPoint = CGPoint(x: metadataRect.midX, y: metadataRect.midY)
        if
            resources?.config.frontendNotes.mirrorPreviewOnly == true,
            previewLayer.connection?.isVideoMirrored == true
        {
            normalizedPoint.x = 1.0 - normalizedPoint.x
            metadataRect.origin.x = 1.0 - metadataRect.origin.x - metadataRect.width
        }

        guard unitRect.contains(normalizedPoint) else {
            return nil
        }
        return normalizedPoint
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
        let timestamp = Date()
        let framePixelSize = currentFramePixelSize
        let overlayState = tracker.process(
            observations: observations,
            frameSize: framePixelSize,
            timestamp: timestamp,
            config: resources.config,
            profile: trackingProfile
        )
        logFilteredObservationsIfNeeded(observations, overlayState: overlayState, config: resources.config)
        let frame = BallTrackerFrame(
            overlayState: overlayState,
            handOverlayState: currentHandOverlayState,
            bodyOverlayState: currentBodyOverlayState,
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

    private func deliverTrackingFrame(_ frame: BallTrackerFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.onTrackingFrame?(frame)
        }
    }

    private func processHandObservations(_ observations: [VNHumanHandPoseObservation]) -> HandPoseOverlayState {
        let candidates = observations
            .compactMap(handCandidate(from:))
            .sorted(by: { $0.confidence > $1.confidence })
            .prefix(2)

        var unmatchedPrevious = trackedHands
        var resolvedHands: [BallTrackerTrackedHand] = []

        for candidate in candidates {
            if let matchIndex = bestHandMatchIndex(for: candidate, in: unmatchedPrevious) {
                let previous = unmatchedPrevious.remove(at: matchIndex)
                resolvedHands.append(
                    BallTrackerTrackedHand(
                        id: previous.id,
                        normalizedRect: blendHandRect(from: previous.normalizedRect, to: candidate.normalizedRect),
                        normalizedPoints: candidate.normalizedPoints,
                        confidence: previous.confidence * Double(1 - handRectBlendAmount) + candidate.confidence * Double(handRectBlendAmount),
                        misses: 0
                    )
                )
            } else {
                resolvedHands.append(
                    BallTrackerTrackedHand(
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
                BallTrackerTrackedHand(
                    id: previous.id,
                    normalizedRect: previous.normalizedRect,
                    normalizedPoints: previous.normalizedPoints,
                    confidence: previous.confidence * 0.82,
                    misses: previous.misses + 1
                )
            )
        }

        trackedHands = Array(resolvedHands.sorted(by: { $0.confidence > $1.confidence }).prefix(2))
        let hands = trackedHands.map {
            HandOverlayState(
                id: $0.id,
                normalizedRect: $0.normalizedRect,
                normalizedPoints: $0.normalizedPoints,
                confidence: $0.confidence
            )
        }
        return HandPoseOverlayState(
            hands: hands,
            statusText: hands.isEmpty ? "Searching" : (hands.count == 1 ? "Hand Found" : "Hands Found"),
            isTracking: !hands.isEmpty,
            candidateCount: candidates.count
        )
    }

    private func handCandidate(from observation: VNHumanHandPoseObservation) -> HandCandidate? {
        guard let points = try? observation.recognizedPoints(.all) else {
            return nil
        }
        let jointNames: [VNHumanHandPoseObservation.JointName] = [
            .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]
        let validPoints = jointNames.compactMap { jointName -> VNRecognizedPoint? in
            guard let point = points[jointName], point.confidence >= minHandPointConfidence else {
                return nil
            }
            return point
        }
        guard validPoints.count >= minRequiredHandPoints else {
            return nil
        }
        let normalizedPoints = validPoints.map {
            CGPoint(x: min(max($0.location.x, 0), 1), y: min(max($0.location.y, 0), 1))
        }
        let minX = normalizedPoints.map(\.x).min() ?? 0
        let maxX = normalizedPoints.map(\.x).max() ?? 0
        let minY = normalizedPoints.map(\.y).min() ?? 0
        let maxY = normalizedPoints.map(\.y).max() ?? 0
        let rawWidth = max(maxX - minX, 0.035)
        let rawHeight = max(maxY - minY, 0.045)
        let horizontalPadding = max(rawWidth * 0.10, 0.018)
        let verticalPadding = max(rawHeight * 0.10, 0.018)
        let rect = CGRect(
            x: minX - horizontalPadding,
            y: minY - verticalPadding,
            width: rawWidth + horizontalPadding * 2,
            height: rawHeight + verticalPadding * 2
        )
        let normalizedRect = expandedHandRect(rect.standardized.intersection(unitRect))
        guard !normalizedRect.isNull, !normalizedRect.isEmpty else {
            return nil
        }
        let averageConfidence = validPoints.reduce(0.0) { $0 + Double($1.confidence) } / Double(validPoints.count)
        return HandCandidate(normalizedRect: normalizedRect, normalizedPoints: normalizedPoints, confidence: averageConfidence)
    }

    private func bestHandMatchIndex(for candidate: HandCandidate, in previousHands: [BallTrackerTrackedHand]) -> Int? {
        let candidateCenter = CGPoint(x: candidate.normalizedRect.midX, y: candidate.normalizedRect.midY)
        return previousHands.enumerated()
            .filter { _, previous in
                let previousCenter = CGPoint(x: previous.normalizedRect.midX, y: previous.normalizedRect.midY)
                return hypot(previousCenter.x - candidateCenter.x, previousCenter.y - candidateCenter.y) <= handMatchDistanceThreshold
            }
            .min { lhs, rhs in
                let lhsCenter = CGPoint(x: lhs.element.normalizedRect.midX, y: lhs.element.normalizedRect.midY)
                let rhsCenter = CGPoint(x: rhs.element.normalizedRect.midX, y: rhs.element.normalizedRect.midY)
                return hypot(lhsCenter.x - candidateCenter.x, lhsCenter.y - candidateCenter.y)
                    < hypot(rhsCenter.x - candidateCenter.x, rhsCenter.y - candidateCenter.y)
            }?
            .offset
    }

    private func blendHandRect(from previous: CGRect, to current: CGRect) -> CGRect {
        CGRect(
            x: previous.origin.x + (current.origin.x - previous.origin.x) * handRectBlendAmount,
            y: previous.origin.y + (current.origin.y - previous.origin.y) * handRectBlendAmount,
            width: previous.width + (current.width - previous.width) * handRectBlendAmount,
            height: previous.height + (current.height - previous.height) * handRectBlendAmount
        )
        .standardized
        .intersection(unitRect)
    }

    private func expandedHandRect(_ rect: CGRect) -> CGRect {
        guard !rect.isNull, !rect.isEmpty else {
            return .null
        }
        let width = max(rect.width, 0.075)
        let height = max(rect.height, 0.09)
        return CGRect(
            x: rect.midX - width * 0.5,
            y: rect.midY - height * 0.5,
            width: width,
            height: height
        )
        .standardized
        .intersection(unitRect)
    }

    private func processBodyObservations(_ observations: [VNHumanBodyPoseObservation]) -> AgilityChallengeOverlayState {
        let candidates = observations.compactMap(bodyCandidate(from:))
        let strongestCandidate = candidates.max(by: { $0.confidence < $1.confidence })

        if let strongestCandidate {
            if let trackedBody {
                self.trackedBody = BallTrackerTrackedBody(
                    normalizedCenter: CGPoint(
                        x: trackedBody.normalizedCenter.x + (strongestCandidate.normalizedCenter.x - trackedBody.normalizedCenter.x) * bodyBlendAmount,
                        y: trackedBody.normalizedCenter.y + (strongestCandidate.normalizedCenter.y - trackedBody.normalizedCenter.y) * bodyBlendAmount
                    ),
                    normalizedSpan: trackedBody.normalizedSpan + (strongestCandidate.normalizedSpan - trackedBody.normalizedSpan) * bodyBlendAmount,
                    confidence: trackedBody.confidence * Double(1 - bodyBlendAmount) + strongestCandidate.confidence * Double(bodyBlendAmount),
                    misses: 0
                )
            } else {
                trackedBody = BallTrackerTrackedBody(
                    normalizedCenter: strongestCandidate.normalizedCenter,
                    normalizedSpan: strongestCandidate.normalizedSpan,
                    confidence: strongestCandidate.confidence,
                    misses: 0
                )
            }
        } else if let trackedBody, trackedBody.misses < maxTrackedBodyMisses {
            self.trackedBody = BallTrackerTrackedBody(
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

    private func bodyCandidate(from observation: VNHumanBodyPoseObservation) -> BallTrackerBodyCandidate? {
        let leftHip = recognizedBodyPoint(for: .leftHip, observation: observation)
        let rightHip = recognizedBodyPoint(for: .rightHip, observation: observation)
        let leftShoulder = recognizedBodyPoint(for: .leftShoulder, observation: observation)
        let rightShoulder = recognizedBodyPoint(for: .rightShoulder, observation: observation)

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

        let leftPoint = clampToUnitPoint(pair.0.location)
        let rightPoint = clampToUnitPoint(pair.1.location)
        let center = CGPoint(
            x: (leftPoint.x + rightPoint.x) * 0.5,
            y: (leftPoint.y + rightPoint.y) * 0.5
        )
        let span = max(abs(rightPoint.x - leftPoint.x), 0.12)
        let confidence = Double(pair.0.confidence + pair.1.confidence) * 0.5

        return BallTrackerBodyCandidate(
            normalizedCenter: clampToUnitPoint(center),
            normalizedSpan: min(max(span, 0.12), 0.36),
            confidence: confidence
        )
    }

    private func recognizedBodyPoint(
        for jointName: VNHumanBodyPoseObservation.JointName,
        observation: VNHumanBodyPoseObservation
    ) -> VNRecognizedPoint? {
        guard
            let point = try? observation.recognizedPoint(jointName),
            point.confidence >= minBodyPointConfidence
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

    private func shouldPublishTrackingFrameToSwiftUI(_ frame: BallTrackerFrame) -> Bool {
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

    private func publish(_ updates: @escaping (BallTrackerCameraController) -> Void) {
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
            logDroppedFrameIfNeeded()
            return
        }
        defer { processingSemaphore.signal() }
        let startedAt = Date()

        let orientation = resources.config.frontendNotes.passCaptureOrientation
            ? CGImagePropertyOrientation(videoOrientation: connection.videoOrientation)
            : .up
        currentFramePixelSize = framePixelSize(from: sampleBuffer, videoOrientation: connection.videoOrientation)
        let handler = VNImageRequestHandler(
            cmSampleBuffer: sampleBuffer,
            orientation: orientation,
            options: [:]
        )

        do {
            var requests: [VNRequest] = [request]
            if detectsHands {
                requests.append(handRequest)
            }
            if detectsBody {
                requests.append(bodyRequest)
            }

            try handler.perform(requests)

            if detectsHands {
                let handObservations = (handRequest.results as? [VNHumanHandPoseObservation]) ?? []
                currentHandOverlayState = processHandObservations(handObservations)
            } else {
                currentHandOverlayState = .idle
                trackedHands = []
            }

            if detectsBody {
                let bodyObservations = bodyRequest.results ?? []
                currentBodyOverlayState = processBodyObservations(bodyObservations)
            } else {
                currentBodyOverlayState = .idle
                trackedBody = nil
            }
            logVisionDurationIfNeeded(Date().timeIntervalSince(startedAt))
        } catch {
            publish {
                $0.errorMessage = "Vision request failed: \(error.localizedDescription)"
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

    private func logDroppedFrameIfNeeded() {
        #if DEBUG
        droppedFrameCount += 1
        logTrackingDiagnosticsIfNeeded()
        #endif
    }

    private func logVisionDurationIfNeeded(_ duration: TimeInterval) {
        #if DEBUG
        processedFrameCount += 1
        totalVisionDuration += duration
        logTrackingDiagnosticsIfNeeded()
        #endif
    }

    private func logTrackingDiagnosticsIfNeeded() {
        #if DEBUG
        let now = Date()
        guard now.timeIntervalSince(lastDiagnosticsLogTimestamp) >= 3.0 else {
            return
        }

        let averageVisionMS = processedFrameCount == 0
            ? 0
            : (totalVisionDuration / Double(processedFrameCount)) * 1000
        print(
            "BallTracker diagnostics: processed=\(processedFrameCount), " +
            "dropped=\(droppedFrameCount), avgVisionMS=\(String(format: "%.1f", averageVisionMS)), " +
            "swiftUIPublishEveryFrame=\(publishesTrackingFramesToSwiftUI)"
        )
        processedFrameCount = 0
        droppedFrameCount = 0
        totalVisionDuration = 0
        lastDiagnosticsLogTimestamp = now
        #endif
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

private struct BallTrackerTrackedHand {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let confidence: Double
    let misses: Int
}

private struct BallTrackerBodyCandidate {
    let normalizedCenter: CGPoint
    let normalizedSpan: CGFloat
    let confidence: Double
}

private struct BallTrackerTrackedBody {
    let normalizedCenter: CGPoint
    let normalizedSpan: CGFloat
    let confidence: Double
    let misses: Int
}

extension AVCaptureVideoOrientation {
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
