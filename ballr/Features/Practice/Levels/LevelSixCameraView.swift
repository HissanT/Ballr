import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct LevelSixCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = LevelSixCoordinator()
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

                LevelSixRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                if !coordinator.hasEnded {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                if cameraController.isStarting {
                    LevelSixLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    LevelSixErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.startPhase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                } else if coordinator.startPhase == .readiness, cameraController.errorMessage == nil {
                    BallrDrillReadinessOverlay(ballFoundStartedAt: coordinator.ballFoundStartedAt)
                }

                if coordinator.hasEnded {
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.finishStartedAt,
                        buttonsVisible: coordinator.showsFinishButtons,
                        title: coordinator.finishTitle,
                        primaryTitle: "TRY AGAIN",
                        showsNextLevelButton: coordinator.didComplete,
                        onNextLevel: { showsNextLevel = true },
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .navigationDestination(isPresented: $showsNextLevel) {
                PracticeLevelPlaceholderView(level: 7)
                    .navigationBarBackButtonHidden(false)
            }
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
                coordinator.tearDown()
                cameraController.onTrackingFrame = nil
                cameraController.publishesTrackingFramesToSwiftUI = true
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
            LevelSixHudChip(
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
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.65), in: Circle())
            }
            .padding(.top, 8)
            Spacer()
            LevelSixHudChip(
                title: "HITS",
                value: "\(coordinator.successfulHits)/20",
                tint: .yellow,
                alignment: .trailing
            )
        }
    }
}

private final class LevelSixCoordinator: ObservableObject {
    enum FinishState {
        case none
        case completed
        case failed
    }

    @Published private(set) var startPhase: BallrDrillStartPhase = .readiness
    @Published private(set) var ballFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var hitStreak = 0
    @Published private(set) var isTracking = false
    @Published private(set) var trackingStatusText = "SEARCHING"
    @Published private(set) var successfulHits = 0
    @Published private(set) var finishStartedAt: Date?
    @Published private(set) var showsFinishButtons = false
    @Published private(set) var finishState: FinishState = .none

    private let requiredBallLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let requiredSuccessfulHits = 20
    private let finishAnimationDuration: TimeInterval = 1.2
    private let finishButtonRevealDelay: TimeInterval = 0.28

    private var gameState = LevelSixGameState()
    private var size: CGSize = .zero
    private weak var renderView: LevelSixRenderView?
    private var finishWorkItem: DispatchWorkItem?
    private var bombFailureWorkItem: DispatchWorkItem?

    var hasEnded: Bool {
        finishState != .none
    }

    var didComplete: Bool {
        finishState == .completed
    }

    var finishTitle: String {
        didComplete ? "DONE" : "TRY AGAIN"
    }

    func attach(renderView: LevelSixRenderView) {
        self.renderView = renderView
        renderView.update(
            ballDisplayRect: nil,
            isTracking: isTracking,
            goodTarget: gameState.goodTarget,
            bombTarget: gameState.bombTarget,
            bombImpact: gameState.bombImpact,
            showsCenterPrompt: gameState.showsCenterPrompt,
            scorePopups: gameState.scorePopups
        )
    }

    func reset(in size: CGSize) {
        cancelFinishWorkItem()
        cancelBombFailureWorkItem()
        gameState = LevelSixGameState()
        startPhase = .readiness
        ballFoundStartedAt = nil
        countdownStartedAt = nil
        hitStreak = 0
        isTracking = false
        trackingStatusText = "SEARCHING"
        successfulHits = 0
        finishStartedAt = nil
        showsFinishButtons = false
        finishState = .none
        prepare(in: size, forceRespawn: true)
    }

    func tearDown() {
        cancelFinishWorkItem()
        cancelBombFailureWorkItem()
    }

    func prepare(in size: CGSize, forceRespawn: Bool = false) {
        self.size = size
        gameState.prepare(in: size, forceRespawn: forceRespawn, allowSpawn: startPhase == .live && !hasEnded)
        renderView?.update(
            ballDisplayRect: nil,
            isTracking: isTracking,
            goodTarget: gameState.goodTarget,
            bombTarget: gameState.bombTarget,
            bombImpact: gameState.bombImpact,
            showsCenterPrompt: gameState.showsCenterPrompt,
            scorePopups: gameState.scorePopups
        )
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        let overlayState = frame.overlayState
        let ballDisplayRect = displayRect(for: overlayState, cameraController: cameraController)
        updateTrackingStatus(from: overlayState)
        updateStartGate(isTracking: overlayState.isTracking, timestamp: frame.timestamp)

        if startPhase == .live, !hasEnded {
            let event = gameState.step(
                overlayState: overlayState,
                ballDisplayRect: ballDisplayRect,
                in: size,
                timestamp: frame.timestamp
            )

            switch event {
            case .goodHit:
                successfulHits += 1
                LevelSixSoundPlayer.playScore()
                if successfulHits >= requiredSuccessfulHits {
                    finish(.completed, at: frame.timestamp)
                }
            case .bombHit:
                scheduleBombFailure()
            case nil:
                break
            }

            syncHudFromGameState()
        }

        renderView?.update(
            ballDisplayRect: ballDisplayRect,
            isTracking: overlayState.isTracking,
            goodTarget: gameState.goodTarget,
            bombTarget: gameState.bombTarget,
            bombImpact: gameState.bombImpact,
            showsCenterPrompt: gameState.showsCenterPrompt,
            scorePopups: gameState.scorePopups
        )
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

    private func updateTrackingStatus(from overlayState: BallTrackerOverlayState) {
        if isTracking != overlayState.isTracking {
            isTracking = overlayState.isTracking
        }

        let statusText = overlayState.statusText.uppercased()
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
            ballFoundStartedAt = nil
            return
        }

        let startedAt = ballFoundStartedAt ?? timestamp
        ballFoundStartedAt = startedAt

        if timestamp.timeIntervalSince(startedAt) >= requiredBallLockSeconds {
            countdownStartedAt = timestamp
            startPhase = .countdown
        }
    }

    private func syncHudFromGameState() {
        if hitStreak != gameState.hitStreak {
            hitStreak = gameState.hitStreak
        }
    }

    private func finish(_ state: FinishState, at timestamp: Date) {
        guard finishState == .none else {
            return
        }
        cancelBombFailureWorkItem()

        if state == .completed {
            BallrDrillSoundPlayer.playWinner()
        }

        finishState = state
        finishStartedAt = timestamp
        showsFinishButtons = false
        gameState.finish()
        renderView?.update(
            ballDisplayRect: nil,
            isTracking: isTracking,
            goodTarget: gameState.goodTarget,
            bombTarget: gameState.bombTarget,
            bombImpact: gameState.bombImpact,
            showsCenterPrompt: gameState.showsCenterPrompt,
            scorePopups: gameState.scorePopups
        )

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

    private func scheduleBombFailure() {
        guard bombFailureWorkItem == nil, finishState == .none else {
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.bombFailureWorkItem = nil
            self?.finish(.failed, at: Date())
        }
        bombFailureWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func cancelBombFailureWorkItem() {
        bombFailureWorkItem?.cancel()
        bombFailureWorkItem = nil
    }
}

private struct LevelSixRenderSurface: UIViewRepresentable {
    let coordinator: LevelSixCoordinator

    func makeUIView(context: Context) -> LevelSixRenderView {
        let view = LevelSixRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: LevelSixRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class LevelSixRenderView: UIView {
    private let goodFillLayer = CAShapeLayer()
    private let goodOuterLayer = CAShapeLayer()
    private let goodInnerLayer = CAShapeLayer()
    private let bombFillLayer = CAShapeLayer()
    private let bombOuterLayer = CAShapeLayer()
    private let bombHighlightLayer = CAShapeLayer()
    private let bombCapLayer = CAShapeLayer()
    private let bombFuseLayer = CAShapeLayer()
    private let bombSparkLayer = CAShapeLayer()
    private let bombBurstLayer = CAShapeLayer()
    private let ballRingLayer = CAShapeLayer()
    private let ballCenterLayer = CAShapeLayer()
    private let promptLabel = UILabel()
    private let centerPromptOverlay = UIView()
    private let centerPromptLabel = UILabel()

    private var popupLayers: [UUID: CATextLayer] = [:]
    private var displayLink: CADisplayLink?
    private var ballDisplayRect: CGRect?
    private var isTracking = false
    private var goodTarget: LevelSixTarget?
    private var bombTarget: LevelSixTarget?
    private var bombImpact: LevelSixBombImpact?
    private var showsCenterPrompt = false
    private var scorePopups: [LevelSixScorePopup] = []

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
        isTracking: Bool,
        goodTarget: LevelSixTarget?,
        bombTarget: LevelSixTarget?,
        bombImpact: LevelSixBombImpact?,
        showsCenterPrompt: Bool,
        scorePopups: [LevelSixScorePopup]
    ) {
        self.ballDisplayRect = ballDisplayRect
        self.isTracking = isTracking
        self.goodTarget = goodTarget
        self.bombTarget = bombTarget
        self.bombImpact = bombImpact
        self.showsCenterPrompt = showsCenterPrompt
        self.scorePopups = scorePopups
        render(date: Date())
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        render(date: Date())
    }

    private func configureLayers() {
        goodFillLayer.fillColor = UIColor.black.withAlphaComponent(0.22).cgColor
        goodOuterLayer.fillColor = UIColor.clear.cgColor
        goodOuterLayer.strokeColor = UIColor.yellow.withAlphaComponent(0.45).cgColor
        goodOuterLayer.lineWidth = 12
        goodInnerLayer.fillColor = UIColor.clear.cgColor
        goodInnerLayer.strokeColor = UIColor.orange.cgColor
        goodInnerLayer.lineWidth = 5
        goodOuterLayer.shadowColor = UIColor.yellow.cgColor
        goodOuterLayer.shadowOpacity = 0.35
        goodOuterLayer.shadowRadius = 16
        goodOuterLayer.shadowOffset = .zero

        bombFillLayer.fillColor = UIColor(red: 0.035, green: 0.038, blue: 0.045, alpha: 0.96).cgColor
        bombOuterLayer.fillColor = UIColor.clear.cgColor
        bombOuterLayer.strokeColor = UIColor(red: 0.55, green: 0.57, blue: 0.62, alpha: 0.95).cgColor
        bombOuterLayer.lineWidth = 5
        bombOuterLayer.shadowColor = UIColor.black.cgColor
        bombOuterLayer.shadowOpacity = 0.68
        bombOuterLayer.shadowRadius = 14
        bombOuterLayer.shadowOffset = .zero
        bombHighlightLayer.fillColor = UIColor.white.withAlphaComponent(0.34).cgColor
        bombCapLayer.fillColor = UIColor(red: 0.23, green: 0.24, blue: 0.27, alpha: 1).cgColor
        bombCapLayer.strokeColor = UIColor(red: 0.72, green: 0.72, blue: 0.68, alpha: 0.95).cgColor
        bombCapLayer.lineWidth = 3
        bombFuseLayer.fillColor = UIColor.clear.cgColor
        bombFuseLayer.strokeColor = UIColor(red: 0.45, green: 0.28, blue: 0.12, alpha: 1).cgColor
        bombFuseLayer.lineWidth = 6
        bombFuseLayer.lineCap = .round
        bombSparkLayer.fillColor = UIColor(red: 1.0, green: 0.82, blue: 0.10, alpha: 0.96).cgColor
        bombSparkLayer.strokeColor = UIColor(red: 1.0, green: 0.24, blue: 0.04, alpha: 1).cgColor
        bombSparkLayer.lineWidth = 2
        bombBurstLayer.fillColor = UIColor(red: 1.0, green: 0.78, blue: 0.10, alpha: 0.42).cgColor
        bombBurstLayer.strokeColor = UIColor(red: 1.0, green: 0.24, blue: 0.05, alpha: 0.95).cgColor
        bombBurstLayer.lineWidth = 6

        ballRingLayer.fillColor = UIColor.clear.cgColor
        ballRingLayer.strokeColor = UIColor.white.cgColor
        ballRingLayer.lineWidth = 2.5
        ballRingLayer.shadowColor = UIColor.black.cgColor
        ballRingLayer.shadowOpacity = 0.45
        ballRingLayer.shadowRadius = 6
        ballRingLayer.shadowOffset = .zero
        ballCenterLayer.fillColor = UIColor.orange.cgColor

        [
            goodFillLayer,
            goodOuterLayer,
            goodInnerLayer,
            bombFillLayer,
            bombOuterLayer,
            bombHighlightLayer,
            bombCapLayer,
            bombFuseLayer,
            bombSparkLayer,
            bombBurstLayer,
            ballRingLayer,
            ballCenterLayer
        ].forEach(layer.addSublayer)

        promptLabel.text = "Find the ball"
        promptLabel.font = .systemFont(ofSize: 15, weight: .black)
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        promptLabel.layer.cornerRadius = 8
        promptLabel.layer.masksToBounds = true
        addSubview(promptLabel)

        centerPromptOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.58)
        centerPromptOverlay.isUserInteractionEnabled = false
        centerPromptOverlay.isHidden = true
        centerPromptLabel.text = "ROLL BACK TO CENTER"
        centerPromptLabel.font = .systemFont(ofSize: 34, weight: .black)
        centerPromptLabel.textColor = .white
        centerPromptLabel.textAlignment = .center
        centerPromptLabel.numberOfLines = 2
        centerPromptLabel.layer.shadowColor = UIColor.black.cgColor
        centerPromptLabel.layer.shadowOpacity = 0.65
        centerPromptLabel.layer.shadowRadius = 10
        centerPromptLabel.layer.shadowOffset = CGSize(width: 0, height: 3)
        centerPromptOverlay.addSubview(centerPromptLabel)
        addSubview(centerPromptOverlay)
    }

    @objc private func renderFrame() {
        render(date: Date())
    }

    private func render(date: Date) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderGoodTarget()
        renderBombTarget()
        renderBombImpact(date: date)
        renderBall()
        renderPopups(date: date)
        renderCenterPrompt()
        promptLabel.isHidden = isTracking || showsCenterPrompt
        let promptSize = CGSize(width: 160, height: 42)
        promptLabel.frame = CGRect(
            x: bounds.midX - promptSize.width * 0.5,
            y: bounds.midY - promptSize.height * 0.5,
            width: promptSize.width,
            height: promptSize.height
        )
        CATransaction.commit()
    }

    private func renderGoodTarget() {
        guard let goodTarget else {
            [goodFillLayer, goodOuterLayer, goodInnerLayer].forEach {
                $0.isHidden = true
                $0.path = nil
            }
            return
        }

        let rect = CGRect(
            x: goodTarget.center.x - goodTarget.radius,
            y: goodTarget.center.y - goodTarget.radius,
            width: goodTarget.radius * 2,
            height: goodTarget.radius * 2
        )
        let innerRect = rect.insetBy(dx: 8, dy: 8)

        goodFillLayer.isHidden = false
        goodOuterLayer.isHidden = false
        goodInnerLayer.isHidden = false
        goodFillLayer.path = UIBezierPath(ovalIn: rect).cgPath
        goodOuterLayer.path = UIBezierPath(ovalIn: rect).cgPath
        goodInnerLayer.path = UIBezierPath(ovalIn: innerRect).cgPath
        goodFillLayer.opacity = 1
        goodOuterLayer.opacity = 1
        goodInnerLayer.opacity = 1
    }

    private func renderBombTarget() {
        guard let bombTarget else {
            [bombFillLayer, bombOuterLayer, bombHighlightLayer, bombCapLayer, bombFuseLayer, bombSparkLayer].forEach {
                $0.isHidden = true
                $0.path = nil
            }
            return
        }

        let bodyRadius = bombTarget.radius * 0.82
        let rect = CGRect(
            x: bombTarget.center.x - bodyRadius,
            y: bombTarget.center.y - bodyRadius * 0.74,
            width: bodyRadius * 2,
            height: bodyRadius * 2
        )

        bombFillLayer.isHidden = false
        bombOuterLayer.isHidden = false
        bombHighlightLayer.isHidden = false
        bombCapLayer.isHidden = false
        bombFuseLayer.isHidden = false
        bombSparkLayer.isHidden = false
        bombFillLayer.path = UIBezierPath(ovalIn: rect).cgPath
        bombOuterLayer.path = UIBezierPath(ovalIn: rect).cgPath

        let highlightRect = CGRect(
            x: rect.minX + rect.width * 0.27,
            y: rect.minY + rect.height * 0.20,
            width: rect.width * 0.22,
            height: rect.height * 0.16
        )
        bombHighlightLayer.path = UIBezierPath(ovalIn: highlightRect).cgPath

        let capRect = CGRect(
            x: rect.midX + rect.width * 0.10,
            y: rect.minY - rect.height * 0.10,
            width: rect.width * 0.34,
            height: rect.height * 0.22
        )
        bombCapLayer.path = UIBezierPath(roundedRect: capRect, cornerRadius: capRect.height * 0.34).cgPath

        let fusePath = UIBezierPath()
        fusePath.move(to: CGPoint(x: capRect.maxX - capRect.width * 0.15, y: capRect.midY))
        fusePath.addCurve(
            to: CGPoint(x: capRect.maxX + rect.width * 0.30, y: capRect.minY - rect.height * 0.24),
            controlPoint1: CGPoint(x: capRect.maxX + rect.width * 0.08, y: capRect.minY - rect.height * 0.04),
            controlPoint2: CGPoint(x: capRect.maxX + rect.width * 0.16, y: capRect.minY - rect.height * 0.22)
        )
        bombFuseLayer.path = fusePath.cgPath

        let sparkCenter = CGPoint(x: capRect.maxX + rect.width * 0.32, y: capRect.minY - rect.height * 0.25)
        let sparkRadius = max(7, bombTarget.radius * 0.17)
        let sparkPath = UIBezierPath()
        for index in 0..<8 {
            let angle = CGFloat(index) / 8.0 * .pi * 2
            let inner = sparkRadius * 0.38
            let outer = sparkRadius * (index.isMultiple(of: 2) ? 1.15 : 0.72)
            let point = CGPoint(
                x: sparkCenter.x + cos(angle) * outer,
                y: sparkCenter.y + sin(angle) * outer
            )
            if index == 0 {
                sparkPath.move(to: point)
            } else {
                let previousAngle = (CGFloat(index) - 0.5) / 8.0 * .pi * 2
                sparkPath.addLine(to: CGPoint(
                    x: sparkCenter.x + cos(previousAngle) * inner,
                    y: sparkCenter.y + sin(previousAngle) * inner
                ))
                sparkPath.addLine(to: point)
            }
        }
        sparkPath.close()
        bombSparkLayer.path = sparkPath.cgPath

        bombFillLayer.opacity = 1
        bombOuterLayer.opacity = 1
        bombHighlightLayer.opacity = 1
        bombCapLayer.opacity = 1
        bombFuseLayer.opacity = 1
        bombSparkLayer.opacity = 1
    }

    private func renderBombImpact(date: Date) {
        guard let bombImpact, bombImpact.isActive(at: date) else {
            bombBurstLayer.isHidden = true
            bombBurstLayer.path = nil
            return
        }

        let progress = bombImpact.progress(at: date)
        let eased = smoothStep(progress)
        let radius = bombImpact.radius * (1.0 + eased * 1.15)
        let rect = CGRect(
            x: bombImpact.center.x - radius,
            y: bombImpact.center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let burstPath = UIBezierPath(ovalIn: rect)
        let rayCount = 10
        for index in 0..<rayCount {
            let angle = CGFloat(index) / CGFloat(rayCount) * .pi * 2
            let inner = bombImpact.radius * (0.72 + eased * 0.22)
            let outer = bombImpact.radius * (1.25 + eased * 1.35)
            burstPath.move(to: CGPoint(
                x: bombImpact.center.x + cos(angle) * inner,
                y: bombImpact.center.y + sin(angle) * inner
            ))
            burstPath.addLine(to: CGPoint(
                x: bombImpact.center.x + cos(angle) * outer,
                y: bombImpact.center.y + sin(angle) * outer
            ))
        }

        bombBurstLayer.isHidden = false
        bombBurstLayer.path = burstPath.cgPath
        bombBurstLayer.opacity = Float(1.0 - progress)
    }

    private func renderCenterPrompt() {
        centerPromptOverlay.isHidden = !showsCenterPrompt
        centerPromptOverlay.frame = bounds
        let labelWidth = max(260, bounds.width * 0.72)
        centerPromptLabel.frame = CGRect(
            x: (bounds.width - labelWidth) * 0.5,
            y: bounds.midY - 54,
            width: labelWidth,
            height: 108
        )
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

    private func makePopupLayer(for popup: LevelSixScorePopup) -> CATextLayer {
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

private struct LevelSixHudChip: View {
    let title: String
    let value: String
    let tint: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.system(size: 36, weight: .black, design: .rounded))
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

private struct LevelSixLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting level 6...")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LevelSixErrorOverlay: View {
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

private struct LevelSixGameState {
    private enum Phase {
        case active
        case returningToCenter
    }

    private enum Side {
        case left
        case right

        var opposite: Side {
            switch self {
            case .left:
                return .right
            case .right:
                return .left
            }
        }
    }

    var goodTarget: LevelSixTarget?
    var bombTarget: LevelSixTarget?
    var bombImpact: LevelSixBombImpact?
    var scorePopups: [LevelSixScorePopup] = []
    var hitStreak = 0
    private(set) var showsCenterPrompt = false

    private let popupValue = 5
    private let sideXFraction: CGFloat = 0.24
    private let laneYFraction: CGFloat = 0.88
    private let centerPromptDelay: TimeInterval = 5.0
    private let centerXReturnMultiplier: CGFloat = 1.45
    private let centerYReturnMultiplier: CGFloat = 2.35
    private let spawnTopFraction: CGFloat = 0.75
    private let clearance: CGFloat = 28
    private let previousGoodDistanceMultiplier: CGFloat = 3.0
    private let minPairSpacingMultiplier: CGFloat = 2.35
    private let maxPairSpacingMultiplier: CGFloat = 3.9
    private let accessCorridorWidthMultiplier: CGFloat = 1.35
    private let spawnCandidateSampleCount = 96
    private var phase: Phase = .active
    private var lastTargetSide: Side?
    private var returnToCenterStartedAt: Date?
    private var completedCenterReturns = 0

    mutating func prepare(in size: CGSize, forceRespawn: Bool = false, allowSpawn: Bool = true) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        guard allowSpawn else {
            goodTarget = nil
            bombTarget = nil
            bombImpact = nil
            showsCenterPrompt = false
            returnToCenterStartedAt = nil
            return
        }

        if forceRespawn {
            bombImpact = nil
            phase = .active
            showsCenterPrompt = false
            returnToCenterStartedAt = nil
            completedCenterReturns = 0
            spawnSidePair(in: size)
        }
    }

    mutating func finish() {
        goodTarget = nil
        bombTarget = nil
        phase = .active
        showsCenterPrompt = false
        returnToCenterStartedAt = nil
    }

    mutating func step(
        overlayState: BallTrackerOverlayState,
        ballDisplayRect: CGRect?,
        in size: CGSize,
        timestamp: Date
    ) -> LevelSixStepEvent? {
        scorePopups.removeAll { !$0.isActive(at: timestamp) }
        if let bombImpact, !bombImpact.isActive(at: timestamp) {
            self.bombImpact = nil
        }
        if bombImpact != nil {
            return nil
        }

        if phase == .returningToCenter {
            updateCenterPrompt(at: timestamp)
            goodTarget = nil
            bombTarget = nil
            guard overlayState.isTracking, let ballDisplayRect else {
                return nil
            }
            let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
            let ballRadius = max(ballDisplayRect.width, ballDisplayRect.height) * 0.5
            if isBallBackAtCenter(ballCenter: ballCenter, ballRadius: ballRadius, in: size) {
                phase = .active
                showsCenterPrompt = false
                returnToCenterStartedAt = nil
                completedCenterReturns += 1
                spawnSidePair(in: size)
            }
            return nil
        }

        guard overlayState.isTracking, let ballDisplayRect else {
            return nil
        }

        let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
        let ballRadius = max(ballDisplayRect.width, ballDisplayRect.height) * 0.5

        if goodTarget == nil || bombTarget == nil {
            spawnSidePair(in: size)
        }

        guard let goodTarget, let bombTarget else {
            return nil
        }

        let hitBomb = hypot(ballCenter.x - bombTarget.center.x, ballCenter.y - bombTarget.center.y) <= ballRadius + bombTarget.radius
        let hitGood = hypot(ballCenter.x - goodTarget.center.x, ballCenter.y - goodTarget.center.y) <= ballRadius + goodTarget.radius

        if hitBomb {
            hitStreak = 0
            self.goodTarget = nil
            self.bombTarget = nil
            bombImpact = LevelSixBombImpact(center: bombTarget.center, radius: bombTarget.radius, startedAt: timestamp)
            return .bombHit
        }

        guard hitGood else {
            return nil
        }

        hitStreak += 1
        scorePopups.append(
            LevelSixScorePopup(
                points: popupValue,
                center: goodTarget.center,
                destination: CGPoint(x: max(size.width - 104, 40), y: 40),
                startedAt: timestamp
            )
        )
        self.goodTarget = nil
        self.bombTarget = nil
        phase = .returningToCenter
        returnToCenterStartedAt = timestamp
        showsCenterPrompt = completedCenterReturns == 0
        return .goodHit
    }

    private mutating func updateCenterPrompt(at timestamp: Date) {
        guard let returnToCenterStartedAt else {
            showsCenterPrompt = completedCenterReturns == 0
            return
        }

        if completedCenterReturns == 0 {
            showsCenterPrompt = true
        } else if timestamp.timeIntervalSince(returnToCenterStartedAt) >= centerPromptDelay {
            showsCenterPrompt = true
        }
    }

    private mutating func spawnSidePair(in size: CGSize) {
        let radius = targetRadius(for: size)
        let targetSide = nextTargetSide()
        let bombSide = targetSide.opposite
        goodTarget = LevelSixTarget(center: point(for: targetSide, in: size, radius: radius), radius: radius)
        bombTarget = LevelSixTarget(center: point(for: bombSide, in: size, radius: radius), radius: radius)
        lastTargetSide = targetSide
    }

    private mutating func nextTargetSide() -> Side {
        if Bool.random() {
            return Bool.random() ? .left : .right
        }
        return lastTargetSide?.opposite ?? (Bool.random() ? .left : .right)
    }

    private func point(for side: Side, in size: CGSize, radius: CGFloat) -> CGPoint {
        let xFraction = side == .left ? sideXFraction : 1.0 - sideXFraction
        let x = min(max(size.width * xFraction, radius + 46), size.width - radius - 46)
        return CGPoint(x: x, y: playLaneY(in: size, radius: radius))
    }

    private func centerPoint(in size: CGSize, radius: CGFloat) -> CGPoint {
        CGPoint(x: size.width * 0.5, y: playLaneY(in: size, radius: radius))
    }

    private func playLaneY(in size: CGSize, radius: CGFloat) -> CGFloat {
        min(max(size.height * laneYFraction, radius + 86), size.height - radius - 42)
    }

    private func isBallBackAtCenter(ballCenter: CGPoint, ballRadius: CGFloat, in size: CGSize) -> Bool {
        let radius = targetRadius(for: size)
        let center = centerPoint(in: size, radius: radius)
        let xTolerance = max(radius * centerXReturnMultiplier, ballRadius + radius * 0.45)
        let yTolerance = max(radius * centerYReturnMultiplier, ballRadius + radius * 0.9)
        return abs(ballCenter.x - center.x) <= xTolerance && abs(ballCenter.y - center.y) <= yTolerance
    }

    private mutating func spawnPair(
        in size: CGSize,
        timestamp: Date,
        previousGoodCenter: CGPoint? = nil,
        ballDisplayRect: CGRect? = nil
    ) {
        let radius = targetRadius(for: size)
        let bounds = spawnBounds(in: size, radius: radius)
        let fallbackBallCenter = CGPoint(x: size.width * 0.5, y: size.height - radius - 72)
        let ballCenter = ballDisplayRect.map { CGPoint(x: $0.midX, y: $0.midY) } ?? fallbackBallCenter
        let ballRadius = ballDisplayRect.map { max($0.width, $0.height) * 0.5 } ?? radius * 0.8
        let minBallDistance = ballRadius + radius + clearance
        let minPreviousGoodDistance = radius * previousGoodDistanceMultiplier
        let minPairSpacing = radius * minPairSpacingMultiplier
        let maxPairSpacing = radius * maxPairSpacingMultiplier
        let accessCorridorHalfWidth = radius * accessCorridorWidthMultiplier
        let approachStart = previousGoodCenter ?? ballCenter

        var bestPair: LevelSixSpawnPair?

        for _ in 0..<spawnCandidateSampleCount {
            let goodCandidate = randomPoint(in: bounds)
            let goodDistance = hypot(goodCandidate.x - ballCenter.x, goodCandidate.y - ballCenter.y)
            let approachDistance = hypot(goodCandidate.x - approachStart.x, goodCandidate.y - approachStart.y)

            guard goodDistance >= minBallDistance else {
                continue
            }
            guard approachDistance >= minBallDistance else {
                continue
            }

            if
                let previousGoodCenter,
                hypot(goodCandidate.x - previousGoodCenter.x, goodCandidate.y - previousGoodCenter.y) < minPreviousGoodDistance
            {
                continue
            }

            for bombCandidate in bombCandidates(
                beside: goodCandidate,
                approachStart: approachStart,
                bounds: bounds,
                radius: radius
            ) {
                let bombDistance = hypot(bombCandidate.x - ballCenter.x, bombCandidate.y - ballCenter.y)
                let pairSpacing = hypot(bombCandidate.x - goodCandidate.x, bombCandidate.y - goodCandidate.y)

                guard bombDistance >= minBallDistance else {
                    continue
                }
                guard pairSpacing >= minPairSpacing else {
                    continue
                }
                guard pairSpacing <= maxPairSpacing else {
                    continue
                }
                guard !isPoint(bombCandidate, insideApproachCorridorFrom: approachStart, to: goodCandidate, halfWidth: accessCorridorHalfWidth) else {
                    continue
                }
                guard !isBombTooCloseToGoodApproach(
                    bombCandidate,
                    ballCenter: approachStart,
                    goodCenter: goodCandidate,
                    minAlongTrackGap: radius * 1.2
                ) else {
                    continue
                }

                let previousGoodDistance = previousGoodCenter.map {
                    hypot(goodCandidate.x - $0.x, goodCandidate.y - $0.y)
                } ?? radius * 2

                let quality =
                    sidePlacementQuality(
                        bombCandidate: bombCandidate,
                        goodCenter: goodCandidate,
                        approachStart: approachStart,
                        preferredSpacing: radius * 3.0
                    ) +
                    previousGoodDistance * 0.45 -
                    abs(pairSpacing - radius * 3.0) * 0.25

                let pair = LevelSixSpawnPair(
                    goodCenter: goodCandidate,
                    bombCenter: bombCandidate,
                    quality: quality
                )
                if bestPair == nil || pair.quality > bestPair?.quality ?? 0 {
                    bestPair = pair
                }
            }
        }

        if bestPair == nil {
            bestPair = fallbackPair(
                in: bounds,
                ballCenter: ballCenter,
                previousGoodCenter: previousGoodCenter,
                radius: radius,
                minBallDistance: minBallDistance,
                minPreviousGoodDistance: minPreviousGoodDistance,
                minPairSpacing: minPairSpacing,
                maxPairSpacing: maxPairSpacing,
                accessCorridorHalfWidth: accessCorridorHalfWidth
            )
        }

        if bestPair == nil, previousGoodCenter != nil {
            bestPair = fallbackPair(
                in: bounds,
                ballCenter: ballCenter,
                previousGoodCenter: nil,
                radius: radius,
                minBallDistance: minBallDistance,
                minPreviousGoodDistance: minPreviousGoodDistance,
                minPairSpacing: minPairSpacing,
                maxPairSpacing: maxPairSpacing,
                accessCorridorHalfWidth: accessCorridorHalfWidth
            )
        }

        if let bestPair {
            goodTarget = LevelSixTarget(center: bestPair.goodCenter, radius: radius)
            bombTarget = LevelSixTarget(center: bestPair.bombCenter, radius: radius)
        } else {
            goodTarget = nil
            bombTarget = nil
        }
    }

    private func fallbackPair(
        in bounds: CGRect,
        ballCenter: CGPoint,
        previousGoodCenter: CGPoint?,
        radius: CGFloat,
        minBallDistance: CGFloat,
        minPreviousGoodDistance: CGFloat,
        minPairSpacing: CGFloat,
        maxPairSpacing: CGFloat,
        accessCorridorHalfWidth: CGFloat
    ) -> LevelSixSpawnPair? {
        let approachStart = previousGoodCenter ?? ballCenter
        let anchors = [
            CGPoint(x: bounds.minX + radius * 0.8, y: bounds.maxY - radius * 0.5),
            CGPoint(x: bounds.midX - radius * 1.2, y: bounds.midY + radius * 0.25),
            CGPoint(x: bounds.midX + radius * 1.2, y: bounds.midY + radius * 0.25),
            CGPoint(x: bounds.maxX - radius * 0.8, y: bounds.maxY - radius * 0.5)
        ]

        var bestPair: LevelSixSpawnPair?

        for goodCandidate in anchors {
            let goodDistance = hypot(goodCandidate.x - ballCenter.x, goodCandidate.y - ballCenter.y)
            let approachDistance = hypot(goodCandidate.x - approachStart.x, goodCandidate.y - approachStart.y)
            guard goodDistance >= minBallDistance else {
                continue
            }
            guard approachDistance >= minBallDistance else {
                continue
            }
            if
                let previousGoodCenter,
                hypot(goodCandidate.x - previousGoodCenter.x, goodCandidate.y - previousGoodCenter.y) < minPreviousGoodDistance
            {
                continue
            }

            for bombCandidate in anchors where bombCandidate != goodCandidate {
                let bombDistance = hypot(bombCandidate.x - ballCenter.x, bombCandidate.y - ballCenter.y)
                let pairSpacing = hypot(bombCandidate.x - goodCandidate.x, bombCandidate.y - goodCandidate.y)
                guard bombDistance >= minBallDistance else {
                    continue
                }
                guard pairSpacing >= minPairSpacing else {
                    continue
                }
                guard pairSpacing <= maxPairSpacing else {
                    continue
                }
                guard !isPoint(bombCandidate, insideApproachCorridorFrom: approachStart, to: goodCandidate, halfWidth: accessCorridorHalfWidth) else {
                    continue
                }

                let quality = sidePlacementQuality(
                    bombCandidate: bombCandidate,
                    goodCenter: goodCandidate,
                    approachStart: approachStart,
                    preferredSpacing: radius * 3.0
                )
                let pair = LevelSixSpawnPair(
                    goodCenter: goodCandidate,
                    bombCenter: bombCandidate,
                    quality: quality
                )
                if bestPair == nil || pair.quality > bestPair?.quality ?? 0 {
                    bestPair = pair
                }
            }
        }

        return bestPair
    }

    private func bombCandidates(
        beside goodCenter: CGPoint,
        approachStart: CGPoint,
        bounds: CGRect,
        radius: CGFloat
    ) -> [CGPoint] {
        let travel = CGPoint(x: goodCenter.x - approachStart.x, y: goodCenter.y - approachStart.y)
        let length = hypot(travel.x, travel.y)
        guard length > 0.001 else {
            return []
        }

        let unit = CGPoint(x: travel.x / length, y: travel.y / length)
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)
        let sideOrder: [CGFloat] = Bool.random() ? [1, -1] : [-1, 1]
        let spacingOptions: [CGFloat] = [2.55, 3.0, 3.45, 3.85]
        let alongOptions: [CGFloat] = [-0.25, 0, 0.25]
        var candidates: [CGPoint] = []

        for side in sideOrder {
            for spacing in spacingOptions.shuffled() {
                for along in alongOptions.shuffled() {
                    let offset = radius * spacing
                    let alongOffset = radius * along
                    let candidate = CGPoint(
                        x: goodCenter.x + perpendicular.x * side * offset + unit.x * alongOffset,
                        y: goodCenter.y + perpendicular.y * side * offset + unit.y * alongOffset
                    )
                    guard bounds.contains(candidate) else {
                        continue
                    }
                    candidates.append(candidate)
                }
            }
        }

        return candidates
    }

    private func sidePlacementQuality(
        bombCandidate: CGPoint,
        goodCenter: CGPoint,
        approachStart: CGPoint,
        preferredSpacing: CGFloat
    ) -> CGFloat {
        let travel = CGPoint(x: goodCenter.x - approachStart.x, y: goodCenter.y - approachStart.y)
        let length = hypot(travel.x, travel.y)
        guard length > 0.001 else {
            return 0
        }

        let unit = CGPoint(x: travel.x / length, y: travel.y / length)
        let perpendicular = CGPoint(x: -unit.y, y: unit.x)
        let toBomb = CGPoint(x: bombCandidate.x - goodCenter.x, y: bombCandidate.y - goodCenter.y)
        let sideDistance = abs(toBomb.x * perpendicular.x + toBomb.y * perpendicular.y)
        let alongDistance = abs(toBomb.x * unit.x + toBomb.y * unit.y)
        let spacingPenalty = abs(sideDistance - preferredSpacing)
        return sideDistance * 1.6 - alongDistance * 1.2 - spacingPenalty * 0.7
    }

    private func targetRadius(for size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.091, 36), 62)
    }

    private func spawnBounds(in size: CGSize, radius: CGFloat) -> CGRect {
        let horizontalPadding = radius + 26
        let top = max(size.height * spawnTopFraction + radius, radius + 76)
        let bottom = max(top, size.height - radius - 58)
        return CGRect(
            x: horizontalPadding,
            y: top,
            width: max(1, size.width - horizontalPadding * 2),
            height: max(1, bottom - top)
        )
    }

    private func randomPoint(in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: CGFloat.random(in: bounds.minX...bounds.maxX),
            y: CGFloat.random(in: bounds.minY...bounds.maxY)
        )
    }

    private func isPoint(
        _ point: CGPoint,
        insideApproachCorridorFrom start: CGPoint,
        to end: CGPoint,
        halfWidth: CGFloat
    ) -> Bool {
        let segment = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let segmentLengthSquared = segment.x * segment.x + segment.y * segment.y
        guard segmentLengthSquared > 0.0001 else {
            return false
        }

        let pointOffset = CGPoint(x: point.x - start.x, y: point.y - start.y)
        let projection = (pointOffset.x * segment.x + pointOffset.y * segment.y) / segmentLengthSquared
        guard projection >= 0, projection <= 1 else {
            return false
        }

        let closestPoint = CGPoint(
            x: start.x + segment.x * projection,
            y: start.y + segment.y * projection
        )
        let distance = hypot(point.x - closestPoint.x, point.y - closestPoint.y)
        return distance < halfWidth
    }

    private func isBombTooCloseToGoodApproach(
        _ bombCenter: CGPoint,
        ballCenter: CGPoint,
        goodCenter: CGPoint,
        minAlongTrackGap: CGFloat
    ) -> Bool {
        let direction = CGPoint(x: goodCenter.x - ballCenter.x, y: goodCenter.y - ballCenter.y)
        let length = hypot(direction.x, direction.y)
        guard length > 0.001 else {
            return false
        }

        let normalized = CGPoint(x: direction.x / length, y: direction.y / length)
        let toBomb = CGPoint(x: bombCenter.x - goodCenter.x, y: bombCenter.y - goodCenter.y)
        let alongTrackDistance = toBomb.x * normalized.x + toBomb.y * normalized.y
        return abs(alongTrackDistance) < minAlongTrackGap
    }
}

private struct LevelSixTarget {
    let center: CGPoint
    let radius: CGFloat
}

private struct LevelSixBombImpact {
    let center: CGPoint
    let radius: CGFloat
    let startedAt: Date

    private let duration: TimeInterval = 0.42

    func progress(at timestamp: Date) -> Double {
        min(max(timestamp.timeIntervalSince(startedAt) / duration, 0), 1)
    }

    func isActive(at timestamp: Date) -> Bool {
        progress(at: timestamp) < 1
    }
}

private struct LevelSixScorePopup: Identifiable {
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

private struct LevelSixSpawnPair {
    let goodCenter: CGPoint
    let bombCenter: CGPoint
    let quality: CGFloat
}

private enum LevelSixStepEvent {
    case goodHit
    case bombHit
}

private enum LevelSixSoundPlayer {
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
                print("Level 6 score sound failed to load: \(error.localizedDescription)")
                return
            }
        }

        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}
