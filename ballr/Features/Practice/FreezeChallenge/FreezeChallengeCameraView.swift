import Combine
import Foundation
import SwiftUI
import UIKit

struct FreezeChallengeCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = FreezeChallengeCameraController()
    @StateObject private var coordinator = FreezeChallengeCoordinator()
    @State private var showsQuitConfirmation = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                FreezeChallengeRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                if coordinator.showsTopBar {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.vertical, 14)
                }

                if cameraController.isStarting {
                    FreezeChallengeLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    FreezeChallengeErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.phase == .readiness, cameraController.errorMessage == nil {
                    FreezeChallengeReadinessOverlay(readyStartedAt: coordinator.readyStartedAt)
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                }

                if coordinator.phase == .finished {
                    FreezeChallengeFinishedOverlay(
                        didSucceed: coordinator.didSucceed,
                        onPrimary: { coordinator.reset(in: geometry.size) },
                        onDone: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(in: geometry.size)
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
                coordinator.tearDown()
                BallrOrientationController.restoreDefaultOrientation()
            }
            .onChange(of: geometry.size) { _, newSize in
                coordinator.prepare(in: newSize)
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
        HStack {
            Button {
                showsQuitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.58), in: Circle())
            }

            Spacer()

            HStack(spacing: 10) {
                FreezeChallengeHudChip(
                    title: "STATE",
                    value: coordinator.modeText,
                    tint: coordinator.modeTint
                )
                FreezeChallengeHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 18)
    }
}

private enum FreezeChallengePhase {
    case readiness
    case countdown
    case move
    case freezeSettling
    case freezeChecking
    case finished
}

private final class FreezeChallengeCoordinator: ObservableObject {
    @Published private(set) var phase: FreezeChallengePhase = .readiness
    @Published private(set) var readyStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var timerText = "60"
    @Published private(set) var didSucceed = false

    private let requiredReadyLockSeconds: TimeInterval = 1.5
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 60.0
    private let freezeSettleDuration: TimeInterval = 0.5
    private let moveDurationRange: ClosedRange<TimeInterval> = 2.5...5.0
    private let freezeDurationRange: ClosedRange<TimeInterval> = 1.5...2.2
    private let freezeLostTrackingFrameThreshold = 5
    private let requiredViolationFrames = 4

    private var size: CGSize = .zero
    private var lastStepAt: Date?
    private var liveElapsed: TimeInterval = 0
    private var ballDisplayRect: CGRect?
    private var displayedBody: FreezeChallengeDisplayedBody?
    private var ballTracker = FreezeChallengeBallTracker()
    private var bodyTracker = FreezeChallengeBodySmoothingTracker()
    private var playPhaseEndsAt: TimeInterval?
    private var freezeSettleEndsAt: TimeInterval?
    private var freezeCheckEndsAt: TimeInterval?
    private var freezeBaselineBallRect: CGRect?
    private var freezeBaselineBody: FreezeChallengeDisplayedBody?
    private var freezeBallLostFrames = 0
    private var freezeBodyLostFrames = 0
    private var freezeViolationFrames = 0
    private weak var renderView: FreezeChallengeRenderView?

    var showsTopBar: Bool {
        switch phase {
        case .readiness, .countdown, .move, .freezeSettling, .freezeChecking:
            return true
        case .finished:
            return false
        }
    }

    var modeText: String {
        switch phase {
        case .readiness, .countdown, .move:
            return "MOVE"
        case .freezeSettling, .freezeChecking:
            return "FREEZE"
        case .finished:
            return didSucceed ? "DONE" : "OUT"
        }
    }

    var modeTint: Color {
        switch phase {
        case .freezeSettling, .freezeChecking:
            return .red
        case .finished:
            return didSucceed ? .green : .red
        default:
            return .yellow
        }
    }

    func attach(renderView: FreezeChallengeRenderView) {
        self.renderView = renderView
        renderView.update(
            ballRect: ballDisplayRect,
            body: displayedBody,
            phase: phase,
            prompt: promptText
        )
    }

    func tearDown() {
        BallrDrillSoundPlayer.stopFreezeMusic()
    }

    func reset(in size: CGSize) {
        self.size = size
        phase = .readiness
        readyStartedAt = nil
        countdownStartedAt = nil
        timerText = "60"
        didSucceed = false
        lastStepAt = nil
        liveElapsed = 0
        ballDisplayRect = nil
        displayedBody = nil
        ballTracker.reset()
        bodyTracker.reset()
        playPhaseEndsAt = nil
        freezeSettleEndsAt = nil
        freezeCheckEndsAt = nil
        freezeBaselineBallRect = nil
        freezeBaselineBody = nil
        freezeBallLostFrames = 0
        freezeBodyLostFrames = 0
        freezeViolationFrames = 0
        BallrDrillSoundPlayer.stopFreezeMusic()

        renderView?.update(
            ballRect: ballDisplayRect,
            body: displayedBody,
            phase: phase,
            prompt: promptText
        )
    }

    func prepare(in size: CGSize) {
        self.size = resolvedGameplaySize(fallback: size)
        renderView?.update(
            ballRect: ballDisplayRect,
            body: displayedBody,
            phase: phase,
            prompt: promptText
        )
    }

    func handle(frame: FreezeChallengeFrame, cameraController: FreezeChallengeCameraController) {
        let rawBallRect = displayRect(for: frame.ballOverlayState, cameraController: cameraController)
        let ballState = ballTracker.update(
            ballDisplayRect: rawBallRect,
            overlayState: frame.ballOverlayState,
            timestamp: frame.timestamp
        )
        ballDisplayRect = ballState.smoothedRect ?? rawBallRect

        let bodyState = displayedBodyState(for: frame.bodyOverlayState, cameraController: cameraController, timestamp: frame.timestamp)
        displayedBody = bodyState

        updateStartGate(
            isReady: ballState.isStable && isBodyReady(frame.bodyOverlayState),
            timestamp: frame.timestamp
        )

        guard phase != .readiness, phase != .countdown else {
            renderView?.update(
                ballRect: ballDisplayRect,
                body: displayedBody,
                phase: phase,
                prompt: promptText
            )
            return
        }

        let previousStepAt = lastStepAt ?? frame.timestamp
        let deltaTime = min(max(frame.timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
        lastStepAt = frame.timestamp
        liveElapsed = min(liveElapsed + deltaTime, roundDuration)
        timerText = String(Int(ceil(max(roundDuration - liveElapsed, 0))))

        if liveElapsed >= roundDuration {
            finish(success: true)
        } else {
            stepLiveState(ballState: ballState, bodyState: bodyState)
        }

        renderView?.update(
            ballRect: ballDisplayRect,
            body: displayedBody,
            phase: phase,
            prompt: promptText
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
        cameraController: FreezeChallengeCameraController
    ) -> CGRect? {
        guard let normalizedRect = overlayState.normalizedRect else {
            return nil
        }
        return cameraController.displayRect(for: normalizedRect)
    }

    private func displayedBodyState(
        for overlayState: FreezeChallengeBodyOverlayState?,
        cameraController: FreezeChallengeCameraController,
        timestamp: Date
    ) -> FreezeChallengeDisplayedBody? {
        guard let overlayState else {
            return bodyTracker.update(body: nil, timestamp: timestamp)
        }

        guard let envelopeRect = cameraController.displayRect(for: overlayState.normalizedEnvelopeRect) else {
            return bodyTracker.update(body: nil, timestamp: timestamp)
        }

        let anchors: [FreezeBodyAnchor: CGPoint] = Dictionary(uniqueKeysWithValues: overlayState.anchors.compactMap { anchorState in
            guard let point = cameraController.displayPoint(for: anchorState.normalizedPoint) else {
                return nil
            }
            return (anchorState.anchor, point)
        })

        let body = FreezeChallengeDisplayedBody(
            envelopeRect: envelopeRect,
            center: CGPoint(x: envelopeRect.midX, y: envelopeRect.midY),
            span: max(envelopeRect.width, envelopeRect.height),
            anchors: anchors,
            lowerBodyCount: overlayState.lowerBodyCount,
            upperBodyCount: overlayState.upperBodyCount
        )
        return bodyTracker.update(body: body, timestamp: timestamp)
    }

    private func isBodyReady(_ overlayState: FreezeChallengeBodyOverlayState?) -> Bool {
        guard let overlayState else {
            return false
        }
        return overlayState.lowerBodyCount >= 2 && overlayState.upperBodyCount >= 1
    }

    private func updateStartGate(isReady: Bool, timestamp: Date) {
        if phase == .finished || phase == .move || phase == .freezeSettling || phase == .freezeChecking {
            return
        }

        if phase == .countdown {
            if
                let countdownStartedAt,
                timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration
            {
                lastStepAt = timestamp
                liveElapsed = 0
                timerText = "60"
                enterMovePhase(startingAt: 0, restartMusic: true)
            }
            return
        }

        guard isReady else {
            readyStartedAt = nil
            return
        }

        let startedAt = readyStartedAt ?? timestamp
        readyStartedAt = startedAt
        if timestamp.timeIntervalSince(startedAt) >= requiredReadyLockSeconds {
            countdownStartedAt = timestamp
            phase = .countdown
        }
    }

    private func stepLiveState(
        ballState: FreezeChallengeBallState,
        bodyState: FreezeChallengeDisplayedBody?
    ) {
        switch phase {
        case .move:
            if liveElapsed >= (playPhaseEndsAt ?? roundDuration) {
                phase = .freezeSettling
                freezeSettleEndsAt = min(liveElapsed + freezeSettleDuration, roundDuration)
                freezeCheckEndsAt = min((freezeSettleEndsAt ?? liveElapsed) + randomFreezeDuration(), roundDuration)
                freezeBaselineBallRect = nil
                freezeBaselineBody = nil
                freezeBallLostFrames = 0
                freezeBodyLostFrames = 0
                freezeViolationFrames = 0
                BallrDrillSoundPlayer.pauseFreezeMusic()
            }
        case .freezeSettling:
            if liveElapsed >= (freezeSettleEndsAt ?? liveElapsed) {
                phase = .freezeChecking
                freezeBaselineBallRect = ballState.smoothedRect ?? ballDisplayRect
                freezeBaselineBody = bodyState
                freezeBallLostFrames = ballState.isTracked ? 0 : 1
                freezeBodyLostFrames = bodyState == nil ? 1 : 0
                freezeViolationFrames = 0
            }
        case .freezeChecking:
            evaluateFreeze(ballState: ballState, bodyState: bodyState)
            if phase == .freezeChecking, liveElapsed >= (freezeCheckEndsAt ?? liveElapsed) {
                enterMovePhase(startingAt: liveElapsed, restartMusic: false)
            }
        case .finished, .readiness, .countdown:
            break
        }
    }

    private func evaluateFreeze(
        ballState: FreezeChallengeBallState,
        bodyState: FreezeChallengeDisplayedBody?
    ) {
        if !ballState.isTracked {
            freezeBallLostFrames += 1
        } else {
            freezeBallLostFrames = 0
        }

        if bodyState == nil {
            freezeBodyLostFrames += 1
        } else {
            freezeBodyLostFrames = 0
        }

        if freezeBallLostFrames > freezeLostTrackingFrameThreshold || freezeBodyLostFrames > freezeLostTrackingFrameThreshold {
            finish(success: false)
            return
        }

        let ballMoved = ballDidMove(
            baseline: freezeBaselineBallRect,
            current: ballState.smoothedRect ?? ballDisplayRect
        )
        let bodyMoved = bodyDidMove(
            baseline: freezeBaselineBody,
            current: bodyState
        )

        if ballMoved || bodyMoved {
            freezeViolationFrames += 1
        } else {
            freezeViolationFrames = 0
        }

        if freezeViolationFrames >= requiredViolationFrames {
            finish(success: false)
        }
    }

    private func enterMovePhase(startingAt elapsed: TimeInterval, restartMusic: Bool) {
        phase = .move
        playPhaseEndsAt = min(elapsed + randomMoveDuration(), roundDuration)
        freezeSettleEndsAt = nil
        freezeCheckEndsAt = nil
        freezeBaselineBallRect = nil
        freezeBaselineBody = nil
        freezeBallLostFrames = 0
        freezeBodyLostFrames = 0
        freezeViolationFrames = 0

        if restartMusic {
            BallrDrillSoundPlayer.startFreezeMusicLoop()
        } else {
            BallrDrillSoundPlayer.resumeFreezeMusic()
        }
    }

    private func finish(success: Bool) {
        guard phase != .finished else {
            return
        }

        phase = .finished
        didSucceed = success
        BallrDrillSoundPlayer.stopFreezeMusic()
        if success {
            BallrDrillSoundPlayer.playWinner()
        }
    }

    private func ballDidMove(baseline: CGRect?, current: CGRect?) -> Bool {
        guard let baseline, let current else {
            return false
        }

        let baselineDiameter = max(baseline.width, baseline.height)
        let currentDiameter = max(current.width, current.height)
        let centerDistance = hypot(current.midX - baseline.midX, current.midY - baseline.midY)
        let diameterChangeRatio = abs(currentDiameter - baselineDiameter) / max(baselineDiameter, 1)

        return centerDistance > max(baselineDiameter * 0.28, 18) || diameterChangeRatio > 0.16
    }

    private func bodyDidMove(
        baseline: FreezeChallengeDisplayedBody?,
        current: FreezeChallengeDisplayedBody?
    ) -> Bool {
        guard let baseline, let current else {
            return false
        }

        let centerDistance = hypot(current.center.x - baseline.center.x, current.center.y - baseline.center.y)
        if centerDistance > max(baseline.span * 0.09, 18) {
            return true
        }

        let anchorThreshold = max(baseline.span * 0.10, 20)
        for anchor in FreezeBodyAnchor.allCases {
            guard let baselinePoint = baseline.anchors[anchor], let currentPoint = current.anchors[anchor] else {
                continue
            }
            let distance = hypot(currentPoint.x - baselinePoint.x, currentPoint.y - baselinePoint.y)
            if distance > anchorThreshold {
                return true
            }
        }

        return false
    }

    private func randomMoveDuration() -> TimeInterval {
        Double.random(in: moveDurationRange)
    }

    private func randomFreezeDuration() -> TimeInterval {
        Double.random(in: freezeDurationRange)
    }

    private var promptText: String? {
        switch phase {
        case .readiness, .countdown, .finished:
            return nil
        case .move:
            return nil
        case .freezeSettling:
            return "FREEZE"
        case .freezeChecking:
            return "DON'T MOVE"
        }
    }
}

private struct FreezeChallengeRenderSurface: UIViewRepresentable {
    let coordinator: FreezeChallengeCoordinator

    func makeUIView(context: Context) -> FreezeChallengeRenderView {
        let view = FreezeChallengeRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: FreezeChallengeRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class FreezeChallengeRenderView: UIView {
    private var ballRect: CGRect?
    private var body: FreezeChallengeDisplayedBody?
    private var phase: FreezeChallengePhase = .readiness
    private let promptLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear

        promptLabel.font = .systemFont(ofSize: 28, weight: .black)
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.numberOfLines = 2
        addSubview(promptLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        promptLabel.frame = CGRect(x: 24, y: bounds.height * 0.16, width: bounds.width - 48, height: 72)
    }

    func update(
        ballRect: CGRect?,
        body: FreezeChallengeDisplayedBody?,
        phase: FreezeChallengePhase,
        prompt: String?
    ) {
        self.ballRect = ballRect
        self.body = body
        self.phase = phase
        promptLabel.text = prompt
        promptLabel.isHidden = prompt == nil
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        if let ballRect {
            drawBall(ballRect, in: context)
        }

        if let body {
            drawBody(body, in: context)
        }
    }

    private func drawBall(_ rect: CGRect, in context: CGContext) {
        let strokeColor: UIColor = isFreezePhase ? .systemRed : .systemYellow
        let ballPath = UIBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2))
        context.saveGState()
        strokeColor.withAlphaComponent(0.95).setStroke()
        context.setLineWidth(4)
        context.addPath(ballPath.cgPath)
        context.strokePath()
        context.restoreGState()
    }

    private func drawBody(_ body: FreezeChallengeDisplayedBody, in context: CGContext) {
        let strokeColor: UIColor = isFreezePhase ? .systemRed : UIColor(red: 0.21, green: 0.85, blue: 0.95, alpha: 1)
        let fillColor = strokeColor.withAlphaComponent(isFreezePhase ? 0.10 : 0.08)
        let envelope = UIBezierPath(roundedRect: body.envelopeRect, cornerRadius: 18)

        context.saveGState()
        fillColor.setFill()
        strokeColor.withAlphaComponent(0.94).setStroke()
        context.setLineWidth(3)
        context.addPath(envelope.cgPath)
        context.drawPath(using: .fillStroke)

        for point in body.anchors.values {
            let dotRect = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
            context.setFillColor(strokeColor.cgColor)
            context.fillEllipse(in: dotRect)
        }
        context.restoreGState()
    }

    private var isFreezePhase: Bool {
        switch phase {
        case .freezeSettling, .freezeChecking:
            return true
        default:
            return false
        }
    }
}

private struct FreezeChallengeDisplayedBody {
    let envelopeRect: CGRect
    let center: CGPoint
    let span: CGFloat
    let anchors: [FreezeBodyAnchor: CGPoint]
    let lowerBodyCount: Int
    let upperBodyCount: Int
}

private struct FreezeChallengeBallState {
    let smoothedRect: CGRect?
    let isTracked: Bool
    let isStable: Bool
}

private struct FreezeChallengeBallTracker {
    private struct Sample {
        let rect: CGRect
        let timestamp: Date
    }

    private var samples: [Sample] = []

    mutating func reset() {
        samples.removeAll()
    }

    mutating func update(
        ballDisplayRect: CGRect?,
        overlayState: BallTrackerOverlayState,
        timestamp: Date
    ) -> FreezeChallengeBallState {
        let isTracked = overlayState.isTracking && overlayState.confirmedFrames >= 4 && ballDisplayRect != nil
        guard isTracked, let ballDisplayRect else {
            samples.removeAll()
            return FreezeChallengeBallState(smoothedRect: ballDisplayRect, isTracked: false, isStable: false)
        }

        samples.append(Sample(rect: ballDisplayRect, timestamp: timestamp))
        samples.removeAll { timestamp.timeIntervalSince($0.timestamp) > 0.35 }
        if samples.count > 10 {
            samples.removeFirst(samples.count - 10)
        }

        let smoothedRect = averagedRect() ?? ballDisplayRect
        let diameters = samples.map { max($0.rect.width, $0.rect.height) }
        let centerXs = samples.map(\.rect.midX)
        let centerYs = samples.map(\.rect.midY)
        let meanDiameter = diameters.reduce(0, +) / CGFloat(max(diameters.count, 1))
        let xRange = (centerXs.max() ?? 0) - (centerXs.min() ?? 0)
        let yRange = (centerYs.max() ?? 0) - (centerYs.min() ?? 0)
        let diameterRange = (diameters.max() ?? 0) - (diameters.min() ?? 0)

        let isStable =
            samples.count >= 6
            && xRange <= max(meanDiameter * 0.20, 18)
            && yRange <= max(meanDiameter * 0.16, 12)
            && diameterRange <= max(meanDiameter * 0.14, 8)

        return FreezeChallengeBallState(smoothedRect: smoothedRect, isTracked: true, isStable: isStable)
    }

    private func averagedRect() -> CGRect? {
        guard !samples.isEmpty else {
            return nil
        }

        let total = samples.reduce((x: CGFloat.zero, y: CGFloat.zero, width: CGFloat.zero, height: CGFloat.zero)) {
            partial, sample in
            (
                x: partial.x + sample.rect.origin.x,
                y: partial.y + sample.rect.origin.y,
                width: partial.width + sample.rect.width,
                height: partial.height + sample.rect.height
            )
        }
        let count = CGFloat(samples.count)
        return CGRect(
            x: total.x / count,
            y: total.y / count,
            width: total.width / count,
            height: total.height / count
        )
    }
}

private struct FreezeChallengeBodySmoothingTracker {
    private struct Sample {
        let body: FreezeChallengeDisplayedBody
        let timestamp: Date
    }

    private var samples: [Sample] = []

    mutating func reset() {
        samples.removeAll()
    }

    mutating func update(
        body: FreezeChallengeDisplayedBody?,
        timestamp: Date
    ) -> FreezeChallengeDisplayedBody? {
        guard let body else {
            samples.removeAll()
            return nil
        }

        samples.append(Sample(body: body, timestamp: timestamp))
        samples.removeAll { timestamp.timeIntervalSince($0.timestamp) > 0.18 }
        if samples.count > 3 {
            samples.removeFirst(samples.count - 3)
        }

        return averagedBody()
    }

    private func averagedBody() -> FreezeChallengeDisplayedBody? {
        guard !samples.isEmpty else {
            return nil
        }

        let count = CGFloat(samples.count)
        let totalRect = samples.reduce((x: CGFloat.zero, y: CGFloat.zero, width: CGFloat.zero, height: CGFloat.zero)) {
            partial, sample in
            (
                x: partial.x + sample.body.envelopeRect.origin.x,
                y: partial.y + sample.body.envelopeRect.origin.y,
                width: partial.width + sample.body.envelopeRect.width,
                height: partial.height + sample.body.envelopeRect.height
            )
        }

        var averagedAnchors: [FreezeBodyAnchor: CGPoint] = [:]
        for anchor in FreezeBodyAnchor.allCases {
            let anchorPoints = samples.compactMap { $0.body.anchors[anchor] }
            guard !anchorPoints.isEmpty else {
                continue
            }
            let totalX = anchorPoints.reduce(CGFloat.zero) { $0 + $1.x }
            let totalY = anchorPoints.reduce(CGFloat.zero) { $0 + $1.y }
            let anchorCount = CGFloat(anchorPoints.count)
            averagedAnchors[anchor] = CGPoint(x: totalX / anchorCount, y: totalY / anchorCount)
        }

        let averagedRect = CGRect(
            x: totalRect.x / count,
            y: totalRect.y / count,
            width: totalRect.width / count,
            height: totalRect.height / count
        )

        let lowerBodyCount = samples.last?.body.lowerBodyCount ?? 0
        let upperBodyCount = samples.last?.body.upperBodyCount ?? 0

        return FreezeChallengeDisplayedBody(
            envelopeRect: averagedRect,
            center: CGPoint(x: averagedRect.midX, y: averagedRect.midY),
            span: max(averagedRect.width, averagedRect.height),
            anchors: averagedAnchors,
            lowerBodyCount: lowerBodyCount,
            upperBodyCount: upperBodyCount
        )
    }
}

private struct FreezeChallengeHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct FreezeChallengeLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.84)
                .ignoresSafeArea()

            ProgressView()
                .tint(.yellow)
                .scaleEffect(1.4)
        }
    }
}

private struct FreezeChallengeErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(permissionDenied ? "Camera Access Needed" : "Unable to Start")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.yellow)

                Text(message)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("DONE")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(24)
        }
    }
}

private struct FreezeChallengeReadinessOverlay: View {
    let readyStartedAt: Date?
    private let requiredLockSeconds: TimeInterval = 1.5

    var body: some View {
        TimelineView(.animation) { timeline in
            ZStack {
                Color.black.opacity(0.86)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Text(readyStartedAt == nil ? "Find The Ball And Your Body" : "Hold Still")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(Color.yellow)
                        .multilineTextAlignment(.center)

                    Text("Keep the ball in frame and make sure your feet, hips, and hands are visible.")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.80))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    if readyStartedAt != nil {
                        ZStack {
                            Circle()
                                .stroke(.white.opacity(0.18), lineWidth: 16)
                                .frame(width: 120, height: 120)

                            Circle()
                                .trim(from: 0, to: readinessProgress(at: timeline.date))
                                .stroke(Color.yellow, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 120, height: 120)

                            Text(readinessCountdownText(at: timeline.date))
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func readinessProgress(at date: Date) -> CGFloat {
        guard let readyStartedAt else {
            return 0
        }
        return CGFloat(min(max(date.timeIntervalSince(readyStartedAt) / requiredLockSeconds, 0), 1))
    }

    private func readinessCountdownText(at date: Date) -> String {
        guard let readyStartedAt else {
            return ""
        }
        let remaining = max(ceil(requiredLockSeconds - date.timeIntervalSince(readyStartedAt)), 0)
        return "\(Int(remaining))"
    }
}

private struct FreezeChallengeFinishedOverlay: View {
    let didSucceed: Bool
    let onPrimary: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(didSucceed ? "You Froze In Time" : "Game Over")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(didSucceed ? Color.yellow : .red)

                Text(didSucceed ? "You survived all 60 seconds." : "You moved during freeze.")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.80))
                    .multilineTextAlignment(.center)

                VStack(spacing: 12) {
                    Button(action: onPrimary) {
                        Text("PLAY AGAIN")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button(action: onDone) {
                        Text("DONE")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 6)
            }
            .padding(24)
        }
    }
}
