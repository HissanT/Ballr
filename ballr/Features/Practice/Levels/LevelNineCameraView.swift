import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit
import Vision

struct LevelNineCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = LevelNineCameraController()
    @StateObject private var coordinator = LevelNineCoordinator()
    @State private var showsQuitConfirmation = false
    @State private var showsNextLevel = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                LevelNineRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                if !coordinator.isCompleted {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

                if cameraController.isStarting {
                    LevelNineLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    LevelNineErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.startPhase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                } else if coordinator.startPhase == .readiness, cameraController.errorMessage == nil {
                    LevelNineReadinessOverlay(pairFoundStartedAt: coordinator.pairFoundStartedAt)
                }

                if coordinator.isCompleted {
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.completionStartedAt,
                        buttonsVisible: coordinator.showsCompletionButtons,
                        onNextLevel: { showsNextLevel = true },
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .ballrAwardsXPOnSuccess(coordinator.isCompleted)
            .navigationDestination(isPresented: $showsNextLevel) {
                LevelTenCameraView()
                    .ballrCameraPresentationChrome()
                    .environment(\.ballrCountdownMascot, BallrCountdownMascot.blue)
            }
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(in: geometry.size)
                cameraController.onTrackingFrame = { [weak coordinator] frame in
                    coordinator?.handle(frame: frame, cameraController: cameraController)
                }
                cameraController.start()
            }
            .onDisappear {
                coordinator.tearDown()
                cameraController.onTrackingFrame = nil
                cameraController.stop()
                BallrOrientationController.restoreDefaultOrientation()
            }
            .onChange(of: geometry.size) { _, newSize in
                coordinator.prepare(in: newSize, forceRespawn: true)
            }
            .alert("Are you sure you want to quit the drill?", isPresented: $showsQuitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive) {
                    dismiss()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            LevelNineHudChip(
                title: "STREAK",
                value: "\(coordinator.hitStreak)",
                tint: .orange,
                alignment: .leading
            )
            Spacer()
            Button {
                showsQuitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.ballr(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.65), in: Circle())
            }
            .padding(.top, 8)
            Spacer()
            LevelNineHudChip(
                title: "HITS",
                value: "\(coordinator.successfulHits)/20",
                tint: .yellow,
                alignment: .trailing
            )
        }
    }
}

private struct LevelNineFrame {
    let ballOverlayState: BallTrackerOverlayState
    let handOverlayState: HandPoseOverlayState
    let timestamp: Date
    let framePixelSize: CGSize
}

private final class LevelNineCameraController: NSObject, ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var permissionDenied = false
    @Published private(set) var isStarting = true

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    var onTrackingFrame: ((LevelNineFrame) -> Void)?

    private let sessionQueue = DispatchQueue(label: "ballr.level9.session")
    private let videoOutputQueue = DispatchQueue(label: "ballr.level9.output")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let processingSemaphore = DispatchSemaphore(value: 1)
    private let ballTracker = BallTrackerEngine()
    private let handRequest = VNDetectHumanHandPoseRequest()
    private let minPointConfidence: VNConfidence = 0.25
    private let minRequiredPoints = 4

    private var ballRequest: VNCoreMLRequest?
    private var resources: BallTrackerResources?
    private var videoInput: AVCaptureDeviceInput?
    private var isConfigured = false
    private var isObservingOrientationChanges = false
    private var currentFramePixelSize: CGSize = .zero

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
                        $0.errorMessage = LevelNineCameraError.cameraPermissionDenied.localizedDescription
                        $0.isStarting = false
                    }
                }
            }
        case .denied, .restricted:
            publish {
                $0.permissionDenied = true
                $0.errorMessage = LevelNineCameraError.cameraPermissionDenied.localizedDescription
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
        }

        publish {
            $0.isStarting = false
            $0.onTrackingFrame = nil
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
            throw LevelNineCameraError.cameraUnavailable
        }

        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else {
            throw LevelNineCameraError.configurationFailed("Unable to add the front camera input.")
        }
        session.addInput(input)
        videoInput = input

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw LevelNineCameraError.configurationFailed("Unable to add the video output.")
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
        let handOverlayState = processHands(observations: handObservations)

        let frame = LevelNineFrame(
            ballOverlayState: ballOverlayState,
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

        let hands = candidates.enumerated().map { index, candidate in
            HandOverlayState(
                id: index,
                normalizedRect: candidate.normalizedRect,
                normalizedPoints: candidate.normalizedPoints,
                confidence: candidate.confidence
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
            .littleTip
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

    private func deliverTrackingFrame(_ frame: LevelNineFrame) {
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

    private func publish(_ updates: @escaping (LevelNineCameraController) -> Void) {
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

extension LevelNineCameraController: AVCaptureVideoDataOutputSampleBufferDelegate {
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
            try handler.perform([ballRequest, handRequest])
            let ballObservations = (ballRequest.results as? [VNRecognizedObjectObservation]) ?? []
            let handObservations = (handRequest.results as? [VNHumanHandPoseObservation]) ?? []
            handleTrackingResults(ballObservations: ballObservations, handObservations: handObservations)
        } catch {
            publish {
                $0.errorMessage = "Level 9 tracking failed: \(error.localizedDescription)"
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

private struct LevelNineDetectedHand: Identifiable {
    let id: Int
    let rect: CGRect
    let collisionPolygon: [CGPoint]
    let confidence: CGFloat

    var collisionBounds: CGRect {
        Self.boundingRect(for: collisionPolygon) ?? rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)
    }

    static func collisionPolygon(from points: [CGPoint], fallbackRect: CGRect) -> [CGPoint] {
        let hull = convexHull(points)
        if hull.count >= 3 {
            return scaled(points: hull, factor: 0.86)
        }

        let fallback = fallbackRect.insetBy(dx: fallbackRect.width * 0.22, dy: fallbackRect.height * 0.22)
        return [
            CGPoint(x: fallback.minX, y: fallback.minY),
            CGPoint(x: fallback.maxX, y: fallback.minY),
            CGPoint(x: fallback.maxX, y: fallback.maxY),
            CGPoint(x: fallback.minX, y: fallback.maxY)
        ]
    }

    private static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sortedPoints = points
            .sorted {
                if abs($0.x - $1.x) > 0.001 {
                    return $0.x < $1.x
                }
                return $0.y < $1.y
            }
            .reduce(into: [CGPoint]()) { result, point in
                guard !result.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 0.5 }) else {
                    return
                }
                result.append(point)
            }

        guard sortedPoints.count > 2 else {
            return sortedPoints
        }

        var lower: [CGPoint] = []
        for point in sortedPoints {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }

        var upper: [CGPoint] = []
        for point in sortedPoints.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }

        return Array(lower.dropLast()) + Array(upper.dropLast())
    }

    private static func cross(_ origin: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x)
    }

    private static func scaled(points: [CGPoint], factor: CGFloat) -> [CGPoint] {
        guard !points.isEmpty else {
            return []
        }

        let center = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let centroid = CGPoint(
            x: center.x / CGFloat(points.count),
            y: center.y / CGFloat(points.count)
        )

        return points.map {
            CGPoint(
                x: centroid.x + ($0.x - centroid.x) * factor,
                y: centroid.y + ($0.y - centroid.y) * factor
            )
        }
    }

    private static func boundingRect(for points: [CGPoint]) -> CGRect? {
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
}

private struct LevelNineHudChip: View {
    let title: String
    let value: String
    let tint: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.ballr(size: 16, weight: .black))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.ballr(size: 36, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .frame(minWidth: 138, minHeight: 74, alignment: alignment == .trailing ? .trailing : .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.86), lineWidth: 2)
        )
    }
}

private struct LevelNineReadinessOverlay: View {
    let pairFoundStartedAt: Date?

    private let requiredLockSeconds: TimeInterval = 3.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = readinessProgress(at: timeline.date)

            ZStack {
                Color.black.opacity(0.86)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Text(pairFoundStartedAt == nil ? "Find the ball and your hand" : "Hold both still")
                        .font(.ballr(size: 32, weight: .black))
                        .foregroundStyle(pairFoundStartedAt == nil ? Color.yellow : .white)
                        .multilineTextAlignment(.center)

                    Text(pairFoundStartedAt == nil ? "Get the ball and a hand in frame to start." : "Starting in \(remainingText(at: timeline.date))")
                        .font(.ballr(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.16))

                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.yellow)
                            .frame(width: 220 * progress)
                    }
                    .frame(width: 220, height: 12)
                    .opacity(pairFoundStartedAt == nil ? 0 : 1)
                }
                .padding(.horizontal, 24)
            }
            .allowsHitTesting(false)
        }
    }

    private func readinessProgress(at date: Date) -> CGFloat {
        guard let pairFoundStartedAt else {
            return 0
        }
        return CGFloat(min(max(date.timeIntervalSince(pairFoundStartedAt) / requiredLockSeconds, 0), 1))
    }

    private func remainingText(at date: Date) -> String {
        guard let pairFoundStartedAt else {
            return "3"
        }
        let remaining = max(ceil(requiredLockSeconds - date.timeIntervalSince(pairFoundStartedAt)), 0)
        return "\(Int(remaining))"
    }
}

private struct LevelNineLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting level 9...")
                .font(.ballr(size: 16, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LevelNineErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Camera Unavailable")
                    .font(.ballr(size: 24, weight: .black))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.ballr(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button(action: onDismiss) {
                        Text("CLOSE")
                            .font(.ballr(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if permissionDenied {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            UIApplication.shared.open(url)
                        } label: {
                            Text("OPEN SETTINGS")
                                .font(.ballr(size: 15, weight: .black))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .frame(height: 42)
                                .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)
        }
    }
}

private struct LevelNineRenderSurface: UIViewRepresentable {
    let coordinator: LevelNineCoordinator

    func makeUIView(context: Context) -> LevelNineRenderView {
        let view = LevelNineRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: LevelNineRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class LevelNineRenderView: UIView {
    private let ballTargetFillLayer = CAShapeLayer()
    private let ballTargetOuterLayer = CAShapeLayer()
    private let ballTargetInnerLayer = CAShapeLayer()
    private let handTargetFillLayer = CAShapeLayer()
    private let handTargetOuterLayer = CAShapeLayer()
    private let handTargetInnerLayer = CAShapeLayer()
    private let ballRingLayer = CAShapeLayer()
    private let ballCenterLayer = CAShapeLayer()
    private let promptLabel = UILabel()

    private var handLayers: [Int: CAShapeLayer] = [:]
    private var popupLayers: [UUID: CATextLayer] = [:]
    private var displayLink: CADisplayLink?
    private var ballDisplayRect: CGRect?
    private var hands: [LevelNineDetectedHand] = []
    private var ballTarget: LevelNineTarget?
    private var handTarget: LevelNineTarget?
    private var scorePopups: [LevelNineScorePopup] = []
    var onBoundsChange: ((CGSize) -> Void)?
    private var lastReportedBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        configureLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else if displayLink == nil {
            let displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 30)
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    func update(
        ballDisplayRect: CGRect?,
        hands: [LevelNineDetectedHand],
        ballTarget: LevelNineTarget?,
        handTarget: LevelNineTarget?,
        scorePopups: [LevelNineScorePopup]
    ) {
        self.ballDisplayRect = ballDisplayRect
        self.hands = hands
        self.ballTarget = ballTarget
        self.handTarget = handTarget
        self.scorePopups = scorePopups
        render(date: Date())
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportBoundsIfNeeded()
        render(date: Date())
    }

    private func reportBoundsIfNeeded() {
        let currentSize = bounds.size
        guard currentSize.width > 0, currentSize.height > 0 else {
            return
        }
        guard currentSize != lastReportedBoundsSize else {
            return
        }
        lastReportedBoundsSize = currentSize
        onBoundsChange?(currentSize)
    }

    private func configureLayers() {
        ballTargetFillLayer.fillColor = UIColor.black.withAlphaComponent(0.22).cgColor
        ballTargetOuterLayer.fillColor = UIColor.clear.cgColor
        ballTargetOuterLayer.strokeColor = UIColor.yellow.withAlphaComponent(0.45).cgColor
        ballTargetOuterLayer.lineWidth = 12
        ballTargetInnerLayer.fillColor = UIColor.clear.cgColor
        ballTargetInnerLayer.strokeColor = UIColor.orange.cgColor
        ballTargetInnerLayer.lineWidth = 5
        ballTargetOuterLayer.shadowColor = UIColor.yellow.cgColor
        ballTargetOuterLayer.shadowOpacity = 0.35
        ballTargetOuterLayer.shadowRadius = 16
        ballTargetOuterLayer.shadowOffset = .zero

        handTargetFillLayer.fillColor = UIColor.black.withAlphaComponent(0.22).cgColor
        handTargetOuterLayer.fillColor = UIColor.clear.cgColor
        handTargetOuterLayer.strokeColor = UIColor.systemTeal.withAlphaComponent(0.65).cgColor
        handTargetOuterLayer.lineWidth = 12
        handTargetInnerLayer.fillColor = UIColor.clear.cgColor
        handTargetInnerLayer.strokeColor = UIColor.white.cgColor
        handTargetInnerLayer.lineWidth = 5
        handTargetOuterLayer.shadowColor = UIColor.systemTeal.cgColor
        handTargetOuterLayer.shadowOpacity = 0.32
        handTargetOuterLayer.shadowRadius = 16
        handTargetOuterLayer.shadowOffset = .zero

        ballRingLayer.fillColor = UIColor.clear.cgColor
        ballRingLayer.strokeColor = UIColor.white.cgColor
        ballRingLayer.lineWidth = 2.5
        ballRingLayer.shadowColor = UIColor.black.cgColor
        ballRingLayer.shadowOpacity = 0.45
        ballRingLayer.shadowRadius = 6
        ballRingLayer.shadowOffset = .zero
        ballCenterLayer.fillColor = UIColor.orange.cgColor

        [
            ballTargetFillLayer,
            ballTargetOuterLayer,
            ballTargetInnerLayer,
            handTargetFillLayer,
            handTargetOuterLayer,
            handTargetInnerLayer,
            ballRingLayer,
            ballCenterLayer
        ].forEach(layer.addSublayer)

        promptLabel.text = "Find the ball and your hand"
        promptLabel.font = .systemFont(ofSize: 15, weight: .black)
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        promptLabel.layer.cornerRadius = 8
        promptLabel.layer.masksToBounds = true
        addSubview(promptLabel)
    }

    @objc private func renderFrame() {
        render(date: Date())
    }

    private func render(date: Date) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderTarget(ballTarget, fillLayer: ballTargetFillLayer, outerLayer: ballTargetOuterLayer, innerLayer: ballTargetInnerLayer)
        renderTarget(handTarget, fillLayer: handTargetFillLayer, outerLayer: handTargetOuterLayer, innerLayer: handTargetInnerLayer)
        renderBall()
        renderHands()
        renderPopups(date: date)
        promptLabel.isHidden = !(ballDisplayRect == nil && hands.isEmpty)
        let promptSize = CGSize(width: 220, height: 42)
        promptLabel.frame = CGRect(
            x: bounds.midX - promptSize.width * 0.5,
            y: bounds.midY - promptSize.height * 0.5,
            width: promptSize.width,
            height: promptSize.height
        )
        CATransaction.commit()
    }

    private func renderTarget(
        _ target: LevelNineTarget?,
        fillLayer: CAShapeLayer,
        outerLayer: CAShapeLayer,
        innerLayer: CAShapeLayer
    ) {
        guard let target else {
            [fillLayer, outerLayer, innerLayer].forEach {
                $0.isHidden = true
                $0.path = nil
            }
            return
        }

        let rect = CGRect(
            x: target.center.x - target.radius,
            y: target.center.y - target.radius,
            width: target.radius * 2,
            height: target.radius * 2
        )
        let innerRect = rect.insetBy(dx: 8, dy: 8)

        fillLayer.isHidden = false
        outerLayer.isHidden = false
        innerLayer.isHidden = false
        fillLayer.path = UIBezierPath(ovalIn: rect).cgPath
        outerLayer.path = UIBezierPath(ovalIn: rect).cgPath
        innerLayer.path = UIBezierPath(ovalIn: innerRect).cgPath
        fillLayer.opacity = 1
        outerLayer.opacity = 1
        innerLayer.opacity = 1
    }

    private func renderBall() {
        guard let ballDisplayRect else {
            ballRingLayer.isHidden = true
            ballCenterLayer.isHidden = true
            ballRingLayer.path = nil
            ballCenterLayer.path = nil
            return
        }

        ballRingLayer.isHidden = false
        ballCenterLayer.isHidden = false
        ballRingLayer.path = UIBezierPath(ovalIn: ballDisplayRect).cgPath
        ballCenterLayer.path = UIBezierPath(
            ovalIn: CGRect(
                x: ballDisplayRect.midX - 5,
                y: ballDisplayRect.midY - 5,
                width: 10,
                height: 10
            )
        ).cgPath
    }

    private func renderHands() {
        let activeIDs = Set(hands.map(\.id))
        let inactiveIDs = handLayers.keys.filter { !activeIDs.contains($0) }
        for id in inactiveIDs {
            handLayers[id]?.removeFromSuperlayer()
            handLayers[id] = nil
        }

        for hand in hands {
            let layer = handLayers[hand.id] ?? makeHandLayer(for: hand)
            layer.path = UIBezierPath(roundedRect: hand.rect, cornerRadius: min(hand.rect.width, hand.rect.height) * 0.18).cgPath
            layer.opacity = Float(min(max(hand.confidence, 0.35), 1.0))
            layer.isHidden = false
        }
    }

    private func renderPopups(date: Date) {
        let activePopups = scorePopups.filter { $0.isActive(at: date) }
        let activeIDs = Set(activePopups.map(\.id))
        let inactiveIDs = popupLayers.keys.filter { !activeIDs.contains($0) }
        for id in inactiveIDs {
            popupLayers[id]?.removeFromSuperlayer()
            popupLayers[id] = nil
        }

        for popup in activePopups {
            let layer = popupLayers[popup.id] ?? makePopupLayer(for: popup)
            let progress = popup.progress(at: date)
            let eased = smoothStep(progress)
            let x = popup.center.x + (popup.destination.x - popup.center.x) * eased
            let y = popup.center.y + (popup.destination.y - popup.center.y) * eased
            let scale = 1.0 + CGFloat(1.0 - progress) * 0.18
            let size = CGSize(width: 120 * scale, height: 54 * scale)
            layer.frame = CGRect(
                x: x - size.width * 0.5,
                y: y - size.height * 0.5,
                width: size.width,
                height: size.height
            )
            layer.opacity = Float(1.0 - progress)
        }
    }

    private func makeHandLayer(for hand: LevelNineDetectedHand) -> CAShapeLayer {
        let outline = CAShapeLayer()
        outline.fillColor = UIColor.clear.cgColor
        outline.strokeColor = UIColor.white.withAlphaComponent(0.58).cgColor
        outline.lineWidth = 3
        outline.shadowColor = UIColor.black.cgColor
        outline.shadowOpacity = 0.3
        outline.shadowRadius = 4
        outline.shadowOffset = .zero
        layer.addSublayer(outline)
        handLayers[hand.id] = outline
        return outline
    }

    private func makePopupLayer(for popup: LevelNineScorePopup) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.contentsScale = traitCollection.displayScale
        textLayer.alignmentMode = .center
        textLayer.string = "+\(popup.points)"
        textLayer.fontSize = 38
        textLayer.foregroundColor = UIColor.yellow.cgColor
        textLayer.shadowColor = UIColor.black.cgColor
        textLayer.shadowOpacity = 0.7
        textLayer.shadowRadius = 7
        textLayer.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(textLayer)
        popupLayers[popup.id] = textLayer
        return textLayer
    }

    private func smoothStep(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }
}

private final class LevelNineCoordinator: ObservableObject {
    @Published private(set) var startPhase: BallrDrillStartPhase = .readiness
    @Published private(set) var pairFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var hitStreak = 0
    @Published private(set) var isTracking = false
    @Published private(set) var trackingStatusText = "SEARCHING"
    @Published private(set) var successfulHits = 0
    @Published private(set) var completionStartedAt: Date?
    @Published private(set) var showsCompletionButtons = false

    private let requiredPairLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let requiredSuccessfulHits = 20
    private let completionAnimationDuration: TimeInterval = 2.05
    private let completionButtonRevealDelay: TimeInterval = 0.28

    private var gameState = LevelNineGameState()
    private var size: CGSize = .zero
    private weak var renderView: LevelNineRenderView?
    private var completionWorkItem: DispatchWorkItem?

    var isCompleted: Bool {
        completionStartedAt != nil
    }

    func attach(renderView: LevelNineRenderView) {
        if self.renderView !== renderView {
            self.renderView = renderView
            renderView.onBoundsChange = { [weak self] size in
                self?.prepare(in: size)
            }
        }

        let renderSize = renderView.bounds.size
        if renderSize.width > 0, renderSize.height > 0 {
            size = renderSize
        }

        renderView.update(
            ballDisplayRect: nil,
            hands: [],
            ballTarget: gameState.ballTarget,
            handTarget: gameState.handTarget,
            scorePopups: gameState.scorePopups
        )
    }

    func reset(in size: CGSize) {
        cancelCompletionWorkItem()
        gameState = LevelNineGameState()
        startPhase = .readiness
        pairFoundStartedAt = nil
        countdownStartedAt = nil
        hitStreak = 0
        isTracking = false
        trackingStatusText = "SEARCHING"
        successfulHits = 0
        completionStartedAt = nil
        showsCompletionButtons = false
        prepare(in: size, forceRespawn: true)
    }

    func tearDown() {
        cancelCompletionWorkItem()
    }

    func prepare(in size: CGSize, forceRespawn: Bool = false) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        self.size = resolvedGameplaySize(fallback: size)
        gameState.prepare(in: self.size, forceRespawn: forceRespawn, allowSpawn: startPhase == .live && !isCompleted)
        renderView?.update(
            ballDisplayRect: nil,
            hands: [],
            ballTarget: gameState.ballTarget,
            handTarget: gameState.handTarget,
            scorePopups: gameState.scorePopups
        )
    }

    func handle(frame: LevelNineFrame, cameraController: LevelNineCameraController) {
        let ballDisplayRect = displayRect(for: frame.ballOverlayState, cameraController: cameraController)
        let detectedHands = frame.handOverlayState.hands.compactMap { handState -> LevelNineDetectedHand? in
            guard let displayRect = cameraController.displayRect(for: handState.normalizedRect) else {
                return nil
            }
            let displayPoints = handState.normalizedPoints.compactMap {
                cameraController.displayPoint(for: $0)
            }
            return LevelNineDetectedHand(
                id: handState.id,
                rect: displayRect,
                collisionPolygon: LevelNineDetectedHand.collisionPolygon(
                    from: displayPoints,
                    fallbackRect: displayRect
                ),
                confidence: CGFloat(handState.confidence)
            )
        }

        updateTrackingStatus(
            ballTracking: frame.ballOverlayState.isTracking,
            handTracking: frame.handOverlayState.isTracking,
            ballStatus: frame.ballOverlayState.statusText,
            handStatus: frame.handOverlayState.statusText
        )
        updateStartGate(
            isTracking: frame.ballOverlayState.isTracking && frame.handOverlayState.isTracking,
            timestamp: frame.timestamp
        )

        if startPhase == .live, !isCompleted {
            let event = gameState.step(
                ballDisplayRect: ballDisplayRect,
                hands: detectedHands,
                in: size,
                timestamp: frame.timestamp
            )
            if event == .hit {
                successfulHits += 1
                LevelNineSoundPlayer.playScore()
                if successfulHits >= requiredSuccessfulHits {
                    completeLevel(at: frame.timestamp)
                }
            }
            syncHudFromGameState()
        }

        renderView?.update(
            ballDisplayRect: ballDisplayRect,
            hands: detectedHands,
            ballTarget: gameState.ballTarget,
            handTarget: gameState.handTarget,
            scorePopups: gameState.scorePopups
        )
    }

    private func resolvedGameplaySize(fallback size: CGSize) -> CGSize {
        guard let renderView else {
            return size
        }

        let renderSize = renderView.bounds.size
        guard renderSize.width > 0, renderSize.height > 0 else {
            return size
        }
        return renderSize
    }

    private func displayRect(
        for overlayState: BallTrackerOverlayState,
        cameraController: LevelNineCameraController
    ) -> CGRect? {
        guard let normalizedRect = overlayState.normalizedRect else {
            return nil
        }
        return cameraController.displayRect(for: normalizedRect)
    }

    private func updateTrackingStatus(
        ballTracking: Bool,
        handTracking: Bool,
        ballStatus: String,
        handStatus: String
    ) {
        let statusText: String
        if ballTracking && handTracking {
            statusText = "Tracking"
        } else if ballTracking {
            statusText = "Ball Found"
        } else if handTracking {
            statusText = "Hand Found"
        } else {
            statusText = "Searching"
        }

        if isTracking != (ballTracking && handTracking) {
            isTracking = ballTracking && handTracking
        }

        if trackingStatusText != statusText {
            trackingStatusText = statusText
        }
    }

    private func updateStartGate(isTracking: Bool, timestamp: Date) {
        if startPhase == .live {
            return
        }

        if startPhase == .countdown {
            if
                let countdownStartedAt,
                timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration
            {
                startPhase = .live
            }
            return
        }

        guard isTracking else {
            pairFoundStartedAt = nil
            return
        }

        let startedAt = pairFoundStartedAt ?? timestamp
        pairFoundStartedAt = startedAt

        if timestamp.timeIntervalSince(startedAt) >= requiredPairLockSeconds {
            countdownStartedAt = timestamp
            startPhase = .countdown
        }
    }

    private func syncHudFromGameState() {
        if hitStreak != gameState.hitStreak {
            hitStreak = gameState.hitStreak
        }
    }

    private func completeLevel(at timestamp: Date) {
        guard completionStartedAt == nil else {
            return
        }

        BallrDrillSoundPlayer.playWinner()
        completionStartedAt = timestamp
        showsCompletionButtons = false
        gameState.finish()
        renderView?.update(
            ballDisplayRect: nil,
            hands: [],
            ballTarget: gameState.ballTarget,
            handTarget: gameState.handTarget,
            scorePopups: gameState.scorePopups
        )

        let workItem = DispatchWorkItem { [weak self] in
            self?.showsCompletionButtons = true
        }
        completionWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + completionAnimationDuration + completionButtonRevealDelay,
            execute: workItem
        )
    }

    private func cancelCompletionWorkItem() {
        completionWorkItem?.cancel()
        completionWorkItem = nil
    }
}

private struct LevelNineGameState {
    var ballTarget: LevelNineTarget?
    var handTarget: LevelNineTarget?
    var scorePopups: [LevelNineScorePopup] = []
    var hitStreak = 0

    private let pairValue = 1
    private let spawnTopFractionBall: CGFloat = 0.75
    private let spawnTopFractionHand: CGFloat = 0.0
    private let handBottomSafeFraction: CGFloat = 0.2
    private let ballClearance: CGFloat = 24
    private let handClearance: CGFloat = 24
    private let previousPairDistanceMultiplier: CGFloat = 3.0
    private let maxPairXSeparationMultiplier: CGFloat = 1.0
    private let spawnCandidateSampleCount = 96

    mutating func prepare(in size: CGSize, forceRespawn: Bool = false, allowSpawn: Bool = true) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        guard allowSpawn else {
            ballTarget = nil
            handTarget = nil
            return
        }

        if forceRespawn || (ballTarget == nil && handTarget == nil) {
            spawnPair(in: size, timestamp: Date())
        }
    }

    mutating func finish() {
        ballTarget = nil
        handTarget = nil
    }

    mutating func step(
        ballDisplayRect: CGRect?,
        hands: [LevelNineDetectedHand],
        in size: CGSize,
        timestamp: Date
    ) -> LevelNineStepEvent? {
        scorePopups.removeAll { !$0.isActive(at: timestamp) }
        prepare(in: size)
        let previousPairCenter = currentPairCenter

        if let currentBallTarget = ballTarget, let ballDisplayRect {
            let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
            let ballRadius = max(ballDisplayRect.width, ballDisplayRect.height) * 0.5
            let distance = hypot(ballCenter.x - currentBallTarget.center.x, ballCenter.y - currentBallTarget.center.y)
            if distance <= ballRadius + currentBallTarget.radius {
                ballTarget = nil
            }
        }

        if let currentHandTarget = handTarget, hands.contains(where: { handIntersectsTarget($0, target: currentHandTarget) }) {
            handTarget = nil
        }

        if ballTarget == nil && handTarget == nil {
            hitStreak += 1
            let popupCenter = previousPairCenter ?? CGPoint(x: size.width * 0.5, y: size.height * 0.5)
            scorePopups.append(
                LevelNineScorePopup(
                    points: pairValue,
                    center: popupCenter,
                    destination: CGPoint(x: max(size.width - 104, 40), y: 40),
                    startedAt: timestamp
                )
            )
            spawnPair(
                in: size,
                timestamp: timestamp,
                previousPairCenter: previousPairCenter,
                ballDisplayRect: ballDisplayRect,
                hands: hands
            )
            return .hit
        }

        return nil
    }

    private var currentPairCenter: CGPoint? {
        guard let ballTarget, let handTarget else {
            return nil
        }

        return CGPoint(
            x: (ballTarget.center.x + handTarget.center.x) * 0.5,
            y: (ballTarget.center.y + handTarget.center.y) * 0.5
        )
    }

    private mutating func spawnPair(
        in size: CGSize,
        timestamp: Date,
        previousPairCenter: CGPoint? = nil,
        ballDisplayRect: CGRect? = nil,
        hands: [LevelNineDetectedHand] = []
    ) {
        let radius = targetRadius(for: size)
        let ballBounds = ballSpawnBounds(in: size, radius: radius)
        let handBounds = handSpawnBounds(in: size, radius: radius)
        let ballCenter = ballDisplayRect.map { CGPoint(x: $0.midX, y: $0.midY) }
        let ballRadius = ballDisplayRect.map { max($0.width, $0.height) * 0.5 } ?? 0

        var bestPair: LevelNineSpawnPair?
        var validPairs: [LevelNineSpawnPair] = []

        for _ in 0..<spawnCandidateSampleCount {
            let pairX = CGFloat.random(in: max(ballBounds.minX, handBounds.minX)...min(ballBounds.maxX, handBounds.maxX))
            let xSeparation = CGFloat.random(in: -radius * maxPairXSeparationMultiplier...radius * maxPairXSeparationMultiplier)
            let handCandidate = randomTarget(xCenter: pairX - xSeparation * 0.5, in: handBounds)
            let ballCandidate = randomTarget(xCenter: pairX + xSeparation * 0.5, in: ballBounds)

            let xDifference = abs(handCandidate.x - ballCandidate.x)
            guard xDifference <= radius * maxPairXSeparationMultiplier else {
                continue
            }
            guard isBallCandidateValid(
                ballCandidate,
                ballCenter: ballCenter,
                ballRadius: ballRadius,
                targetRadius: radius
            ) else {
                continue
            }
            guard isHandCandidateValid(
                handCandidate,
                ballCenter: ballCenter,
                hands: hands,
                targetRadius: radius
            ) else {
                continue
            }
            if
                let previousPairCenter,
                hypot(pairCenter(ballCandidate, handCandidate).x - previousPairCenter.x, pairCenter(ballCandidate, handCandidate).y - previousPairCenter.y) < radius * previousPairDistanceMultiplier
            {
                continue
            }

            let quality = pairQuality(
                ballCandidate: ballCandidate,
                handCandidate: handCandidate,
                ballCenter: ballCenter,
                ballRadius: ballRadius,
                previousPairCenter: previousPairCenter,
                targetRadius: radius
            )

            let pair = LevelNineSpawnPair(
                ballCenter: ballCandidate,
                handCenter: handCandidate,
                quality: quality
            )
            validPairs.append(pair)
            if bestPair == nil || pair.quality > bestPair?.quality ?? 0 {
                bestPair = pair
            }
        }

        if !validPairs.isEmpty {
            let sortedPairs = validPairs.sorted { $0.quality > $1.quality }
            let topPairCount = max(1, min(sortedPairs.count, 12))
            bestPair = Array(sortedPairs.prefix(topPairCount)).randomElement()
        }

        if bestPair == nil, previousPairCenter != nil {
            bestPair = fallbackPair(
                in: size,
                radius: radius,
                ballCenter: ballCenter,
                ballRadius: ballRadius,
                hands: hands
            )
        }

        if let bestPair {
            ballTarget = LevelNineTarget(center: bestPair.ballCenter, radius: radius)
            handTarget = LevelNineTarget(center: bestPair.handCenter, radius: radius)
        } else {
            ballTarget = nil
            handTarget = nil
        }
    }

    private func fallbackPair(
        in size: CGSize,
        radius: CGFloat,
        ballCenter: CGPoint?,
        ballRadius: CGFloat,
        hands: [LevelNineDetectedHand]
    ) -> LevelNineSpawnPair? {
        let ballAnchors = [
            CGPoint(x: size.width * 0.2, y: size.height * 0.82),
            CGPoint(x: size.width * 0.4, y: size.height * 0.88),
            CGPoint(x: size.width * 0.6, y: size.height * 0.83),
            CGPoint(x: size.width * 0.8, y: size.height * 0.91)
        ]
        let handAnchors = [
            CGPoint(x: size.width * 0.2, y: size.height * 0.18),
            CGPoint(x: size.width * 0.4, y: size.height * 0.28),
            CGPoint(x: size.width * 0.6, y: size.height * 0.22),
            CGPoint(x: size.width * 0.8, y: size.height * 0.32)
        ]

        var bestPair: LevelNineSpawnPair?
        for ballCandidate in ballAnchors {
            guard isBallCandidateValid(
                ballCandidate,
                ballCenter: ballCenter,
                ballRadius: ballRadius,
                targetRadius: radius
            ) else {
                continue
            }

            for handCandidate in handAnchors {
                guard abs(handCandidate.x - ballCandidate.x) <= radius * 1.2 else {
                    continue
                }
                guard isHandCandidateValid(
                    handCandidate,
                    ballCenter: ballCenter,
                    hands: hands,
                    targetRadius: radius
                ) else {
                    continue
                }

                let quality = pairQuality(
                    ballCandidate: ballCandidate,
                    handCandidate: handCandidate,
                    ballCenter: ballCenter,
                    ballRadius: ballRadius,
                    previousPairCenter: nil,
                    targetRadius: radius
                )
                let pair = LevelNineSpawnPair(
                    ballCenter: ballCandidate,
                    handCenter: handCandidate,
                    quality: quality
                )
                if bestPair == nil || pair.quality > bestPair?.quality ?? 0 {
                    bestPair = pair
                }
            }
        }

        return bestPair
    }

    private func pairQuality(
        ballCandidate: CGPoint,
        handCandidate: CGPoint,
        ballCenter: CGPoint?,
        ballRadius: CGFloat,
        previousPairCenter: CGPoint?,
        targetRadius: CGFloat
    ) -> CGFloat {
        var quality = targetRadius * 10
        let pairCenter = self.pairCenter(ballCandidate, handCandidate)
        let xDifference = abs(ballCandidate.x - handCandidate.x)
        quality += max(0, targetRadius - xDifference) * 0.35
        if let previousPairCenter {
            quality += hypot(pairCenter.x - previousPairCenter.x, pairCenter.y - previousPairCenter.y)
        }
        if let ballCenter {
            quality += max(hypot(ballCandidate.x - ballCenter.x, ballCandidate.y - ballCenter.y) - ballRadius - targetRadius, 0)
        }
        return quality
    }

    private func pairCenter(_ ballCandidate: CGPoint, _ handCandidate: CGPoint) -> CGPoint {
        CGPoint(
            x: (ballCandidate.x + handCandidate.x) * 0.5,
            y: (ballCandidate.y + handCandidate.y) * 0.5
        )
    }

    private func targetRadius(for size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.091, 36), 62)
    }

    private func ballSpawnBounds(in size: CGSize, radius: CGFloat) -> CGRect {
        let horizontalPadding = radius + 26
        let top = max(size.height * spawnTopFractionBall + radius, radius + 76)
        let bottom = max(top, size.height - radius - 58)
        return CGRect(
            x: horizontalPadding,
            y: top,
            width: max(1, size.width - horizontalPadding * 2),
            height: max(1, bottom - top)
        )
    }

    private func handSpawnBounds(in size: CGSize, radius: CGFloat) -> CGRect {
        let horizontalPadding = radius + 26
        let top = max(size.height * spawnTopFractionHand + radius, radius + 76)
        let bottom = min(
            max(top + 1, size.height * (1 - handBottomSafeFraction) - radius),
            size.height - radius - 58
        )
        return CGRect(
            x: horizontalPadding,
            y: top,
            width: max(1, size.width - horizontalPadding * 2),
            height: max(1, bottom - top)
        )
    }

    private func randomTarget(xCenter: CGFloat, in bounds: CGRect) -> CGPoint {
        let x = min(max(xCenter, bounds.minX), bounds.maxX)
        let y = CGFloat.random(in: bounds.minY...bounds.maxY)
        return CGPoint(x: x, y: y)
    }

    private func isBallCandidateValid(
        _ candidate: CGPoint,
        ballCenter: CGPoint?,
        ballRadius: CGFloat,
        targetRadius: CGFloat
    ) -> Bool {
        if let ballCenter {
            let distance = hypot(candidate.x - ballCenter.x, candidate.y - ballCenter.y)
            if distance < ballRadius + targetRadius + ballClearance {
                return false
            }
        }
        return true
    }

    private func isHandCandidateValid(
        _ candidate: CGPoint,
        ballCenter: CGPoint?,
        hands: [LevelNineDetectedHand],
        targetRadius: CGFloat
    ) -> Bool {
        if let ballCenter {
            let distance = hypot(candidate.x - ballCenter.x, candidate.y - ballCenter.y)
            if distance < targetRadius + handClearance {
                return false
            }
        }

        for hand in hands {
            let bounds = hand.collisionBounds
            let requiredClearance = targetRadius + max(handClearance, min(bounds.width, bounds.height) * 0.2)
            if distance(from: candidate, to: hand) < requiredClearance {
                return false
            }
        }

        return true
    }

    private func handIntersectsTarget(_ hand: LevelNineDetectedHand, target: LevelNineTarget) -> Bool {
        distance(from: target.center, to: hand) <= target.radius
    }

    private func distance(from point: CGPoint, to hand: LevelNineDetectedHand) -> CGFloat {
        let polygon = hand.collisionPolygon
        guard polygon.count >= 3 else {
            return distance(from: point, to: hand.collisionBounds)
        }

        if polygonContains(point, polygon: polygon) {
            return 0
        }

        var minimumDistance = CGFloat.greatestFiniteMagnitude
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            minimumDistance = min(minimumDistance, distance(from: point, toSegmentFrom: start, to: end))
        }
        return minimumDistance
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        return hypot(point.x - clampedX, point.y - clampedY)
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        let projected = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projected.x, point.y - projected.y)
    }

    private func polygonContains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var contains = false
        var previousIndex = polygon.count - 1

        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[previousIndex]
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            let denominator = previous.y - current.y
            if crossesY, abs(denominator) > 0.000001 {
                let intersectionX = (previous.x - current.x) * (point.y - current.y) / denominator + current.x
                if point.x < intersectionX {
                    contains.toggle()
                }
            }
            previousIndex = index
        }

        return contains
    }
}

private struct LevelNineTarget {
    let center: CGPoint
    let radius: CGFloat
}

private struct LevelNineScorePopup: Identifiable {
    let id = UUID()
    let points: Int
    let center: CGPoint
    let destination: CGPoint
    let startedAt: Date

    private let duration: TimeInterval = 0.75

    func progress(at timestamp: Date) -> Double {
        min(max(timestamp.timeIntervalSince(startedAt) / duration, 0), 1)
    }

    func isActive(at timestamp: Date) -> Bool {
        progress(at: timestamp) < 1
    }
}

private struct LevelNineSpawnPair {
    let ballCenter: CGPoint
    let handCenter: CGPoint
    let quality: CGFloat
}

private enum LevelNineStepEvent {
    case hit
}

private enum LevelNineSoundPlayer {
    private static var player: AVAudioPlayer?

    static func playScore() {
        if player == nil {
            guard let url = Bundle.main.url(forResource: "target_scored_sound_effect", withExtension: "wav") else {
                return
            }

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)

                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.prepareToPlay()
                player = audioPlayer
            } catch {
                print("Level 9 score sound failed to load: \(error.localizedDescription)")
                return
            }
        }

        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}

private enum LevelNineCameraError: LocalizedError {
    case cameraPermissionDenied
    case cameraUnavailable
    case configurationFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to test level 9."
        case .cameraUnavailable:
            return "The front camera is unavailable on this device."
        case .configurationFailed(let message):
            return message
        }
    }
}
