import Combine
import Foundation
import SwiftUI
import UIKit

enum HunterDifficulty: String, Identifiable {
    case easy
    case hard

    var id: String { rawValue }

    fileprivate var gameConfig: HunterGameConfig {
        switch self {
        case .easy:
            return HunterGameConfig(
                radiusScale: 0.78,
                xSpeedMultiplier: 0.68,
                diveSpeedMultiplier: 0.58,
                recoverSpeedMultiplier: 0.76,
                aimDurationMultiplier: 1.38,
                impactDurationMultiplier: 1.22
            )
        case .hard:
            return HunterGameConfig(
                radiusScale: 0.92,
                xSpeedMultiplier: 0.88,
                diveSpeedMultiplier: 0.78,
                recoverSpeedMultiplier: 0.90,
                aimDurationMultiplier: 1.12,
                impactDurationMultiplier: 1.08
            )
        }
    }
}

fileprivate struct HunterGameConfig {
    let radiusScale: CGFloat
    let xSpeedMultiplier: CGFloat
    let diveSpeedMultiplier: CGFloat
    let recoverSpeedMultiplier: CGFloat
    let aimDurationMultiplier: Double
    let impactDurationMultiplier: Double
}

struct HunterCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator: HunterCoordinator
    @State private var showsQuitConfirmation = false

    let difficulty: HunterDifficulty

    init(difficulty: HunterDifficulty = .hard) {
        self.difficulty = difficulty
        _coordinator = StateObject(wrappedValue: HunterCoordinator(difficulty: difficulty))
    }

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

                if coordinator.phase != .gameOver && coordinator.phase != .won {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

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
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.finishStartedAt,
                        buttonsVisible: coordinator.showsFinishButtons,
                        title: "TRY AGAIN",
                        primaryTitle: "TRY AGAIN",
                        backButtonTitle: "BACK TO HOME",
                        showsNextLevelButton: false,
                        onNextLevel: {},
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }

                if coordinator.phase == .won {
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.finishStartedAt,
                        buttonsVisible: coordinator.showsFinishButtons,
                        backButtonTitle: "BACK TO HOME",
                        showsNextLevelButton: false,
                        onNextLevel: {},
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .ballrAwardsXPOnSuccess(coordinator.phase == .won)
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
                    .font(.ballr(size: 18, weight: .black))
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
    case caughtAnimating
    case gameOver
    case won
}

private final class HunterCoordinator: ObservableObject {
    @Published private(set) var phase: HunterPhase = .readiness
    @Published private(set) var ballFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var timerText = "60"
    @Published private(set) var survivedTimeText = "0s"
    @Published private(set) var finishStartedAt: Date?
    @Published private(set) var showsFinishButtons = false

    private let requiredBallLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 60.0
    private let finishAnimationDuration: TimeInterval = 2.05
    private let finishButtonRevealDelay: TimeInterval = 0.28
    private let lostBallPromptFrameThreshold = 18

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var lostBallFrameCount = 0
    private var heldBallDisplayRect: CGRect?
    private var isTracking = false
    private let difficulty: HunterDifficulty
    private var gameState: HunterGameState
    private weak var renderView: HunterRenderView?
    private var caughtOverlayWorkItem: DispatchWorkItem?
    private var finishWorkItem: DispatchWorkItem?

    init(difficulty: HunterDifficulty) {
        self.difficulty = difficulty
        gameState = HunterGameState(config: difficulty.gameConfig)
    }

    func attach(renderView: HunterRenderView) {
        self.renderView = renderView
        renderView.update(
            hunter: gameState.hunter,
            ballDisplayRect: nil,
            isTracking: false,
            prompt: promptText
        )
    }

    func tearDown() {
        cancelFinishWorkItem()
        caughtOverlayWorkItem?.cancel()
        caughtOverlayWorkItem = nil
    }

    func reset(in size: CGSize) {
        cancelFinishWorkItem()
        caughtOverlayWorkItem?.cancel()
        caughtOverlayWorkItem = nil
        self.size = size
        phase = .readiness
        ballFoundStartedAt = nil
        countdownStartedAt = nil
        timerText = "60"
        survivedTimeText = "0s"
        finishStartedAt = nil
        showsFinishButtons = false
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
        case .caught(let point):
            BallrDrillSoundPlayer.playHunterExplosion()
            renderView?.triggerExplosion(at: point)
            phase = .caughtAnimating
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, self.phase == .caughtAnimating else {
                    return
                }
                self.finish(as: .gameOver, at: timestamp)
                self.caughtOverlayWorkItem = nil
            }
            caughtOverlayWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: workItem)
        case .none:
            if liveElapsed >= roundDuration {
                BallrDrillSoundPlayer.playWinner()
                timerText = "0"
                survivedTimeText = "60s"
                finish(as: .won, at: timestamp)
            }
        }
    }

    private func finish(as finishPhase: HunterPhase, at timestamp: Date) {
        guard phase != .gameOver, phase != .won else {
            return
        }

        phase = finishPhase
        finishStartedAt = timestamp

        let workItem = DispatchWorkItem { [weak self] in
            self?.showsFinishButtons = true
        }
        finishWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + finishAnimationDuration + finishButtonRevealDelay,
            execute: workItem
        )
    }

    private func cancelFinishWorkItem() {
        finishWorkItem?.cancel()
        finishWorkItem = nil
    }

    private var promptText: String? {
        switch phase {
        case .readiness, .countdown:
            return nil
        case .live:
            return isTracking ? nil : "Find the ball"
        case .caughtAnimating:
            return nil
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
    private let hunterImageLayer = CALayer()
    private let hunterLegLayer = CAShapeLayer()
    private let hunterFootLayer = CAShapeLayer()
    private let hunterFillLayer = CAShapeLayer()
    private let hunterStrokeLayer = CAShapeLayer()
    private let hunterTickLayer = CAShapeLayer()
    private let hunterHighlightLayer = CAShapeLayer()
    private let hunterImpactLayer = CAShapeLayer()
    private let bombFuseLayer = CAShapeLayer()
    private let bombBodyLayer = CAShapeLayer()
    private let bombShineLayer = CAShapeLayer()
    private let bombFlameLayer = CAShapeLayer()
    private let explosionLayer = CALayer()
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

    func triggerExplosion(at point: CGPoint) {
        let radius = max(86, min(bounds.width, bounds.height) * 0.20)
        let explosionBounds = CGRect(x: 0, y: 0, width: radius * 2, height: radius * 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if explosionLayer.contents == nil {
            explosionLayer.contents = Self.loadExplosionImage()?.cgImage
        }
        explosionLayer.bounds = explosionBounds
        explosionLayer.position = point
        explosionLayer.opacity = 1
        explosionLayer.transform = CATransform3DIdentity
        explosionLayer.isHidden = false
        CATransaction.commit()

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.18, 1.08, 0.96, 1.0]
        scale.keyTimes = [0, 0.36, 0.62, 1]
        scale.duration = 0.46
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]

        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.12, 0.62, 1]
        fade.duration = 0.58
        fade.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeIn)
        ]

        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.58
        group.isRemovedOnCompletion = true

        explosionLayer.add(group, forKey: "hunterExplosion")

        DispatchQueue.main.asyncAfter(deadline: .now() + group.duration) { [weak self] in
            self?.explosionLayer.isHidden = true
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        render()
    }

    private func configureLayers() {
        hunterGlowLayer.fillColor = UIColor.clear.cgColor
        hunterGlowLayer.strokeColor = UIColor.clear.cgColor
        hunterGlowLayer.lineWidth = 0
        hunterGlowLayer.shadowOpacity = 0
        hunterGlowLayer.shadowOffset = .zero
        layer.addSublayer(hunterGlowLayer)

        hunterImageLayer.contentsGravity = .resizeAspect
        hunterImageLayer.magnificationFilter = .linear
        hunterImageLayer.minificationFilter = .linear
        hunterImageLayer.contents = Self.loadTargetImage()?.cgImage
        layer.addSublayer(hunterImageLayer)

        hunterLegLayer.fillColor = UIColor(red: 0.12, green: 0.10, blue: 0.10, alpha: 1).cgColor
        hunterLegLayer.strokeColor = UIColor.black.cgColor
        hunterLegLayer.lineWidth = 0.9
        layer.addSublayer(hunterLegLayer)

        hunterFootLayer.fillColor = UIColor(red: 0.84, green: 0.84, blue: 0.82, alpha: 1).cgColor
        hunterFootLayer.strokeColor = UIColor.black.cgColor
        hunterFootLayer.lineWidth = 1.1
        layer.addSublayer(hunterFootLayer)

        hunterFillLayer.fillColor = UIColor(red: 0.96, green: 0.42, blue: 0.00, alpha: 1).cgColor
        layer.addSublayer(hunterFillLayer)

        hunterStrokeLayer.fillColor = UIColor.clear.cgColor
        hunterStrokeLayer.strokeColor = UIColor.black.cgColor
        hunterStrokeLayer.lineWidth = 1.1
        hunterStrokeLayer.lineCap = .round
        hunterStrokeLayer.lineJoin = .round
        layer.addSublayer(hunterStrokeLayer)

        hunterTickLayer.fillColor = UIColor(red: 1.0, green: 0.70, blue: 0.43, alpha: 1).cgColor
        hunterTickLayer.strokeColor = UIColor.clear.cgColor
        layer.addSublayer(hunterTickLayer)

        hunterHighlightLayer.fillColor = UIColor(red: 1.0, green: 0.72, blue: 0.46, alpha: 0.94).cgColor
        layer.addSublayer(hunterHighlightLayer)

        hunterImpactLayer.fillColor = UIColor.clear.cgColor
        hunterImpactLayer.strokeColor = UIColor(red: 1.0, green: 0.72, blue: 0.20, alpha: 0.56).cgColor
        hunterImpactLayer.lineWidth = 4
        layer.addSublayer(hunterImpactLayer)

        bombFuseLayer.fillColor = UIColor.clear.cgColor
        bombFuseLayer.strokeColor = UIColor(red: 0.48, green: 0.48, blue: 0.47, alpha: 1).cgColor
        bombFuseLayer.lineWidth = 9
        bombFuseLayer.lineCap = .round
        layer.addSublayer(bombFuseLayer)

        bombBodyLayer.fillColor = UIColor(red: 0.17, green: 0.15, blue: 0.15, alpha: 1).cgColor
        bombBodyLayer.strokeColor = UIColor.clear.cgColor
        bombBodyLayer.shadowColor = UIColor(red: 1.0, green: 0.76, blue: 0.20, alpha: 1).cgColor
        bombBodyLayer.shadowOpacity = 0.32
        bombBodyLayer.shadowRadius = 8
        bombBodyLayer.shadowOffset = .zero
        layer.addSublayer(bombBodyLayer)

        bombShineLayer.fillColor = UIColor.white.withAlphaComponent(0.22).cgColor
        bombShineLayer.strokeColor = UIColor.clear.cgColor
        layer.addSublayer(bombShineLayer)

        bombFlameLayer.fillColor = UIColor(red: 1.0, green: 0.69, blue: 0.18, alpha: 1).cgColor
        bombFlameLayer.strokeColor = UIColor.clear.cgColor
        bombFlameLayer.shadowColor = UIColor(red: 1.0, green: 0.64, blue: 0.08, alpha: 1).cgColor
        bombFlameLayer.shadowOpacity = 0.70
        bombFlameLayer.shadowRadius = 7
        bombFlameLayer.shadowOffset = .zero
        layer.addSublayer(bombFlameLayer)

        explosionLayer.contentsGravity = .resizeAspect
        explosionLayer.magnificationFilter = .linear
        explosionLayer.minificationFilter = .linear
        explosionLayer.contents = Self.loadExplosionImage()?.cgImage
        explosionLayer.isHidden = true
        layer.addSublayer(explosionLayer)

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
            hunterImageLayer.isHidden = true
            hunterFillLayer.isHidden = true
            hunterStrokeLayer.isHidden = true
            hunterTickLayer.isHidden = true
            hunterHighlightLayer.isHidden = true
            hunterLegLayer.isHidden = true
            hunterFootLayer.isHidden = true
            hunterImpactLayer.isHidden = true
            bombFuseLayer.isHidden = true
            bombBodyLayer.isHidden = true
            bombShineLayer.isHidden = true
            bombFlameLayer.isHidden = true
            return
        }

        hunterGlowLayer.isHidden = true
        hunterImageLayer.isHidden = false
        hunterLegLayer.isHidden = true
        hunterFootLayer.isHidden = true
        hunterFillLayer.isHidden = true
        hunterStrokeLayer.isHidden = true
        hunterTickLayer.isHidden = true
        hunterHighlightLayer.isHidden = true
        hunterImpactLayer.isHidden = hunter.phase != .impact
        bombFuseLayer.isHidden = true
        bombBodyLayer.isHidden = true
        bombShineLayer.isHidden = true
        bombFlameLayer.isHidden = true

        let width = hunter.radius * 3.76
        let height = width * (164.0 / 260.0)
        let characterRect = CGRect(
            x: hunter.center.x - width * 0.5,
            y: hunter.center.y - height * 0.48,
            width: width,
            height: height
        )

        if hunterImageLayer.contents == nil {
            hunterImageLayer.contents = Self.loadTargetImage()?.cgImage
        }
        hunterImageLayer.frame = characterRect
        hunterImpactLayer.path = impactPath(for: hunter).cgPath
        hunterImpactLayer.opacity = Float(max(0, 1 - hunter.phaseElapsed / 0.22))
        renderBomb(for: hunter)
    }

    private static func loadTargetImage() -> UIImage? {
        if let image = UIImage(named: "HunterTarget") {
            return image
        }
        if let image = UIImage(named: "TARGET") {
            return image
        }
        if let image = UIImage(named: "Features/Practice/TARGET") {
            return image
        }
        if let url = Bundle.main.url(forResource: "TARGET", withExtension: "svg") {
            return UIImage(contentsOfFile: url.path)
        }
        if let url = Bundle.main.url(forResource: "TARGET", withExtension: "svg", subdirectory: "Features/Practice") {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    private static func loadExplosionImage() -> UIImage? {
        if let image = UIImage(named: "HunterExplosion") {
            return image
        }
        if let image = UIImage(named: "Explosion") {
            return image
        }
        if let image = UIImage(named: "Features/Practice/Explosion") {
            return image
        }
        if let url = Bundle.main.url(forResource: "Explosion", withExtension: "svg") {
            return UIImage(contentsOfFile: url.path)
        }
        if let url = Bundle.main.url(forResource: "Explosion", withExtension: "svg", subdirectory: "Features/Practice") {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
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
        let center = hunter.bombCenter ?? hunter.bombSpawnPoint
        let radius = hunter.bombRadius * (1.15 + min(hunter.phaseElapsed / 0.22, 1) * 0.65)
        let rect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
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

    private func renderBomb(for hunter: HunterZone) {
        guard hunter.phase != .impact, let bombCenter = hunter.bombCenter else {
            bombFuseLayer.isHidden = true
            bombBodyLayer.isHidden = true
            bombShineLayer.isHidden = true
            bombFlameLayer.isHidden = true
            return
        }

        bombFuseLayer.isHidden = false
        bombBodyLayer.isHidden = false
        bombShineLayer.isHidden = false
        bombFlameLayer.isHidden = false

        let radius = hunter.bombRadius
        let rect = CGRect(
            x: bombCenter.x - radius,
            y: bombCenter.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        bombBodyLayer.path = bombBodyPath(in: rect).cgPath
        bombBodyLayer.shadowPath = bombBodyLayer.path
        bombShineLayer.path = bombShinePath(in: rect).cgPath
        bombFuseLayer.path = bombFusePath(in: rect).cgPath
        bombFuseLayer.lineWidth = max(4, radius * 0.22)
        bombFlameLayer.path = bombFlamePath(in: rect).cgPath
    }

    private func hunterFillPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        path.append(hunterCrownPath(in: rect))
        path.append(hunterBrimPath(in: rect))
        return path
    }

    private func hunterOutlinePath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        path.append(hunterCrownVisibleStrokePath(in: rect))
        path.append(hunterBrimVisibleStrokePath(in: rect))
        return path
    }

    private func hunterCrownPath(in rect: CGRect) -> UIBezierPath {
        UIBezierPath(
            roundedRect: CGRect(
                x: rect.minX + rect.width * 0.265,
                y: rect.minY + rect.height * 0.01,
                width: rect.width * 0.47,
                height: rect.height * 0.52
            ),
            cornerRadius: rect.width * 0.15
        )
    }

    private func hunterBrimPath(in rect: CGRect) -> UIBezierPath {
        UIBezierPath(
            ovalIn: CGRect(
                x: rect.minX,
                y: rect.minY + rect.height * 0.48,
                width: rect.width,
                height: rect.height * 0.36
            )
        )
    }

    private func hunterBrimVisibleStrokePath(in rect: CGRect) -> UIBezierPath {
        let brim = CGRect(
            x: rect.minX,
            y: rect.minY + rect.height * 0.48,
            width: rect.width,
            height: rect.height * 0.36
        )
        let crownLeft = rect.minX + rect.width * 0.265
        let crownRight = rect.minX + rect.width * 0.735
        let brimTop = brim.minY
        let brimMidY = brim.midY
        let brimBottom = brim.maxY
        let path = UIBezierPath()
        path.move(to: CGPoint(x: crownLeft, y: brimTop))
        path.addCurve(
            to: CGPoint(x: crownRight, y: brimTop),
            controlPoint1: CGPoint(x: rect.minX + rect.width * 0.40, y: rect.minY + rect.height * 0.56),
            controlPoint2: CGPoint(x: rect.minX + rect.width * 0.60, y: rect.minY + rect.height * 0.56)
        )

        path.move(to: CGPoint(x: crownLeft, y: brimTop))
        path.addCurve(
            to: CGPoint(x: brim.minX, y: brimMidY),
            controlPoint1: CGPoint(x: rect.minX + rect.width * 0.12, y: brimTop),
            controlPoint2: CGPoint(x: brim.minX, y: rect.minY + rect.height * 0.54)
        )
        path.addCurve(
            to: CGPoint(x: brim.midX, y: brimBottom),
            controlPoint1: CGPoint(x: brim.minX, y: rect.minY + rect.height * 0.78),
            controlPoint2: CGPoint(x: rect.minX + rect.width * 0.22, y: brimBottom)
        )
        path.addCurve(
            to: CGPoint(x: brim.maxX, y: brimMidY),
            controlPoint1: CGPoint(x: rect.minX + rect.width * 0.78, y: brimBottom),
            controlPoint2: CGPoint(x: brim.maxX, y: rect.minY + rect.height * 0.78)
        )
        path.addCurve(
            to: CGPoint(x: crownRight, y: brimTop),
            controlPoint1: CGPoint(x: brim.maxX, y: rect.minY + rect.height * 0.54),
            controlPoint2: CGPoint(x: rect.minX + rect.width * 0.88, y: brimTop)
        )
        return path
    }

    private func hunterCrownVisibleStrokePath(in rect: CGRect) -> UIBezierPath {
        let crown = CGRect(
            x: rect.minX + rect.width * 0.265,
            y: rect.minY + rect.height * 0.01,
            width: rect.width * 0.47,
            height: rect.height * 0.52
        )
        let radius = rect.width * 0.15
        let path = UIBezierPath()
        path.move(to: CGPoint(x: crown.minX, y: crown.maxY))
        path.addLine(to: CGPoint(x: crown.minX, y: crown.minY + radius))
        path.addCurve(
            to: CGPoint(x: crown.minX + radius, y: crown.minY),
            controlPoint1: CGPoint(x: crown.minX, y: crown.minY + radius * 0.45),
            controlPoint2: CGPoint(x: crown.minX + radius * 0.45, y: crown.minY)
        )
        path.addLine(to: CGPoint(x: crown.maxX - radius, y: crown.minY))
        path.addCurve(
            to: CGPoint(x: crown.maxX, y: crown.minY + radius),
            controlPoint1: CGPoint(x: crown.maxX - radius * 0.45, y: crown.minY),
            controlPoint2: CGPoint(x: crown.maxX, y: crown.minY + radius * 0.45)
        )
        path.addLine(to: CGPoint(x: crown.maxX, y: crown.maxY))
        return path
    }

    private func hunterLegPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let legWidth = rect.width * 0.038
        let legHeight = rect.height * 0.20
        let legY = rect.minY + rect.height * 0.80
        let leftCenterX = rect.minX + rect.width * 0.245
        let rightCenterX = rect.minX + rect.width * 0.755
        let leftLeg = UIBezierPath(
            roundedRect: CGRect(x: leftCenterX - legWidth * 0.5, y: legY, width: legWidth, height: legHeight),
            cornerRadius: legWidth * 0.5
        )
        .rotated(by: 12.83 * .pi / 180, around: CGPoint(x: leftCenterX, y: legY))
        let rightLeg = UIBezierPath(
            roundedRect: CGRect(x: rightCenterX - legWidth * 0.5, y: legY, width: legWidth, height: legHeight),
            cornerRadius: legWidth * 0.5
        )
        .rotated(by: -12.83 * .pi / 180, around: CGPoint(x: rightCenterX, y: legY))
        path.append(leftLeg)
        path.append(rightLeg)
        return path
    }

    private func hunterFootPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let footWidth = rect.width * 0.095
        let footHeight = rect.height * 0.07
        let footY = rect.minY + rect.height * 0.95
        let leftCenterX = rect.minX + rect.width * 0.225
        let rightCenterX = rect.minX + rect.width * 0.775
        path.append(semicirclePath(in: CGRect(x: leftCenterX - footWidth * 0.5, y: footY, width: footWidth, height: footHeight)))
        path.append(semicirclePath(in: CGRect(x: rightCenterX - footWidth * 0.5, y: footY, width: footWidth, height: footHeight)))
        return path
    }

    private func semicirclePath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addArc(
            withCenter: CGPoint(x: rect.midX, y: rect.maxY),
            radius: rect.width * 0.5,
            startAngle: .pi,
            endAngle: 0,
            clockwise: true
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.close()
        return path
    }

    private func hunterDotPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let dots: [CGPoint] = [
            CGPoint(x: rect.minX + rect.width * 0.052, y: rect.minY + rect.height * 0.66),
            CGPoint(x: rect.minX + rect.width * 0.150, y: rect.minY + rect.height * 0.73),
            CGPoint(x: rect.minX + rect.width * 0.258, y: rect.minY + rect.height * 0.77),
            CGPoint(x: rect.minX + rect.width * 0.363, y: rect.minY + rect.height * 0.79),
            CGPoint(x: rect.minX + rect.width * 0.468, y: rect.minY + rect.height * 0.80),
            CGPoint(x: rect.minX + rect.width * 0.572, y: rect.minY + rect.height * 0.79),
            CGPoint(x: rect.minX + rect.width * 0.676, y: rect.minY + rect.height * 0.77),
            CGPoint(x: rect.minX + rect.width * 0.783, y: rect.minY + rect.height * 0.72),
            CGPoint(x: rect.minX + rect.width * 0.876, y: rect.minY + rect.height * 0.67),
            CGPoint(x: rect.minX + rect.width * 0.958, y: rect.minY + rect.height * 0.62)
        ]
        let dotSize = rect.width * 0.043
        for dot in dots {
            path.append(UIBezierPath(ovalIn: CGRect(x: dot.x - dotSize * 0.5, y: dot.y - dotSize * 0.5, width: dotSize, height: dotSize)))
        }
        return path
    }

    private func hunterHighlightPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: x + w * 0.46, y: y + h * 0.08))
        path.addLine(to: CGPoint(x: x + w * 0.64, y: y + h * 0.08))
        path.addCurve(
            to: CGPoint(x: x + w * 0.70, y: y + h * 0.41),
            controlPoint1: CGPoint(x: x + w * 0.71, y: y + h * 0.08),
            controlPoint2: CGPoint(x: x + w * 0.70, y: y + h * 0.22)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.67, y: y + h * 0.41),
            controlPoint1: CGPoint(x: x + w * 0.70, y: y + h * 0.47),
            controlPoint2: CGPoint(x: x + w * 0.67, y: y + h * 0.48)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.62, y: y + h * 0.24),
            controlPoint1: CGPoint(x: x + w * 0.65, y: y + h * 0.30),
            controlPoint2: CGPoint(x: x + w * 0.65, y: y + h * 0.29)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.49, y: y + h * 0.15),
            controlPoint1: CGPoint(x: x + w * 0.59, y: y + h * 0.20),
            controlPoint2: CGPoint(x: x + w * 0.53, y: y + h * 0.18)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.46, y: y + h * 0.08),
            controlPoint1: CGPoint(x: x + w * 0.43, y: y + h * 0.10),
            controlPoint2: CGPoint(x: x + w * 0.44, y: y + h * 0.08)
        )
        path.close()
        return path
    }

    private func bombBodyPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        path.append(UIBezierPath(ovalIn: CGRect(x: x + w * 0.08, y: y + h * 0.28, width: w * 0.84, height: h * 0.84)))
        path.append(UIBezierPath(roundedRect: CGRect(x: x + w * 0.42, y: y + h * 0.16, width: w * 0.16, height: h * 0.18), cornerRadius: w * 0.04))
        path.append(UIBezierPath(roundedRect: CGRect(x: x + w * 0.35, y: y + h * 0.26, width: w * 0.30, height: h * 0.15), cornerRadius: w * 0.05))
        return path
    }

    private func bombShinePath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        path.append(UIBezierPath(
            ovalIn: CGRect(
                x: x + w * 0.23,
                y: y + h * 0.43,
                width: w * 0.22,
                height: h * 0.13
            )
        ))
        path.append(UIBezierPath(
            ovalIn: CGRect(
                x: x + w * 0.31,
                y: y + h * 0.58,
                width: w * 0.10,
                height: h * 0.07
            )
        ))
        return path
    }

    private func bombFusePath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: x + w * 0.51, y: y + h * 0.18))
        path.addCurve(
            to: CGPoint(x: x + w * 0.66, y: y - h * 0.08),
            controlPoint1: CGPoint(x: x + w * 0.52, y: y + h * 0.06),
            controlPoint2: CGPoint(x: x + w * 0.58, y: y - h * 0.05)
        )
        return path
    }

    private func bombFlamePath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: x + w * 0.62, y: y - h * 0.30))
        path.addCurve(
            to: CGPoint(x: x + w * 0.66, y: y - h * 0.14),
            controlPoint1: CGPoint(x: x + w * 0.59, y: y - h * 0.30),
            controlPoint2: CGPoint(x: x + w * 0.59, y: y - h * 0.17)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.72, y: y - h * 0.18),
            controlPoint1: CGPoint(x: x + w * 0.69, y: y - h * 0.13),
            controlPoint2: CGPoint(x: x + w * 0.71, y: y - h * 0.15)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.61, y: y - h * 0.01),
            controlPoint1: CGPoint(x: x + w * 0.77, y: y - h * 0.08),
            controlPoint2: CGPoint(x: x + w * 0.71, y: y + h * 0.01)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.53, y: y - h * 0.16),
            controlPoint1: CGPoint(x: x + w * 0.53, y: y - h * 0.04),
            controlPoint2: CGPoint(x: x + w * 0.51, y: y - h * 0.10)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.62, y: y - h * 0.30),
            controlPoint1: CGPoint(x: x + w * 0.54, y: y - h * 0.24),
            controlPoint2: CGPoint(x: x + w * 0.58, y: y - h * 0.30)
        )
        path.close()
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

private extension UIBezierPath {
    func rotated(by radians: CGFloat, around anchor: CGPoint) -> UIBezierPath {
        let copy = UIBezierPath(cgPath: cgPath)
        var transform = CGAffineTransform(translationX: anchor.x, y: anchor.y)
        transform = transform.rotated(by: radians)
        transform = transform.translatedBy(x: -anchor.x, y: -anchor.y)
        copy.apply(transform)
        return copy
    }
}

private struct HunterGameState {
    private let config: HunterGameConfig
    private(set) var hunter: HunterZone?

    init(config: HunterGameConfig) {
        self.config = config
    }

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
            config: config,
            delta: delta
        )
        if let collisionPoint = activeHunter.collisionPoint(with: ballDisplayRect) {
            activeHunter.phase = .impact
            activeHunter.phaseElapsed = 0
            hunter = activeHunter
            return .caught(collisionPoint)
        }

        hunter = activeHunter
        return nil
    }

    private func makeHunter(awayFrom ballDisplayRect: CGRect, in size: CGSize) -> HunterZone {
        let minDimension = min(size.width, size.height)
        let radius = min(max(minDimension * 0.09 * config.radiusScale, 34), 62)
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
            bombCenter: nil,
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
    var bombCenter: CGPoint?
    var pulsePhase: CGFloat
    var phase: HunterAttackPhase
    var phaseElapsed: TimeInterval

    var bombRadius: CGFloat {
        radius * 1.00
    }

    var bombSpawnPoint: CGPoint {
        CGPoint(x: center.x, y: center.y + radius * 1.46)
    }

    mutating func advance(
        toward target: CGPoint,
        in size: CGSize,
        progress: Double,
        config: HunterGameConfig,
        delta: TimeInterval
    ) {
        pulsePhase += CGFloat(delta) * (phase == .diving ? 9.0 : 6.0)
        phaseElapsed += delta

        let easedProgress = pow(progress, 1.35)
        let minDimension = min(size.width, size.height)

        switch phase {
        case .aiming:
            let topY = topLine(in: size)
            let xSpeed = minDimension * CGFloat(0.64 + easedProgress * 0.34) * config.xSpeedMultiplier
            moveToward(
                CGPoint(x: target.x, y: topY),
                speed: xSpeed,
                delta: delta,
                in: size
            )

            let aimDuration = max(0.38, (0.82 - progress * 0.30) * config.aimDurationMultiplier)
            let releaseTarget = impactTarget(for: target, in: size)
            let horizontalAlignment = abs(center.x - releaseTarget.x)
            let isAlignedForDrop = horizontalAlignment <= max(10, radius * 0.22)
            if phaseElapsed >= aimDuration, isAlignedForDrop {
                self.target = releaseTarget
                bombCenter = bombSpawnPoint
                phase = .diving
                phaseElapsed = 0
            }

        case .diving:
            let topY = topLine(in: size)
            let xSpeed = minDimension * CGFloat(0.42 + easedProgress * 0.24) * config.xSpeedMultiplier
            moveToward(
                CGPoint(x: target.x, y: topY),
                speed: xSpeed,
                delta: delta,
                in: size
            )
            self.target = impactTarget(for: target, in: size)
            let diveSpeed = minDimension * CGFloat(0.78 + easedProgress * 0.62) * config.diveSpeedMultiplier
            moveBombDown(speed: diveSpeed, delta: delta)
            if bombDistance(to: self.target) <= max(8, bombRadius * 0.28) || (bombCenter?.y ?? 0) >= lowerLimit(in: size) {
                phase = .impact
                phaseElapsed = 0
            }

        case .impact:
            if phaseElapsed >= max(0.13, (0.22 - progress * 0.06) * config.impactDurationMultiplier) {
                let topY = topLine(in: size)
                self.target = CGPoint(x: center.x, y: topY)
                bombCenter = nil
                phase = .recovering
                phaseElapsed = 0
            }

        case .recovering:
            let recoverSpeed = minDimension * CGFloat(0.88 + easedProgress * 0.42) * config.recoverSpeedMultiplier
            moveToward(self.target, speed: recoverSpeed, delta: delta, in: size)
            if distance(to: self.target) <= max(8, radius * 0.18) {
                bombCenter = nil
                phase = .aiming
                phaseElapsed = 0
            }
        }

        center.x = min(max(center.x, radius), size.width - radius)
        center.y = topLine(in: size)
    }

    func collisionPoint(with ballDisplayRect: CGRect) -> CGPoint? {
        guard (phase == .diving || phase == .impact), let bombCenter else {
            return nil
        }
        let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
        let ballRadius = max(ballDisplayRect.width, ballDisplayRect.height) * 0.5 * 0.72
        let distance = hypot(ballCenter.x - bombCenter.x, ballCenter.y - bombCenter.y)
        guard distance <= bombRadius + ballRadius else {
            return nil
        }
        return CGPoint(
            x: (ballCenter.x + bombCenter.x) * 0.5,
            y: (ballCenter.y + bombCenter.y) * 0.5
        )
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

    private mutating func moveBombDown(speed: CGFloat, delta: TimeInterval) {
        guard var bombCenter else {
            self.bombCenter = bombSpawnPoint
            return
        }
        bombCenter.y += speed * CGFloat(delta)
        self.bombCenter = bombCenter
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

    private func bombDistance(to point: CGPoint) -> CGFloat {
        guard let bombCenter else {
            return .greatestFiniteMagnitude
        }
        return hypot(bombCenter.x - point.x, bombCenter.y - point.y)
    }
}

private enum HunterEvent {
    case caught(CGPoint)
}

private struct HunterHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.ballr(size: 11, weight: .black))
                .tracking(1.3)
                .foregroundStyle(.white.opacity(0.58))
            Text(value)
                .font(.ballr(size: 26, weight: .black))
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
                .font(.ballr(size: 16, weight: .black))
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
                    .font(.ballr(size: 28, weight: .black))
                    .foregroundStyle(Color.yellow)

                Text(subtitle)
                    .font(.ballr(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.76))

                Text(timeText)
                    .font(.ballr(size: 54, weight: .black))
                    .foregroundStyle(.white)
                    .monospacedDigit()

                HStack(spacing: 10) {
                    Button(action: onPrimary) {
                        Text(primaryTitle)
                            .font(.ballr(size: 14, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button(action: onDone) {
                        Text("DONE")
                            .font(.ballr(size: 14, weight: .black))
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
