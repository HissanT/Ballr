import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

enum BallBlastRockDropDifficulty: String, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    fileprivate var gameConfig: BallBlastRockDropGameConfig {
        switch self {
        case .easy:
            return BallBlastRockDropGameConfig(
                initialSpawnDelay: 0.75,
                maxRocksBase: 3,
                maxRocksRamp: 6,
                spawnIntervalMinimumStart: 1.08,
                spawnIntervalMinimumRamp: 0.28,
                spawnIntervalMaximumStart: 1.55,
                spawnIntervalMaximumRamp: 0.40,
                speedBaseStart: 95,
                speedBaseRamp: 115,
                speedProgressMultiplier: 0.04,
                speedRandomRange: 0.70...1.15,
                targetChanceBase: 0.10,
                targetChanceRamp: 0.12,
                targetChanceCap: 0.28
            )
        case .medium:
            return BallBlastRockDropGameConfig(
                initialSpawnDelay: 0.64,
                maxRocksBase: 4,
                maxRocksRamp: 7,
                spawnIntervalMinimumStart: 1.02,
                spawnIntervalMinimumRamp: 0.31,
                spawnIntervalMaximumStart: 1.48,
                spawnIntervalMaximumRamp: 0.44,
                speedBaseStart: 102,
                speedBaseRamp: 128,
                speedProgressMultiplier: 0.05,
                speedRandomRange: 0.70...1.18,
                targetChanceBase: 0.14,
                targetChanceRamp: 0.16,
                targetChanceCap: 0.36
            )
        case .hard:
            return BallBlastRockDropGameConfig(
                initialSpawnDelay: 0.35,
                maxRocksBase: 5,
                maxRocksRamp: 12,
                spawnIntervalMinimumStart: 0.78,
                spawnIntervalMinimumRamp: 0.46,
                spawnIntervalMaximumStart: 1.24,
                spawnIntervalMaximumRamp: 0.74,
                speedBaseStart: 125,
                speedBaseRamp: 185,
                speedProgressMultiplier: 0.10,
                speedRandomRange: 0.72...1.38,
                targetChanceBase: 0.26,
                targetChanceRamp: 0.28,
                targetChanceCap: 0.64
            )
        }
    }
}

fileprivate struct BallBlastRockDropGameConfig {
    let initialSpawnDelay: TimeInterval
    let maxRocksBase: Int
    let maxRocksRamp: Int
    let spawnIntervalMinimumStart: Double
    let spawnIntervalMinimumRamp: Double
    let spawnIntervalMaximumStart: Double
    let spawnIntervalMaximumRamp: Double
    let speedBaseStart: Double
    let speedBaseRamp: Double
    let speedProgressMultiplier: Double
    let speedRandomRange: ClosedRange<CGFloat>
    let targetChanceBase: Double
    let targetChanceRamp: Double
    let targetChanceCap: Double
}

struct BallBlastRockDropCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator: BallBlastRockDropCoordinator
    @State private var showsQuitConfirmation = false
    let difficulty: BallBlastRockDropDifficulty

    init(difficulty: BallBlastRockDropDifficulty = .hard) {
        self.difficulty = difficulty
        _coordinator = StateObject(wrappedValue: BallBlastRockDropCoordinator(difficulty: difficulty))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                BallBlastRockDropRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                }
                .padding(.vertical, 14)
                .zIndex(100)

                if cameraController.isStarting {
                    BallBlastRockDropLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    BallBlastRockDropErrorOverlay(
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
                    BallBlastRockDropFinishedOverlay(
                        title: "SO CLOSE, TRY AGAIN",
                        subtitle: "A rock hit the ball.",
                        timeText: coordinator.survivedTimeText,
                        primaryTitle: "PLAY AGAIN",
                        onPrimary: { coordinator.reset(in: geometry.size) },
                        onDone: { dismiss() }
                    )
                }

                if coordinator.phase == .won {
                    BallBlastRockDropFinishedOverlay(
                        title: "YOU SURVIVED, GOOD JOB!",
                        subtitle: "Clean run.",
                        timeText: "60s",
                        primaryTitle: "PLAY AGAIN",
                        onPrimary: { coordinator.reset(in: geometry.size) },
                        onDone: { dismiss() }
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
                coordinator.stopSounds()
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

            BallBlastRockDropHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
                .padding(.top, 8)
        }
    }
}

private enum BallBlastRockDropPhase {
    case readiness
    case countdown
    case live
    case gameOver
    case won
}

private final class BallBlastRockDropCoordinator: ObservableObject {
    @Published private(set) var phase: BallBlastRockDropPhase = .readiness
    @Published private(set) var ballFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var isTracking = false
    @Published private(set) var trackingStatusText = "SEARCHING"
    @Published private(set) var confidenceText = "--"
    @Published private(set) var timerText = "60"
    @Published private(set) var survivedTimeText = "0s"
    @Published private(set) var activeRockCount = 0
    @Published private(set) var modeText = "READY"

    private let requiredBallLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 60.0
    private let lostBallPromptFrameThreshold = 18
    private let difficulty: BallBlastRockDropDifficulty

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var lostBallFrameCount = 0
    private var heldBallDisplayRect: CGRect?
    private var gameState: BallBlastRockDropGameState
    private weak var renderView: BallBlastRockDropRenderView?

    init(difficulty: BallBlastRockDropDifficulty) {
        self.difficulty = difficulty
        gameState = BallBlastRockDropGameState(config: difficulty.gameConfig)
    }

    func attach(renderView: BallBlastRockDropRenderView) {
        self.renderView = renderView
        renderView.update(
            rocks: gameState.rocks,
            ballDisplayRect: nil,
            isTracking: isTracking,
            prompt: promptText
        )
    }

    func reset(in size: CGSize) {
        self.size = size
        BallrDrillSoundPlayer.stopRockDropSounds()
        phase = .readiness
        ballFoundStartedAt = nil
        countdownStartedAt = nil
        isTracking = false
        trackingStatusText = "SEARCHING"
        confidenceText = "--"
        timerText = "60"
        survivedTimeText = "0s"
        activeRockCount = 0
        modeText = "READY"
        liveElapsed = 0
        lastStepAt = nil
        lostBallFrameCount = 0
        heldBallDisplayRect = nil
        gameState.reset()
        renderView?.update(
            rocks: gameState.rocks,
            ballDisplayRect: nil,
            isTracking: false,
            prompt: promptText
        )
    }

    func prepare(in size: CGSize) {
        self.size = size
        renderView?.update(
            rocks: gameState.rocks,
            ballDisplayRect: nil,
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
        trackingStatusText = statusText(for: overlayState.statusText, isHoldingBall: isHoldingBall)
        confidenceText = overlayState.confidence.map { String(format: "%.2f", $0) } ?? "--"

        guard phase != .gameOver, phase != .won else {
            renderView?.update(
                rocks: gameState.rocks,
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

        activeRockCount = gameState.rocks.count
        modeText = modeText(for: effectiveIsTracking)
        renderView?.update(
            rocks: gameState.rocks,
            ballDisplayRect: effectiveBallDisplayRect,
            isTracking: effectiveIsTracking,
            prompt: promptText
        )
    }

    private var isHoldingBall: Bool {
        heldBallDisplayRect != nil && lostBallFrameCount > 0 && lostBallFrameCount < lostBallPromptFrameThreshold
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

    private func statusText(for rawStatusText: String, isHoldingBall: Bool) -> String {
        isHoldingBall ? "HOLDING" : rawStatusText.uppercased()
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
                modeText = "DODGE"
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
            modeText = "PAUSED"
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
        case .collision:
            BallrDrillSoundPlayer.playRockHitBall()
            phase = .gameOver
            modeText = "HIT"
        case .none:
            if liveElapsed >= roundDuration {
                BallrDrillSoundPlayer.stopRockDropLoop()
                BallrDrillSoundPlayer.playWinner()
                phase = .won
                timerText = "0"
                survivedTimeText = "60s"
                modeText = "CLEAR"
            } else {
                modeText = "DODGE"
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
            return "So close, try again"
        case .won:
            return "You survived, Good job"
        }
    }

    private func modeText(for tracking: Bool) -> String {
        switch phase {
        case .readiness:
            return "READY"
        case .countdown:
            return "SET"
        case .live:
            return tracking ? "DODGE" : "PAUSED"
        case .gameOver:
            return "HIT"
        case .won:
            return "CLEAR"
        }
    }

    func stopSounds() {
        BallrDrillSoundPlayer.stopRockDropSounds()
    }
}

private struct BallBlastRockDropRenderSurface: UIViewRepresentable {
    let coordinator: BallBlastRockDropCoordinator

    func makeUIView(context: Context) -> BallBlastRockDropRenderView {
        let view = BallBlastRockDropRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: BallBlastRockDropRenderView, context: Context) {
    }
}

private final class BallBlastRockDropRenderView: UIView {
    private let ballRingLayer = CAShapeLayer()
    private let ballCenterLayer = CAShapeLayer()
    private let promptLabel = UILabel()

    private var rockLayers: [UUID: BallBlastRockLayerSet] = [:]
    private var rocks: [BallBlastRock] = []
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
        rocks: [BallBlastRock],
        ballDisplayRect: CGRect?,
        isTracking: Bool,
        prompt: String?
    ) {
        self.rocks = rocks
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
        ballRingLayer.fillColor = UIColor.clear.cgColor
        ballRingLayer.strokeColor = UIColor.white.cgColor
        ballRingLayer.lineWidth = 3
        ballRingLayer.shadowColor = UIColor.black.cgColor
        ballRingLayer.shadowOpacity = 0.45
        ballRingLayer.shadowRadius = 6
        ballRingLayer.shadowOffset = .zero
        ballCenterLayer.fillColor = UIColor.orange.cgColor
        layer.addSublayer(ballRingLayer)
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
        renderRocks()
        renderBall()
        renderPrompt()
        CATransaction.commit()
    }

    private func renderRocks() {
        let activeIDs = Set(rocks.map(\.id))
        let inactiveIDs = rockLayers.keys.filter { !activeIDs.contains($0) }
        for id in inactiveIDs {
            rockLayers[id]?.container.removeFromSuperlayer()
            rockLayers[id] = nil
        }

        for rock in rocks {
            let layerSet = rockLayers[rock.id] ?? makeRockLayerSet(for: rock)
            update(layerSet: layerSet, with: rock)
        }
    }

    private func makeRockLayerSet(for rock: BallBlastRock) -> BallBlastRockLayerSet {
        let container = CALayer()
        container.shadowColor = UIColor.black.cgColor
        container.shadowOpacity = 0.36
        container.shadowRadius = 8
        container.shadowOffset = CGSize(width: 0, height: 4)

        let body = CAShapeLayer()
        body.lineJoin = .round
        body.lineCap = .round
        body.fillColor = UIColor(red: 0.45, green: 0.47, blue: 0.50, alpha: 1).cgColor
        body.strokeColor = UIColor(red: 0.12, green: 0.13, blue: 0.14, alpha: 1).cgColor
        body.lineWidth = 4

        let highlight = CAShapeLayer()
        highlight.fillColor = UIColor.white.withAlphaComponent(0.28).cgColor

        let crack = CAShapeLayer()
        crack.fillColor = UIColor.clear.cgColor
        crack.strokeColor = UIColor(red: 0.18, green: 0.19, blue: 0.21, alpha: 0.82).cgColor
        crack.lineWidth = 3
        crack.lineCap = .round
        crack.lineJoin = .round

        container.addSublayer(body)
        container.addSublayer(highlight)
        container.addSublayer(crack)
        layer.insertSublayer(container, below: ballRingLayer)

        let set = BallBlastRockLayerSet(
            container: container,
            body: body,
            highlight: highlight,
            crack: crack
        )
        rockLayers[rock.id] = set
        return set
    }

    private func update(layerSet: BallBlastRockLayerSet, with rock: BallBlastRock) {
        let side = rock.radius * 2.35
        let bounds = CGRect(x: 0, y: 0, width: side, height: side)
        layerSet.container.bounds = bounds
        layerSet.container.position = rock.center
        layerSet.container.setAffineTransform(CGAffineTransform(rotationAngle: rock.rotation))

        let rockRect = bounds.insetBy(dx: side * 0.12, dy: side * 0.14)
        let rockPath = makeRockPath(in: rockRect, seed: rock.seed)
        layerSet.body.frame = bounds
        layerSet.body.path = rockPath.cgPath

        let highlightRect = CGRect(
            x: bounds.width * 0.33,
            y: bounds.height * 0.24,
            width: bounds.width * 0.24,
            height: bounds.height * 0.15
        )
        layerSet.highlight.frame = bounds
        layerSet.highlight.path = UIBezierPath(ovalIn: highlightRect).cgPath

        layerSet.crack.frame = bounds
        layerSet.crack.path = makeCrackPath(in: bounds, seed: rock.seed).cgPath
    }

    private func makeRockPath(in rect: CGRect, seed: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pointCount = 11
        for index in 0..<pointCount {
            let angle = (CGFloat(index) / CGFloat(pointCount)) * .pi * 2
            let wobble = 0.84
                + 0.12 * sin(seed * 1.7 + CGFloat(index) * 1.31)
                + 0.08 * cos(seed * 0.9 + CGFloat(index) * 2.11)
            let xRadius = rect.width * 0.5 * wobble
            let yRadius = rect.height * 0.5 * (0.92 + 0.10 * cos(seed + CGFloat(index)))
            let point = CGPoint(
                x: center.x + cos(angle) * xRadius,
                y: center.y + sin(angle) * yRadius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path
    }

    private func makeCrackPath(in bounds: CGRect, seed: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let start = CGPoint(x: bounds.midX + sin(seed) * bounds.width * 0.08, y: bounds.height * 0.34)
        path.move(to: start)
        path.addLine(to: CGPoint(x: bounds.midX - bounds.width * 0.06, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.midX + bounds.width * 0.05, y: bounds.midY + bounds.height * 0.14))
        path.move(to: CGPoint(x: bounds.midX - bounds.width * 0.05, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.midX - bounds.width * 0.18, y: bounds.midY + bounds.height * 0.05))
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

private struct BallBlastRockLayerSet {
    let container: CALayer
    let body: CAShapeLayer
    let highlight: CAShapeLayer
    let crack: CAShapeLayer
}

private struct BallBlastRockDropGameState {
    var rocks: [BallBlastRock] = []
    let config: BallBlastRockDropGameConfig

    private var nextSpawnElapsed: TimeInterval
    private var lastSpawnX: CGFloat?
    private var recentBallCenters: [CGPoint] = []

    init(config: BallBlastRockDropGameConfig) {
        self.config = config
        nextSpawnElapsed = config.initialSpawnDelay
    }

    mutating func reset() {
        rocks = []
        nextSpawnElapsed = config.initialSpawnDelay
        lastSpawnX = nil
        recentBallCenters.removeAll()
    }

    mutating func step(
        ballDisplayRect: CGRect,
        in size: CGSize,
        elapsed: TimeInterval,
        delta: TimeInterval
    ) -> BallBlastRockDropEvent? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let progress = min(max(elapsed / 60.0, 0), 1)
        recordBallCenter(from: ballDisplayRect)
        for index in rocks.indices {
            rocks[index].advance(delta: delta)
        }
        rocks.removeAll { $0.center.y - $0.radius > size.height + 80 }

        spawnRocksIfNeeded(in: size, elapsed: elapsed, progress: progress)

        guard collides(with: ballDisplayRect) else {
            return nil
        }
        return .collision
    }

    private mutating func spawnRocksIfNeeded(
        in size: CGSize,
        elapsed: TimeInterval,
        progress: Double
    ) {
        let maxRocks = Int(Double(config.maxRocksBase) + progress * Double(config.maxRocksRamp))
        while elapsed >= nextSpawnElapsed, rocks.count < maxRocks {
            spawnRock(in: size, progress: progress)
            let interval = Double.random(in: spawnIntervalRange(progress: progress))
            nextSpawnElapsed = elapsed + interval
        }
    }

    private mutating func spawnRock(in size: CGSize, progress: Double) {
        let minDimension = min(size.width, size.height)
        let radius = CGFloat.random(in: max(22, minDimension * 0.042)...max(34, minDimension * 0.085))
        let xBounds = (radius + 10)...(size.width - radius - 10)
        var x = spawnX(in: xBounds, radius: radius, progress: progress)
        if
            !shouldTargetRecentBall(progress: progress),
            let lastSpawnX,
            abs(x - lastSpawnX) < radius * 2.5
        {
            x = min(max(x + radius * 3.2, xBounds.lowerBound), xBounds.upperBound)
        }
        lastSpawnX = x

        let baseSpeed = CGFloat(config.speedBaseStart + progress * config.speedBaseRamp)
            * CGFloat(1.0 + progress * config.speedProgressMultiplier)
        let speed = baseSpeed * CGFloat.random(in: config.speedRandomRange)
        let radiusPadding = CGFloat.random(in: 0...80)
        rocks.append(
            BallBlastRock(
                center: CGPoint(x: x, y: -radius - radiusPadding),
                radius: radius,
                speed: speed,
                rotation: CGFloat.random(in: -.pi ... .pi),
                rotationSpeed: CGFloat.random(in: -1.6...1.6),
                seed: CGFloat.random(in: 0.1...20)
            )
        )
    }

    private func collides(with ballDisplayRect: CGRect) -> Bool {
        let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
        let ballRadius = max(ballDisplayRect.width, ballDisplayRect.height) * 0.5 * 0.74

        return rocks.contains { rock in
            let distance = hypot(ballCenter.x - rock.center.x, ballCenter.y - rock.center.y)
            return distance <= ballRadius + rock.collisionRadius
        }
    }

    private func spawnIntervalRange(progress: Double) -> ClosedRange<Double> {
        let minimum = max(0.20, config.spawnIntervalMinimumStart - progress * config.spawnIntervalMinimumRamp)
        let maximum = max(minimum + 0.08, config.spawnIntervalMaximumStart - progress * config.spawnIntervalMaximumRamp)
        return minimum...maximum
    }

    private mutating func recordBallCenter(from ballDisplayRect: CGRect) {
        recentBallCenters.append(CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY))
        if recentBallCenters.count > 36 {
            recentBallCenters.removeFirst(recentBallCenters.count - 36)
        }
    }

    private func spawnX(
        in bounds: ClosedRange<CGFloat>,
        radius: CGFloat,
        progress: Double
    ) -> CGFloat {
        if shouldTargetRecentBall(progress: progress), let targetX = targetedSpawnX(in: bounds, radius: radius) {
            return targetX
        }
        return CGFloat.random(in: bounds)
    }

    private func shouldTargetRecentBall(progress: Double) -> Bool {
        guard recentBallCenters.count >= 8 else {
            return false
        }
        let chance = min(config.targetChanceCap, config.targetChanceBase + progress * config.targetChanceRamp)
        return Double.random(in: 0...1) < chance
    }

    private func targetedSpawnX(in bounds: ClosedRange<CGFloat>, radius: CGFloat) -> CGFloat? {
        guard let clusterCenterX = recentStandingClusterX() else {
            return nil
        }

        let jitter = CGFloat.random(in: -radius * 1.15...radius * 1.15)
        return min(max(clusterCenterX + jitter, bounds.lowerBound), bounds.upperBound)
    }

    private func recentStandingClusterX() -> CGFloat? {
        let recent = recentBallCenters.suffix(18)
        guard recent.count >= 8 else {
            return nil
        }

        let averageX = recent.reduce(CGFloat.zero) { $0 + $1.x } / CGFloat(recent.count)
        let averageY = recent.reduce(CGFloat.zero) { $0 + $1.y } / CGFloat(recent.count)
        let spread = recent.reduce(CGFloat.zero) { partial, point in
            partial + hypot(point.x - averageX, point.y - averageY)
        } / CGFloat(recent.count)

        guard spread <= 95 else {
            return nil
        }
        return averageX
    }
}

private struct BallBlastRock: Identifiable {
    let id = UUID()
    var center: CGPoint
    let radius: CGFloat
    let speed: CGFloat
    var rotation: CGFloat
    let rotationSpeed: CGFloat
    let seed: CGFloat

    var collisionRadius: CGFloat {
        radius * 0.78
    }

    mutating func advance(delta: TimeInterval) {
        center.y += speed * CGFloat(delta)
        rotation += rotationSpeed * CGFloat(delta)
    }
}

private enum BallBlastRockDropEvent {
    case collision
}

private struct BallBlastRockDropHudChip: View {
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
                .stroke(tint.opacity(0.48), lineWidth: 1.5)
        )
    }
}

private struct BallBlastRockDropMiniHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.ballr(size: 9, weight: .black))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(value)
                .font(.ballr(size: 12, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(width: 72, height: 40, alignment: .leading)
        .padding(.horizontal, 9)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.76), lineWidth: 1.2)
        )
    }
}

private struct BallBlastRockDropLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting Rock Drop...")
                .font(.ballr(size: 16, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BallBlastRockDropErrorOverlay: View {
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

private struct BallBlastRockDropFinishedOverlay: View {
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
