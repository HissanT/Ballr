import AVFoundation
import Combine
import Foundation
import UIKit
import Vision

struct FastTouchingFrame {
    let ballOverlayState: BallTrackerOverlayState
    let footOverlayState: FootPoseOverlayState
    let handOverlayState: HandPoseOverlayState
    let timestamp: Date
    let framePixelSize: CGSize
}

final class FastTouchingCameraController: NSObject, ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var isStarting = true

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    var onTrackingFrame: ((FastTouchingFrame) -> Void)?
    var publishesTrackingFramesToSwiftUI = true

    private let sessionQueue = DispatchQueue(label: "ballr.fast-touching.session")
    private let videoOutputQueue = DispatchQueue(label: "ballr.fast-touching.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingSemaphore = DispatchSemaphore(value: 1)
    private let ballTracker = BallTrackerEngine()
    private let footRequest = VNDetectHumanBodyPoseRequest()
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let minPointConfidence: VNConfidence = 0.25
    private let minRequiredHandPoints = 4
    private let maxTrackedFootMisses = 1
    private let maxTrackedHandMisses = 1
    private let handMatchDistanceThreshold: CGFloat = 0.22
    private let rectBlendAmount: CGFloat = 0.42

    private var ballRequest: VNCoreMLRequest?
    private var resources: BallTrackerResources?
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isObservingOrientationChanges = false
    private var currentFramePixelSize: CGSize = .zero
    private var trackedFeet: [TrackedFoot] = []
    private var trackedHands: [FastTouchingTrackedHand] = []
    private var nextHandID = 0

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
                        $0.errorMessage = FastTouchingCameraError.cameraPermissionDenied.localizedDescription
                        $0.isStarting = false
                    }
                }
            }
        case .denied, .restricted:
            publish {
                $0.permissionDenied = true
                $0.errorMessage = FastTouchingCameraError.cameraPermissionDenied.localizedDescription
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
            trackedFeet = []
            trackedHands = []
            nextHandID = 0
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
            throw FastTouchingCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw FastTouchingCameraError.configurationFailed("Unable to add the front camera input.")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw FastTouchingCameraError.configurationFailed("Unable to add the video output.")
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
        footObservations: [VNHumanBodyPoseObservation],
        handObservations: [VNHumanHandPoseObservation]
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
        let footOverlayState = processFeet(observations: footObservations)
        let handOverlayState = processHands(observations: handObservations)

        let frame = FastTouchingFrame(
            ballOverlayState: ballOverlayState,
            footOverlayState: footOverlayState,
            handOverlayState: handOverlayState,
            timestamp: timestamp,
            framePixelSize: framePixelSize
        )
        deliverTrackingFrame(frame)
    }

    private func processHands(observations: [VNHumanHandPoseObservation]) -> HandPoseOverlayState {
        let candidates = observations
            .compactMap(handCandidate(from:))
            .sorted(by: { $0.confidence > $1.confidence })
            .prefix(2)

        var unmatchedPrevious = trackedHands
        var resolvedHands: [FastTouchingTrackedHand] = []

        for candidate in candidates {
            if let matchIndex = bestHandMatchIndex(for: candidate, in: unmatchedPrevious) {
                let previous = unmatchedPrevious.remove(at: matchIndex)
                resolvedHands.append(
                    FastTouchingTrackedHand(
                        id: previous.id,
                        normalizedRect: blendRect(from: previous.normalizedRect, to: candidate.normalizedRect, amount: rectBlendAmount),
                        normalizedPoints: candidate.normalizedPoints,
                        confidence: previous.confidence * Double(1 - rectBlendAmount) + candidate.confidence * Double(rectBlendAmount),
                        misses: 0
                    )
                )
            } else {
                resolvedHands.append(
                    FastTouchingTrackedHand(
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
                FastTouchingTrackedHand(
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

    private func processFeet(observations: [VNHumanBodyPoseObservation]) -> FootPoseOverlayState {
        let candidates = observations.compactMap(bodyCandidate(from:))
        let strongestFeet = candidates.max(by: { $0.confidence < $1.confidence })?.feet ?? []

        var previousByID = Dictionary(uniqueKeysWithValues: trackedFeet.map { ($0.id, $0) })
        var resolvedFeet: [TrackedFoot] = []

        for candidate in strongestFeet {
            if let previous = previousByID.removeValue(forKey: candidate.id) {
                resolvedFeet.append(
                    TrackedFoot(
                        id: candidate.id,
                        normalizedRect: blendRect(from: previous.normalizedRect, to: candidate.normalizedRect, amount: rectBlendAmount),
                        normalizedPoints: blendPoints(from: previous.normalizedPoints, to: candidate.normalizedPoints, amount: rectBlendAmount),
                        confidence: previous.confidence * Double(1 - rectBlendAmount) + candidate.confidence * Double(rectBlendAmount),
                        misses: 0
                    )
                )
            } else {
                resolvedFeet.append(
                    TrackedFoot(
                        id: candidate.id,
                        normalizedRect: candidate.normalizedRect,
                        normalizedPoints: candidate.normalizedPoints,
                        confidence: candidate.confidence,
                        misses: 0
                    )
                )
            }
        }

        for previous in previousByID.values where previous.misses < maxTrackedFootMisses {
            resolvedFeet.append(
                TrackedFoot(
                    id: previous.id,
                    normalizedRect: previous.normalizedRect,
                    normalizedPoints: previous.normalizedPoints,
                    confidence: previous.confidence * 0.82,
                    misses: previous.misses + 1
                )
            )
        }

        trackedFeet = resolvedFeet.sorted(by: { $0.confidence > $1.confidence })

        let feet = trackedFeet.map {
            FootOverlayState(
                id: $0.id,
                normalizedRect: $0.normalizedRect,
                normalizedPoints: $0.normalizedPoints,
                confidence: $0.confidence
            )
        }

        let statusText: String
        if feet.isEmpty {
            statusText = "Searching"
        } else if feet.count == 1 {
            statusText = "Foot Found"
        } else {
            statusText = "Feet Found"
        }

        return FootPoseOverlayState(
            feet: feet,
            statusText: statusText,
            isTracking: !feet.isEmpty,
            candidateCount: strongestFeet.count
        )
    }

    private func bodyCandidate(from observation: VNHumanBodyPoseObservation) -> BodyCandidate? {
        let feet = FastTouchingFootSide.allCases.compactMap { footCandidate(for: $0, observation: observation) }
        guard !feet.isEmpty else {
            return nil
        }
        let confidence = feet.reduce(0.0) { $0 + $1.confidence } / Double(feet.count)
        return BodyCandidate(feet: feet, confidence: confidence)
    }

    private func handCandidate(from observation: VNHumanHandPoseObservation) -> FastTouchingHandCandidate? {
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
            .littleTip
        ]

        let validPoints = jointNames.compactMap { jointName -> CGPoint? in
            guard
                let point = points[jointName],
                point.confidence >= minPointConfidence
            else {
                return nil
            }
            return swiftUINormalizedPoint(fromVisionPoint: point.location)
        }

        guard validPoints.count >= minRequiredHandPoints else {
            return nil
        }

        guard let boundingRect = boundingRect(for: validPoints) else {
            return nil
        }

        let normalizedRect = expandedToMinimumSize(
            rect: boundingRect.standardized.intersection(unitRect),
            minimumWidth: 0.08,
            minimumHeight: 0.08
        )

        guard !normalizedRect.isNull, !normalizedRect.isEmpty else {
            return nil
        }

        let confidence = validPoints.isEmpty
            ? 0
            : jointNames.reduce(0.0) { partial, jointName in
                partial + Double(points[jointName]?.confidence ?? 0)
            } / Double(validPoints.count)

        return FastTouchingHandCandidate(
            normalizedRect: normalizedRect,
            normalizedPoints: validPoints,
            confidence: confidence
        )
    }

    private func bestHandMatchIndex(
        for candidate: FastTouchingHandCandidate,
        in trackedHands: [FastTouchingTrackedHand]
    ) -> Int? {
        let candidateCenter = CGPoint(x: candidate.normalizedRect.midX, y: candidate.normalizedRect.midY)
        return trackedHands
            .enumerated()
            .filter { _, previous in
                let previousCenter = CGPoint(x: previous.normalizedRect.midX, y: previous.normalizedRect.midY)
                return hypot(candidateCenter.x - previousCenter.x, candidateCenter.y - previousCenter.y) <= handMatchDistanceThreshold
            }
            .min { lhs, rhs in
                let lhsCenter = CGPoint(x: lhs.element.normalizedRect.midX, y: lhs.element.normalizedRect.midY)
                let rhsCenter = CGPoint(x: rhs.element.normalizedRect.midX, y: rhs.element.normalizedRect.midY)
                return hypot(candidateCenter.x - lhsCenter.x, candidateCenter.y - lhsCenter.y)
                    < hypot(candidateCenter.x - rhsCenter.x, candidateCenter.y - rhsCenter.y)
            }?
            .offset
    }

    private func footCandidate(
        for side: FastTouchingFootSide,
        observation: VNHumanBodyPoseObservation
    ) -> FootCandidate? {
        guard
            let knee = recognizedPoint(for: side.kneeJoint, observation: observation),
            let ankle = recognizedPoint(for: side.ankleJoint, observation: observation)
        else {
            return nil
        }

        let kneePoint = swiftUINormalizedPoint(fromVisionPoint: knee.location)
        let anklePoint = swiftUINormalizedPoint(fromVisionPoint: ankle.location)

        let dx = anklePoint.x - kneePoint.x
        let dy = anklePoint.y - kneePoint.y
        let shinLength = hypot(dx, dy)
        guard shinLength > 0.015 else {
            return nil
        }

        let direction = CGPoint(x: dx / shinLength, y: dy / shinLength)
        let perpendicular = CGPoint(x: -direction.y, y: direction.x)

        let footLength = clamp(shinLength * 0.58, minValue: 0.055, maxValue: 0.14)
        let footWidth = clamp(shinLength * 0.26, minValue: 0.03, maxValue: 0.075)
        let center = CGPoint(
            x: anklePoint.x + direction.x * footLength * 0.22,
            y: anklePoint.y + direction.y * footLength * 0.22
        )
        let halfLength = footLength * 0.5
        let halfWidth = footWidth * 0.5

        let polygon = [
            CGPoint(
                x: center.x + direction.x * halfLength + perpendicular.x * halfWidth,
                y: center.y + direction.y * halfLength + perpendicular.y * halfWidth
            ),
            CGPoint(
                x: center.x + direction.x * halfLength - perpendicular.x * halfWidth,
                y: center.y + direction.y * halfLength - perpendicular.y * halfWidth
            ),
            CGPoint(
                x: center.x - direction.x * halfLength - perpendicular.x * halfWidth,
                y: center.y - direction.y * halfLength - perpendicular.y * halfWidth
            ),
            CGPoint(
                x: center.x - direction.x * halfLength + perpendicular.x * halfWidth,
                y: center.y - direction.y * halfLength + perpendicular.y * halfWidth
            )
        ]
        .map(clampToUnitPoint)

        guard let boundingRect = boundingRect(for: polygon) else {
            return nil
        }

        let normalizedRect = expandedToMinimumSize(
            rect: boundingRect.standardized.intersection(unitRect),
            minimumWidth: 0.06,
            minimumHeight: 0.04
        )

        guard !normalizedRect.isNull, !normalizedRect.isEmpty else {
            return nil
        }

        return FootCandidate(
            id: side.id,
            normalizedRect: normalizedRect,
            normalizedPoints: polygon,
            confidence: Double(knee.confidence + ankle.confidence) * 0.5
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

    private func blendPoints(from previous: [CGPoint], to current: [CGPoint], amount: CGFloat) -> [CGPoint] {
        guard previous.count == current.count else {
            return current
        }

        return zip(previous, current).map { previousPoint, currentPoint in
            CGPoint(
                x: previousPoint.x + (currentPoint.x - previousPoint.x) * amount,
                y: previousPoint.y + (currentPoint.y - previousPoint.y) * amount
            )
        }
    }

    private func clamp(_ value: CGFloat, minValue: CGFloat, maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }

    private func deliverTrackingFrame(_ frame: FastTouchingFrame) {
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

    private func publish(_ updates: @escaping (FastTouchingCameraController) -> Void) {
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
}

extension FastTouchingCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard processingSemaphore.wait(timeout: .now()) == .success else {
            return
        }
        defer { processingSemaphore.signal() }

        guard let ballRequest, resources != nil else {
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
            try handler.perform([ballRequest, footRequest, handRequest])
            let ballObservations = (ballRequest.results as? [VNRecognizedObjectObservation]) ?? []
            let footObservations = (footRequest.results as? [VNHumanBodyPoseObservation]) ?? []
            let handObservations = (handRequest.results as? [VNHumanHandPoseObservation]) ?? []
            handleTrackingResults(
                ballObservations: ballObservations,
                footObservations: footObservations,
                handObservations: handObservations
            )
        } catch {
            publish {
                $0.errorMessage = "Fast Touching tracking failed: \(error.localizedDescription)"
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

private struct TrackedFoot {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let confidence: Double
    let misses: Int
}

private struct BodyCandidate {
    let feet: [FootCandidate]
    let confidence: Double
}

private struct FootCandidate {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let confidence: Double
}

private struct FastTouchingTrackedHand {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let confidence: Double
    let misses: Int
}

private struct FastTouchingHandCandidate {
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let confidence: Double
}

private enum FastTouchingFootSide: CaseIterable {
    case left
    case right

    var id: Int {
        switch self {
        case .left:
            return 0
        case .right:
            return 1
        }
    }

    var kneeJoint: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .left:
            return .leftKnee
        case .right:
            return .rightKnee
        }
    }

    var ankleJoint: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .left:
            return .leftAnkle
        case .right:
            return .rightAnkle
        }
    }
}

private enum FastTouchingCameraError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to count toe touches."
        case .cameraUnavailable:
            return "The front camera is unavailable on this device."
        case .configurationFailed(let message):
            return message
        }
    }
}
