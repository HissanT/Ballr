import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct PassingConesCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBallSpec: PassingConesBallSpec?

    var body: some View {
        Group {
            if let selectedBallSpec {
                PassingConesLiveCameraView(ballSpec: selectedBallSpec)
            } else {
                PassingConesSetupView(
                    onSelect: { selectedBallSpec = $0 },
                    onCancel: { dismiss() }
                )
            }
        }
        .ballrCameraPresentationChrome()
    }
}

private struct PassingConesSetupView: View {
    let onSelect: (PassingConesBallSpec) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            PassingConesSetupBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    PassingConesIconButton(systemName: "xmark", action: onCancel)
                    Spacer()
                }

                Spacer(minLength: 10)

                Text("Passing Cones")
                    .font(.ballr(size: 36, weight: .black))
                    .foregroundStyle(.white)

                Text("Choose the ball size before calibration.")
                    .font(.ballr(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))

                VStack(spacing: 12) {
                    ForEach(PassingConesBallSpec.presets) { spec in
                        Button {
                            onSelect(spec)
                        } label: {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(Color.yellow)
                                    Circle()
                                        .stroke(Color.orange, lineWidth: 4)
                                    Text(spec.sizeName)
                                        .font(.ballr(size: 20, weight: .black))
                                        .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                                }
                                .frame(width: 58, height: 58)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(spec.label)
                                        .font(.ballr(size: 22, weight: .black))
                                        .foregroundStyle(.white)

                                    Text("\(String(format: "%.1f", spec.diameterCM)) cm diameter")
                                        .font(.ballr(size: 15, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.55))
                                }

                                Spacer()

                                Image(systemName: "play.fill")
                                    .font(.ballr(size: 20, weight: .black))
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 86)
                            .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.orange.opacity(0.8), lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 10)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }
}

private struct PassingConesSetupBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.01, green: 0.14, blue: 0.04)

            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.018) : Color.black.opacity(0.045))
                }
            }

            GeometryReader { geometry in
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    path.addRect(CGRect(x: 24, y: 0, width: width - 48, height: height - 18))
                    for index in 1..<8 {
                        let y = CGFloat(index) * height / 8
                        path.move(to: CGPoint(x: 24, y: y))
                        path.addLine(to: CGPoint(x: width - 24, y: y))
                    }
                    for index in 0..<4 {
                        let y = CGFloat(index) * height / 3
                        path.addEllipse(in: CGRect(x: width / 2 - 54, y: y + 80, width: 108, height: 108))
                    }
                }
                .stroke(Color.white.opacity(0.045), lineWidth: 3)
            }
        }
    }
}

private struct PassingConesIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.ballr(size: 18, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.65), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct PassingConesLiveCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = PassingConesCoordinator()
    @State private var showsQuitConfirmation = false

    let ballSpec: PassingConesBallSpec

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

                PassingConesRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                if !coordinator.hasEnded {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                        if coordinator.showsStatusPanel {
                            bottomStatus
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

                if cameraController.isStarting {
                    PassingConesLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    PassingConesErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                }

                if coordinator.requiresPassingSpotReturn && !coordinator.hasEnded {
                    PassingConesFullscreenPromptOverlay(message: "MOVE BACK TO THE\nPASSING SPOT")
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                        .zIndex(250)
                }

                if let result = coordinator.result {
                    PassingConesResultsOverlay(
                        result: result,
                        onReplay: { coordinator.reset(ballSpec: ballSpec, viewSize: geometry.size) },
                        onExit: { dismiss() }
                    )
                    .zIndex(300)
                }
            }
            .animation(.easeInOut(duration: 0.28), value: coordinator.requiresPassingSpotReturn)
            .ballrCameraPresentationChrome()
            .ballrAwardsXPOnSuccess(coordinator.passesMade > 0)
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(ballSpec: ballSpec, viewSize: geometry.size)
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

            HStack(spacing: 8) {
                PassingConesHudChip(title: "MADE", value: "\(coordinator.passesMade)", tint: .yellow)
                PassingConesHudChip(title: "TIME", value: coordinator.timeText, tint: .orange)
                PassingConesHudChip(title: "ATTEMPTS", value: "\(coordinator.passesTaken)", tint: .white)
                PassingConesHudChip(title: "ACCURACY", value: coordinator.accuracyText, tint: .green, width: 102)
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
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 86)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PassingConesBallSpec: Identifiable, Equatable {
    let id: String
    let label: String
    let sizeName: String
    let diameterCM: CGFloat

    var diameterM: CGFloat {
        diameterCM / 100.0
    }

    static let presets = [
        PassingConesBallSpec(id: "3", label: "Size 3", sizeName: "3", diameterCM: 19.1),
        PassingConesBallSpec(id: "4", label: "Size 4", sizeName: "4", diameterCM: 20.3),
        PassingConesBallSpec(id: "5", label: "Size 5", sizeName: "5", diameterCM: 22.0)
    ]
}

private enum PassingConesPhase {
    case reference
    case calibration
    case countdown
    case live
    case finished
}

private enum PassingConesPassPhase {
    case idle
    case outboundCandidate
    case outboundConfirmed
    case cooldown
}

private struct PassingConesDepthEstimate {
    let distanceM: CGFloat
    let pixelDiameter: CGFloat
}

private struct PassingConesDepthSample {
    let timestamp: Date
    let centerPixels: CGPoint
    let pixelDiameter: CGFloat
    let smoothedDiameter: CGFloat
    let rawDistanceM: CGFloat
    let estimatedDistanceM: CGFloat
}

private struct PassingConesWallCalibration {
    let wallDistanceM: CGFloat
    let impactPixelDiameter: CGFloat
    let groundYPixels: CGFloat
    let wallCenterXPixels: CGFloat
    let framePixelSize: CGSize
}

private struct PassingConesImpact {
    let centerPixels: CGPoint
    let displayPoint: CGPoint?
    let made: Bool
    let timestamp: Date
}

private struct PassingConesTrackerOverlay {
    let displayRect: CGRect?
    let rawDisplayRect: CGRect?
    let center: CGPoint?
    let confidence: Double?
    let isTracking: Bool
    let misses: Int
}

private struct PassingConesThrowState {
    var phase: PassingConesPassPhase = .idle
    var nearStartDepthM: CGFloat?
    var outboundFrames = 0
    var missingFrames = 0
    var furthestSample: PassingConesDepthSample?
    var eligibleSamples: [PassingConesDepthSample] = []
}

private struct PassingConesGate {
    let centerPixels: CGPoint
    let groundYPixels: CGFloat
    let innerGapPixels: CGFloat
    let coneHeightPixels: CGFloat
    let coneBaseWidthPixels: CGFloat
    let framePixelSize: CGSize
    let spawnedAt: Date
    var scoredAt: Date?

    var innerLeftPixels: CGFloat {
        centerPixels.x - innerGapPixels * 0.5
    }

    var innerRightPixels: CGFloat {
        centerPixels.x + innerGapPixels * 0.5
    }

    var scoringTopPixels: CGFloat {
        min(groundYPixels + framePixelSize.height * 0.25, framePixelSize.height)
    }
}

private struct PassingConesDisplayGate {
    let leftBaseCenter: CGPoint
    let rightBaseCenter: CGPoint
    let groundY: CGFloat
    let coneHeight: CGFloat
    let coneBaseWidth: CGFloat
    let innerLeftX: CGFloat
    let innerRightX: CGFloat
    let scoringTopY: CGFloat
    let spawnedAt: Date
    let scoredAt: Date?
}

private struct PassingConesResult {
    let passesMade: Int
    let passesTaken: Int

    var accuracyText: String {
        guard passesTaken > 0 else {
            return "0%"
        }
        return "\(Int(round(Double(passesMade) / Double(passesTaken) * 100)))%"
    }
}

private final class PassingConesCoordinator: ObservableObject {
    @Published private(set) var passesMade = 0
    @Published private(set) var passesTaken = 0
    @Published private(set) var accuracyText = "0%"
    @Published private(set) var timeText = "2:00"
    @Published private(set) var phaseTitle = "PASSING SPOT"
    @Published private(set) var statusText = "Hold the ball at your passing spot for 5 seconds"
    @Published private(set) var showsStatusPanel = true
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var requiresPassingSpotReturn = false
    @Published private(set) var hasEnded = false
    @Published private(set) var result: PassingConesResult?

    private let defaultFocalLengthPX: CGFloat = 2400.0
    private let focalReferenceWidthPX: CGFloat = 1920.0
    private let referenceHoldSeconds: TimeInterval = 5.0
    private let wallHoldSeconds: TimeInterval = 10.0
    private let countdownDuration: TimeInterval = 4.0
    private let drillDuration: TimeInterval = 120.0
    private let holdMaxMissingFrames = 15
    private let holdMaxFrameDelta: TimeInterval = 0.1
    private let smoothingAlpha: CGFloat = 0.35
    private let minValidCalibrationSamples = 12
    private let minCalibrationDiameterPX: CGFloat = 16.0
    private let minWallDistanceM: CGFloat = 1.5
    private let maxWallDistanceM: CGFloat = 14.0
    private let outboundMinimumFrames = 4
    private let impactReversalM: CGFloat = 0.04
    private let cooldownMissingFrames = 6
    private let impactDisappearFrames = 4
    private let maxLiveCenterJumpPX: CGFloat = 220
    private let maxLiveCenterJumpDiameters: CGFloat = 4.0
    private let maxLiveDiameterRatio: CGFloat = 2.35
    private let returnTravelFraction: CGFloat = 0.20
    private let returnPromptDelay: TimeInterval = 5.0
    private let minimumReturnMarginM: CGFloat = 0.20
    private let groundCenterYOffsetRatio: CGFloat = 0.60
    private let coneInnerGapCM: CGFloat = 80
    private let coneHeightCM: CGFloat = 30
    private let coneBaseWidthCM: CGFloat = 32
    private let maxGateCenterOffsetCM: CGFloat = 145
    private let maxGateMakesBeforeRespawn = 8
    private let scoredRespawnDelay: TimeInterval = 0.5

    private var phase: PassingConesPhase = .reference
    private var ballSpec: PassingConesBallSpec = PassingConesBallSpec.presets[2]
    private var viewSize: CGSize = .zero
    private var wallCalibration: PassingConesWallCalibration?
    private var currentDepth: PassingConesDepthEstimate?
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
    private var calibrationFinalSecondDiameterSamples: [CGFloat] = []
    private var calibrationCenterXSamples: [CGFloat] = []
    private var calibrationFrameSize: CGSize = .zero
    private var diameterWindow: [CGFloat] = []
    private var smoothedDiameter: CGFloat?
    private var throwState = PassingConesThrowState()
    private var gate: PassingConesGate?
    private var currentGateMadeCount = 0
    private var displayGate: PassingConesDisplayGate?
    private var pendingRespawnAt: Date?
    private var liveStartedAt: Date?
    private var returnPromptEligibleAt: Date?
    private var lastImpact: PassingConesImpact?
    private var trackerOverlay = PassingConesTrackerOverlay(
        displayRect: nil,
        rawDisplayRect: nil,
        center: nil,
        confidence: nil,
        isTracking: false,
        misses: 0
    )
    private weak var renderView: PassingConesRenderView?

    func attach(renderView: PassingConesRenderView) {
        self.renderView = renderView
        publishRender()
    }

    func reset(ballSpec: PassingConesBallSpec, viewSize: CGSize) {
        self.ballSpec = ballSpec
        self.viewSize = viewSize
        phase = .reference
        passesMade = 0
        passesTaken = 0
        accuracyText = "0%"
        timeText = "2:00"
        phaseTitle = "PASSING SPOT"
        statusText = "Hold the ball at your passing spot for 5 seconds"
        showsStatusPanel = true
        countdownStartedAt = nil
        requiresPassingSpotReturn = false
        hasEnded = false
        result = nil
        wallCalibration = nil
        currentDepth = nil
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
        calibrationFinalSecondDiameterSamples.removeAll()
        calibrationCenterXSamples.removeAll()
        calibrationFrameSize = .zero
        diameterWindow.removeAll()
        smoothedDiameter = nil
        throwState = PassingConesThrowState()
        gate = nil
        currentGateMadeCount = 0
        displayGate = nil
        pendingRespawnAt = nil
        liveStartedAt = nil
        returnPromptEligibleAt = nil
        lastImpact = nil
        trackerOverlay = PassingConesTrackerOverlay(
            displayRect: nil,
            rawDisplayRect: nil,
            center: nil,
            confidence: nil,
            isTracking: false,
            misses: 0
        )
        publishRender()
    }

    func prepare(viewSize: CGSize) {
        self.viewSize = viewSize
        publishRender()
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        guard phase != .finished else {
            return
        }

        updateTrackerOverlay(from: frame.overlayState, cameraController: cameraController)
        let focalLength = effectiveFocalLength(frameWidth: frame.framePixelSize.width)
        let sample = buildDepthSample(frame: frame, focalLength: focalLength)
        currentDepth = sample.map {
            PassingConesDepthEstimate(distanceM: $0.estimatedDistanceM, pixelDiameter: $0.smoothedDiameter)
        }
        updateHUDDepth()

        switch phase {
        case .reference:
            stepReference(sample: sample, timestamp: frame.timestamp)
        case .calibration:
            stepCalibration(sample: sample, frame: frame, timestamp: frame.timestamp)
        case .countdown:
            stepCountdown(timestamp: frame.timestamp, frame: frame, cameraController: cameraController)
        case .live:
            stepLive(sample: sample, frame: frame, cameraController: cameraController)
        case .finished:
            break
        }

        publishRender()
    }

    private func buildDepthSample(frame: BallTrackerFrame, focalLength: CGFloat) -> PassingConesDepthSample? {
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
        return PassingConesDepthSample(
            timestamp: frame.timestamp,
            centerPixels: centerPixels,
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

    private func stepReference(sample: PassingConesDepthSample?, timestamp: Date) {
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
            statusText = "Passing spot failed. Hold the ball still and try again."
            referenceStartedAt = nil
            return
        }

        zeroReferenceDepthM = zeroDepth
        phase = .calibration
        phaseTitle = "WALL DEPTH"
        statusText = "Reference locked. Place the ball next to the wall and hold it for 10 seconds"
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
        calibrationFinalSecondDiameterSamples.removeAll()
        calibrationCenterXSamples.removeAll()
    }

    private func stepCalibration(sample: PassingConesDepthSample?, frame: BallTrackerFrame, timestamp: Date) {
        guard let sample else {
            if calibrationElapsed <= 0 {
                statusText = "Keep the ball visible next to the wall"
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
        if calibrationElapsed >= wallHoldSeconds - 1.0 {
            calibrationFinalSecondDiameterSamples.append(sample.pixelDiameter)
        }
        calibrationCenterXSamples.append(sample.centerPixels.x)
        calibrationFrameSize = frame.framePixelSize

        if calibrationElapsed < wallHoldSeconds {
            statusText = "Hold the ball next to the wall: \(remainingText(wallHoldSeconds - calibrationElapsed))"
            return
        }

        guard
            calibrationDepthSamples.count >= minValidCalibrationSamples,
            let wallDistance = median(calibrationDepthSamples),
            let impactDiameter = average(calibrationFinalSecondDiameterSamples),
            let centerX = median(calibrationCenterXSamples)
        else {
            resetCalibration(message: "Wall calibration failed. Hold the ball at the wall again.")
            return
        }
        let groundY = sample.centerPixels.y - impactDiameter * groundCenterYOffsetRatio

        if wallDistance > maxWallDistanceM || impactDiameter < minCalibrationDiameterPX {
            resetCalibration(message: "Wall calibration failed. Hold the ball at the wall again.")
            return
        }

        guard wallDistance >= minWallDistanceM else {
            resetCalibration(message: "Wall calibration failed. Hold the ball at the wall again.")
            return
        }

        wallCalibration = PassingConesWallCalibration(
            wallDistanceM: wallDistance,
            impactPixelDiameter: impactDiameter,
            groundYPixels: min(max(groundY, 0), max(calibrationFrameSize.height, 1)),
            wallCenterXPixels: min(max(centerX, 0), max(calibrationFrameSize.width, 1)),
            framePixelSize: calibrationFrameSize
        )
        phase = .countdown
        phaseTitle = "GET READY"
        showsStatusPanel = true
        statusText = "Passing Cones starts in 3"
        countdownStartedAt = timestamp
        throwState = PassingConesThrowState()
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
        calibrationFinalSecondDiameterSamples.removeAll()
        calibrationCenterXSamples.removeAll()
    }

    private func resetCalibration(message: String) {
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
        calibrationFinalSecondDiameterSamples.removeAll()
        calibrationCenterXSamples.removeAll()
        countdownStartedAt = nil
        diameterWindow.removeAll()
        smoothedDiameter = nil
        statusText = message
    }

    private func stepCountdown(timestamp: Date, frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        guard let countdownStartedAt else {
            self.countdownStartedAt = timestamp
            return
        }

        let elapsed = timestamp.timeIntervalSince(countdownStartedAt)
        if elapsed >= countdownDuration {
            phase = .live
            phaseTitle = "LIVE"
            showsStatusPanel = false
            statusText = "Pass through the cones."
            self.countdownStartedAt = nil
            liveStartedAt = timestamp
            spawnGate(timestamp: timestamp, frameSize: frame.framePixelSize, cameraController: cameraController)
        }
    }

    private func stepLive(
        sample: PassingConesDepthSample?,
        frame: BallTrackerFrame,
        cameraController: BallTrackerCameraController
    ) {
        guard let wallCalibration else {
            phase = .calibration
            phaseTitle = "WALL DEPTH"
            showsStatusPanel = true
            statusText = "Passing Cones needs calibration"
            setRequiresPassingSpotReturn(false)
            returnPromptEligibleAt = nil
            return
        }

        guard let liveStartedAt else {
            self.liveStartedAt = frame.timestamp
            return
        }

        let elapsed = frame.timestamp.timeIntervalSince(liveStartedAt)
        let remaining = max(drillDuration - elapsed, 0)
        timeText = timeString(remaining)
        if remaining <= 0 {
            finish()
            return
        }

        if gate == nil {
            spawnGate(timestamp: frame.timestamp, frameSize: frame.framePixelSize, cameraController: cameraController)
        }

        if let pendingRespawnAt {
            if frame.timestamp >= pendingRespawnAt {
                self.pendingRespawnAt = nil
                spawnGate(timestamp: frame.timestamp, frameSize: frame.framePixelSize, cameraController: cameraController)
                statusText = "Ready for the next pass"
            } else {
                statusText = "New cone gate in \(remainingText(pendingRespawnAt.timeIntervalSince(frame.timestamp)))"
            }
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
                    lockWallArrival(furthestSample, frame: frame, cameraController: cameraController)
                }
            } else if throwState.phase == .cooldown {
                throwState.missingFrames += 1
                setRequiresPassingSpotReturn(shouldShowReturnPrompt(at: frame.timestamp))
                if throwState.missingFrames > cooldownMissingFrames {
                    throwState.missingFrames = cooldownMissingFrames
                    statusText = "Bring the ball back to the passing spot"
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
            returnPromptEligibleAt = nil
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
                statusText = "Pass detected. Tracking wall approach."
            } else if pendingRespawnAt == nil {
                statusText = "Pass through the cones"
            }
        case .outboundCandidate:
            appendEligibleSample(sample)
            guard let nearStart = throwState.nearStartDepthM else {
                return
            }
            if sample.rawDistanceM < nearStart + 0.05 {
                throwState = PassingConesThrowState(nearStartDepthM: sample.rawDistanceM)
                statusText = "Pass through the cones"
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
                statusText = "Wall approach confirmed"
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
                lockWallArrival(furthestSample, frame: frame, cameraController: cameraController)
                return
            }

            if
                let nearStart = throwState.nearStartDepthM,
                sample.rawDistanceM < nearStart + 0.10
            {
                throwState = PassingConesThrowState(nearStartDepthM: sample.rawDistanceM)
                statusText = "Pass through the cones"
            }
        case .cooldown:
            if isBackAtPassingSpot(sample.rawDistanceM, zeroDepth: zeroDepth, wallDistance: wallDistance) {
                throwState = PassingConesThrowState(nearStartDepthM: sample.rawDistanceM)
                lastImpact = nil
                setRequiresPassingSpotReturn(false)
                returnPromptEligibleAt = nil
                if pendingRespawnAt == nil {
                    statusText = "Ready for the next pass"
                }
            } else {
                setRequiresPassingSpotReturn(shouldShowReturnPrompt(at: frame.timestamp))
                statusText = "Bring the ball back to the passing spot"
            }
        }
    }

    private func lockWallArrival(
        _ impactSample: PassingConesDepthSample,
        frame: BallTrackerFrame,
        cameraController: BallTrackerCameraController
    ) {
        guard throwState.phase != .cooldown, pendingRespawnAt == nil else {
            return
        }
        guard var currentGate = gate else {
            return
        }

        let centerPixels = robustImpactCenter(impactTimestamp: impactSample.timestamp) ?? impactSample.centerPixels
        let displayPoint = displayPoint(forPixelPoint: centerPixels, frameSize: frame.framePixelSize, cameraController: cameraController)
        let made = isImpact(centerPixels, inside: currentGate)

        passesTaken += 1
        if made {
            passesMade += 1
            currentGateMadeCount += 1
            BallrDrillSoundPlayer.playCombo()
            if currentGateMadeCount >= maxGateMakesBeforeRespawn {
                BallrDrillSoundPlayer.playWinner()
                currentGate.scoredAt = impactSample.timestamp
                gate = currentGate
                pendingRespawnAt = impactSample.timestamp.addingTimeInterval(scoredRespawnDelay)
                statusText = "Pass made: +1. New gate next."
            } else {
                statusText = "Pass made: +1"
            }
        } else {
            BallrDrillSoundPlayer.playIncorrect()
            statusText = "Missed the cones"
        }
        updateAccuracy()
        lastImpact = PassingConesImpact(
            centerPixels: centerPixels,
            displayPoint: displayPoint,
            made: made,
            timestamp: impactSample.timestamp
        )
        throwState.phase = .cooldown
        throwState.missingFrames = 0
        returnPromptEligibleAt = impactSample.timestamp.addingTimeInterval(returnPromptDelay)
        setRequiresPassingSpotReturn(false)
        updateDisplayGate(cameraController: cameraController)
    }

    private func isImpact(_ centerPixels: CGPoint, inside gate: PassingConesGate) -> Bool {
        return centerPixels.x >= gate.innerLeftPixels
            && centerPixels.x <= gate.innerRightPixels
            && centerPixels.y >= gate.groundYPixels
            && centerPixels.y <= gate.scoringTopPixels
    }

    private func spawnGate(timestamp: Date, frameSize: CGSize, cameraController: BallTrackerCameraController) {
        guard let wallCalibration else {
            return
        }
        let focalLength = effectiveFocalLength(frameWidth: frameSize.width)
        let innerGapPixels = cmToPixels(coneInnerGapCM, wallDistanceM: wallCalibration.wallDistanceM, focalLength: focalLength)
        let coneHeightPixels = cmToPixels(coneHeightCM, wallDistanceM: wallCalibration.wallDistanceM, focalLength: focalLength)
        let coneBaseWidthPixels = cmToPixels(coneBaseWidthCM, wallDistanceM: wallCalibration.wallDistanceM, focalLength: focalLength)
        let halfGatePixels = innerGapPixels * 0.5 + coneBaseWidthPixels
        let depthProgress = min(max((wallCalibration.wallDistanceM - minWallDistanceM) / (10.0 - minWallDistanceM), 0), 1)
        let sideLimitFraction = 0.90 - depthProgress * 0.20
        let rawSafeMinX = frameSize.width * (1 - sideLimitFraction) + halfGatePixels
        let rawSafeMaxX = frameSize.width * sideLimitFraction - halfGatePixels
        let fallbackCenterX = frameSize.width * 0.5
        let safeMinX = rawSafeMinX <= rawSafeMaxX ? rawSafeMinX : fallbackCenterX
        let safeMaxX = rawSafeMinX <= rawSafeMaxX ? rawSafeMaxX : fallbackCenterX
        let maxOffsetByFrame = max(0, min(wallCalibration.wallCenterXPixels - safeMinX, safeMaxX - wallCalibration.wallCenterXPixels))
        let maxOffsetCMByFrame = pixelsToCM(maxOffsetByFrame, wallDistanceM: wallCalibration.wallDistanceM, focalLength: focalLength)
        let depthAdjustedMaxOffsetCM = maxGateCenterOffsetCM - depthProgress * 80
        let resolvedMaxOffsetCM = min(depthAdjustedMaxOffsetCM, max(0, maxOffsetCMByFrame))
        let offsetCM = resolvedMaxOffsetCM > 12 ? CGFloat.random(in: -resolvedMaxOffsetCM...resolvedMaxOffsetCM) : 0
        let offsetPixels = cmToPixels(offsetCM, wallDistanceM: wallCalibration.wallDistanceM, focalLength: focalLength)
        let centerX = min(max(wallCalibration.wallCenterXPixels + offsetPixels, safeMinX), safeMaxX)
        let groundY = min(max(wallCalibration.groundYPixels, coneHeightPixels + 6), frameSize.height - 4)

        gate = PassingConesGate(
            centerPixels: CGPoint(x: centerX, y: groundY),
            groundYPixels: groundY,
            innerGapPixels: innerGapPixels,
            coneHeightPixels: coneHeightPixels,
            coneBaseWidthPixels: coneBaseWidthPixels,
            framePixelSize: frameSize,
            spawnedAt: timestamp,
            scoredAt: nil
        )
        currentGateMadeCount = 0
        lastImpact = nil
        updateDisplayGate(cameraController: cameraController)
    }

    private func updateDisplayGate(cameraController: BallTrackerCameraController) {
        guard let gate else {
            displayGate = nil
            return
        }

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint? {
            displayPoint(forPixelPoint: CGPoint(x: x, y: y), frameSize: gate.framePixelSize, cameraController: cameraController)
        }

        let leftConeX = gate.innerLeftPixels - gate.coneBaseWidthPixels * 0.5
        let rightConeX = gate.innerRightPixels + gate.coneBaseWidthPixels * 0.5
        guard
            let leftCenter = point(leftConeX, gate.groundYPixels),
            let rightCenter = point(rightConeX, gate.groundYPixels),
            let leftBaseStart = point(leftConeX - gate.coneBaseWidthPixels * 0.5, gate.groundYPixels),
            let leftBaseEnd = point(leftConeX + gate.coneBaseWidthPixels * 0.5, gate.groundYPixels),
            let leftTop = point(leftConeX, gate.groundYPixels - gate.coneHeightPixels),
            let innerLeft = point(gate.innerLeftPixels, gate.groundYPixels),
            let innerRight = point(gate.innerRightPixels, gate.groundYPixels),
            let scoringTop = point(gate.centerPixels.x, gate.scoringTopPixels)
        else {
            displayGate = nil
            return
        }

        displayGate = PassingConesDisplayGate(
            leftBaseCenter: leftCenter,
            rightBaseCenter: rightCenter,
            groundY: (leftCenter.y + rightCenter.y) * 0.5,
            coneHeight: abs(leftCenter.y - leftTop.y),
            coneBaseWidth: max(abs(leftBaseEnd.x - leftBaseStart.x), 24),
            innerLeftX: min(innerLeft.x, innerRight.x),
            innerRightX: max(innerLeft.x, innerRight.x),
            scoringTopY: scoringTop.y,
            spawnedAt: gate.spawnedAt,
            scoredAt: gate.scoredAt
        )
    }

    private func isBackAtPassingSpot(_ distance: CGFloat, zeroDepth: CGFloat, wallDistance: CGFloat) -> Bool {
        let travel = max(wallDistance - zeroDepth, 0.5)
        let margin = max(travel * returnTravelFraction, minimumReturnMarginM)
        return distance >= zeroDepth - margin && distance <= zeroDepth + margin
    }

    private func shouldShowReturnPrompt(at timestamp: Date) -> Bool {
        guard let returnPromptEligibleAt else {
            return false
        }
        return timestamp >= returnPromptEligibleAt
    }

    private func appendEligibleSample(_ sample: PassingConesDepthSample) {
        throwState.eligibleSamples.append(sample)
        if throwState.eligibleSamples.count > 12 {
            throwState.eligibleSamples.removeFirst(throwState.eligibleSamples.count - 12)
        }
    }

    private func isLiveSampleConsistent(_ sample: PassingConesDepthSample) -> Bool {
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
        let maxJump = max(
            maxLiveCenterJumpPX,
            max(sample.pixelDiameter, previous.pixelDiameter) * maxLiveCenterJumpDiameters
        )
        guard centerJump <= maxJump else {
            return false
        }

        let smallerDiameter = max(min(sample.pixelDiameter, previous.pixelDiameter), 1)
        let diameterRatio = max(sample.pixelDiameter, previous.pixelDiameter) / smallerDiameter
        return diameterRatio <= maxLiveDiameterRatio
    }

    private func robustImpactCenter(impactTimestamp: Date) -> CGPoint? {
        var samples: [PassingConesDepthSample] = []
        for sample in throwState.eligibleSamples.reversed() where sample.timestamp <= impactTimestamp {
            samples.append(sample)
            if samples.count == 5 {
                break
            }
        }
        guard !samples.isEmpty else {
            return nil
        }

        let centerX = median(samples.map { $0.centerPixels.x })
        let centerY = median(samples.map { $0.centerPixels.y })
        guard let centerX, let centerY else {
            return nil
        }

        return CGPoint(x: centerX, y: centerY)
    }

    private func finish() {
        phase = .finished
        hasEnded = true
        countdownStartedAt = nil
        setRequiresPassingSpotReturn(false)
        returnPromptEligibleAt = nil
        result = PassingConesResult(passesMade: passesMade, passesTaken: passesTaken)
        if passesMade > 0 {
            BallrDrillSoundPlayer.playWinner()
        }
        publishRender()
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
        trackerOverlay = PassingConesTrackerOverlay(
            displayRect: displayRect,
            rawDisplayRect: rawDisplayRect,
            center: center,
            confidence: overlayState.confidence,
            isTracking: overlayState.isTracking,
            misses: overlayState.misses
        )
    }

    private func updateHUDDepth() {
        guard let currentDepth else {
            return
        }

        if let zeroReferenceDepthM {
            let relativeDepth = max(currentDepth.distanceM - zeroReferenceDepthM, 0)
            if phase == .live {
                phaseTitle = "LIVE"
            }
            // Keep depth out of the main HUD, but use it for readable status during calibration.
            if phase == .reference || phase == .calibration {
                _ = String(format: "%.1fm", relativeDepth)
            }
        }
    }

    private func updateAccuracy() {
        guard passesTaken > 0 else {
            accuracyText = "0%"
            return
        }
        accuracyText = "\(Int(round(Double(passesMade) / Double(passesTaken) * 100)))%"
    }

    private func publishRender() {
        renderView?.update(
            gate: displayGate,
            lastImpact: lastImpact,
            trackerOverlay: trackerOverlay,
            phase: phase,
            passesMade: passesMade
        )
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
        (ballSpec.diameterM * focalLength) / max(pixelDiameter, 0.000001)
    }

    private func effectiveFocalLength(frameWidth: CGFloat) -> CGFloat {
        defaultFocalLengthPX * max(frameWidth, 1) / focalReferenceWidthPX
    }

    private func cmToPixels(_ cm: CGFloat, wallDistanceM: CGFloat, focalLength: CGFloat) -> CGFloat {
        (cm / 100.0) * focalLength / max(wallDistanceM, 0.000001)
    }

    private func pixelsToCM(_ pixels: CGFloat, wallDistanceM: CGFloat, focalLength: CGFloat) -> CGFloat {
        pixels * wallDistanceM / focalLength * 100.0
    }

    private func remainingText(_ seconds: TimeInterval) -> String {
        "\(String(format: "%.1f", max(seconds, 0)))s remaining"
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(Int(ceil(seconds)), 0)
        return "\(totalSeconds / 60):\(String(format: "%02d", totalSeconds % 60))"
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

    private func average(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / CGFloat(values.count)
    }

    private func setRequiresPassingSpotReturn(_ isRequired: Bool) {
        guard requiresPassingSpotReturn != isRequired else {
            return
        }
        requiresPassingSpotReturn = isRequired
    }
}

private struct PassingConesRenderSurface: UIViewRepresentable {
    let coordinator: PassingConesCoordinator

    func makeUIView(context: Context) -> PassingConesRenderView {
        let view = PassingConesRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: PassingConesRenderView, context: Context) {
    }
}

private final class PassingConesRenderView: UIView {
    private var gate: PassingConesDisplayGate?
    private var lastImpact: PassingConesImpact?
    private var trackerOverlay = PassingConesTrackerOverlay(
        displayRect: nil,
        rawDisplayRect: nil,
        center: nil,
        confidence: nil,
        isTracking: false,
        misses: 0
    )
    private var phase: PassingConesPhase = .reference
    private var passesMade = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        gate: PassingConesDisplayGate?,
        lastImpact: PassingConesImpact?,
        trackerOverlay: PassingConesTrackerOverlay,
        phase: PassingConesPhase,
        passesMade: Int
    ) {
        self.gate = gate
        self.lastImpact = lastImpact
        self.trackerOverlay = trackerOverlay
        self.phase = phase
        self.passesMade = passesMade
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }
        renderGate(in: context)
        renderTracker(in: context)
        renderImpact(in: context)
    }

    private func renderGate(in context: CGContext) {
        guard let gate else {
            return
        }

        let now = Date()
        let spawnProgress = CGFloat(min(max(now.timeIntervalSince(gate.spawnedAt) / 0.34, 0), 1))
        let spawnOffsetY = (1 - easeOutCubic(spawnProgress)) * max(bounds.height - gate.groundY + gate.coneHeight + 80, 150)
        let scoredElapsed = gate.scoredAt.map { now.timeIntervalSince($0) }
        let scoredProgress = CGFloat(scoredElapsed.map { min(max($0 / 0.50, 0), 1) } ?? 0)
        let shakeProgress = CGFloat(scoredElapsed.map { min(max($0 / 0.18, 0), 1) } ?? 0)
        let dropProgress = CGFloat(scoredElapsed.map { min(max(($0 - 0.16) / 0.34, 0), 1) } ?? 0)
        let shakeX = scoredElapsed.map {
            CGFloat(sin($0 * 92.0)) * 11.0 * (1 - shakeProgress)
        } ?? 0
        let dropOffsetY = easeInCubic(dropProgress) * max(bounds.height - gate.groundY + gate.coneHeight + 120, 180)
        let flashAlpha = scoredElapsed == nil ? CGFloat(0) : 1 - dropProgress
        let coneOffset = CGSize(width: shakeX, height: spawnOffsetY + dropOffsetY)

        let zoneTopY = gate.scoringTopY + coneOffset.height
        let zoneBottomY = gate.groundY + coneOffset.height
        let zoneRect = CGRect(
            x: gate.innerLeftX + coneOffset.width,
            y: min(zoneTopY, zoneBottomY),
            width: gate.innerRightX - gate.innerLeftX,
            height: abs(zoneBottomY - zoneTopY)
        )
        let zonePath = UIBezierPath(roundedRect: zoneRect, cornerRadius: 6)
        UIColor.systemGreen.withAlphaComponent(0.12).setFill()
        zonePath.fill()
        UIColor.systemGreen.withAlphaComponent(0.50).setStroke()
        zonePath.lineWidth = 3
        zonePath.stroke()

        drawCone(
            in: context,
            baseCenter: CGPoint(
                x: gate.leftBaseCenter.x + coneOffset.width,
                y: gate.leftBaseCenter.y + coneOffset.height
            ),
            baseWidth: gate.coneBaseWidth,
            height: gate.coneHeight,
            rotation: -0.40 * scoredProgress + 0.10 * shakeProgress * CGFloat(sin(now.timeIntervalSinceReferenceDate * 90.0)),
            flashAlpha: flashAlpha
        )
        drawCone(
            in: context,
            baseCenter: CGPoint(
                x: gate.rightBaseCenter.x + coneOffset.width,
                y: gate.rightBaseCenter.y + coneOffset.height
            ),
            baseWidth: gate.coneBaseWidth,
            height: gate.coneHeight,
            rotation: 0.40 * scoredProgress - 0.10 * shakeProgress * CGFloat(sin(now.timeIntervalSinceReferenceDate * 90.0)),
            flashAlpha: flashAlpha
        )
    }

    private func drawCone(
        in context: CGContext,
        baseCenter: CGPoint,
        baseWidth: CGFloat,
        height: CGFloat,
        rotation: CGFloat,
        flashAlpha: CGFloat
    ) {
        let width = max(baseWidth, 26)
        let coneHeight = max(height, 42)
        let baseHeight = max(width * 0.18, 8)
        let bodyBottomY = baseCenter.y - baseHeight * 0.40
        let topY = bodyBottomY - coneHeight
        let topWidth = width * 0.22
        let bottomWidth = width * 0.72

        context.saveGState()
        context.translateBy(x: baseCenter.x, y: baseCenter.y)
        context.rotate(by: rotation)
        context.translateBy(x: -baseCenter.x, y: -baseCenter.y)

        let plateRect = CGRect(
            x: baseCenter.x - width * 0.58,
            y: baseCenter.y - baseHeight * 0.58,
            width: width * 1.16,
            height: baseHeight
        )
        let plate = UIBezierPath(roundedRect: plateRect, cornerRadius: min(8, baseHeight * 0.35))
        UIColor(red: 1.0, green: 0.28, blue: 0.0, alpha: 0.94).setFill()
        plate.fill()

        let body = UIBezierPath()
        body.move(to: CGPoint(x: baseCenter.x - topWidth * 0.5, y: topY))
        body.addLine(to: CGPoint(x: baseCenter.x + topWidth * 0.5, y: topY))
        body.addLine(to: CGPoint(x: baseCenter.x + bottomWidth * 0.5, y: bodyBottomY))
        body.addLine(to: CGPoint(x: baseCenter.x - bottomWidth * 0.5, y: bodyBottomY))
        body.close()
        UIColor(red: 1.0, green: 0.30, blue: 0.0, alpha: 0.98).setFill()
        body.fill()

        context.saveGState()
        body.addClip()
        drawStripe(centerX: baseCenter.x, y: topY + coneHeight * 0.40, width: bottomWidth * 0.80, height: coneHeight * 0.14)
        drawStripe(centerX: baseCenter.x, y: topY + coneHeight * 0.68, width: bottomWidth * 0.92, height: coneHeight * 0.15)
        context.restoreGState()

        let topOval = UIBezierPath(ovalIn: CGRect(
            x: baseCenter.x - topWidth * 0.5,
            y: topY - topWidth * 0.18,
            width: topWidth,
            height: topWidth * 0.36
        ))
        UIColor(red: 0.45, green: 0.12, blue: 0.02, alpha: 0.70).setFill()
        topOval.fill()

        if flashAlpha > 0 {
            UIColor.white.withAlphaComponent(0.30 * flashAlpha).setStroke()
            body.lineWidth = 5
            body.stroke()
        }

        context.restoreGState()
    }

    private func easeOutCubic(_ value: CGFloat) -> CGFloat {
        1 - pow(1 - value, 3)
    }

    private func easeInCubic(_ value: CGFloat) -> CGFloat {
        value * value * value
    }

    private func drawStripe(centerX: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let stripe = UIBezierPath(roundedRect: CGRect(
            x: centerX - width * 0.5,
            y: y - height * 0.5,
            width: width,
            height: height
        ), cornerRadius: height * 0.45)
        UIColor.white.withAlphaComponent(0.92).setFill()
        stripe.fill()
    }

    private func renderTracker(in context: CGContext) {
        guard let displayRect = trackerOverlay.displayRect else {
            return
        }
        context.saveGState()
        let trackingColor = trackerOverlay.isTracking
            ? UIColor.systemGreen.withAlphaComponent(0.92)
            : UIColor.systemOrange.withAlphaComponent(0.82)
        trackingColor.setStroke()
        UIBezierPath(roundedRect: displayRect, cornerRadius: 8).stroke(with: .normal, alpha: 1.0)

        if
            let rawDisplayRect = trackerOverlay.rawDisplayRect,
            trackerOverlay.isTracking
        {
            UIColor.white.withAlphaComponent(0.34).setStroke()
            let rawPath = UIBezierPath(roundedRect: rawDisplayRect, cornerRadius: 8)
            rawPath.setLineDash([5, 4], count: 2, phase: 0)
            rawPath.lineWidth = 1.5
            rawPath.stroke()
        }

        let center = trackerOverlay.center ?? CGPoint(x: displayRect.midX, y: displayRect.midY)
        let crosshair = UIBezierPath()
        crosshair.move(to: CGPoint(x: center.x - 8, y: center.y))
        crosshair.addLine(to: CGPoint(x: center.x + 8, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 8))
        crosshair.addLine(to: CGPoint(x: center.x, y: center.y + 8))
        crosshair.lineWidth = 2
        trackingColor.setStroke()
        crosshair.stroke()
        context.restoreGState()
    }

    private func renderImpact(in context: CGContext) {
        guard let impact = lastImpact, let displayPoint = impact.displayPoint else {
            return
        }

        context.saveGState()
        let color = impact.made ? UIColor.systemGreen : UIColor.systemRed
        color.withAlphaComponent(0.92).setStroke()
        let ring = UIBezierPath(ovalIn: CGRect(x: displayPoint.x - 15, y: displayPoint.y - 15, width: 30, height: 30))
        ring.lineWidth = 4
        ring.stroke()

        let text = impact.made ? "+1" : "0"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: BallrFont.uiFont(size: 30, weight: .black),
            .foregroundColor: impact.made ? UIColor.yellow : UIColor.white
        ]
        let rect = CGRect(x: displayPoint.x - 42, y: displayPoint.y - 58, width: 84, height: 38)
        text.draw(in: rect, withAttributes: attributes)
        context.restoreGState()
    }
}

private struct PassingConesHudChip: View {
    let title: String
    let value: String
    let tint: Color
    var width: CGFloat = 86

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.ballr(size: 12, weight: .black))
                .tracking(1)
                .foregroundStyle(tint.opacity(0.90))
            Text(value)
                .font(.ballr(size: 22, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: width, height: 56)
        .background(.black.opacity(0.60), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.54), lineWidth: 1.4)
        )
    }
}

private struct PassingConesFullscreenPromptOverlay: View {
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

private struct PassingConesResultsOverlay: View {
    let result: PassingConesResult
    let onReplay: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.70)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Passing Complete")
                    .font(.ballr(size: 34, weight: .black))
                    .foregroundStyle(Color.yellow)

                HStack(spacing: 12) {
                    resultStat(value: "\(result.passesMade)", label: "MADE")
                    resultStat(value: "\(result.passesTaken)", label: "TAKEN")
                    resultStat(value: result.accuracyText, label: "ACCURACY")
                }

                HStack(spacing: 12) {
                    Button(action: onExit) {
                        Text("EXIT")
                            .font(.ballr(size: 18, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 150, height: 60)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: onReplay) {
                        Text("RETRY")
                            .font(.ballr(size: 18, weight: .black))
                            .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.05))
                            .frame(width: 150, height: 60)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.8), lineWidth: 2)
            )
            .padding(.horizontal, 34)
        }
    }

    private func resultStat(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.ballr(size: 32, weight: .black))
                .foregroundStyle(Color.yellow)
            Text(label)
                .font(.ballr(size: 13, weight: .black))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(width: 112, height: 92)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.72), lineWidth: 1.5)
        )
    }
}

private struct PassingConesLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text("Starting Passing Cones...")
                .font(.ballr(size: 16, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 70)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PassingConesErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
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
                    .buttonStyle(.plain)

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
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.40), lineWidth: 1.4)
            )
        }
    }
}
