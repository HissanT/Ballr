import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct CrossbarChallengeCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = CrossbarChallengeCoordinator()
    @State private var showsQuitConfirmation = false
    @State private var dragStartBox: CGRect?
    @State private var dragMode: CrossbarChallengePlacementDragMode = .none
    @State private var dragPassedMoveThreshold = false
    @State private var pinchStartBox: CGRect?
    @State private var isPinchingTarget = false
    @State private var suppressDragUntil = Date.distantPast

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                CrossbarChallengeRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if coordinator.phase == .setup {
                        setupControls
                    } else {
                        bottomStatus
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .zIndex(100)

                if cameraController.isStarting {
                    CrossbarChallengeLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    CrossbarChallengeErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt, showsYellowCharacterFlight: true)
                }

                if coordinator.requiresPassingSpotReturn {
                    CrossbarChallengeFullscreenPromptOverlay(message: "MOVE BACK TO THE\nSHOOTING SPOT")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(250)
                }

                if coordinator.isComplete {
                    CrossbarChallengeCompletionOverlay(score: coordinator.score)
                        .zIndex(300)
                }
            }
            .animation(.easeInOut(duration: 0.24), value: coordinator.requiresPassingSpotReturn)
            .contentShape(Rectangle())
            .gesture(setupDragGesture(in: geometry.size))
            .simultaneousGesture(setupPinchGesture(in: geometry.size))
            .ballrCameraPresentationChrome()
            .ballrAwardsXPOnSuccess(coordinator.isComplete)
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(viewSize: geometry.size)
                cameraController.trackingProfile = .shooting
                cameraController.publishesTrackingFramesToSwiftUI = false
                cameraController.onTrackingFrame = { [weak coordinator, weak cameraController] frame in
                    guard let cameraController else {
                        return
                    }
                    coordinator?.handle(frame: frame, cameraController: cameraController)
                }
                cameraController.start()
            }
            .onDisappear {
                cameraController.onTrackingFrame = nil
                cameraController.publishesTrackingFramesToSwiftUI = true
                cameraController.trackingProfile = .standard
                cameraController.stop()
                BallrOrientationController.restoreDefaultOrientation()
            }
            .onChange(of: geometry.size) { _, newSize in
                coordinator.prepare(viewSize: newSize)
            }
            .alert("Are you sure you want to quit the drill?", isPresented: $showsQuitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive) {
                    dismiss()
                }
            }
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                showsQuitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.ballr(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 10) {
                CrossbarChallengeHudChip(title: "SCORE", value: "\(coordinator.score)", tint: .yellow)
                CrossbarChallengeHudChip(title: "SHOTS", value: "\(coordinator.shotsRemaining)", tint: .orange)
            }
        }
    }

    private var bottomStatus: some View {
        VStack(spacing: 8) {
            Text(coordinator.phaseTitle)
                .font(.ballr(size: 18, weight: .black))
                .foregroundStyle(Color.yellow)

            Text(coordinator.statusText)
                .font(.ballr(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 86)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }

    private var setupControls: some View {
        Button {
            coordinator.startCalibration()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text("START")
            }
            .font(.ballr(size: 22, weight: .black))
            .tracking(1.8)
            .foregroundStyle(.black)
            .frame(width: 190, height: 62)
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.78, green: 0.64, blue: 0.00))
                    .frame(height: 7)
                    .offset(y: 4)
            }
        }
        .buttonStyle(.plain)
    }

    private func setupDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard coordinator.phase == .setup, !isPinchingTarget, Date() >= suppressDragUntil else {
                    return
                }
                if dragStartBox == nil {
                    dragStartBox = coordinator.targetBox
                    dragMode = coordinator.placementDragMode(at: value.startLocation)
                    dragPassedMoveThreshold = false
                }
                guard let startBox = dragStartBox else {
                    return
                }
                switch dragMode {
                case .moveFromCenter:
                    let distance = hypot(value.translation.width, value.translation.height)
                    guard dragPassedMoveThreshold || distance >= 8 else {
                        return
                    }
                    dragPassedMoveThreshold = true
                    coordinator.updateTargetBox(
                        startBox.offsetBy(dx: value.translation.width, dy: value.translation.height),
                        in: size
                    )
                case .moveFromOutside:
                    coordinator.moveTargetBox(startBox, center: value.location, in: size)
                case .resize(let edge):
                    coordinator.resizeTargetBox(startBox, edge: edge, translation: value.translation, in: size)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                dragStartBox = nil
                dragMode = .none
                dragPassedMoveThreshold = false
            }
    }

    private func setupPinchGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                guard coordinator.phase == .setup else {
                    return
                }
                guard isPinchingTarget || abs(scale - 1.0) >= 0.035 else {
                    return
                }
                isPinchingTarget = true
                suppressDragUntil = .distantFuture
                dragStartBox = nil
                dragMode = .none
                dragPassedMoveThreshold = false
                if pinchStartBox == nil {
                    pinchStartBox = coordinator.targetBox
                }
                guard let startBox = pinchStartBox else {
                    return
                }
                coordinator.scaleTargetBox(startBox, scale: scale, in: size)
            }
            .onEnded { _ in
                pinchStartBox = nil
                isPinchingTarget = false
                suppressDragUntil = Date().addingTimeInterval(0.2)
                dragStartBox = nil
                dragMode = .none
                dragPassedMoveThreshold = false
            }
    }
}

private enum CrossbarChallengePlacementDragMode: Equatable {
    case none
    case moveFromOutside
    case moveFromCenter
    case resize(CrossbarChallengeResizeEdge)
}

private enum CrossbarChallengeResizeEdge {
    case top
    case bottom
    case left
    case right
}

private enum CrossbarChallengePhase {
    case setup
    case reference
    case calibration
    case countdown
    case live
}

private enum ShootingZoneCell: CaseIterable, Hashable {
    case topLeft
    case topMiddle
    case topRight
    case middleLeft
    case center
    case middleRight
    case bottomLeft
    case bottomMiddle
    case bottomRight

    var row: Int {
        switch self {
        case .topLeft, .topMiddle, .topRight:
            return 0
        case .middleLeft, .center, .middleRight:
            return 1
        case .bottomLeft, .bottomMiddle, .bottomRight:
            return 2
        }
    }

    var column: Int {
        switch self {
        case .topLeft, .middleLeft, .bottomLeft:
            return 0
        case .topMiddle, .center, .bottomMiddle:
            return 1
        case .topRight, .middleRight, .bottomRight:
            return 2
        }
    }

    var index: Int {
        row * 3 + column
    }

    static func cell(row: Int, column: Int) -> ShootingZoneCell? {
        allCases.first { $0.row == row && $0.column == column }
    }
}

private enum ShootingZoneTileState {
    case intact
    case breaking(startedAt: Date)
    case gone

    var isAvailableForHit: Bool {
        if case .intact = self {
            return true
        }
        return false
    }

    var isBroken: Bool {
        switch self {
        case .intact:
            return false
        case .breaking, .gone:
            return true
        }
    }
}

private enum CrossbarChallengeHitResult {
    case crossbar
    case leftPost
    case rightPost
    case miss

    var points: Int {
        switch self {
        case .crossbar:
            return 5
        case .leftPost, .rightPost:
            return 2
        case .miss:
            return 0
        }
    }

    var label: String {
        switch self {
        case .crossbar:
            return "+5"
        case .leftPost, .rightPost:
            return "+2"
        case .miss:
            return "MISS"
        }
    }

    var isHit: Bool {
        points > 0
    }
}

private struct CrossbarChallengeTrackerOverlay {
    let displayRect: CGRect?
    let rawDisplayRect: CGRect?
    let center: CGPoint?
    let confidence: Double?
    let isTracking: Bool
    let misses: Int

    static let idle = CrossbarChallengeTrackerOverlay(
        displayRect: nil,
        rawDisplayRect: nil,
        center: nil,
        confidence: nil,
        isTracking: false,
        misses: 0
    )
}

private struct CrossbarChallengeDepthSample {
    let timestamp: Date
    let centerPixels: CGPoint
    let frameWidth: CGFloat
    let pixelDiameter: CGFloat
    let smoothedDiameter: CGFloat
    let rawDistanceM: CGFloat
    let estimatedDistanceM: CGFloat
}

private struct CrossbarChallengeWallCalibration {
    let wallDistanceM: CGFloat
    let impactPixelDiameter: CGFloat
}

private enum CrossbarChallengeThrowPhase {
    case idle
    case outboundCandidate
    case outboundConfirmed
    case cooldown
}

private struct CrossbarChallengeThrowState {
    var phase: CrossbarChallengeThrowPhase = .idle
    var nearStartDepthM: CGFloat?
    var outboundFrames = 0
    var missingFrames = 0
    var cooldownStartedAt: Date?
    var furthestSample: CrossbarChallengeDepthSample?
    var eligibleSamples: [CrossbarChallengeDepthSample] = []
}

private struct CrossbarChallengeImpact {
    let displayPoint: CGPoint?
    let hitResult: CrossbarChallengeHitResult
    let timestamp: Date
}

private final class CrossbarChallengeCoordinator: ObservableObject {
    @Published private(set) var phase: CrossbarChallengePhase = .setup
    @Published private(set) var phaseTitle = "PLACE TARGET"
    @Published private(set) var statusText = "Place the crossbar frame. Pinch to resize."
    @Published private(set) var score = 0
    @Published private(set) var shotsTaken = 0
    @Published private(set) var shotsRemaining = 10
    @Published private(set) var isComplete = false
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var requiresPassingSpotReturn = false
    @Published private(set) var targetBox: CGRect = .zero

    private let targetAspectRatio: CGFloat = 1.62
    private let ballDiameterM: CGFloat = 0.22
    private let defaultFocalLengthPX: CGFloat = 2400.0
    private let focalReferenceWidthPX: CGFloat = 1920.0
    private let referenceHoldSeconds: TimeInterval = 5.0
    private let wallHoldSeconds: TimeInterval = 10.0
    private let holdMaxMissingFrames = 15
    private let holdMaxFrameDelta: TimeInterval = 0.1
    private let countdownDuration: TimeInterval = 4.0
    private let smoothingAlpha: CGFloat = 0.35
    private let minValidCalibrationSamples = 12
    private let minCalibrationDiameterPX: CGFloat = 16.0
    private let minWallDistanceM: CGFloat = 1.5
    private let maxWallDistanceM: CGFloat = 14.0
    private let outboundMinimumFrames = 4
    private let impactReversalM: CGFloat = 0.04
    private let passingSpotReturnDistanceMargin: CGFloat = 0.20
    private let returnPromptDelay: TimeInterval = 7.0
    private let cooldownMissingFrames = 6
    private let impactDisappearFrames = 8
    private let maxLiveCenterJumpPX: CGFloat = 220
    private let maxLiveCenterJumpDiameters: CGFloat = 4.0
    private let maxLiveDiameterRatio: CGFloat = 2.35
    private let edgeLiveCenterJumpMultiplier: CGFloat = 1.55
    private let edgeLiveDiameterRatioMultiplier: CGFloat = 1.30
    private let maxShots = 10

    private var viewSize: CGSize = .zero
    private var wallCalibration: CrossbarChallengeWallCalibration?
    private var zeroReferenceDepthM: CGFloat?
    private var referenceStartedAt: Date?
    private var referenceElapsed: TimeInterval = 0
    private var referenceMissingFrames = 0
    private var referenceSamples: [CGFloat] = []
    private var calibrationStartedAt: Date?
    private var calibrationElapsed: TimeInterval = 0
    private var calibrationMissingFrames = 0
    private var calibrationDepthSamples: [CGFloat] = []
    private var calibrationDiameterSamples: [CGFloat] = []
    private var diameterWindow: [CGFloat] = []
    private var smoothedDiameter: CGFloat?
    private var throwState = CrossbarChallengeThrowState()
    private var lastImpact: CrossbarChallengeImpact?
    private var trackerOverlay = CrossbarChallengeTrackerOverlay.idle
    private weak var renderView: CrossbarChallengeRenderView?

    func attach(renderView: CrossbarChallengeRenderView) {
        self.renderView = renderView
        publishRender()
    }

    func reset(viewSize: CGSize) {
        self.viewSize = viewSize
        phase = .setup
        phaseTitle = "PLACE TARGET"
        statusText = "Drag the center or open space to move. Drag the bar or posts to resize."
        score = 0
        shotsTaken = 0
        shotsRemaining = maxShots
        isComplete = false
        countdownStartedAt = nil
        requiresPassingSpotReturn = false
        targetBox = defaultTargetBox(in: viewSize)
        wallCalibration = nil
        zeroReferenceDepthM = nil
        referenceStartedAt = nil
        referenceElapsed = 0
        referenceMissingFrames = 0
        referenceSamples.removeAll()
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
        diameterWindow.removeAll()
        smoothedDiameter = nil
        throwState = CrossbarChallengeThrowState()
        lastImpact = nil
        trackerOverlay = .idle
        publishRender()
    }

    func prepare(viewSize: CGSize) {
        self.viewSize = viewSize
        if targetBox == .zero {
            targetBox = defaultTargetBox(in: viewSize)
        } else {
            targetBox = clampedBox(targetBox, in: viewSize)
        }
        publishRender()
    }

    func updateTargetBox(_ box: CGRect, in size: CGSize) {
        guard phase == .setup else {
            return
        }
        targetBox = clampedBox(box, in: size)
        publishRender()
    }

    func moveTargetBox(_ box: CGRect, center: CGPoint, in size: CGSize) {
        guard phase == .setup else {
            return
        }
        let moved = CGRect(
            x: center.x - box.width * 0.5,
            y: center.y - box.height * 0.5,
            width: box.width,
            height: box.height
        )
        targetBox = clampedBox(moved, in: size)
        publishRender()
    }

    func placementDragMode(at point: CGPoint) -> CrossbarChallengePlacementDragMode {
        guard phase == .setup, targetBox.width > 0, targetBox.height > 0 else {
            return .none
        }

        let strokeWidth = goalStrokeWidth
        let edgeBand = max(strokeWidth * 1.4, 28)
        let leftPostRect = CGRect(
            x: targetBox.minX - edgeBand,
            y: targetBox.minY - edgeBand * 0.35,
            width: edgeBand * 2,
            height: targetBox.height + edgeBand * 0.7
        )
        let rightPostRect = CGRect(
            x: targetBox.maxX - edgeBand,
            y: targetBox.minY - edgeBand * 0.35,
            width: edgeBand * 2,
            height: targetBox.height + edgeBand * 0.7
        )
        let crossbarRect = CGRect(
            x: targetBox.minX - edgeBand * 0.35,
            y: targetBox.minY - edgeBand,
            width: targetBox.width + edgeBand * 0.7,
            height: edgeBand * 2
        )

        if leftPostRect.contains(point) {
            return .resize(.left)
        }
        if rightPostRect.contains(point) {
            return .resize(.right)
        }
        if crossbarRect.contains(point) {
            return .resize(.top)
        }

        let centerRect = targetBox.insetBy(dx: targetBox.width * 0.34, dy: targetBox.height * 0.30)
        if centerRect.contains(point) {
            return .moveFromCenter
        }
        if !targetBox.insetBy(dx: -edgeBand, dy: -edgeBand).contains(point) {
            return .moveFromOutside
        }
        return .none
    }

    func resizeTargetBox(
        _ box: CGRect,
        edge: CrossbarChallengeResizeEdge,
        translation: CGSize,
        in size: CGSize
    ) {
        guard phase == .setup else {
            return
        }

        var resized = box
        switch edge {
        case .left:
            let width = clampedTargetWidth(box.width - translation.width, in: size)
            resized = CGRect(x: box.maxX - width, y: box.minY, width: width, height: box.height)
        case .right:
            let width = clampedTargetWidth(box.width + translation.width, in: size)
            resized = CGRect(x: box.minX, y: box.minY, width: width, height: box.height)
        case .top:
            let height = clampedTargetHeight(box.height - translation.height, in: size)
            resized = CGRect(x: box.minX, y: box.maxY - height, width: box.width, height: height)
        case .bottom:
            let height = clampedTargetHeight(box.height + translation.height, in: size)
            resized = CGRect(x: box.minX, y: box.minY, width: box.width, height: height)
        }

        targetBox = clampedBox(resized, in: size)
        publishRender()
    }

    func scaleTargetBox(_ box: CGRect, scale: CGFloat, in size: CGSize) {
        guard phase == .setup else {
            return
        }
        let resolvedScale = clampedScale(for: box, scale: scale, in: size)
        let newSize = CGSize(
            width: box.width * resolvedScale,
            height: box.height * resolvedScale
        )
        let scaled = CGRect(
            x: box.midX - newSize.width * 0.5,
            y: box.midY - newSize.height * 0.5,
            width: newSize.width,
            height: newSize.height
        )
        targetBox = clampedBox(scaled, in: size)
        publishRender()
    }

    func startCalibration() {
        guard phase == .setup else {
            return
        }
        phase = .reference
        phaseTitle = "PASSING SPOT"
        statusText = "Hold the ball at your passing spot for 5 seconds"
        referenceStartedAt = nil
        referenceElapsed = 0
        referenceMissingFrames = 0
        referenceSamples.removeAll()
        setRequiresPassingSpotReturn(false)
        publishRender()
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        updateTrackerOverlay(from: frame.overlayState, cameraController: cameraController)
        let focalLength = effectiveFocalLength(frameWidth: frame.framePixelSize.width)
        let sample = buildDepthSample(frame: frame, focalLength: focalLength)

        switch phase {
        case .setup:
            phaseTitle = "PLACE TARGET"
            statusText = "Drag the center or open space to move. Drag the bar or posts to resize."
            setRequiresPassingSpotReturn(false)
        case .reference:
            stepReference(sample: sample, timestamp: frame.timestamp)
        case .calibration:
            stepCalibration(sample: sample, timestamp: frame.timestamp)
        case .countdown:
            stepCountdown(timestamp: frame.timestamp)
        case .live:
            if !isComplete {
                stepLive(sample: sample, frame: frame, cameraController: cameraController)
            }
        }

        publishRender()
    }

    private func buildDepthSample(frame: BallTrackerFrame, focalLength: CGFloat) -> CrossbarChallengeDepthSample? {
        let overlay = frame.overlayState
        guard
            overlay.confirmedFrames >= 1,
            overlay.misses == 0,
            let centerPixels = overlay.centerPixels,
            let pixelDiameter = overlay.pixelDiameter,
            pixelDiameter >= 1
        else {
            return nil
        }

        appendDiameter(pixelDiameter)
        let medianDiameter = median(diameterWindow) ?? pixelDiameter
        let nextSmoothed = smoothedDiameter.map {
            $0 + (medianDiameter - $0) * smoothingAlpha
        } ?? medianDiameter
        smoothedDiameter = nextSmoothed

        let rawDistance = estimateDistance(pixelDiameter: pixelDiameter, focalLength: focalLength)
        let estimatedDistance = estimateDistance(pixelDiameter: nextSmoothed, focalLength: focalLength)
        return CrossbarChallengeDepthSample(
            timestamp: frame.timestamp,
            centerPixels: centerPixels,
            frameWidth: frame.framePixelSize.width,
            pixelDiameter: pixelDiameter,
            smoothedDiameter: nextSmoothed,
            rawDistanceM: rawDistance,
            estimatedDistanceM: estimatedDistance
        )
    }

    private func appendDiameter(_ diameter: CGFloat) {
        diameterWindow.append(diameter)
        if diameterWindow.count > 5 {
            diameterWindow.removeFirst(diameterWindow.count - 5)
        }
    }

    private func stepReference(sample: CrossbarChallengeDepthSample?, timestamp: Date) {
        guard let sample else {
            if referenceElapsed <= 0 {
                statusText = "Keep the ball visible at your passing spot"
                return
            }
            referenceMissingFrames += 1
            if referenceMissingFrames > holdMaxMissingFrames {
                referenceStartedAt = nil
                referenceElapsed = 0
                referenceMissingFrames = 0
                referenceSamples.removeAll()
                statusText = "Passing spot hold lost. Hold the ball still and start again."
                return
            }
            referenceStartedAt = nil
            statusText = "Passing spot paused. Reacquire the ball: \(remainingText(referenceHoldSeconds - referenceElapsed))"
            return
        }

        if let referenceStartedAt {
            referenceElapsed += min(max(timestamp.timeIntervalSince(referenceStartedAt), 0), holdMaxFrameDelta)
        }
        referenceStartedAt = timestamp
        referenceMissingFrames = 0
        referenceSamples.append(sample.rawDistanceM)

        if referenceElapsed < referenceHoldSeconds {
            statusText = "Hold the ball at your passing spot: \(remainingText(referenceHoldSeconds - referenceElapsed))"
            return
        }

        guard let zeroDepth = median(referenceSamples) else {
            statusText = "Reference failed. Hold the ball still and try again."
            referenceStartedAt = nil
            return
        }

        zeroReferenceDepthM = zeroDepth
        phase = .calibration
        phaseTitle = "WALL DEPTH"
        statusText = "Reference locked. Hold the ball at the wall for 10 seconds"
        referenceStartedAt = nil
        referenceElapsed = 0
        referenceMissingFrames = 0
        referenceSamples.removeAll()
        diameterWindow.removeAll()
        smoothedDiameter = nil
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
    }

    private func stepCalibration(sample: CrossbarChallengeDepthSample?, timestamp: Date) {
        guard let sample else {
            if calibrationElapsed <= 0 {
                statusText = "Keep the ball visible at the wall"
                return
            }
            calibrationMissingFrames += 1
            if calibrationMissingFrames > holdMaxMissingFrames {
                resetCalibration(message: "Wall hold lost. Hold the ball at the wall again.")
                return
            }
            calibrationStartedAt = nil
            statusText = "Wall hold paused. Reacquire the ball: \(remainingText(wallHoldSeconds - calibrationElapsed))"
            return
        }

        if let calibrationStartedAt {
            calibrationElapsed += min(max(timestamp.timeIntervalSince(calibrationStartedAt), 0), holdMaxFrameDelta)
        }
        calibrationStartedAt = timestamp
        calibrationMissingFrames = 0
        calibrationDepthSamples.append(sample.rawDistanceM)
        calibrationDiameterSamples.append(sample.pixelDiameter)

        if calibrationElapsed < wallHoldSeconds {
            statusText = "Hold the ball at the wall: \(remainingText(wallHoldSeconds - calibrationElapsed))"
            return
        }

        guard
            calibrationDepthSamples.count >= minValidCalibrationSamples,
            let wallDistance = median(calibrationDepthSamples),
            let impactDiameter = median(calibrationDiameterSamples),
            wallDistance >= minWallDistanceM,
            wallDistance <= maxWallDistanceM,
            impactDiameter >= minCalibrationDiameterPX
        else {
            resetCalibration(message: "Wall calibration failed. Hold the ball at the wall again.")
            return
        }

        wallCalibration = CrossbarChallengeWallCalibration(
            wallDistanceM: wallDistance,
            impactPixelDiameter: impactDiameter
        )
        phase = .countdown
        phaseTitle = "GET READY"
        statusText = "Crossbar Challenge starts in 3"
        countdownStartedAt = timestamp
        throwState = CrossbarChallengeThrowState()
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
    }

    private func resetCalibration(message: String) {
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
        countdownStartedAt = nil
        diameterWindow.removeAll()
        smoothedDiameter = nil
        statusText = message
    }

    private func stepCountdown(timestamp: Date) {
        guard let countdownStartedAt else {
            self.countdownStartedAt = timestamp
            return
        }

        let elapsed = timestamp.timeIntervalSince(countdownStartedAt)
        if elapsed >= countdownDuration {
            phase = .live
            phaseTitle = "LIVE"
            statusText = "Hit the crossbar or posts. Shots left: \(shotsRemaining)"
            self.countdownStartedAt = nil
        }
    }

    private func stepLive(
        sample: CrossbarChallengeDepthSample?,
        frame: BallTrackerFrame,
        cameraController: BallTrackerCameraController
    ) {
        guard let wallCalibration else {
            phase = .calibration
            phaseTitle = "WALL DEPTH"
            statusText = "Crossbar Challenge needs calibration"
            setRequiresPassingSpotReturn(false)
            return
        }

        let wallDistance = wallCalibration.wallDistanceM
        let zeroDepth = zeroReferenceDepthM ?? 0
        let wallTravel = max(wallDistance - zeroDepth, 0.5)
        let impactTolerance = max(CGFloat(0.20), wallDistance * 0.06)
        let liveSample = sample.flatMap { isLiveSampleConsistent($0) ? $0 : nil }

        guard let sample = liveSample else {
            if
                throwState.phase == .outboundConfirmed,
                let furthestSample = throwState.furthestSample,
                throwState.eligibleSamples.count >= outboundMinimumFrames
            {
                throwState.missingFrames += 1
                if
                    throwState.missingFrames <= impactDisappearFrames,
                    furthestSample.rawDistanceM >= wallDistance - impactTolerance
                {
                    lockImpact(furthestSample, frame: frame, cameraController: cameraController)
                }
            } else if throwState.phase == .cooldown {
                throwState.missingFrames += 1
                setRequiresPassingSpotReturn(shouldShowReturnPrompt(at: frame.timestamp))
                if throwState.missingFrames > cooldownMissingFrames {
                    throwState.missingFrames = cooldownMissingFrames
                    statusText = requiresPassingSpotReturn ? "Bring the ball back to the passing spot" : "Shot locked. Get ready to return."
                }
            }
            return
        }

        throwState.missingFrames = 0
        if let nearStart = throwState.nearStartDepthM {
            throwState.nearStartDepthM = min(nearStart, sample.rawDistanceM)
        } else {
            throwState.nearStartDepthM = sample.rawDistanceM
        }
        if throwState.phase != .cooldown {
            setRequiresPassingSpotReturn(false)
        }

        switch throwState.phase {
        case .idle:
            throwState.eligibleSamples.removeAll()
            throwState.outboundFrames = 0
            throwState.furthestSample = nil
            if
                let nearStart = throwState.nearStartDepthM,
                sample.rawDistanceM - nearStart >= 0.12
            {
                throwState.phase = .outboundCandidate
                appendEligibleSample(sample)
                throwState.outboundFrames = 1
                statusText = "Shot detected. Tracking wall approach."
            } else {
                statusText = "Shoot toward the crossbar"
            }
        case .outboundCandidate:
            appendEligibleSample(sample)
            guard let nearStart = throwState.nearStartDepthM else {
                return
            }
            if sample.rawDistanceM < nearStart + 0.05 {
                throwState = CrossbarChallengeThrowState(nearStartDepthM: sample.rawDistanceM)
                statusText = "Shoot toward the crossbar"
                return
            }

            let previous = throwState.eligibleSamples.dropLast().last
            if previous == nil || sample.rawDistanceM >= (previous?.rawDistanceM ?? sample.rawDistanceM) - 0.02 {
                throwState.outboundFrames += 1
            } else {
                throwState.outboundFrames = max(throwState.outboundFrames - 1, 0)
            }

            if
                throwState.outboundFrames >= outboundMinimumFrames,
                sample.rawDistanceM - nearStart >= wallTravel * 0.40
            {
                throwState.phase = .outboundConfirmed
                throwState.furthestSample = sample
                statusText = "Outbound shot confirmed."
            }
        case .outboundConfirmed:
            appendEligibleSample(sample)
            let previous = throwState.eligibleSamples.dropLast().last
            if throwState.furthestSample == nil || sample.rawDistanceM > (throwState.furthestSample?.rawDistanceM ?? 0) {
                throwState.furthestSample = sample
            }

            guard let furthestSample = throwState.furthestSample else {
                return
            }

            let reversedEnough = sample.rawDistanceM <= furthestSample.rawDistanceM - impactReversalM
                || (previous != nil && sample.rawDistanceM <= (previous?.rawDistanceM ?? sample.rawDistanceM) - 0.03)
            if furthestSample.rawDistanceM >= wallDistance - impactTolerance, reversedEnough {
                lockImpact(furthestSample, frame: frame, cameraController: cameraController)
                return
            }

            if
                let nearStart = throwState.nearStartDepthM,
                sample.rawDistanceM < nearStart + 0.10
            {
                throwState = CrossbarChallengeThrowState(nearStartDepthM: sample.rawDistanceM)
                statusText = "Shoot toward the crossbar"
            }
        case .cooldown:
            if isBackAtPassingSpot(sample.rawDistanceM, zeroDepth: zeroDepth) {
                throwState = CrossbarChallengeThrowState(nearStartDepthM: sample.rawDistanceM)
                setRequiresPassingSpotReturn(false)
                statusText = "Ready for the next shot. Shots left: \(shotsRemaining)"
            } else {
                setRequiresPassingSpotReturn(shouldShowReturnPrompt(at: sample.timestamp))
                statusText = requiresPassingSpotReturn ? "Bring the ball back to the passing spot" : "Shot locked. Hold for a moment."
            }
        }
    }

    private func lockImpact(
        _ impactSample: CrossbarChallengeDepthSample,
        frame: BallTrackerFrame,
        cameraController: BallTrackerCameraController
    ) {
        guard throwState.phase != .cooldown else {
            return
        }
        let centerPixels = robustImpactCenter(impactTimestamp: impactSample.timestamp) ?? impactSample.centerPixels
        let displayPoint = displayPoint(forPixelPoint: centerPixels, frameSize: frame.framePixelSize, cameraController: cameraController)
        let hitResult = displayPoint.map(crossbarHitResult) ?? .miss

        shotsTaken += 1
        shotsRemaining = max(maxShots - shotsTaken, 0)
        score += hitResult.points

        if hitResult.isHit {
            CrossbarChallengeSoundPlayer.playFrameHit()
            statusText = "\(hitResult.label) scored. Shots left: \(shotsRemaining)"
        } else {
            BallrDrillSoundPlayer.playIncorrect()
            statusText = "Missed the frame. Shots left: \(shotsRemaining)"
        }

        lastImpact = CrossbarChallengeImpact(
            displayPoint: displayPoint,
            hitResult: hitResult,
            timestamp: impactSample.timestamp
        )

        if shotsTaken >= maxShots {
            completeChallenge()
        }

        throwState.phase = .cooldown
        throwState.cooldownStartedAt = impactSample.timestamp
        throwState.missingFrames = 0
        setRequiresPassingSpotReturn(false)
    }

    private func completeChallenge() {
        guard !isComplete else {
            return
        }
        isComplete = true
        phaseTitle = "COMPLETE"
        statusText = "Challenge complete. Final score: \(score)"
        BallrDrillSoundPlayer.playWinner()
    }

    private func crossbarHitResult(for point: CGPoint) -> CrossbarChallengeHitResult {
        guard targetBox.width > 0, targetBox.height > 0 else {
            return .miss
        }
        let strokeWidth = goalStrokeWidth
        let postTolerance = max(strokeWidth * 0.85, min(targetBox.width, targetBox.height) * 0.10)
        let crossbarRect = CGRect(
            x: targetBox.minX - strokeWidth * 0.45,
            y: targetBox.minY - strokeWidth * 0.5,
            width: targetBox.width + strokeWidth * 0.9,
            height: strokeWidth * 1.75
        )
        let leftPostRect = CGRect(
            x: targetBox.minX - postTolerance,
            y: targetBox.minY - strokeWidth * 0.15,
            width: postTolerance * 2,
            height: targetBox.height + strokeWidth * 0.45
        )
        let rightPostRect = CGRect(
            x: targetBox.maxX - postTolerance,
            y: targetBox.minY - strokeWidth * 0.15,
            width: postTolerance * 2,
            height: targetBox.height + strokeWidth * 0.45
        )

        if crossbarRect.contains(point) {
            return .crossbar
        }
        if leftPostRect.contains(point) {
            return .leftPost
        }
        if rightPostRect.contains(point) {
            return .rightPost
        }
        return .miss
    }

    private var goalStrokeWidth: CGFloat {
        max(18, min(targetBox.width, targetBox.height) * 0.085)
    }

    private func appendEligibleSample(_ sample: CrossbarChallengeDepthSample) {
        throwState.eligibleSamples.append(sample)
        if throwState.eligibleSamples.count > 12 {
            throwState.eligibleSamples.removeFirst(throwState.eligibleSamples.count - 12)
        }
    }

    private func isLiveSampleConsistent(_ sample: CrossbarChallengeDepthSample) -> Bool {
        guard
            let previous = throwState.eligibleSamples.last ?? throwState.furthestSample,
            sample.timestamp.timeIntervalSince(previous.timestamp) <= 0.22
        else {
            return true
        }

        let centerJump = hypot(
            sample.centerPixels.x - previous.centerPixels.x,
            sample.centerPixels.y - previous.centerPixels.y
        )
        let edgeTolerance = liveEdgeTolerance(for: sample)
        let maxJump = max(
            maxLiveCenterJumpPX,
            max(sample.pixelDiameter, previous.pixelDiameter) * maxLiveCenterJumpDiameters
        ) * (1 + edgeTolerance * (edgeLiveCenterJumpMultiplier - 1))
        guard centerJump <= maxJump else {
            return false
        }

        let smallerDiameter = max(min(sample.pixelDiameter, previous.pixelDiameter), 1)
        let diameterRatio = max(sample.pixelDiameter, previous.pixelDiameter) / smallerDiameter
        return diameterRatio <= maxLiveDiameterRatio * (1 + edgeTolerance * (edgeLiveDiameterRatioMultiplier - 1))
    }

    private func liveEdgeTolerance(for sample: CrossbarChallengeDepthSample) -> CGFloat {
        let frameWidth = max(sample.frameWidth, 1)
        let normalizedX = min(max(sample.centerPixels.x / frameWidth, 0), 1)
        let distanceToEdge = min(normalizedX, 1 - normalizedX)
        return min(max((0.24 - distanceToEdge) / 0.24, 0), 1)
    }

    private func robustImpactCenter(impactTimestamp: Date) -> CGPoint? {
        var samples: [CrossbarChallengeDepthSample] = []
        for sample in throwState.eligibleSamples.reversed() where sample.timestamp <= impactTimestamp {
            samples.append(sample)
            if samples.count == 5 {
                break
            }
        }
        guard !samples.isEmpty else {
            return nil
        }

        guard
            let centerX = median(samples.map { $0.centerPixels.x }),
            let centerY = median(samples.map { $0.centerPixels.y })
        else {
            return nil
        }
        return CGPoint(x: centerX, y: centerY)
    }

    private func isBackAtPassingSpot(_ distance: CGFloat, zeroDepth: CGFloat) -> Bool {
        let margin = max(zeroDepth * passingSpotReturnDistanceMargin, 0.12)
        return distance >= zeroDepth - margin && distance <= zeroDepth + margin
    }

    private func shouldShowReturnPrompt(at timestamp: Date) -> Bool {
        guard let cooldownStartedAt = throwState.cooldownStartedAt else {
            return false
        }
        return timestamp.timeIntervalSince(cooldownStartedAt) >= returnPromptDelay
    }

    private func updateTrackerOverlay(
        from overlayState: BallTrackerOverlayState,
        cameraController: BallTrackerCameraController
    ) {
        let displayRect = overlayState.normalizedRect.flatMap {
            cameraController.displayRect(for: $0)
        }
        let rawDisplayRect = overlayState.rawNormalizedRect.flatMap {
            cameraController.displayRect(for: $0)
        }
        let center = displayRect.map {
            CGPoint(x: $0.midX, y: $0.midY)
        }
        trackerOverlay = CrossbarChallengeTrackerOverlay(
            displayRect: displayRect,
            rawDisplayRect: rawDisplayRect,
            center: center,
            confidence: overlayState.confidence,
            isTracking: overlayState.isTracking,
            misses: overlayState.misses
        )
    }

    private func publishRender() {
        renderView?.update(
            targetBox: targetBox,
            trackerOverlay: trackerOverlay,
            impact: lastImpact,
            phase: phase
        )
    }

    private func defaultTargetBox(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return .zero
        }
        let width = min(size.width * 0.46, 360)
        let height = width / targetAspectRatio
        return CGRect(
            x: size.width * 0.5 - width * 0.5,
            y: size.height * 0.46 - height * 0.5,
            width: width,
            height: height
        )
    }

    private func clampedBox(_ box: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return box
        }
        let width = box.width
        let height = box.height
        let strokeOverflow = max(18, min(width, height) * 0.085) * 0.5
        let safeTop: CGFloat = 74
        let safeBottom: CGFloat = 108
        let horizontalEdgeAllowance = max(strokeOverflow * 3.5, 72)
        let minX = strokeOverflow * 0.35
        let maxX = max(minX, size.width - width + horizontalEdgeAllowance)
        let minY = safeTop
        let maxY = max(minY, size.height - height - safeBottom)
        let originX = min(max(box.midX - width * 0.5, minX), maxX)
        let originY = min(max(box.midY - height * 0.5, minY), maxY)
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func clampedScale(for box: CGRect, scale: CGFloat, in size: CGSize) -> CGFloat {
        guard box.width > 0, box.height > 0, size.width > 0, size.height > 0 else {
            return scale
        }
        let minWidth = minimumTargetWidth(in: size)
        let maxWidth = maximumTargetWidth(in: size)
        let minHeight = minimumTargetHeight(in: size)
        let maxHeight = maximumTargetHeight(in: size)
        let minScale = max(minWidth / box.width, minHeight / box.height)
        let maxScale = min(maxWidth / box.width, maxHeight / box.height)
        return min(max(scale, minScale), maxScale)
    }

    private func clampedTargetWidth(_ width: CGFloat, in size: CGSize) -> CGFloat {
        min(max(width, minimumTargetWidth(in: size)), maximumTargetWidth(in: size))
    }

    private func clampedTargetHeight(_ height: CGFloat, in size: CGSize) -> CGFloat {
        min(max(height, minimumTargetHeight(in: size)), maximumTargetHeight(in: size))
    }

    private func minimumTargetWidth(in size: CGSize) -> CGFloat {
        min(max(size.width * 0.20, 140), 220)
    }

    private func maximumTargetWidth(in size: CGSize) -> CGFloat {
        max(size.width + 72, minimumTargetWidth(in: size))
    }

    private func minimumTargetHeight(in size: CGSize) -> CGFloat {
        min(max(size.height * 0.20, 105), 190)
    }

    private func maximumTargetHeight(in size: CGSize) -> CGFloat {
        max(size.height - 190, minimumTargetHeight(in: size))
    }

    private func setRequiresPassingSpotReturn(_ isRequired: Bool) {
        guard requiresPassingSpotReturn != isRequired else {
            return
        }
        requiresPassingSpotReturn = isRequired
    }

    private func displayPoint(
        forPixelPoint pixelPoint: CGPoint,
        frameSize: CGSize,
        cameraController: BallTrackerCameraController
    ) -> CGPoint? {
        guard frameSize.width > 0, frameSize.height > 0 else {
            return nil
        }
        let trackerPoint = CGPoint(x: pixelPoint.x / frameSize.width, y: pixelPoint.y / frameSize.height)
        return cameraController.displayPoint(forTrackerPoint: trackerPoint)
    }

    private func estimateDistance(pixelDiameter: CGFloat, focalLength: CGFloat) -> CGFloat {
        (ballDiameterM * focalLength) / max(pixelDiameter, 0.000001)
    }

    private func effectiveFocalLength(frameWidth: CGFloat) -> CGFloat {
        defaultFocalLengthPX * max(frameWidth, 1) / focalReferenceWidthPX
    }

    private func remainingText(_ seconds: TimeInterval) -> String {
        "\(String(format: "%.1f", max(seconds, 0)))s remaining"
    }

    private func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }
        return sorted[middle]
    }
}

private struct CrossbarChallengeRenderSurface: UIViewRepresentable {
    let coordinator: CrossbarChallengeCoordinator

    func makeUIView(context: Context) -> CrossbarChallengeRenderView {
        let view = CrossbarChallengeRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: CrossbarChallengeRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class CrossbarChallengeRenderView: UIView {
    private let gridLayer = CALayer()
    private let trackerRawLayer = CAShapeLayer()
    private let trackerLayer = CAShapeLayer()
    private let trackerCenterLayer = CAShapeLayer()
    private let trackerTextLayer = CATextLayer()
    private let impactLayer = CAShapeLayer()
    private let impactTextLayer = CATextLayer()
    private var displayLink: CADisplayLink?
    private var targetBox: CGRect = .zero
    private var trackerOverlay = CrossbarChallengeTrackerOverlay.idle
    private var impact: CrossbarChallengeImpact?
    private var phase: CrossbarChallengePhase = .setup

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.addSublayer(gridLayer)
        layer.addSublayer(trackerRawLayer)
        layer.addSublayer(trackerLayer)
        layer.addSublayer(trackerCenterLayer)
        layer.addSublayer(trackerTextLayer)
        layer.addSublayer(impactLayer)
        layer.addSublayer(impactTextLayer)
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
        targetBox: CGRect,
        trackerOverlay: CrossbarChallengeTrackerOverlay,
        impact: CrossbarChallengeImpact?,
        phase: CrossbarChallengePhase
    ) {
        self.targetBox = targetBox
        self.trackerOverlay = trackerOverlay
        self.impact = impact
        self.phase = phase
        render(date: Date())
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gridLayer.frame = bounds
        trackerRawLayer.frame = bounds
        trackerLayer.frame = bounds
        trackerCenterLayer.frame = bounds
        trackerTextLayer.frame = bounds
        impactLayer.frame = bounds
        impactTextLayer.frame = bounds
        render(date: Date())
    }

    private func configureLayers() {
        trackerRawLayer.fillColor = UIColor.clear.cgColor
        trackerRawLayer.strokeColor = UIColor.white.withAlphaComponent(0.38).cgColor
        trackerRawLayer.lineWidth = 1.5
        trackerRawLayer.lineDashPattern = [5, 4]

        trackerLayer.fillColor = UIColor.clear.cgColor
        trackerLayer.lineWidth = 2.2
        trackerLayer.shadowColor = UIColor.black.cgColor
        trackerLayer.shadowOpacity = 0.42
        trackerLayer.shadowRadius = 5
        trackerLayer.shadowOffset = .zero

        trackerCenterLayer.fillColor = UIColor.clear.cgColor
        trackerCenterLayer.lineWidth = 2
        trackerCenterLayer.shadowColor = UIColor.black.cgColor
        trackerCenterLayer.shadowOpacity = 0.45
        trackerCenterLayer.shadowRadius = 4
        trackerCenterLayer.shadowOffset = .zero

        trackerTextLayer.contentsScale = UIScreen.main.scale
        trackerTextLayer.alignmentMode = .center
        trackerTextLayer.font = BallrFont.uiFont(size: 11, weight: .black)
        trackerTextLayer.fontSize = 11
        trackerTextLayer.foregroundColor = UIColor.white.cgColor
        trackerTextLayer.shadowColor = UIColor.black.cgColor
        trackerTextLayer.shadowOpacity = 0.7
        trackerTextLayer.shadowRadius = 3
        trackerTextLayer.shadowOffset = .zero

        impactLayer.fillColor = UIColor.clear.cgColor
        impactLayer.strokeColor = UIColor.white.cgColor
        impactLayer.lineWidth = 3
        impactLayer.shadowColor = UIColor.black.cgColor
        impactLayer.shadowOpacity = 0.45
        impactLayer.shadowRadius = 8
        impactLayer.shadowOffset = .zero

        impactTextLayer.contentsScale = UIScreen.main.scale
        impactTextLayer.alignmentMode = .center
        impactTextLayer.font = BallrFont.uiFont(size: 20, weight: .black)
        impactTextLayer.fontSize = 20
        impactTextLayer.shadowColor = UIColor.black.cgColor
        impactTextLayer.shadowOpacity = 0.62
        impactTextLayer.shadowRadius = 4
        impactTextLayer.shadowOffset = .zero

    }

    @objc private func renderFrame() {
        render(date: Date())
    }

    private func render(date: Date) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderGrid()
        renderTracker()
        renderImpact()
        CATransaction.commit()
    }

    private func renderGrid() {
        gridLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard targetBox.width > 0, targetBox.height > 0 else {
            return
        }

        let strokeWidth = max(18, min(targetBox.width, targetBox.height) * 0.085)
        let framePath = UIBezierPath()
        framePath.move(to: CGPoint(x: targetBox.minX, y: targetBox.maxY))
        framePath.addLine(to: CGPoint(x: targetBox.minX, y: targetBox.minY))
        framePath.addLine(to: CGPoint(x: targetBox.maxX, y: targetBox.minY))
        framePath.addLine(to: CGPoint(x: targetBox.maxX, y: targetBox.maxY))

        let frameLayer = CAShapeLayer()
        frameLayer.path = framePath.cgPath
        frameLayer.fillColor = UIColor.clear.cgColor
        frameLayer.strokeColor = UIColor(red: 1.00, green: 0.78, blue: 0.02, alpha: 0.97).cgColor
        frameLayer.lineWidth = strokeWidth
        frameLayer.lineCap = .round
        frameLayer.lineJoin = .round
        frameLayer.shadowColor = UIColor.yellow.cgColor
        frameLayer.shadowOpacity = phase == .setup ? 0.60 : 0.42
        frameLayer.shadowRadius = phase == .setup ? 18 : 12
        frameLayer.shadowOffset = .zero
        gridLayer.addSublayer(frameLayer)

        let innerPath = UIBezierPath()
        innerPath.move(to: CGPoint(x: targetBox.minX, y: targetBox.minY + strokeWidth * 1.25))
        innerPath.addLine(to: CGPoint(x: targetBox.maxX, y: targetBox.minY + strokeWidth * 1.25))
        let accentLayer = CAShapeLayer()
        accentLayer.path = innerPath.cgPath
        accentLayer.fillColor = UIColor.clear.cgColor
        accentLayer.strokeColor = UIColor.white.withAlphaComponent(0.22).cgColor
        accentLayer.lineWidth = max(2, strokeWidth * 0.16)
        accentLayer.lineCap = .round
        gridLayer.addSublayer(accentLayer)
    }

    private func addTileLayer(in rect: CGRect, alpha: CGFloat) {
        let cellLayer = CAShapeLayer()
        cellLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath
        cellLayer.fillColor = UIColor(red: 1.00, green: 0.78, blue: 0.02, alpha: alpha).cgColor
        cellLayer.strokeColor = UIColor(red: 1.00, green: 0.96, blue: 0.52, alpha: 0.58).cgColor
        cellLayer.lineWidth = 1.3
        cellLayer.shadowColor = UIColor(red: 1.00, green: 0.61, blue: 0.00, alpha: 1.0).cgColor
        cellLayer.shadowOpacity = phase == .setup ? 0.34 : 0.22
        cellLayer.shadowRadius = phase == .setup ? 9 : 6
        cellLayer.shadowOffset = .zero
        gridLayer.addSublayer(cellLayer)

        let topShine = CAShapeLayer()
        topShine.path = UIBezierPath(
            roundedRect: CGRect(x: rect.minX + 4, y: rect.minY + 4, width: max(rect.width - 8, 1), height: max(rect.height * 0.20, 2)),
            cornerRadius: 3
        ).cgPath
        topShine.fillColor = UIColor.white.withAlphaComponent(0.16).cgColor
        gridLayer.addSublayer(topShine)

        let slash = CAShapeLayer()
        let slashPath = UIBezierPath()
        slashPath.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: rect.maxY - rect.height * 0.18))
        slashPath.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.18))
        slash.path = slashPath.cgPath
        slash.strokeColor = UIColor.white.withAlphaComponent(0.13).cgColor
        slash.lineWidth = max(1.2, min(rect.width, rect.height) * 0.035)
        slash.lineCap = .round
        gridLayer.addSublayer(slash)
    }

    private func addCornerBrackets() {
        let length = min(targetBox.width, targetBox.height) * 0.16
        let inset: CGFloat = 8
        let corners = [
            (CGPoint(x: targetBox.minX + inset, y: targetBox.minY + inset), CGFloat(0)),
            (CGPoint(x: targetBox.maxX - inset, y: targetBox.minY + inset), CGFloat.pi / 2),
            (CGPoint(x: targetBox.maxX - inset, y: targetBox.maxY - inset), CGFloat.pi),
            (CGPoint(x: targetBox.minX + inset, y: targetBox.maxY - inset), -CGFloat.pi / 2)
        ]

        for (origin, rotation) in corners {
            let path = UIBezierPath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: length, y: 0))
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: length))

            let bracket = CAShapeLayer()
            bracket.path = path.cgPath
            bracket.strokeColor = UIColor(red: 1.00, green: 0.40, blue: 0.04, alpha: 0.92).cgColor
            bracket.lineWidth = 4
            bracket.lineCap = .round
            bracket.shadowColor = UIColor.orange.cgColor
            bracket.shadowOpacity = 0.40
            bracket.shadowRadius = 8
            bracket.shadowOffset = .zero
            bracket.position = origin
            bracket.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
            gridLayer.addSublayer(bracket)
        }
    }

    private func renderBreakingTile(cell: ShootingZoneCell, rect: CGRect, startedAt: Date) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let progress = CGFloat(min(max(elapsed / 0.62, 0), 1))
        let eased = progress * progress * (3 - 2 * progress)
        let shardColor = UIColor.yellow.withAlphaComponent(max(0, 0.92 - 0.92 * progress)).cgColor
        let strokeColor = UIColor.white.withAlphaComponent(max(0, 0.42 - 0.42 * progress)).cgColor
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let shardPaths = shardPolygons(in: rect)

        for (index, path) in shardPaths.enumerated() {
            let direction = shardDirection(cell: cell, index: index)
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.fillColor = shardColor
            layer.strokeColor = strokeColor
            layer.lineWidth = 0.8
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let distance = min(rect.width, rect.height) * (0.18 + CGFloat(index % 3) * 0.035)
            let translation = CGSize(width: direction.x * distance * eased, height: direction.y * distance * eased)
            let angle = direction.rotation * eased
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, translation.width, translation.height, 0)
            transform = CATransform3DRotate(transform, angle, 0, 0, 1)
            transform = CATransform3DScale(transform, 1 - 0.22 * eased, 1 - 0.22 * eased, 1)
            layer.transform = transform
            layer.opacity = Float(max(0, 1 - progress))
            gridLayer.addSublayer(layer)
        }

        let flash = CAShapeLayer()
        flash.path = UIBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 5).cgPath
        flash.fillColor = UIColor.white.withAlphaComponent(max(0, 0.30 - 0.30 * progress)).cgColor
        flash.strokeColor = UIColor.white.withAlphaComponent(max(0, 0.72 - 0.72 * progress)).cgColor
        flash.lineWidth = 2
        flash.position = CGPoint(x: center.x - rect.midX, y: center.y - rect.midY)
        gridLayer.addSublayer(flash)
    }

    private func shardPolygons(in rect: CGRect) -> [UIBezierPath] {
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.midX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        let triangles: [[CGPoint]] = [
            [points[0], points[1], points[4]],
            [points[0], points[4], points[3]],
            [points[1], points[2], points[5], points[4]],
            [points[3], points[4], points[7], points[6]],
            [points[4], points[5], points[8], points[7]],
            [points[6], points[7], points[8]]
        ]
        return triangles.map { polygon in
            let path = UIBezierPath()
            guard let first = polygon.first else {
                return path
            }
            path.move(to: first)
            for point in polygon.dropFirst() {
                path.addLine(to: point)
            }
            path.close()
            return path
        }
    }

    private func shardDirection(cell: ShootingZoneCell, index: Int) -> (x: CGFloat, y: CGFloat, rotation: CGFloat) {
        let seed = CGFloat((cell.index + 1) * (index + 2))
        let angle = seed * 1.37
        let x = cos(angle)
        let y = sin(angle)
        let rotation = (index.isMultiple(of: 2) ? 1 : -1) * (0.45 + CGFloat(index) * 0.08)
        return (x, y, rotation)
    }

    private func renderTracker() {
        guard let displayRect = trackerOverlay.displayRect else {
            trackerLayer.path = nil
            trackerRawLayer.path = nil
            trackerCenterLayer.path = nil
            trackerTextLayer.string = nil
            return
        }

        let trackingColor = trackerOverlay.isTracking
            ? UIColor.systemGreen.withAlphaComponent(0.92)
            : UIColor.systemOrange.withAlphaComponent(0.82)
        trackerLayer.strokeColor = trackingColor.cgColor
        trackerCenterLayer.strokeColor = trackingColor.cgColor
        trackerLayer.path = UIBezierPath(roundedRect: displayRect, cornerRadius: 8).cgPath

        if
            let rawDisplayRect = trackerOverlay.rawDisplayRect,
            trackerOverlay.isTracking
        {
            trackerRawLayer.path = UIBezierPath(roundedRect: rawDisplayRect, cornerRadius: 8).cgPath
        } else {
            trackerRawLayer.path = nil
        }

        let center = trackerOverlay.center ?? CGPoint(x: displayRect.midX, y: displayRect.midY)
        let crosshair = UIBezierPath()
        crosshair.move(to: CGPoint(x: center.x - 8, y: center.y))
        crosshair.addLine(to: CGPoint(x: center.x + 8, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 8))
        crosshair.addLine(to: CGPoint(x: center.x, y: center.y + 8))
        trackerCenterLayer.path = crosshair.cgPath

        let confidence = trackerOverlay.confidence.map { String(format: "%.2f", $0) } ?? "--"
        trackerTextLayer.string = trackerOverlay.isTracking
            ? "BALL \(confidence)"
            : "BALL HOLD \(trackerOverlay.misses)"
        trackerTextLayer.frame = CGRect(
            x: displayRect.midX - 48,
            y: max(displayRect.minY - 20, 0),
            width: 96,
            height: 16
        )
    }

    private func renderImpact() {
        guard let impact, let displayPoint = impact.displayPoint else {
            impactLayer.path = nil
            impactTextLayer.string = nil
            return
        }

        let isHit = impact.hitResult.isHit
        impactLayer.strokeColor = (isHit ? UIColor.yellow : UIColor.white).cgColor
        impactLayer.path = UIBezierPath(
            ovalIn: CGRect(x: displayPoint.x - 13, y: displayPoint.y - 13, width: 26, height: 26)
        ).cgPath

        impactTextLayer.string = impact.hitResult.label
        impactTextLayer.foregroundColor = (isHit ? UIColor.yellow : UIColor.white).cgColor
        impactTextLayer.frame = CGRect(
            x: displayPoint.x - 48,
            y: max(displayPoint.y - 46, 0),
            width: 96,
            height: 24
        )
    }
}

private struct CrossbarChallengeHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.ballr(size: 14, weight: .black))
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.ballr(size: 34, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .frame(minWidth: 104, minHeight: 70, alignment: .trailing)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.82), lineWidth: 2)
        )
    }
}

private struct CrossbarChallengeCompletionOverlay: View {
    let score: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.ballr(size: 42, weight: .black))
                    .foregroundStyle(Color.yellow)

                Text("CHALLENGE COMPLETE")
                    .font(.ballr(size: 26, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Final score: \(score)")
                    .font(.ballr(size: 20, weight: .black))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.62), lineWidth: 2)
            )
            .padding(.horizontal, 24)
        }
        .allowsHitTesting(false)
    }
}

private enum CrossbarChallengeSoundPlayer {
    private static var frameHitPlayer: AVAudioPlayer?

    static func playFrameHit() {
        if frameHitPlayer == nil {
            guard let url = Bundle.main.url(forResource: "hitting-the-crossbar-by-fnc-effects", withExtension: "mp3") else {
                return
            }

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)

                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                frameHitPlayer = player
            } catch {
                print("Crossbar Challenge sound failed to load: \(error.localizedDescription)")
                return
            }
        }

        frameHitPlayer?.stop()
        frameHitPlayer?.currentTime = 0
        frameHitPlayer?.play()
    }
}

private struct CrossbarChallengeLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting Crossbar Challenge...")
                .font(.ballr(size: 16, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CrossbarChallengeErrorOverlay: View {
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

private struct CrossbarChallengeFullscreenPromptOverlay: View {
    let message: String
    @State private var isPresented = false

    var body: some View {
        GeometryReader { geometry in
            let safeInsets = geometry.safeAreaInsets
            let safeTextWidth = max(geometry.size.width - safeInsets.leading - safeInsets.trailing - 96, 260)

            ZStack {
                Color.black.opacity(0.76)
                    .ignoresSafeArea()
                    .offset(y: isPresented ? 0 : geometry.size.height)

                Text(message)
                    .font(.ballr(size: min(max(geometry.size.width * 0.115, 50), 104), weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
                    .frame(width: safeTextWidth)
                    .position(
                        x: safeInsets.leading + (geometry.size.width - safeInsets.leading - safeInsets.trailing) / 2,
                        y: geometry.size.height / 2
                    )
                    .offset(y: isPresented ? 0 : geometry.size.height * 0.38)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .onAppear {
                isPresented = false
                withAnimation(.easeOut(duration: 0.42)) {
                    isPresented = true
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
