import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct JumpingChallengeCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = JumpingPoseCameraController()
    @StateObject private var coordinator: JumpingChallengeCoordinator
    @State private var showsQuitConfirmation = false
    private let includesTimedHandTargets: Bool
    private let targetsFootX: Bool

    init(includesTimedHandTargets: Bool = false, targetsFootX: Bool = false) {
        self.includesTimedHandTargets = includesTimedHandTargets
        self.targetsFootX = targetsFootX
        _coordinator = StateObject(
            wrappedValue: JumpingChallengeCoordinator(
                includesTimedHandTargets: includesTimedHandTargets,
                targetsFootX: targetsFootX
            )
        )
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

                JumpingChallengeRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                if coordinator.phase == .readiness || coordinator.phase == .countdown || coordinator.phase == .live {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

                if cameraController.isStarting {
                    JumpingChallengeLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    JumpingChallengeErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.phase == .readiness, cameraController.errorMessage == nil {
                    JumpingChallengeReadinessOverlay(legsFoundStartedAt: coordinator.legsFoundStartedAt)
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                }

                if coordinator.phase == .gameOver {
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.finishStartedAt,
                        buttonsVisible: coordinator.showsFinishButtons,
                        title: "GAME OVER",
                        primaryTitle: "TRY AGAIN",
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

            HStack(spacing: 10) {
                if includesTimedHandTargets {
                    JumpingChallengeHudChip(title: "HITS", value: "\(coordinator.handHits)", tint: .yellow)
                }
                JumpingChallengeHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 18)
    }
}

private enum JumpingChallengePhase {
    case readiness
    case countdown
    case live
    case gameOver
    case won
}

private final class JumpingChallengeCoordinator: ObservableObject {
    @Published private(set) var phase: JumpingChallengePhase = .readiness
    @Published private(set) var legsFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var timerText = "60"
    @Published private(set) var survivedTimeText = "0s"
    @Published private(set) var handHits = 0
    @Published private(set) var finishStartedAt: Date?
    @Published private(set) var showsFinishButtons = false

    private let requiredLegLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 60.0
    private let finishAnimationDuration: TimeInterval = 2.05
    private let finishButtonRevealDelay: TimeInterval = 0.28
    private let lostLegPromptFrameThreshold = 12
    private let includesTimedHandTargets: Bool
    private let targetsFootX: Bool

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var lostLegFrameCount = 0
    private var lastDetectedLegs: [JumpingDetectedLeg] = []
    private var lastDetectedHands: [JumpingHandTargetHand] = []
    private var laneBaselineY: CGFloat?
    private var gameState = JumpingChallengeGameState()
    private var handTargetState = JumpingTimedHandTargetState()
    private var finishWorkItem: DispatchWorkItem?
    private weak var renderView: JumpingChallengeRenderView?

    init(includesTimedHandTargets: Bool = false, targetsFootX: Bool = false) {
        self.includesTimedHandTargets = includesTimedHandTargets
        self.targetsFootX = targetsFootX
    }

    func attach(renderView: JumpingChallengeRenderView) {
        self.renderView = renderView
        renderView.update(
            legs: lastDetectedLegs,
            obstacles: gameState.obstacles,
            hands: lastDetectedHands,
            handTarget: includesTimedHandTargets ? handTargetState.target : nil,
            handPopups: handTargetState.scorePopups,
            prompt: promptText,
            groundLineY: resolvedGroundLine(for: size)
        )
    }

    func tearDown() {
        cancelFinishWorkItem()
    }

    func reset(in size: CGSize) {
        cancelFinishWorkItem()
        self.size = size
        phase = .readiness
        legsFoundStartedAt = nil
        countdownStartedAt = nil
        timerText = "60"
        survivedTimeText = "0s"
        handHits = 0
        finishStartedAt = nil
        showsFinishButtons = false
        liveElapsed = 0
        lastStepAt = nil
        lostLegFrameCount = 0
        lastDetectedLegs = []
        lastDetectedHands = []
        laneBaselineY = nil
        gameState.reset()
        handTargetState.reset()
        renderView?.update(
            legs: lastDetectedLegs,
            obstacles: gameState.obstacles,
            hands: lastDetectedHands,
            handTarget: includesTimedHandTargets ? handTargetState.target : nil,
            handPopups: handTargetState.scorePopups,
            prompt: promptText,
            groundLineY: resolvedGroundLine(for: size)
        )
    }

    func prepare(in size: CGSize) {
        self.size = resolvedGameplaySize(fallback: size)
        renderView?.update(
            legs: lastDetectedLegs,
            obstacles: gameState.obstacles,
            hands: lastDetectedHands,
            handTarget: includesTimedHandTargets ? handTargetState.target : nil,
            handPopups: handTargetState.scorePopups,
            prompt: promptText,
            groundLineY: resolvedGroundLine(for: self.size)
        )
    }

    func handle(frame: JumpingChallengeFrame, cameraController: JumpingPoseCameraController) {
        let detectedLegs = frame.overlayState.legs.compactMap { legState -> JumpingDetectedLeg? in
            guard let displayRect = cameraController.displayRect(for: legState.normalizedRect) else {
                return nil
            }
            let displayPoints = legState.normalizedPoints.compactMap {
                cameraController.displayPoint(for: $0)
            }
            return JumpingDetectedLeg(
                id: legState.id,
                rect: displayRect,
                collisionPolygon: JumpingDetectedLeg.collisionPolygon(
                    from: displayPoints,
                    fallbackRect: displayRect
                ),
                footRect: cameraController.displayRect(for: legState.normalizedFootRect) ?? displayRect,
                footCollisionPolygon: JumpingDetectedLeg.collisionPolygon(
                    from: legState.normalizedFootPoints.compactMap {
                        cameraController.displayPoint(for: $0)
                    },
                    fallbackRect: cameraController.displayRect(for: legState.normalizedFootRect) ?? displayRect
                ),
                confidence: CGFloat(legState.confidence)
            )
        }
        lastDetectedLegs = detectedLegs
        let detectedHands = frame.handOverlayState.hands.compactMap { handState -> JumpingHandTargetHand? in
            guard let displayRect = cameraController.displayRect(for: handState.normalizedRect) else {
                return nil
            }
            let displayPoints = handState.normalizedPoints.compactMap {
                cameraController.displayPoint(for: $0)
            }
            return JumpingHandTargetHand(
                id: handState.id,
                rect: displayRect,
                collisionPolygon: JumpingHandTargetHand.collisionPolygon(from: displayPoints, fallbackRect: displayRect)
            )
        }
        lastDetectedHands = detectedHands

        let hasTrackedLegs = detectedLegs.count >= 2
        if hasTrackedLegs {
            lostLegFrameCount = 0
            updateLaneBaseline(using: detectedLegs)
        } else if phase == .live {
            lostLegFrameCount += 1
        }

        guard phase != .gameOver, phase != .won else {
            renderView?.update(
                legs: detectedLegs,
                obstacles: gameState.obstacles,
                hands: detectedHands,
                handTarget: includesTimedHandTargets ? handTargetState.target : nil,
                handPopups: handTargetState.scorePopups,
                prompt: promptText,
                groundLineY: resolvedGroundLine(for: size)
            )
            return
        }

        updateStartGate(isTracking: hasTrackedLegs, timestamp: frame.timestamp)

        if phase == .live {
            let previousStepAt = lastStepAt ?? frame.timestamp
            let deltaTime = min(max(frame.timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
            lastStepAt = frame.timestamp

            let effectiveSize = resolvedGameplaySize(fallback: size)
            let event = gameState.step(
                deltaTime: deltaTime,
                elapsed: liveElapsed,
                in: effectiveSize,
                groundLineY: resolvedGroundLine(for: effectiveSize),
                legs: detectedLegs,
                isTracking: hasTrackedLegs,
                targetsFootX: targetsFootX
            )
            if includesTimedHandTargets {
                let handEvent = handTargetState.step(
                    hands: detectedHands,
                    isTracking: frame.handOverlayState.isTracking,
                    in: effectiveSize,
                    timestamp: frame.timestamp
                )
                if handEvent == .hit {
                    handHits += 1
                    JumpingHandTargetSoundPlayer.playScore()
                } else if handEvent == .miss {
                    BallrDrillSoundPlayer.playIncorrect()
                }
            }

            liveElapsed = min(liveElapsed + deltaTime, roundDuration)
            timerText = String(Int(ceil(max(roundDuration - liveElapsed, 0))))
            survivedTimeText = "\(Int(liveElapsed.rounded(.down)))s"

            if event == .collision {
                finish(as: .gameOver, at: frame.timestamp)
            } else if liveElapsed >= roundDuration {
                finish(as: .won, at: frame.timestamp)
            }
        }

        renderView?.update(
            legs: detectedLegs,
            obstacles: gameState.obstacles,
            hands: detectedHands,
            handTarget: includesTimedHandTargets ? handTargetState.target : nil,
            handPopups: handTargetState.scorePopups,
            prompt: promptText,
            groundLineY: resolvedGroundLine(for: size)
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

    private func updateStartGate(isTracking: Bool, timestamp: Date) {
        if phase == .live || phase == .gameOver || phase == .won {
            return
        }

        if phase == .countdown {
            if
                let countdownStartedAt,
                timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration
            {
                phase = .live
                lastStepAt = timestamp
                liveElapsed = 0
                timerText = "60"
                survivedTimeText = "0s"
                gameState.start(
                    in: resolvedGameplaySize(fallback: size),
                    groundLineY: resolvedGroundLine(for: resolvedGameplaySize(fallback: size))
                )
                if includesTimedHandTargets {
                    handTargetState.prepare(
                        in: resolvedGameplaySize(fallback: size),
                        timestamp: timestamp,
                        forceRespawn: true,
                        allowSpawn: true
                    )
                }
            }
            return
        }

        guard isTracking else {
            legsFoundStartedAt = nil
            return
        }

        let startedAt = legsFoundStartedAt ?? timestamp
        legsFoundStartedAt = startedAt

        if timestamp.timeIntervalSince(startedAt) >= requiredLegLockSeconds {
            countdownStartedAt = timestamp
            phase = .countdown
        }
    }

    private func finish(as finishPhase: JumpingChallengePhase, at timestamp: Date) {
        guard phase != .gameOver, phase != .won else {
            return
        }

        phase = finishPhase
        finishStartedAt = timestamp
        gameState.finish()
        handTargetState.finish()

        if finishPhase == .won {
            BallrDrillSoundPlayer.playWinner()
        }

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

    private func updateLaneBaseline(using legs: [JumpingDetectedLeg]) {
        guard let maxBottom = legs.map(\.footCollisionBounds.maxY).max() else {
            return
        }

        let clampedBaseline = maxBottom + 6
        if let laneBaselineY {
            let blend: CGFloat = phase == .readiness ? 0.24 : 0.14
            self.laneBaselineY = laneBaselineY + (clampedBaseline - laneBaselineY) * blend
        } else {
            laneBaselineY = clampedBaseline
        }
    }

    private func resolvedGroundLine(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else {
            return 0
        }

        let fallback = size.height * 0.82
        let baseline = laneBaselineY ?? fallback
        return min(max(baseline, size.height * 0.62), size.height * 0.92)
    }

    private var promptText: String? {
        guard phase == .live, lostLegFrameCount >= lostLegPromptFrameThreshold else {
            return nil
        }
        return "Find both feet"
    }
}

private struct JumpingChallengeRenderSurface: UIViewRepresentable {
    let coordinator: JumpingChallengeCoordinator

    func makeUIView(context: Context) -> JumpingChallengeRenderView {
        let view = JumpingChallengeRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: JumpingChallengeRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class JumpingChallengeRenderView: UIView {
    private var legs: [JumpingDetectedLeg] = []
    private var obstacles: [JumpingObstacle] = []
    private var hands: [JumpingHandTargetHand] = []
    private var handTarget: JumpingHandTarget?
    private var handPopups: [JumpingHandScorePopup] = []
    private var prompt: String?
    private var groundLineY: CGFloat = 0
    private let promptLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        promptLabel.font = .systemFont(ofSize: 16, weight: .black)
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        promptLabel.layer.cornerRadius = 10
        promptLabel.layer.masksToBounds = true
        promptLabel.isHidden = true
        addSubview(promptLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        legs: [JumpingDetectedLeg],
        obstacles: [JumpingObstacle],
        hands: [JumpingHandTargetHand],
        handTarget: JumpingHandTarget?,
        handPopups: [JumpingHandScorePopup],
        prompt: String?,
        groundLineY: CGFloat
    ) {
        self.legs = legs
        self.obstacles = obstacles
        self.hands = hands
        self.handTarget = handTarget
        self.handPopups = handPopups
        self.prompt = prompt
        self.groundLineY = groundLineY
        promptLabel.text = prompt
        promptLabel.isHidden = prompt == nil
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        promptLabel.frame = CGRect(
            x: max((bounds.width - 180) * 0.5, 16),
            y: 84,
            width: min(180, bounds.width - 32),
            height: 38
        )
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        drawGroundLine(in: context)
        drawFeet(in: context)
        drawObstacles(in: context)
        drawHandTarget(in: context, date: Date())
        drawHandPopups(in: context, date: Date())
    }

    private func drawHandTarget(in context: CGContext, date: Date) {
        guard let handTarget else {
            return
        }
        let rect = CGRect(
            x: handTarget.center.x - handTarget.radius,
            y: handTarget.center.y - handTarget.radius,
            width: handTarget.radius * 2,
            height: handTarget.radius * 2
        )
        let progress = handTarget.progress(at: date)
        let remaining = max(CGFloat(0.02), 1 - CGFloat(progress))
        context.saveGState()
        context.setShadow(offset: .zero, blur: 16, color: UIColor.systemYellow.withAlphaComponent(0.44).cgColor)
        UIColor.black.withAlphaComponent(0.22).setFill()
        UIBezierPath(ovalIn: rect).fill()
        UIColor.systemYellow.withAlphaComponent(0.82).setStroke()
        let outer = UIBezierPath(ovalIn: rect)
        outer.lineWidth = 8
        outer.stroke()
        UIColor.orange.withAlphaComponent(0.94).setStroke()
        let inner = UIBezierPath(ovalIn: rect.insetBy(dx: 8, dy: 8))
        inner.lineWidth = 4
        inner.stroke()
        UIColor.white.withAlphaComponent(0.95).setStroke()
        let progressPath = UIBezierPath(
            arcCenter: handTarget.center,
            radius: max(handTarget.radius - 16, 1),
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + .pi * 2 * remaining,
            clockwise: true
        )
        progressPath.lineWidth = 4
        progressPath.lineCapStyle = .round
        progressPath.stroke()
        context.restoreGState()
    }

    private func drawHandPopups(in context: CGContext, date: Date) {
        for popup in handPopups where popup.isActive(at: date) {
            let progress = popup.progress(at: date)
            let eased = CGFloat(progress * progress * (3 - 2 * progress))
            let y = popup.center.y - 48 * eased
            let alpha = 1 - CGFloat(progress)
            let text = "+1" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 34, weight: .black),
                .foregroundColor: UIColor.systemYellow.withAlphaComponent(alpha)
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: CGPoint(x: popup.center.x - size.width * 0.5, y: y - size.height * 0.5),
                withAttributes: attributes
            )
        }
    }

    private func drawGroundLine(in context: CGContext) {
        guard groundLineY > 0 else {
            return
        }

        context.saveGState()
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.18).cgColor)
        context.setLineWidth(3)
        context.setLineDash(phase: 0, lengths: [10, 10])
        context.move(to: CGPoint(x: 24, y: groundLineY + 4))
        context.addLine(to: CGPoint(x: bounds.width - 24, y: groundLineY + 4))
        context.strokePath()
        context.restoreGState()
    }

    private func drawFeet(in context: CGContext) {
        for leg in legs {
            let bounds = leg.footCollisionBounds

            let path = UIBezierPath()
            guard let first = leg.footCollisionPolygon.first else {
                continue
            }
            path.move(to: first)
            for point in leg.footCollisionPolygon.dropFirst() {
                path.addLine(to: point)
            }
            path.close()

            context.saveGState()
            context.setFillColor(UIColor.white.withAlphaComponent(0.10).cgColor)
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.32).cgColor)
            context.setLineWidth(3)
            context.addPath(path.cgPath)
            context.drawPath(using: .fillStroke)
            context.restoreGState()

            context.saveGState()
            context.setShadow(offset: .zero, blur: 14, color: UIColor.systemYellow.withAlphaComponent(0.34).cgColor)
            context.setStrokeColor(UIColor.systemYellow.withAlphaComponent(0.92).cgColor)
            context.setLineWidth(2)
            context.stroke(
                bounds.insetBy(dx: 3, dy: 3),
                width: 2
            )
            context.restoreGState()

            UIColor.white.withAlphaComponent(0.88).setFill()
            UIBezierPath(
                ovalIn: CGRect(
                    x: bounds.midX - 4,
                    y: bounds.maxY - 10,
                    width: 8,
                    height: 8
                )
            )
            .fill()
        }
    }

    private func drawObstacles(in context: CGContext) {
        for obstacle in obstacles {
            drawObstacle(obstacle, in: context)
        }
    }

    private func drawObstacle(_ obstacle: JumpingObstacle, in context: CGContext) {
        let rect = obstacle.rect
        let baseCenter = CGPoint(x: rect.midX, y: rect.maxY)
        let rotation = sin(Date().timeIntervalSinceReferenceDate * 7.0 + Double(obstacle.animationPhase)) * (.pi / 10.0)
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: 8),
            blur: 14,
            color: UIColor(red: 1.0, green: 0.28, blue: 0.0, alpha: 0.42).cgColor
        )
        drawCone(
            in: context,
            baseCenter: baseCenter,
            baseWidth: rect.width,
            height: rect.height,
            rotation: rotation
        )
        context.restoreGState()
    }

    private func drawCone(
        in context: CGContext,
        baseCenter: CGPoint,
        baseWidth: CGFloat,
        height: CGFloat,
        rotation: CGFloat
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
        drawConeStripe(centerX: baseCenter.x, y: topY + coneHeight * 0.40, width: bottomWidth * 0.80, height: coneHeight * 0.14)
        drawConeStripe(centerX: baseCenter.x, y: topY + coneHeight * 0.68, width: bottomWidth * 0.92, height: coneHeight * 0.15)
        context.restoreGState()

        let topOval = UIBezierPath(ovalIn: CGRect(
            x: baseCenter.x - topWidth * 0.5,
            y: topY - topWidth * 0.18,
            width: topWidth,
            height: topWidth * 0.36
        ))
        UIColor(red: 0.45, green: 0.12, blue: 0.02, alpha: 0.70).setFill()
        topOval.fill()
        context.restoreGState()
    }

    private func drawConeStripe(centerX: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        let stripe = UIBezierPath(roundedRect: CGRect(
            x: centerX - width * 0.5,
            y: y - height * 0.5,
            width: width,
            height: height
        ), cornerRadius: height * 0.45)
        UIColor.white.withAlphaComponent(0.92).setFill()
        stripe.fill()
    }
}

private struct JumpingDetectedLeg: Identifiable {
    let id: Int
    let rect: CGRect
    let collisionPolygon: [CGPoint]
    let footRect: CGRect
    let footCollisionPolygon: [CGPoint]
    let confidence: CGFloat

    var collisionBounds: CGRect {
        Self.boundingRect(for: collisionPolygon) ?? rect
    }

    var footCollisionBounds: CGRect {
        Self.boundingRect(for: footCollisionPolygon) ?? footRect
    }

    static func collisionPolygon(from points: [CGPoint], fallbackRect: CGRect) -> [CGPoint] {
        guard points.count >= 4 else {
            return [
                CGPoint(x: fallbackRect.minX, y: fallbackRect.minY),
                CGPoint(x: fallbackRect.maxX, y: fallbackRect.minY),
                CGPoint(x: fallbackRect.maxX, y: fallbackRect.maxY),
                CGPoint(x: fallbackRect.minX, y: fallbackRect.maxY)
            ]
        }
        return points
    }

    static func boundingRect(for points: [CGPoint]) -> CGRect? {
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

private struct JumpingHandTargetHand: Identifiable {
    let id: Int
    let rect: CGRect
    let collisionPolygon: [CGPoint]

    var collisionBounds: CGRect {
        JumpingDetectedLeg.boundingRect(for: collisionPolygon) ?? rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)
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
        let sortedPoints = points.sorted {
            abs($0.x - $1.x) > 0.001 ? $0.x < $1.x : $0.y < $1.y
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
        let centroid = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let center = CGPoint(x: centroid.x / CGFloat(points.count), y: centroid.y / CGFloat(points.count))
        return points.map { CGPoint(x: center.x + ($0.x - center.x) * factor, y: center.y + ($0.y - center.y) * factor) }
    }
}

private enum JumpingHandTargetEvent {
    case hit
    case miss
}

private struct JumpingTimedHandTargetState {
    private(set) var target: JumpingHandTarget?
    private(set) var scorePopups: [JumpingHandScorePopup] = []
    private let lifetime: TimeInterval = 3.0

    mutating func reset() {
        target = nil
        scorePopups = []
    }

    mutating func finish() {
        target = nil
    }

    mutating func prepare(in size: CGSize, timestamp: Date, forceRespawn: Bool = false, allowSpawn: Bool = true) {
        guard allowSpawn, size.width > 0, size.height > 0 else {
            target = nil
            return
        }
        if target == nil || forceRespawn {
            spawn(in: size, timestamp: timestamp, previousCenter: target?.center)
        }
    }

    mutating func step(
        hands: [JumpingHandTargetHand],
        isTracking: Bool,
        in size: CGSize,
        timestamp: Date
    ) -> JumpingHandTargetEvent? {
        scorePopups.removeAll { !$0.isActive(at: timestamp) }
        prepare(in: size, timestamp: timestamp)
        guard let currentTarget = target else {
            return nil
        }
        if currentTarget.progress(at: timestamp) >= 1 {
            spawn(in: size, timestamp: timestamp, previousCenter: currentTarget.center)
            return .miss
        }
        guard isTracking else {
            return nil
        }
        if hands.contains(where: { distance(from: currentTarget.center, to: $0) <= currentTarget.radius }) {
            scorePopups.append(JumpingHandScorePopup(center: currentTarget.center, startedAt: timestamp))
            spawn(in: size, timestamp: timestamp, previousCenter: currentTarget.center)
            return .hit
        }
        return nil
    }

    private mutating func spawn(in size: CGSize, timestamp: Date, previousCenter: CGPoint?) {
        let radius = min(max(min(size.width, size.height) * 0.074, 30), 52)
        let minX = radius + 32
        let maxX = max(minX, size.width - radius - 32)
        let minY = radius + 26
        let maxY = max(minY, size.height * 0.42)
        var best = CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
        var bestDistance: CGFloat = 0
        for _ in 0..<28 {
            let candidate = CGPoint(x: CGFloat.random(in: minX...maxX), y: CGFloat.random(in: minY...maxY))
            let distance = previousCenter.map { hypot(candidate.x - $0.x, candidate.y - $0.y) } ?? radius * 5
            if distance > bestDistance {
                bestDistance = distance
                best = candidate
            }
        }
        target = JumpingHandTarget(center: best, radius: radius, spawnedAt: timestamp, lifetime: lifetime)
    }

    private func distance(from point: CGPoint, to hand: JumpingHandTargetHand) -> CGFloat {
        let bounds = hand.collisionBounds
        let clampedX = min(max(point.x, bounds.minX), bounds.maxX)
        let clampedY = min(max(point.y, bounds.minY), bounds.maxY)
        return hypot(point.x - clampedX, point.y - clampedY)
    }
}

private struct JumpingHandTarget {
    let center: CGPoint
    let radius: CGFloat
    let spawnedAt: Date
    let lifetime: TimeInterval

    func progress(at timestamp: Date) -> Double {
        min(max(timestamp.timeIntervalSince(spawnedAt) / lifetime, 0), 1)
    }
}

private struct JumpingHandScorePopup: Identifiable {
    let id = UUID()
    let center: CGPoint
    let startedAt: Date

    func progress(at timestamp: Date) -> Double {
        min(max(timestamp.timeIntervalSince(startedAt) / 0.75, 0), 1)
    }

    func isActive(at timestamp: Date) -> Bool {
        progress(at: timestamp) < 1
    }
}

private enum JumpingHandTargetSoundPlayer {
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
                return
            }
        }
        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}

private enum JumpingChallengeEvent {
    case collision
}

private struct JumpingChallengeGameState {
    private(set) var obstacles: [JumpingObstacle] = []
    private var timeUntilNextSpawn: TimeInterval = 2.6
    private var didStart = false
    private var isFinished = false
    private let groundCalibrationDuration: TimeInterval = 1.0
    private let minimumGroundCalibrationSamples = 4
    private var groundCalibrationSamples: [CGFloat] = []
    private var calibratedGroundLineY: CGFloat?

    mutating func start(in size: CGSize, groundLineY: CGFloat) {
        obstacles = []
        timeUntilNextSpawn = 2.6
        didStart = true
        isFinished = false
        groundCalibrationSamples = []
        calibratedGroundLineY = nil
    }

    mutating func reset() {
        obstacles = []
        timeUntilNextSpawn = 2.6
        didStart = false
        isFinished = false
        groundCalibrationSamples = []
        calibratedGroundLineY = nil
    }

    mutating func finish() {
        isFinished = true
    }

    mutating func step(
        deltaTime: TimeInterval,
        elapsed: TimeInterval,
        in size: CGSize,
        groundLineY: CGFloat,
        legs: [JumpingDetectedLeg],
        isTracking: Bool,
        targetsFootX: Bool
    ) -> JumpingChallengeEvent? {
        guard didStart, !isFinished, size.width > 0, size.height > 0 else {
            return nil
        }

        let progress = min(max(elapsed / 60.0, 0), 1)
        if elapsed <= groundCalibrationDuration, isTracking {
            recordGroundCalibrationSample(from: legs)
        }
        let obstacleGroundLineY = resolvedObstacleGroundLine(fallback: groundLineY, in: size)

        for index in obstacles.indices {
            obstacles[index].rect.origin.x += obstacles[index].speed * deltaTime
        }
        obstacles.removeAll { $0.rect.minX > size.width + 80 }

        timeUntilNextSpawn -= deltaTime
        while timeUntilNextSpawn <= 0 {
            spawnObstacle(
                in: size,
                groundLineY: obstacleGroundLineY,
                progress: progress,
                targetFootX: targetsFootX && isTracking ? targetFootX(from: legs, in: size) : nil
            )
            timeUntilNextSpawn += nextSpawnInterval(progress: progress)
        }

        guard isTracking else {
            return nil
        }

        if obstacles.contains(where: { obstacleIntersectsFeet($0, legs: legs) }) {
            isFinished = true
            return .collision
        }

        return nil
    }

    private mutating func spawnObstacle(
        in size: CGSize,
        groundLineY: CGFloat,
        progress: CGFloat,
        targetFootX: CGFloat? = nil
    ) {
        let height = size.height * 0.765 * CGFloat.random(in: (0.095 + progress * 0.018)...(0.125 + progress * 0.022))
        let width = height * 1.20 * CGFloat.random(in: 1.05...1.38)
        let startX = -width - 36
        let baseY = min(max(groundLineY, height), size.height)
        let rect = CGRect(
            x: startX,
            y: baseY - height,
            width: width,
            height: height
        )
        let speed: CGFloat
        if let targetFootX {
            let travelTime = max(1.32, 1.85 - progress * 0.24)
            let targetCenterX = min(max(targetFootX, width * 0.5), size.width - width * 0.5)
            let startCenterX = startX + width * 0.5
            let targetedSpeed = (targetCenterX - startCenterX) / travelTime
            let minSpeed = size.width * (0.24 + progress * 0.08)
            let maxSpeed = size.width * (0.52 + progress * 0.12) * 0.65
            speed = min(max(targetedSpeed, minSpeed), maxSpeed) * 0.85
        } else {
            let minSpeedFactor = 0.28 + progress * 0.11
            let maxSpeedFactor = max(minSpeedFactor, (0.34 + progress * 0.13) * 0.65)
            speed = size.width * 0.85 * CGFloat.random(in: minSpeedFactor...maxSpeedFactor)
        }

        obstacles.append(
            JumpingObstacle(
                rect: rect,
                speed: speed,
                animationPhase: CGFloat.random(in: 0...(.pi * 2))
            )
        )
    }

    private mutating func recordGroundCalibrationSample(from legs: [JumpingDetectedLeg]) {
        let footBottoms = legs
            .map(\.footCollisionBounds)
            .filter { !$0.isNull && !$0.isEmpty }
            .map(\.maxY)
        guard let lowestFootY = footBottoms.max() else {
            return
        }

        groundCalibrationSamples.append(lowestFootY)
        if groundCalibrationSamples.count >= minimumGroundCalibrationSamples {
            calibratedGroundLineY = groundCalibrationSamples.reduce(CGFloat.zero, +) / CGFloat(groundCalibrationSamples.count)
        }
    }

    private func resolvedObstacleGroundLine(fallback: CGFloat, in size: CGSize) -> CGFloat {
        let baseline = calibratedGroundLineY ?? fallback
        return min(max(baseline, size.height * 0.62), size.height * 0.94)
    }

    private func nextSpawnInterval(progress: CGFloat) -> TimeInterval {
        let fastConeGapMultiplier = 1.55 + progress * 0.25
        let minGap = max(1.28, 1.95 - progress * 0.32) * 1.20 * fastConeGapMultiplier
        let maxGap = max(minGap + 0.28, (2.60 - progress * 0.42) * 1.20 * fastConeGapMultiplier)
        return Double.random(in: minGap...maxGap)
    }

    private func targetFootX(from legs: [JumpingDetectedLeg], in size: CGSize) -> CGFloat? {
        let trackedLegCenters = legs
            .map(\.footCollisionBounds)
            .filter { !$0.isNull && !$0.isEmpty }
            .map(\.midX)

        guard !trackedLegCenters.isEmpty else {
            return nil
        }

        let averageX = trackedLegCenters.reduce(CGFloat.zero, +) / CGFloat(trackedLegCenters.count)
        return min(max(averageX, size.width * 0.08), size.width * 0.92)
    }

    private func obstacleIntersectsFeet(_ obstacle: JumpingObstacle, legs: [JumpingDetectedLeg]) -> Bool {
        let collisionRect = obstacle.rect.insetBy(dx: 8, dy: 8)
        return legs.contains { leg in
            obstacleOverlapExceedsThreshold(collisionRect, foot: leg)
        }
    }

    private func obstacleOverlapExceedsThreshold(_ obstacleRect: CGRect, foot leg: JumpingDetectedLeg) -> Bool {
        obstacleOverlapExceedsThreshold(
            obstacleRect,
            regionBounds: leg.footCollisionBounds.insetBy(dx: 1, dy: 1),
            polygon: leg.footCollisionPolygon,
            minimumOverlapRatio: 0.08
        )
    }

    private func obstacleOverlapExceedsThreshold(
        _ obstacleRect: CGRect,
        regionBounds: CGRect,
        polygon: [CGPoint],
        minimumOverlapRatio: CGFloat
    ) -> Bool {
        guard !regionBounds.isNull, !regionBounds.isEmpty else {
            return false
        }

        let overlapRect = obstacleRect.intersection(regionBounds)
        guard !overlapRect.isNull, !overlapRect.isEmpty else {
            return false
        }

        let overlapArea = overlapRect.width * overlapRect.height
        let obstacleArea = obstacleRect.width * obstacleRect.height
        let regionArea = regionBounds.width * regionBounds.height
        let referenceArea = min(obstacleArea, regionArea)
        guard referenceArea > 0 else {
            return false
        }

        let overlapRatio = overlapArea / referenceArea
        guard overlapRatio >= minimumOverlapRatio else {
            return false
        }

        return polygonIntersectsRect(polygon, rect: overlapRect)
    }

    private func polygonIntersectsRect(_ polygon: [CGPoint], rect: CGRect) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }

        if polygon.contains(where: { rect.contains($0) }) {
            return true
        }

        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]

        if corners.contains(where: { pointInPolygon($0, polygon: polygon) }) {
            return true
        }

        let polygonEdges = zip(polygon, polygon.dropFirst() + [polygon[0]])
        let rectEdges = [
            (corners[0], corners[1]),
            (corners[1], corners[2]),
            (corners[2], corners[3]),
            (corners[3], corners[0])
        ]

        for (a1, a2) in polygonEdges {
            for (b1, b2) in rectEdges where segmentsIntersect(a1, a2, b1, b2) {
                return true
            }
        }

        return false
    }

    private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var contains = false
        var previous = polygon.last!

        for current in polygon {
            let intersects = ((current.y > point.y) != (previous.y > point.y))
                && (point.x < (previous.x - current.x) * (point.y - current.y) / max(previous.y - current.y, 0.0001) + current.x)
            if intersects {
                contains.toggle()
            }
            previous = current
        }

        return contains
    }

    private func segmentsIntersect(_ p1: CGPoint, _ p2: CGPoint, _ q1: CGPoint, _ q2: CGPoint) -> Bool {
        func orientation(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
            (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        }

        let o1 = orientation(p1, p2, q1)
        let o2 = orientation(p1, p2, q2)
        let o3 = orientation(q1, q2, p1)
        let o4 = orientation(q1, q2, p2)

        if (o1 > 0 && o2 < 0 || o1 < 0 && o2 > 0), (o3 > 0 && o4 < 0 || o3 < 0 && o4 > 0) {
            return true
        }

        return false
    }
}

private enum JumpingObstacleLane: CaseIterable {
    case bottom

    func originY(in size: CGSize, height: CGFloat) -> CGFloat {
        max(size.height * 0.87 - height, 0)
    }
}

private struct JumpingObstacle: Identifiable {
    let id = UUID()
    var rect: CGRect
    let speed: CGFloat
    let animationPhase: CGFloat
}

private struct JumpingChallengeHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.ballr(size: 11, weight: .black))
                .foregroundStyle(.white.opacity(0.68))

            Text(value)
                .font(.ballr(size: 26, weight: .black))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct JumpingChallengeLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.86)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.yellow)
                    .scaleEffect(1.4)

                Text("Starting camera...")
                    .font(.ballr(size: 24, weight: .black))
                    .foregroundStyle(.white)
            }
        }
    }
}

private struct JumpingChallengeErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.94)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text(permissionDenied ? "CAMERA ACCESS NEEDED" : "CAMERA ERROR")
                    .font(.ballr(size: 28, weight: .black))
                    .foregroundStyle(Color.yellow)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.ballr(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("CLOSE")
                        .font(.ballr(size: 16, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 148, height: 50)
                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct JumpingChallengeReadinessOverlay: View {
    let legsFoundStartedAt: Date?
    private let requiredLockSeconds: TimeInterval

    init(legsFoundStartedAt: Date?, requiredLockSeconds: TimeInterval = 3.0) {
        self.legsFoundStartedAt = legsFoundStartedAt
        self.requiredLockSeconds = requiredLockSeconds
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = readinessProgress(at: timeline.date)

            ZStack {
                Color.black.opacity(0.86)
                    .ignoresSafeArea()

                if legsFoundStartedAt == nil {
                    VStack(spacing: 14) {
                        Text("Find both feet")
                            .font(.ballr(size: 36, weight: .black))
                            .foregroundStyle(Color.yellow)

                        Text("Stand sideways with both feet visible, then hold still.")
                            .font(.ballr(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 18) {
                        Text("Hold still")
                            .font(.ballr(size: 34, weight: .black))
                            .foregroundStyle(.white)

                        Text("Starting in \(remainingText(at: timeline.date))")
                            .font(.ballr(size: 18, weight: .bold))
                            .foregroundStyle(Color.yellow)

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(width: 230, height: 16)

                            Capsule()
                                .fill(Color.yellow)
                                .frame(width: 230 * progress, height: 16)
                        }
                    }
                    .padding(.horizontal, 24)
                }
            }
        }
    }

    private func readinessProgress(at date: Date) -> CGFloat {
        guard let legsFoundStartedAt else {
            return 0
        }
        return CGFloat(min(max(date.timeIntervalSince(legsFoundStartedAt) / requiredLockSeconds, 0), 1))
    }

    private func remainingText(at date: Date) -> String {
        guard let legsFoundStartedAt else {
            return "3"
        }
        let remaining = max(ceil(requiredLockSeconds - date.timeIntervalSince(legsFoundStartedAt)), 0)
        return "\(Int(remaining))"
    }
}

private struct JumpingChallengeFinishedOverlay: View {
    let title: String
    let subtitle: String
    let timeText: String
    let primaryTitle: String
    let onPrimary: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                Text(title)
                    .font(.ballr(size: 46, weight: .black))
                    .foregroundStyle(Color.yellow)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.ballr(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                Text(timeText)
                    .font(.ballr(size: 32, weight: .black))
                    .foregroundStyle(.orange)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    Button(action: onDone) {
                        Text("DONE")
                            .font(.ballr(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: onPrimary) {
                        Text(primaryTitle)
                            .font(.ballr(size: 15, weight: .black))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: 360)
                .padding(.top, 8)

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }
}
