import AVFoundation
import Combine
import Foundation
import UIKit
import Vision

struct JumpingChallengeFrame {
    let overlayState: JumpingChallengeOverlayState
    let handOverlayState: HandPoseOverlayState
    let timestamp: Date
    let framePixelSize: CGSize
}

struct JumpingLegOverlayState: Identifiable {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let normalizedFootRect: CGRect
    let normalizedFootPoints: [CGPoint]
    let confidence: Double
}

struct JumpingChallengeOverlayState {
    let legs: [JumpingLegOverlayState]
    let statusText: String
    let isTracking: Bool
    let candidateCount: Int

    static let idle = JumpingChallengeOverlayState(
        legs: [],
        statusText: "Searching",
        isTracking: false,
        candidateCount: 0
    )
}

final class JumpingPoseCameraController: NSObject, ObservableObject {
    @Published private(set) var overlayState: JumpingChallengeOverlayState = .idle
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var isStarting = true

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    var onTrackingFrame: ((JumpingChallengeFrame) -> Void)?
    var publishesTrackingFramesToSwiftUI = true

    private let sessionQueue = DispatchQueue(label: "ballr.jumping.session")
    private let videoOutputQueue = DispatchQueue(label: "ballr.jumping.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingSemaphore = DispatchSemaphore(value: 1)
    private let throttledTrackingPublishInterval: TimeInterval = 0.15
    private let request = VNDetectHumanBodyPoseRequest()
    private let handRequest = VNDetectHumanHandPoseRequest()

    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isObservingOrientationChanges = false
    private var lastTrackingPublishTimestamp = Date.distantPast
    private var lastPublishedTrackingStatus: Bool?
    private var currentFramePixelSize: CGSize = .zero
    private var trackedLegs: [TrackedLeg] = []
    private var trackedHands: [JumpingTrackedHand] = []
    private var lockedBodyCenter: CGPoint?
    private var lockedBodyConfidence: Double = 0
    private var lockedBodyMisses = 0
    private var nextHandID = 0

    private let minPointConfidence: VNConfidence = 0.25
    private let maxTrackedLegMisses = 1
    private let lockedBodyHorizontalMatchDistance: CGFloat = 0.18
    private let lockedBodyVerticalMatchDistance: CGFloat = 0.46
    private let lockedBodyCenterBlend: CGFloat = 0.24
    private let weakLockedBodyConfidence = 0.30
    private let switchBodyConfidence = 0.72
    private let switchBodyConfidenceMargin = 0.22
    private let minRequiredHandPoints = 4
    private let maxTrackedHandMisses = 1
    private let handMatchDistanceThreshold: CGFloat = 0.22
    private let rectBlendAmount: CGFloat = 0.42

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
                        $0.errorMessage = JumpingPoseCameraError.cameraPermissionDenied.localizedDescription
                        $0.isStarting = false
                    }
                }
            }
        case .denied, .restricted:
            publish {
                $0.permissionDenied = true
                $0.errorMessage = JumpingPoseCameraError.cameraPermissionDenied.localizedDescription
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
            trackedLegs = []
            trackedHands = []
            lockedBodyCenter = nil
            lockedBodyConfidence = 0
            lockedBodyMisses = 0
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
            throw JumpingPoseCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw JumpingPoseCameraError.configurationFailed("Unable to add the front camera input.")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw JumpingPoseCameraError.configurationFailed("Unable to add the video output.")
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

    private func handleBodyPoseResults(
        _ observations: [VNHumanBodyPoseObservation],
        handObservations: [VNHumanHandPoseObservation]
    ) {
        let timestamp = Date()
        let framePixelSize = currentFramePixelSize
        let overlayState = process(observations: observations)
        let handOverlayState = processHandObservations(handObservations)
        let frame = JumpingChallengeFrame(
            overlayState: overlayState,
            handOverlayState: handOverlayState,
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

    private func process(observations: [VNHumanBodyPoseObservation]) -> JumpingChallengeOverlayState {
        let candidates = observations.compactMap(bodyCandidate(from:))
        let selectedCandidate = selectBodyCandidate(from: candidates)
        let strongestLegs = selectedCandidate?.legs ?? []

        var previousByID = Dictionary(uniqueKeysWithValues: trackedLegs.map { ($0.id, $0) })
        var resolvedLegs: [TrackedLeg] = []

        for candidate in strongestLegs {
            if let previous = previousByID.removeValue(forKey: candidate.id) {
                resolvedLegs.append(
                    TrackedLeg(
                        id: candidate.id,
                        normalizedRect: blendRect(from: previous.normalizedRect, to: candidate.normalizedRect, amount: rectBlendAmount),
                        normalizedPoints: blendPoints(from: previous.normalizedPoints, to: candidate.normalizedPoints, amount: rectBlendAmount),
                        normalizedFootRect: blendRect(from: previous.normalizedFootRect, to: candidate.normalizedFootRect, amount: rectBlendAmount),
                        normalizedFootPoints: blendPoints(from: previous.normalizedFootPoints, to: candidate.normalizedFootPoints, amount: rectBlendAmount),
                        confidence: previous.confidence * Double(1 - rectBlendAmount) + candidate.confidence * Double(rectBlendAmount),
                        misses: 0
                    )
                )
            } else {
                resolvedLegs.append(
                    TrackedLeg(
                        id: candidate.id,
                        normalizedRect: candidate.normalizedRect,
                        normalizedPoints: candidate.normalizedPoints,
                        normalizedFootRect: candidate.normalizedFootRect,
                        normalizedFootPoints: candidate.normalizedFootPoints,
                        confidence: candidate.confidence,
                        misses: 0
                    )
                )
            }
        }

        for previous in previousByID.values where previous.misses < maxTrackedLegMisses {
            resolvedLegs.append(
                TrackedLeg(
                    id: previous.id,
                    normalizedRect: previous.normalizedRect,
                    normalizedPoints: previous.normalizedPoints,
                    normalizedFootRect: previous.normalizedFootRect,
                    normalizedFootPoints: previous.normalizedFootPoints,
                    confidence: previous.confidence * 0.82,
                    misses: previous.misses + 1
                )
            )
        }

        trackedLegs = resolvedLegs.sorted(by: { $0.confidence > $1.confidence })

        let legs = trackedLegs.map {
            JumpingLegOverlayState(
                id: $0.id,
                normalizedRect: $0.normalizedRect,
                normalizedPoints: $0.normalizedPoints,
                normalizedFootRect: $0.normalizedFootRect,
                normalizedFootPoints: $0.normalizedFootPoints,
                confidence: $0.confidence
            )
        }

        let statusText: String
        if legs.isEmpty {
            statusText = "Searching"
        } else if legs.count < 2 {
            statusText = "Find Both Feet"
        } else {
            statusText = "Feet Found"
        }

        return JumpingChallengeOverlayState(
            legs: legs,
            statusText: statusText,
            isTracking: legs.count >= 2,
            candidateCount: candidates.count
        )
    }

    private func selectBodyCandidate(from candidates: [BodyCandidate]) -> BodyCandidate? {
        guard !candidates.isEmpty else {
            lockedBodyMisses += 1
            lockedBodyConfidence *= 0.72
            return nil
        }

        guard let lockedBodyCenter else {
            let selected = candidates.max(by: { centerLockScore($0) < centerLockScore($1) })
            updateLockedBody(with: selected)
            return selected
        }

        let current = candidates
            .filter { isLockedBodyMatch($0.center, lockedBodyCenter) }
            .max(by: { $0.confidence < $1.confidence })
        let contender = candidates.max(by: { $0.confidence < $1.confidence })

        if let current {
            let currentIsWeak = current.confidence < weakLockedBodyConfidence || lockedBodyConfidence < weakLockedBodyConfidence
            if
                currentIsWeak,
                let contender,
                horizontalDistance(contender.center, current.center) > lockedBodyHorizontalMatchDistance,
                contender.confidence >= switchBodyConfidence,
                contender.confidence >= current.confidence + switchBodyConfidenceMargin
            {
                updateLockedBody(with: contender)
                return contender
            }

            updateLockedBody(with: current)
            return current
        }

        lockedBodyMisses += 1
        lockedBodyConfidence *= 0.72

        if
            let contender,
            contender.confidence >= switchBodyConfidence,
            lockedBodyConfidence < weakLockedBodyConfidence
        {
            updateLockedBody(with: contender)
            return contender
        }

        return nil
    }

    private func updateLockedBody(with candidate: BodyCandidate?) {
        guard let candidate else {
            return
        }

        if let previousCenter = lockedBodyCenter {
            lockedBodyCenter = CGPoint(
                x: previousCenter.x + (candidate.center.x - previousCenter.x) * lockedBodyCenterBlend,
                y: previousCenter.y + (candidate.center.y - previousCenter.y) * lockedBodyCenterBlend
            )
        } else {
            lockedBodyCenter = candidate.center
        }
        lockedBodyConfidence = candidate.confidence
        lockedBodyMisses = 0
    }

    private func centerLockScore(_ candidate: BodyCandidate) -> Double {
        let horizontalDistanceFromCenter = abs(candidate.center.x - 0.5)
        return candidate.confidence - Double(horizontalDistanceFromCenter * 0.90)
    }

    private func isLockedBodyMatch(_ candidateCenter: CGPoint, _ lockedCenter: CGPoint) -> Bool {
        abs(candidateCenter.x - lockedCenter.x) <= lockedBodyHorizontalMatchDistance
            && abs(candidateCenter.y - lockedCenter.y) <= lockedBodyVerticalMatchDistance
    }

    private func horizontalDistance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        abs(a.x - b.x)
    }

    private func processHandObservations(_ observations: [VNHumanHandPoseObservation]) -> HandPoseOverlayState {
        let candidates = observations
            .compactMap(handCandidate(from:))
            .sorted(by: { $0.confidence > $1.confidence })
            .prefix(2)

        var unmatchedPrevious = trackedHands
        var resolvedHands: [JumpingTrackedHand] = []

        for candidate in candidates {
            if let matchIndex = bestHandMatchIndex(for: candidate, in: unmatchedPrevious) {
                let previous = unmatchedPrevious.remove(at: matchIndex)
                resolvedHands.append(
                    JumpingTrackedHand(
                        id: previous.id,
                        normalizedRect: blendRect(from: previous.normalizedRect, to: candidate.normalizedRect, amount: rectBlendAmount),
                        normalizedPoints: candidate.normalizedPoints,
                        confidence: previous.confidence * Double(1 - rectBlendAmount) + candidate.confidence * Double(rectBlendAmount),
                        misses: 0
                    )
                )
            } else {
                resolvedHands.append(
                    JumpingTrackedHand(
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
                JumpingTrackedHand(
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
        let statusText = hands.isEmpty ? "Searching" : (hands.count == 1 ? "Hand Found" : "Hands Found")
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
            .wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
            .indexMCP, .indexPIP, .indexDIP, .indexTip,
            .middleMCP, .middlePIP, .middleDIP, .middleTip,
            .ringMCP, .ringPIP, .ringDIP, .ringTip,
            .littleMCP, .littlePIP, .littleDIP, .littleTip
        ]
        let validPoints = jointNames.compactMap { jointName -> VNRecognizedPoint? in
            guard let point = points[jointName], point.confidence >= minPointConfidence else {
                return nil
            }
            return point
        }
        guard validPoints.count >= minRequiredHandPoints else {
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
        let paddedRect = CGRect(
            x: minX - max(rawWidth * 0.10, 0.018),
            y: minY - max(rawHeight * 0.10, 0.018),
            width: rawWidth + max(rawWidth * 0.10, 0.018) * 2,
            height: rawHeight + max(rawHeight * 0.10, 0.018) * 2
        )
        let normalizedRect = expandedHandRectToMinimumSize(
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

    private func bestHandMatchIndex(for candidate: HandCandidate, in previousHands: [JumpingTrackedHand]) -> Int? {
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

    private func expandedHandRectToMinimumSize(rect: CGRect, minimumWidth: CGFloat, minimumHeight: CGFloat) -> CGRect {
        guard !rect.isNull, !rect.isEmpty else {
            return .null
        }
        let adjustedRect = CGRect(
            x: rect.midX - max(rect.width, minimumWidth) * 0.5,
            y: rect.midY - max(rect.height, minimumHeight) * 0.5,
            width: max(rect.width, minimumWidth),
            height: max(rect.height, minimumHeight)
        )
        return adjustedRect.standardized.intersection(unitRect)
    }

    private func bodyCandidate(from observation: VNHumanBodyPoseObservation) -> BodyCandidate? {
        let legs = JumpingLegSide.allCases.compactMap { legCandidate(for: $0, observation: observation) }
        guard !legs.isEmpty else {
            return nil
        }
        let confidence = legs.reduce(0.0) { $0 + $1.confidence } / Double(legs.count)
        let center = bodyCenter(from: legs)
        return BodyCandidate(legs: legs, center: center, confidence: confidence)
    }

    private func bodyCenter(from legs: [JumpingLegCandidate]) -> CGPoint {
        let centers = legs.map {
            CGPoint(x: $0.normalizedFootRect.midX, y: $0.normalizedFootRect.midY)
        }
        guard !centers.isEmpty else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        let total = centers.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(x: total.x / CGFloat(centers.count), y: total.y / CGFloat(centers.count))
    }

    private func legCandidate(
        for side: JumpingLegSide,
        observation: VNHumanBodyPoseObservation
    ) -> JumpingLegCandidate? {
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
        guard shinLength > 0.02 else {
            return nil
        }

        let direction = CGPoint(x: dx / shinLength, y: dy / shinLength)
        let perpendicular = CGPoint(x: -direction.y, y: direction.x)

        let topCenter = CGPoint(
            x: kneePoint.x,
            y: kneePoint.y
        )
        let bottomCenter = CGPoint(
            x: anklePoint.x + direction.x * shinLength * 0.08,
            y: anklePoint.y + direction.y * shinLength * 0.08
        )
        let topHalfWidth = clamp(shinLength * 0.075, minValue: 0.010, maxValue: 0.024)
        let bottomHalfWidth = clamp(shinLength * 0.11, minValue: 0.016, maxValue: 0.036)
        let footHalfWidth = clamp(shinLength * 0.1144, minValue: 0.01584, maxValue: 0.03344)
        let footHalfHeight = clamp(shinLength * 0.14, minValue: 0.024, maxValue: 0.048)
        let footCenter = CGPoint(
            x: anklePoint.x + direction.x * shinLength * 0.12,
            y: anklePoint.y + direction.y * shinLength * 0.12
        )

        let polygon = [
            CGPoint(
                x: topCenter.x + perpendicular.x * topHalfWidth,
                y: topCenter.y + perpendicular.y * topHalfWidth
            ),
            CGPoint(
                x: topCenter.x - perpendicular.x * topHalfWidth,
                y: topCenter.y - perpendicular.y * topHalfWidth
            ),
            CGPoint(
                x: bottomCenter.x - perpendicular.x * bottomHalfWidth,
                y: bottomCenter.y - perpendicular.y * bottomHalfWidth
            ),
            CGPoint(
                x: bottomCenter.x + perpendicular.x * bottomHalfWidth,
                y: bottomCenter.y + perpendicular.y * bottomHalfWidth
            )
        ]
        .map(clampToUnitPoint)
        let footPolygon = [
            CGPoint(
                x: footCenter.x + perpendicular.x * footHalfWidth - direction.x * footHalfHeight,
                y: footCenter.y + perpendicular.y * footHalfWidth - direction.y * footHalfHeight
            ),
            CGPoint(
                x: footCenter.x - perpendicular.x * footHalfWidth - direction.x * footHalfHeight,
                y: footCenter.y - perpendicular.y * footHalfWidth - direction.y * footHalfHeight
            ),
            CGPoint(
                x: footCenter.x - perpendicular.x * footHalfWidth + direction.x * footHalfHeight,
                y: footCenter.y - perpendicular.y * footHalfWidth + direction.y * footHalfHeight
            ),
            CGPoint(
                x: footCenter.x + perpendicular.x * footHalfWidth + direction.x * footHalfHeight,
                y: footCenter.y + perpendicular.y * footHalfWidth + direction.y * footHalfHeight
            )
        ]
        .map(clampToUnitPoint)

        guard
            let legBoundingRect = boundingRect(for: polygon),
            let footBoundingRect = boundingRect(for: footPolygon)
        else {
            return nil
        }

        let normalizedRect = expandedToMinimumSize(
            rect: legBoundingRect.standardized.intersection(unitRect),
            minimumWidth: 0.032,
            minimumHeight: 0.072
        )

        guard !normalizedRect.isNull, !normalizedRect.isEmpty else {
            return nil
        }

        return JumpingLegCandidate(
            id: side.id,
            normalizedRect: normalizedRect,
            normalizedPoints: polygon,
            normalizedFootRect: footBoundingRect.standardized.intersection(unitRect),
            normalizedFootPoints: footPolygon,
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

    private func clamp(_ value: CGFloat, minValue: CGFloat, maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
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

    private func deliverTrackingFrame(_ frame: JumpingChallengeFrame) {
        DispatchQueue.main.async { [weak self] in
            self?.onTrackingFrame?(frame)
        }
    }

    private func shouldPublishTrackingFrameToSwiftUI(_ frame: JumpingChallengeFrame) -> Bool {
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

    private func publish(_ updates: @escaping (JumpingPoseCameraController) -> Void) {
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

extension JumpingPoseCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
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
            try handler.perform([request, handRequest])
            let observations = (request.results as? [VNHumanBodyPoseObservation]) ?? []
            let handObservations = (handRequest.results as? [VNHumanHandPoseObservation]) ?? []
            handleBodyPoseResults(observations, handObservations: handObservations)
        } catch {
            publish {
                $0.errorMessage = "Jump tracking failed: \(error.localizedDescription)"
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

private struct BodyCandidate {
    let legs: [JumpingLegCandidate]
    let center: CGPoint
    let confidence: Double
}

private struct JumpingLegCandidate {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let normalizedFootRect: CGRect
    let normalizedFootPoints: [CGPoint]
    let confidence: Double
}

private struct TrackedLeg {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let normalizedFootRect: CGRect
    let normalizedFootPoints: [CGPoint]
    let confidence: Double
    let misses: Int
}

private struct JumpingTrackedHand {
    let id: Int
    let normalizedRect: CGRect
    let normalizedPoints: [CGPoint]
    let confidence: Double
    let misses: Int
}

private enum JumpingLegSide: CaseIterable {
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

private enum JumpingPoseCameraError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to play Jumping Challenge."
        case .cameraUnavailable:
            return "The front camera is unavailable on this device."
        case .configurationFailed(let message):
            return message
        }
    }
}
