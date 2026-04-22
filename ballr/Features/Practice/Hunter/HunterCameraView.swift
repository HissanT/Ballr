import Combine
import Foundation
import SwiftUI
import UIKit

struct HunterCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = HunterCoordinator()
    @State private var showsQuitConfirmation = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                HunterRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                }
                .padding(.vertical, 14)

                if cameraController.isStarting {
                    HunterLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    HunterErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                } else if coordinator.phase == .readiness && cameraController.errorMessage == nil {
                    BallrDrillReadinessOverlay(ballFoundStartedAt: coordinator.ballFoundStartedAt)
                }

                if coordinator.phase == .gameOver {
                    HunterFinishedOverlay(
                        title: "CAUGHT",
                        subtitle: "The hunter touched the ball.",
                        timeText: coordinator.survivedTimeText,
                        primaryTitle: "PLAY AGAIN",
                        onPrimary: { coordinator.reset(in: geometry.size) },
                        onDone: { dismiss() }
                    )
                }

                if coordinator.phase == .won {
                    HunterFinishedOverlay(
                        title: "ESCAPED",
                        subtitle: "Clean run.",
                        timeText: "60s",
                        primaryTitle: "PLAY AGAIN",
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

            HunterHudChip(title: "TIME", value: coordinator.timerText, tint: .red)
                .padding(.top, 8)
        }
    }
}

private enum HunterPhase {
    case readiness
    case countdown
    case live
    case gameOver
    case won
}

private final class HunterCoordinator: ObservableObject {
    @Published private(set) var phase: HunterPhase = .readiness
    @Published private(set) var ballFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var timerText = "60"
    @Published private(set) var survivedTimeText = "0s"

    private let requiredBallLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 60.0
    private let lostBallPromptFrameThreshold = 18

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var lostBallFrameCount = 0
    private var heldBallDisplayRect: CGRect?
    private var isTracking = false
    private var gameState = HunterGameState()
    private weak var renderView: HunterRenderView?

    func attach(renderView: HunterRenderView) {
        self.renderView = renderView
        renderView.update(
            hunter: gameState.hunter,
            ballDisplayRect: nil,
            isTracking: false,
            prompt: promptText
        )
    }

    func reset(in size: CGSize) {
        self.size = size
        phase = .readiness
        ballFoundStartedAt = nil
        countdownStartedAt = nil
        timerText = "60"
        survivedTimeText = "0s"
        liveElapsed = 0
        lastStepAt = nil
        lostBallFrameCount = 0
        heldBallDisplayRect = nil
        isTracking = false
        gameState.reset()
        renderView?.update(
            hunter: gameState.hunter,
            ballDisplayRect: nil,
            isTracking: false,
            prompt: promptText
        )
    }

    func prepare(in size: CGSize) {
        self.size = size
        renderView?.update(
            hunter: gameState.hunter,
            ballDisplayRect: heldBallDisplayRect,
            isTracking: isTracking,
            prompt: promptText
        )
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        let overlayState = frame.overlayState
        let detectedBallDisplayRect = displayRect(for: overlayState, cameraController: cameraController)
        let effectiveBallDisplayRect = resolvedBallDisplayRect(
            detectedBallDisplayRect,
            rawIsTracking: overlayState.isTracking
        )
        let effectiveIsTracking = effectiveBallDisplayRect != nil
        isTracking = effectiveIsTracking

        guard phase != .gameOver, phase != .won else {
            renderView?.update(
                hunter: gameState.hunter,
                ballDisplayRect: effectiveBallDisplayRect,
                isTracking: effectiveIsTracking,
                prompt: promptText
            )
            return
        }

        updateStartGate(isTracking: effectiveIsTracking, timestamp: frame.timestamp)

        if phase == .live {
            stepLiveGame(
                ballDisplayRect: effectiveBallDisplayRect,
                isTracking: effectiveIsTracking,
                timestamp: frame.timestamp
            )
        }

        renderView?.update(
            hunter: gameState.hunter,
            ballDisplayRect: effectiveBallDisplayRect,
            isTracking: effectiveIsTracking,
            prompt: promptText
        )
    }

    private func resolvedBallDisplayRect(
        _ detectedBallDisplayRect: CGRect?,
        rawIsTracking: Bool
    ) -> CGRect? {
        if rawIsTracking, let detectedBallDisplayRect {
            heldBallDisplayRect = detectedBallDisplayRect
            lostBallFrameCount = 0
            return detectedBallDisplayRect
        }

        guard phase == .live, let heldBallDisplayRect else {
            lostBallFrameCount = 0
            return nil
        }

        lostBallFrameCount += 1
        if lostBallFrameCount < lostBallPromptFrameThreshold {
            return heldBallDisplayRect
        }

        return nil
    }

    private func displayRect(
        for overlayState: BallTrackerOverlayState,
        cameraController: BallTrackerCameraController
    ) -> CGRect? {
        guard let normalizedRect = overlayState.normalizedRect else {
            return nil
        }
        return cameraController.displayRect(for: normalizedRect)
    }

    private func updateStartGate(isTracking: Bool, timestamp: Date) {
        if phase == .live {
            return
        }

        if phase == .countdown {
            if
                let countdownStartedAt,
                timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration
            {
                phase = .live
                lastStepAt = nil
            }
            return
        }

        guard phase == .readiness else {
            return
        }

        guard isTracking else {
            ballFoundStartedAt = nil
            return
        }

        let startedAt = ballFoundStartedAt ?? timestamp
        ballFoundStartedAt = startedAt
        if timestamp.timeIntervalSince(startedAt) >= requiredBallLockSeconds {
            countdownStartedAt = timestamp
            phase = .countdown
        }
    }

    private func stepLiveGame(
        ballDisplayRect: CGRect?,
        isTracking: Bool,
        timestamp: Date
    ) {
        guard isTracking, let ballDisplayRect else {
            lastStepAt = nil
            return
        }

        let previousStepAt = lastStepAt ?? timestamp
        lastStepAt = timestamp
        let delta = min(max(timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
        liveElapsed = min(roundDuration, liveElapsed + delta)
        timerText = "\(max(Int(ceil(roundDuration - liveElapsed)), 0))"
        survivedTimeText = "\(Int(floor(liveElapsed)))s"

        let event = gameState.step(
            ballDisplayRect: ballDisplayRect,
            in: size,
            elapsed: liveElapsed,
            delta: delta
        )

        switch event {
        case .caught:
            phase = .gameOver
        case .none:
            if liveElapsed >= roundDuration {
                BallrDrillSoundPlayer.playWinner()
                phase = .won
                timerText = "0"
                survivedTimeText = "60s"
            }
        }
    }

    private var promptText: String? {
        switch phase {
        case .readiness, .countdown:
            return nil
        case .live:
            return isTracking ? nil : "Find the ball"
        case .gameOver:
            return "Game over"
        case .won:
            return "Escaped"
        }
    }
}

private struct HunterRenderSurface: UIViewRepresentable {
    let coordinator: HunterCoordinator

    func makeUIView(context: Context) -> HunterRenderView {
        let view = HunterRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: HunterRenderView, context: Context) {
    }
}

private final class HunterRenderView: UIView {
    private let hunterGlowLayer = CAShapeLayer()
    private let hunterFillLayer = CAShapeLayer()
    private let hunterStrokeLayer = CAShapeLayer()
    private let hunterTickLayer = CAShapeLayer()
    private let hunterImpactLayer = CAShapeLayer()
    private let ballRingLayer = CAShapeLayer()
    private let ballCenterLayer = CAShapeLayer()
    private let promptLabel = UILabel()

    private var hunter: HunterZone?
    private var ballDisplayRect: CGRect?
    private var isTracking = false
    private var prompt: String?

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

    func update(
        hunter: HunterZone?,
        ballDisplayRect: CGRect?,
        isTracking: Bool,
        prompt: String?
    ) {
        self.hunter = hunter
        self.ballDisplayRect = ballDisplayRect
        self.isTracking = isTracking
        self.prompt = prompt
        render()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        render()
    }

    private func configureLayers() {
        hunterGlowLayer.fillColor = UIColor.clear.cgColor
        hunterGlowLayer.strokeColor = UIColor.red.withAlphaComponent(0.26).cgColor
        hunterGlowLayer.lineWidth = 20
        hunterGlowLayer.shadowColor = UIColor.red.cgColor
        hunterGlowLayer.shadowOpacity = 0.72
        hunterGlowLayer.shadowRadius = 18
        hunterGlowLayer.shadowOffset = .zero
        layer.addSublayer(hunterGlowLayer)

        hunterFillLayer.fillColor = UIColor(red: 1.0, green: 0.02, blue: 0.02, alpha: 0.17).cgColor
        layer.addSublayer(hunterFillLayer)

        hunterStrokeLayer.fillColor = UIColor.clear.cgColor
        hunterStrokeLayer.strokeColor = UIColor(red: 1.0, green: 0.06, blue: 0.03, alpha: 0.92).cgColor
        hunterStrokeLayer.lineWidth = 5
        layer.addSublayer(hunterStrokeLayer)

        hunterTickLayer.fillColor = UIColor.clear.cgColor
        hunterTickLayer.strokeColor = UIColor(red: 1.0, green: 0.92, blue: 0.32, alpha: 0.88).cgColor
        hunterTickLayer.lineWidth = 4
        hunterTickLayer.lineCap = .round
        hunterTickLayer.lineJoin = .round
        layer.addSublayer(hunterTickLayer)

        hunterImpactLayer.fillColor = UIColor.clear.cgColor
        hunterImpactLayer.strokeColor = UIColor(red: 1.0, green: 0.08, blue: 0.02, alpha: 0.48).cgColor
        hunterImpactLayer.lineWidth = 5
        layer.addSublayer(hunterImpactLayer)

        ballRingLayer.fillColor = UIColor.clear.cgColor
        ballRingLayer.strokeColor = UIColor.white.cgColor
        ballRingLayer.lineWidth = 3
        ballRingLayer.shadowColor = UIColor.black.cgColor
        ballRingLayer.shadowOpacity = 0.45
        ballRingLayer.shadowRadius = 6
        ballRingLayer.shadowOffset = .zero
        layer.addSublayer(ballRingLayer)

        ballCenterLayer.fillColor = UIColor.yellow.cgColor
        layer.addSublayer(ballCenterLayer)

        promptLabel.font = .systemFont(ofSize: 17, weight: .black)
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        promptLabel.layer.cornerRadius = 8
        promptLabel.layer.masksToBounds = true
        addSubview(promptLabel)
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderHunter()
        renderBall()
        renderPrompt()
        CATransaction.commit()
    }

    private func renderHunter() {
        guard let hunter else {
            hunterGlowLayer.isHidden = true
            hunterFillLayer.isHidden = true
            hunterStrokeLayer.isHidden = true
            hunterTickLayer.isHidden = true
            hunterImpactLayer.isHidden = true
            return
        }

        hunterGlowLayer.isHidden = false
        hunterFillLayer.isHidden = false
        hunterStrokeLayer.isHidden = false
        hunterTickLayer.isHidden = false
        hunterImpactLayer.isHidden = hunter.phase != .impact

        let pulse = 0.5 + 0.5 * sin(hunter.pulsePhase)
        let pulseInset = hunter.radius * CGFloat(0.08 * pulse)
        let ringRect = CGRect(
            x: hunter.center.x - hunter.radius - pulseInset,
            y: hunter.center.y - hunter.radius - pulseInset,
            width: (hunter.radius + pulseInset) * 2,
            height: (hunter.radius + pulseInset) * 2
        )
        let coreRect = CGRect(
            x: hunter.center.x - hunter.radius,
            y: hunter.center.y - hunter.radius,
            width: hunter.radius * 2,
            height: hunter.radius * 2
        )

        hunterGlowLayer.path = UIBezierPath(ovalIn: ringRect).cgPath
        hunterGlowLayer.lineWidth = hunter.phase == .diving ? 18 + pulse * 13 : 12 + pulse * 8
        hunterGlowLayer.opacity = Float((hunter.phase == .recovering ? 0.28 : 0.48) + pulse * 0.28)

        hunterFillLayer.path = UIBezierPath(ovalIn: coreRect).cgPath
        hunterFillLayer.fillColor = fillColor(for: hunter).cgColor
        hunterStrokeLayer.path = UIBezierPath(ovalIn: coreRect).cgPath
        hunterStrokeLayer.strokeColor = strokeColor(for: hunter).cgColor
        hunterTickLayer.path = makeTickPath(for: hunter).cgPath
        hunterImpactLayer.path = impactPath(for: hunter).cgPath
        hunterImpactLayer.opacity = Float(max(0, 1 - hunter.phaseElapsed / 0.22))
    }

    private func fillColor(for hunter: HunterZone) -> UIColor {
        switch hunter.phase {
        case .aiming:
            return UIColor(red: 1.0, green: 0.02, blue: 0.02, alpha: 0.14)
        case .diving:
            return UIColor(red: 1.0, green: 0.02, blue: 0.02, alpha: 0.24)
        case .impact:
            return UIColor(red: 1.0, green: 0.02, blue: 0.02, alpha: 0.30)
        case .recovering:
            return UIColor(red: 1.0, green: 0.02, blue: 0.02, alpha: 0.10)
        }
    }

    private func strokeColor(for hunter: HunterZone) -> UIColor {
        switch hunter.phase {
        case .aiming:
            return UIColor(red: 1.0, green: 0.10, blue: 0.04, alpha: 0.78)
        case .diving, .impact:
            return UIColor(red: 1.0, green: 0.04, blue: 0.02, alpha: 0.96)
        case .recovering:
            return UIColor(red: 1.0, green: 0.24, blue: 0.12, alpha: 0.48)
        }
    }

    private func impactPath(for hunter: HunterZone) -> UIBezierPath {
        let radius = hunter.radius * (1.15 + min(hunter.phaseElapsed / 0.22, 1) * 0.65)
        let rect = CGRect(
            x: hunter.center.x - radius,
            y: hunter.center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        return UIBezierPath(ovalIn: rect)
    }

    private func makeTickPath(for hunter: HunterZone) -> UIBezierPath {
        let path = UIBezierPath()
        let angles: [CGFloat] = [-.pi / 2, 0, .pi / 2, .pi]
        for angle in angles {
            let inner = hunter.radius * 0.70
            let outer = hunter.radius * 1.10
            let start = CGPoint(
                x: hunter.center.x + cos(angle) * inner,
                y: hunter.center.y + sin(angle) * inner
            )
            let end = CGPoint(
                x: hunter.center.x + cos(angle) * outer,
                y: hunter.center.y + sin(angle) * outer
            )
            path.move(to: start)
            path.addLine(to: end)
        }
        return path
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
        ballRingLayer.strokeColor = (isTracking ? UIColor.white : UIColor.systemOrange).cgColor
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

    private func renderPrompt() {
        promptLabel.text = prompt
        promptLabel.isHidden = prompt == nil
        let size = CGSize(width: 180, height: 44)
        promptLabel.frame = CGRect(
            x: bounds.midX - size.width * 0.5,
            y: bounds.midY - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }
}

private struct HunterGameState {
    private(set) var hunter: HunterZone?

    mutating func reset() {
        hunter = nil
    }

    mutating func step(
        ballDisplayRect: CGRect,
        in size: CGSize,
        elapsed: TimeInterval,
        delta: TimeInterval
    ) -> HunterEvent? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        if hunter == nil {
            hunter = makeHunter(awayFrom: ballDisplayRect, in: size)
        }

        guard var activeHunter = hunter else {
            return nil
        }

        let progress = min(max(elapsed / 60.0, 0), 1)
        let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
        activeHunter.advance(
            toward: ballCenter,
            in: size,
            progress: progress,
            delta: delta
        )
        hunter = activeHunter

        return activeHunter.collides(with: ballDisplayRect) ? .caught : nil
    }

    private func makeHunter(awayFrom ballDisplayRect: CGRect, in size: CGSize) -> HunterZone {
        let minDimension = min(size.width, size.height)
        let radius = min(max(minDimension * 0.09, 40), 62)
        let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
        let topY = radius + max(18, size.height * 0.045)
        let spawnPoints = [
            CGPoint(x: radius + 24, y: topY),
            CGPoint(x: size.width - radius - 24, y: topY),
            CGPoint(x: size.width * 0.5, y: topY)
        ]
        let spawn = spawnPoints.max {
            hypot($0.x - ballCenter.x, $0.y - ballCenter.y) < hypot($1.x - ballCenter.x, $1.y - ballCenter.y)
        } ?? CGPoint(x: radius + 24, y: topY)
        return HunterZone(
            center: spawn,
            target: spawn,
            radius: radius,
            pulsePhase: 0,
            phase: .aiming,
            phaseElapsed: 0
        )
    }
}

private enum HunterAttackPhase {
    case aiming
    case diving
    case impact
    case recovering
}

private struct HunterZone {
    var center: CGPoint
    var target: CGPoint
    let radius: CGFloat
    var pulsePhase: CGFloat
    var phase: HunterAttackPhase
    var phaseElapsed: TimeInterval

    mutating func advance(
        toward target: CGPoint,
        in size: CGSize,
        progress: Double,
        delta: TimeInterval
    ) {
        pulsePhase += CGFloat(delta) * (phase == .diving ? 9.0 : 6.0)
        phaseElapsed += delta

        let easedProgress = pow(progress, 1.35)
        let minDimension = min(size.width, size.height)

        switch phase {
        case .aiming:
            let topY = topLine(in: size)
            let xSpeed = minDimension * CGFloat(0.64 + easedProgress * 0.34)
            moveToward(
                CGPoint(x: target.x, y: topY),
                speed: xSpeed,
                delta: delta,
                in: size
            )

            let aimDuration = max(0.38, 0.82 - progress * 0.30)
            if phaseElapsed >= aimDuration {
                self.target = impactTarget(for: target, in: size)
                phase = .diving
                phaseElapsed = 0
            }

        case .diving:
            let diveSpeed = minDimension * CGFloat(0.78 + easedProgress * 0.62)
            moveToward(self.target, speed: diveSpeed, delta: delta, in: size)
            if distance(to: self.target) <= max(8, radius * 0.18) || center.y >= lowerLimit(in: size) {
                phase = .impact
                phaseElapsed = 0
            }

        case .impact:
            if phaseElapsed >= max(0.13, 0.22 - progress * 0.06) {
                let topY = topLine(in: size)
                self.target = CGPoint(x: center.x, y: topY)
                phase = .recovering
                phaseElapsed = 0
            }

        case .recovering:
            let recoverSpeed = minDimension * CGFloat(0.88 + easedProgress * 0.42)
            moveToward(self.target, speed: recoverSpeed, delta: delta, in: size)
            if distance(to: self.target) <= max(8, radius * 0.18) {
                phase = .aiming
                phaseElapsed = 0
            }
        }

        center.x = min(max(center.x, radius), size.width - radius)
        center.y = min(max(center.y, radius), size.height - radius)
    }

    func collides(with ballDisplayRect: CGRect) -> Bool {
        guard phase == .diving || phase == .impact else {
            return false
        }
        let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
        let ballRadius = max(ballDisplayRect.width, ballDisplayRect.height) * 0.5 * 0.72
        let distance = hypot(ballCenter.x - center.x, ballCenter.y - center.y)
        return distance <= radius + ballRadius
    }

    private mutating func moveToward(
        _ destination: CGPoint,
        speed: CGFloat,
        delta: TimeInterval,
        in size: CGSize
    ) {
        let dx = destination.x - center.x
        let dy = destination.y - center.y
        let distance = max(hypot(dx, dy), 0.001)
        let step = min(speed * CGFloat(delta), distance)
        center.x += dx / distance * step
        center.y += dy / distance * step
    }

    private func impactTarget(for ballCenter: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(ballCenter.x, radius), size.width - radius),
            y: min(max(ballCenter.y, size.height * 0.46), lowerLimit(in: size))
        )
    }

    private func topLine(in size: CGSize) -> CGFloat {
        radius + max(18, size.height * 0.045)
    }

    private func lowerLimit(in size: CGSize) -> CGFloat {
        size.height - radius - max(10, size.height * 0.03)
    }

    private func distance(to point: CGPoint) -> CGFloat {
        hypot(center.x - point.x, center.y - point.y)
    }
}

private enum HunterEvent {
    case caught
}

private struct HunterHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(width: 92, height: 66)
        .background(.black.opacity(0.44), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.58), lineWidth: 1.5)
        )
    }
}

private struct HunterLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting The Hunter...")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HunterErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Camera Unavailable")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button(action: onDismiss) {
                        Text("CLOSE")
                            .font(.system(size: 15, weight: .black, design: .rounded))
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
                                .font(.system(size: 15, weight: .black, design: .rounded))
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

private struct HunterFinishedOverlay: View {
    let title: String
    let subtitle: String
    let timeText: String
    let primaryTitle: String
    let onPrimary: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(title)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)

                Text(subtitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))

                Text(timeText)
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                HStack(spacing: 10) {
                    Button(action: onPrimary) {
                        Text(primaryTitle)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button(action: onDone) {
                        Text("DONE")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)
        }
    }
}
