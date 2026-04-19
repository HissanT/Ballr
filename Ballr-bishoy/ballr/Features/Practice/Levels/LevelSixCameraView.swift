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
            .statusBarHidden(true)
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
            scorePopups: gameState.scorePopups
        )
    }

    func reset(in size: CGSize) {
        cancelFinishWorkItem()
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
                finish(.failed, at: frame.timestamp)
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
    private let bombXLayer = CAShapeLayer()
    private let bombBurstLayer = CAShapeLayer()
    private let ballRingLayer = CAShapeLayer()
    private let ballCenterLayer = CAShapeLayer()
    private let promptLabel = UILabel()

    private var popupLayers: [UUID: CATextLayer] = [:]
    private var displayLink: CADisplayLink?
    private var ballDisplayRect: CGRect?
    private var isTracking = false
    private var goodTarget: LevelSixTarget?
    private var bombTarget: LevelSixTarget?
    private var bombImpact: LevelSixBombImpact?
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
        scorePopups: [LevelSixScorePopup]
    ) {
        self.ballDisplayRect = ballDisplayRect
        self.isTracking = isTracking
        self.goodTarget = goodTarget
        self.bombTarget = bombTarget
        self.bombImpact = bombImpact
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

        bombFillLayer.fillColor = UIColor(red: 0.74, green: 0.08, blue: 0.12, alpha: 0.42).cgColor
        bombOuterLayer.fillColor = UIColor.clear.cgColor
        bombOuterLayer.strokeColor = UIColor(red: 1.0, green: 0.2, blue: 0.24, alpha: 0.95).cgColor
        bombOuterLayer.lineWidth = 12
        bombOuterLayer.shadowColor = UIColor.red.cgColor
        bombOuterLayer.shadowOpacity = 0.45
        bombOuterLayer.shadowRadius = 16
        bombOuterLayer.shadowOffset = .zero
        bombXLayer.fillColor = UIColor.clear.cgColor
        bombXLayer.strokeColor = UIColor.white.cgColor
        bombXLayer.lineWidth = 7
        bombXLayer.lineCap = .round
        bombBurstLayer.fillColor = UIColor(red: 1.0, green: 0.16, blue: 0.18, alpha: 0.42).cgColor
        bombBurstLayer.strokeColor = UIColor(red: 1.0, green: 0.34, blue: 0.3, alpha: 0.9).cgColor
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
            bombXLayer,
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
        promptLabel.isHidden = isTracking
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
            [bombFillLayer, bombOuterLayer, bombXLayer].forEach {
                $0.isHidden = true
                $0.path = nil
            }
            return
        }

        let rect = CGRect(
            x: bombTarget.center.x - bombTarget.radius,
            y: bombTarget.center.y - bombTarget.radius,
            width: bombTarget.radius * 2,
            height: bombTarget.radius * 2
        )
        let xInset = bombTarget.radius * 0.55
        let xPath = UIBezierPath()
        xPath.move(to: CGPoint(x: rect.minX + xInset, y: rect.minY + xInset))
        xPath.addLine(to: CGPoint(x: rect.maxX - xInset, y: rect.maxY - xInset))
        xPath.move(to: CGPoint(x: rect.maxX - xInset, y: rect.minY + xInset))
        xPath.addLine(to: CGPoint(x: rect.minX + xInset, y: rect.maxY - xInset))

        bombFillLayer.isHidden = false
        bombOuterLayer.isHidden = false
        bombXLayer.isHidden = false
        bombFillLayer.path = UIBezierPath(ovalIn: rect).cgPath
        bombOuterLayer.path = UIBezierPath(ovalIn: rect).cgPath
        bombXLayer.path = xPath.cgPath
        bombFillLayer.opacity = 1
        bombOuterLayer.opacity = 1
        bombXLayer.opacity = 1
    }

    private func renderBombImpact(date: Date) {
        guard let bombImpact, bombImpact.isActive(at: date) else {
            bombBurstLayer.isHidden = true
            bombBurstLayer.path = nil
            return
        }

        let progress = bombImpact.progress(at: date)
        let eased = smoothStep(progress)
        let radius = bombImpact.radius * (1.0 + eased * 0.7)
        let rect = CGRect(
            x: bombImpact.center.x - radius,
            y: bombImpact.center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        bombBurstLayer.isHidden = false
        bombBurstLayer.path = UIBezierPath(ovalIn: rect).cgPath
        bombBurstLayer.opacity = Float(1.0 - progress)
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
    var goodTarget: LevelSixTarget?
    var bombTarget: LevelSixTarget?
    var bombImpact: LevelSixBombImpact?
    var scorePopups: [LevelSixScorePopup] = []
    var hitStreak = 0

    private let popupValue = 5
    private let spawnTopFraction: CGFloat = 0.75
    private let clearance: CGFloat = 28
    private let previousGoodDistanceMultiplier: CGFloat = 3.0
    private let pairSpacingMultiplier: CGFloat = 3.2
    private let bombFurtherMarginMultiplier: CGFloat = 1.4
    private let accessCorridorWidthMultiplier: CGFloat = 1.35

    mutating func prepare(in size: CGSize, forceRespawn: Bool = false, allowSpawn: Bool = true) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        guard allowSpawn else {
            goodTarget = nil
            bombTarget = nil
            bombImpact = nil
            return
        }

        if forceRespawn {
            bombImpact = nil
            spawnPair(in: size, timestamp: Date())
        }
    }

    mutating func finish() {
        goodTarget = nil
        bombTarget = nil
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

        guard overlayState.isTracking, let ballDisplayRect else {
            return nil
        }

        if goodTarget == nil || bombTarget == nil {
            spawnPair(in: size, timestamp: timestamp, ballDisplayRect: ballDisplayRect)
        }

        guard let goodTarget, let bombTarget else {
            return nil
        }

        let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
        let ballRadius = max(ballDisplayRect.width, ballDisplayRect.height) * 0.5
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
        spawnPair(
            in: size,
            timestamp: timestamp,
            previousGoodCenter: goodTarget.center,
            ballDisplayRect: ballDisplayRect
        )
        return .goodHit
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
        let minPairSpacing = radius * pairSpacingMultiplier
        let bombFurtherMargin = radius * bombFurtherMarginMultiplier
        let accessCorridorHalfWidth = radius * accessCorridorWidthMultiplier

        var bestPair: LevelSixSpawnPair?

        for _ in 0..<72 {
            let goodCandidate = randomPoint(in: bounds)
            let goodDistance = hypot(goodCandidate.x - ballCenter.x, goodCandidate.y - ballCenter.y)

            guard goodDistance >= minBallDistance else {
                continue
            }

            if
                let previousGoodCenter,
                hypot(goodCandidate.x - previousGoodCenter.x, goodCandidate.y - previousGoodCenter.y) < minPreviousGoodDistance
            {
                continue
            }

            for _ in 0..<72 {
                let bombCandidate = randomPoint(in: bounds)
                let bombDistance = hypot(bombCandidate.x - ballCenter.x, bombCandidate.y - ballCenter.y)
                let pairSpacing = hypot(bombCandidate.x - goodCandidate.x, bombCandidate.y - goodCandidate.y)

                guard bombDistance >= minBallDistance else {
                    continue
                }
                guard bombDistance > goodDistance + bombFurtherMargin else {
                    continue
                }
                guard pairSpacing >= minPairSpacing else {
                    continue
                }
                guard !isPoint(bombCandidate, insideApproachCorridorFrom: ballCenter, to: goodCandidate, halfWidth: accessCorridorHalfWidth) else {
                    continue
                }
                guard !isBombTooCloseToGoodApproach(
                    bombCandidate,
                    ballCenter: ballCenter,
                    goodCenter: goodCandidate,
                    minAlongTrackGap: radius * 1.2
                ) else {
                    continue
                }

                let previousGoodDistance = previousGoodCenter.map {
                    hypot(goodCandidate.x - $0.x, goodCandidate.y - $0.y)
                } ?? radius * 2

                let quality =
                    pairSpacing * 1.15 +
                    (bombDistance - goodDistance) * 0.8 +
                    previousGoodDistance * 0.45 -
                    goodDistance * 0.18

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
                bombFurtherMargin: bombFurtherMargin,
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
                bombFurtherMargin: bombFurtherMargin,
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
        bombFurtherMargin: CGFloat,
        accessCorridorHalfWidth: CGFloat
    ) -> LevelSixSpawnPair? {
        let anchors = [
            CGPoint(x: bounds.minX + radius * 0.8, y: bounds.maxY - radius * 0.5),
            CGPoint(x: bounds.midX - radius * 1.2, y: bounds.midY + radius * 0.25),
            CGPoint(x: bounds.midX + radius * 1.2, y: bounds.midY + radius * 0.25),
            CGPoint(x: bounds.maxX - radius * 0.8, y: bounds.maxY - radius * 0.5)
        ]

        var bestPair: LevelSixSpawnPair?

        for goodCandidate in anchors {
            let goodDistance = hypot(goodCandidate.x - ballCenter.x, goodCandidate.y - ballCenter.y)
            guard goodDistance >= minBallDistance else {
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
                guard bombDistance > goodDistance + bombFurtherMargin else {
                    continue
                }
                guard pairSpacing >= minPairSpacing else {
                    continue
                }
                guard !isPoint(bombCandidate, insideApproachCorridorFrom: ballCenter, to: goodCandidate, halfWidth: accessCorridorHalfWidth) else {
                    continue
                }

                let quality = pairSpacing + (bombDistance - goodDistance)
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

    private let duration: TimeInterval = 0.22

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
