import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct TargetDrillCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = TargetDrillCoordinator()
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

                TargetDrillRenderSurface(coordinator: coordinator)
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
                    TargetDrillLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    TargetDrillErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.startPhase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                } else if coordinator.startPhase == .readiness && cameraController.errorMessage == nil {
                    BallrDrillReadinessOverlay(ballFoundStartedAt: coordinator.ballFoundStartedAt)
                }

                if coordinator.isCompleted {
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.completionStartedAt,
                        buttonsVisible: coordinator.showsCompletionButtons,
                        showsNextLevelButton: false,
                        onNextLevel: {},
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .ballrAwardsXPOnSuccess(coordinator.isCompleted)
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
            TargetDrillHudChip(
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
            TargetDrillHudChip(
                title: "SCORE",
                value: "\(coordinator.score)",
                tint: .yellow,
                alignment: .trailing
            )
        }
    }
}

private final class TargetDrillCoordinator: ObservableObject {
    @Published private(set) var startPhase: BallrDrillStartPhase = .readiness
    @Published private(set) var ballFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var score = 0
    @Published private(set) var hitStreak = 0
    @Published private(set) var lastEventText = "READY"
    @Published private(set) var lastEventIsPositive = true
    @Published private(set) var isTracking = false
    @Published private(set) var trackingStatusText = "SEARCHING"
    @Published private(set) var completionStartedAt: Date?
    @Published private(set) var showsCompletionButtons = false

    private let requiredBallLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let requiredHitStreak = 10
    private let completionAnimationDuration: TimeInterval = 2.05
    private let completionButtonRevealDelay: TimeInterval = 0.28

    private var gameState = TargetDrillGameState()
    private var size: CGSize = .zero
    private weak var renderView: TargetDrillRenderView?
    private var completionWorkItem: DispatchWorkItem?

    var isCompleted: Bool {
        completionStartedAt != nil
    }

    func attach(renderView: TargetDrillRenderView) {
        self.renderView = renderView
        renderView.update(
            ballDisplayRect: nil,
            isTracking: isTracking,
            target: gameState.target,
            scorePopups: gameState.scorePopups
        )
    }

    func reset(in size: CGSize) {
        cancelCompletionWorkItem()
        gameState = TargetDrillGameState()
        startPhase = .readiness
        ballFoundStartedAt = nil
        countdownStartedAt = nil
        score = 0
        hitStreak = 0
        lastEventText = "READY"
        lastEventIsPositive = true
        isTracking = false
        trackingStatusText = "SEARCHING"
        completionStartedAt = nil
        showsCompletionButtons = false
        prepare(in: size, forceRespawn: true)
    }

    func tearDown() {
        cancelCompletionWorkItem()
    }

    func prepare(in size: CGSize, forceRespawn: Bool = false) {
        self.size = size
        gameState.prepare(in: size, forceRespawn: forceRespawn, allowSpawn: startPhase == .live && !isCompleted)
        renderView?.update(
            ballDisplayRect: nil,
            isTracking: isTracking,
            target: gameState.target,
            scorePopups: gameState.scorePopups
        )
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        let overlayState = frame.overlayState
        let ballDisplayRect = displayRect(for: overlayState, cameraController: cameraController)
        updateTrackingStatus(from: overlayState)
        updateStartGate(isTracking: overlayState.isTracking, timestamp: frame.timestamp)

        if startPhase == .live && !isCompleted {
            let event = gameState.step(
                overlayState: overlayState,
                ballDisplayRect: ballDisplayRect,
                in: size,
                timestamp: frame.timestamp
            )
            switch event {
            case .hit:
                if gameState.didStartComboOnLastHit {
                    BallrDrillSoundPlayer.playCombo()
                } else {
                    TargetDrillSoundPlayer.playScore()
                }
            case .miss:
                BallrDrillSoundPlayer.playIncorrect()
            case nil:
                break
            }
            syncHudFromGameState()
            if hitStreak >= requiredHitStreak {
                complete(at: frame.timestamp)
            }
        }

        renderView?.update(
            ballDisplayRect: ballDisplayRect,
            isTracking: overlayState.isTracking,
            target: gameState.target,
            scorePopups: gameState.scorePopups
        )
    }

    private func complete(at timestamp: Date) {
        guard !isCompleted else {
            return
        }

        completionStartedAt = timestamp
        BallrDrillSoundPlayer.playWinner()

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
        if score != gameState.score {
            score = gameState.score
        }
        if hitStreak != gameState.hitStreak {
            hitStreak = gameState.hitStreak
        }
        if lastEventText != gameState.lastEventText {
            lastEventText = gameState.lastEventText
        }
        if lastEventIsPositive != gameState.lastEventIsPositive {
            lastEventIsPositive = gameState.lastEventIsPositive
        }
    }
}

private struct TargetDrillRenderSurface: UIViewRepresentable {
    let coordinator: TargetDrillCoordinator

    func makeUIView(context: Context) -> TargetDrillRenderView {
        let view = TargetDrillRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: TargetDrillRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class TargetDrillRenderView: UIView {
    private let targetFillLayer = CAShapeLayer()
    private let targetOuterLayer = CAShapeLayer()
    private let targetInnerLayer = CAShapeLayer()
    private let targetProgressLayer = CAShapeLayer()
    private let ballRingLayer = CAShapeLayer()
    private let ballCenterLayer = CAShapeLayer()
    private let promptLabel = UILabel()

    private var popupLayers: [UUID: CATextLayer] = [:]
    private var displayLink: CADisplayLink?
    private var ballDisplayRect: CGRect?
    private var isTracking = false
    private var target: TargetDrillTarget?
    private var scorePopups: [TargetDrillScorePopup] = []

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
        target: TargetDrillTarget?,
        scorePopups: [TargetDrillScorePopup]
    ) {
        self.ballDisplayRect = ballDisplayRect
        self.isTracking = isTracking
        self.target = target
        self.scorePopups = scorePopups
        render(date: Date())
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        render(date: Date())
    }

    private func configureLayers() {
        targetFillLayer.fillColor = UIColor.black.withAlphaComponent(0.22).cgColor
        targetOuterLayer.fillColor = UIColor.clear.cgColor
        targetOuterLayer.strokeColor = UIColor.yellow.withAlphaComponent(0.45).cgColor
        targetOuterLayer.lineWidth = 12
        targetInnerLayer.fillColor = UIColor.clear.cgColor
        targetInnerLayer.strokeColor = UIColor.orange.cgColor
        targetInnerLayer.lineWidth = 5
        targetProgressLayer.fillColor = UIColor.clear.cgColor
        targetProgressLayer.strokeColor = UIColor.white.cgColor
        targetProgressLayer.lineWidth = 5
        targetProgressLayer.lineCap = .round
        targetOuterLayer.shadowColor = UIColor.yellow.cgColor
        targetOuterLayer.shadowOpacity = 0.35
        targetOuterLayer.shadowRadius = 16
        targetOuterLayer.shadowOffset = .zero

        ballRingLayer.fillColor = UIColor.clear.cgColor
        ballRingLayer.strokeColor = UIColor.white.cgColor
        ballRingLayer.lineWidth = 2.5
        ballRingLayer.shadowColor = UIColor.black.cgColor
        ballRingLayer.shadowOpacity = 0.45
        ballRingLayer.shadowRadius = 6
        ballRingLayer.shadowOffset = .zero
        ballCenterLayer.fillColor = UIColor.orange.cgColor

        [
            targetFillLayer,
            targetOuterLayer,
            targetInnerLayer,
            targetProgressLayer,
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
        renderTarget(date: date)
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

    private func renderTarget(date: Date) {
        guard let target else {
            [targetFillLayer, targetOuterLayer, targetInnerLayer, targetProgressLayer].forEach {
                $0.isHidden = true
                $0.path = nil
            }
            return
        }

        let alpha = CGFloat(1.0 - targetAgeProgress(for: target, at: date))
        let rect = CGRect(
            x: target.center.x - target.radius,
            y: target.center.y - target.radius,
            width: target.radius * 2,
            height: target.radius * 2
        )
        let innerRect = rect.insetBy(dx: 8, dy: 8)
        let progressRadius = max(target.radius - 16, 1)
        let remainingProgress = max(CGFloat(0.02), 1.0 - CGFloat(targetAgeProgress(for: target, at: date)))

        targetFillLayer.isHidden = false
        targetOuterLayer.isHidden = false
        targetInnerLayer.isHidden = false
        targetProgressLayer.isHidden = false
        targetFillLayer.path = UIBezierPath(ovalIn: rect).cgPath
        targetOuterLayer.path = UIBezierPath(ovalIn: rect).cgPath
        targetInnerLayer.path = UIBezierPath(ovalIn: innerRect).cgPath
        targetProgressLayer.path = UIBezierPath(
            arcCenter: target.center,
            radius: progressRadius,
            startAngle: -.pi / 2,
            endAngle: -.pi / 2 + (.pi * 2 * remainingProgress),
            clockwise: true
        ).cgPath
        targetFillLayer.opacity = Float(alpha)
        targetOuterLayer.opacity = Float(alpha)
        targetInnerLayer.opacity = Float(alpha)
        targetProgressLayer.opacity = Float(alpha)
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
            layer.frame = CGRect(x: x - size.width * 0.5, y: y - size.height * 0.5, width: size.width, height: size.height)
            layer.opacity = Float(1.0 - progress)
        }
    }

    private func makePopupLayer(for popup: TargetDrillScorePopup) -> CATextLayer {
        let textLayer = CATextLayer()
        textLayer.contentsScale = traitCollection.displayScale
        textLayer.alignmentMode = .center
        textLayer.string = popup.points > 0 ? "+\(popup.points)" : "\(popup.points)"
        textLayer.fontSize = 38
        textLayer.foregroundColor = (popup.points > 0 ? UIColor.yellow : UIColor.white).cgColor
        textLayer.shadowColor = UIColor.black.cgColor
        textLayer.shadowOpacity = 0.7
        textLayer.shadowRadius = 7
        textLayer.shadowOffset = CGSize(width: 0, height: 2)
        layer.addSublayer(textLayer)
        popupLayers[popup.id] = textLayer
        return textLayer
    }

    private func targetAgeProgress(for target: TargetDrillTarget, at date: Date) -> Double {
        min(max(date.timeIntervalSince(target.spawnedAt) / TargetDrillGameState.targetLifetime, 0), 1)
    }

    private func smoothStep(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }
}

private struct TargetDrillHudChip: View {
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

private struct TargetDrillLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting target drill...")
                .font(.ballr(size: 16, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TargetDrillErrorOverlay: View {
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

private struct TargetDrillGameState {
    static let targetLifetime: TimeInterval = 4.0

    var target: TargetDrillTarget?
    var scorePopups: [TargetDrillScorePopup] = []
    var score = 0
    var hitStreak = 0
    var misses = 0
    var lastEventText = "READY"
    var lastEventIsPositive = true
    private(set) var didStartComboOnLastHit = false
    private var lastAnnouncedComboMultiplier = 1

    private let fullValueWindow: TimeInterval = 2.0
    private let scoreStep: TimeInterval = 0.4
    private let scoreValue = 5
    private let comboStreakStep = 10
    private let lowerYFraction: CGFloat = 0.58
    private let clearance: CGFloat = 20

    mutating func prepare(in size: CGSize, forceRespawn: Bool = false, allowSpawn: Bool = true) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        guard allowSpawn else {
            target = nil
            return
        }

        if target == nil || forceRespawn {
            spawnTarget(in: size, timestamp: Date())
        }
    }

    mutating func step(
        overlayState: BallTrackerOverlayState,
        ballDisplayRect: CGRect?,
        in size: CGSize,
        timestamp: Date
    ) -> TargetDrillStepEvent? {
        scorePopups.removeAll { !$0.isActive(at: timestamp) }
        didStartComboOnLastHit = false
        prepare(in: size)

        guard let currentTarget = target else {
            return nil
        }

        if targetAge(for: currentTarget, at: timestamp) >= Self.targetLifetime {
            misses += 1
            hitStreak = 0
            lastAnnouncedComboMultiplier = 1
            lastEventText = "-1"
            lastEventIsPositive = false
            score = max(score - 1, 0)
            scorePopups.append(
                TargetDrillScorePopup(
                    points: -1,
                    center: currentTarget.center,
                    destination: CGPoint(x: 104, y: 40),
                    startedAt: timestamp
                )
            )
            spawnTarget(in: size, timestamp: timestamp, previousCenter: currentTarget.center, avoiding: ballDisplayRect)
            return .miss
        }

        guard overlayState.isTracking, let ballDisplayRect else {
            return nil
        }

        let ballCenter = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
        let ballRadius = max(ballDisplayRect.width, ballDisplayRect.height) * 0.5
        let distance = hypot(ballCenter.x - currentTarget.center.x, ballCenter.y - currentTarget.center.y)
        guard distance <= ballRadius + currentTarget.radius else {
            return nil
        }

        let awardedComboMultiplier = comboMultiplier
        let points = basePoints(for: currentTarget, at: timestamp) * awardedComboMultiplier
        score += points
        didStartComboOnLastHit = awardedComboMultiplier > lastAnnouncedComboMultiplier
        lastAnnouncedComboMultiplier = awardedComboMultiplier
        hitStreak += 1
        lastEventText = "+\(points)"
        lastEventIsPositive = true
        scorePopups.append(
            TargetDrillScorePopup(
                points: points,
                center: currentTarget.center,
                destination: CGPoint(x: max(size.width - 104, 40), y: 40),
                startedAt: timestamp
            )
        )
        spawnTarget(in: size, timestamp: timestamp, previousCenter: currentTarget.center, avoiding: ballDisplayRect)
        return .hit
    }

    func targetAlpha(at timestamp: Date) -> Double {
        guard let target else {
            return 0
        }
        return 1.0 - targetAgeProgress(for: target, at: timestamp)
    }

    func targetAgeProgress(at timestamp: Date) -> Double {
        guard let target else {
            return 0
        }
        return targetAgeProgress(for: target, at: timestamp)
    }

    private var comboMultiplier: Int {
        1 + max(hitStreak, 0) / comboStreakStep
    }

    private func basePoints(for target: TargetDrillTarget, at timestamp: Date) -> Int {
        let age = targetAge(for: target, at: timestamp)
        guard age > fullValueWindow else {
            return scoreValue
        }

        let elapsedAfterFullValue = age - fullValueWindow
        let steps = Int(floor(elapsedAfterFullValue / scoreStep)) + 1
        return max(1, scoreValue - steps)
    }

    private func targetAgeProgress(for target: TargetDrillTarget, at timestamp: Date) -> Double {
        min(max(targetAge(for: target, at: timestamp) / Self.targetLifetime, 0), 1)
    }

    private func targetAge(for target: TargetDrillTarget, at timestamp: Date) -> TimeInterval {
        max(0, timestamp.timeIntervalSince(target.spawnedAt))
    }

    private mutating func spawnTarget(
        in size: CGSize,
        timestamp: Date,
        previousCenter: CGPoint? = nil,
        avoiding ballRect: CGRect? = nil
    ) {
        let radius = targetRadius(for: size)
        let bounds = spawnBounds(in: size, radius: radius)
        let ballCenter = ballRect.map { CGPoint(x: $0.midX, y: $0.midY) }
        let ballRadius = ballRect.map { max($0.width, $0.height) * 0.5 } ?? 0

        var bestCandidate = CGPoint(x: bounds.midX, y: bounds.midY)
        var bestQuality = CGFloat.leastNonzeroMagnitude

        for _ in 0..<64 {
            let candidate = CGPoint(
                x: CGFloat.random(in: bounds.minX...bounds.maxX),
                y: CGFloat.random(in: bounds.minY...bounds.maxY)
            )
            let quality = candidateQuality(
                candidate,
                previousCenter: previousCenter,
                ballCenter: ballCenter,
                ballRadius: ballRadius,
                targetRadius: radius
            )
            if quality > bestQuality {
                bestCandidate = candidate
                bestQuality = quality
            }
            if isCandidateValid(
                candidate,
                previousCenter: previousCenter,
                ballCenter: ballCenter,
                ballRadius: ballRadius,
                targetRadius: radius
            ) {
                target = TargetDrillTarget(center: candidate, radius: radius, spawnedAt: timestamp)
                return
            }
        }

        target = TargetDrillTarget(center: bestCandidate, radius: radius, spawnedAt: timestamp)
    }

    private func targetRadius(for size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.091, 36), 62)
    }

    private func spawnBounds(in size: CGSize, radius: CGFloat) -> CGRect {
        let horizontalPadding = radius + 26
        let top = max(size.height * lowerYFraction, radius + 76)
        let bottom = max(top, size.height - radius - 58)
        return CGRect(
            x: horizontalPadding,
            y: top,
            width: max(1, size.width - horizontalPadding * 2),
            height: max(1, bottom - top)
        )
    }

    private func candidateQuality(
        _ candidate: CGPoint,
        previousCenter: CGPoint?,
        ballCenter: CGPoint?,
        ballRadius: CGFloat,
        targetRadius: CGFloat
    ) -> CGFloat {
        var quality = targetRadius * 10
        if let previousCenter {
            quality += hypot(candidate.x - previousCenter.x, candidate.y - previousCenter.y)
        }
        if let ballCenter {
            quality += max(
                hypot(candidate.x - ballCenter.x, candidate.y - ballCenter.y) - ballRadius - targetRadius,
                0
            )
        }
        return quality
    }

    private func isCandidateValid(
        _ candidate: CGPoint,
        previousCenter: CGPoint?,
        ballCenter: CGPoint?,
        ballRadius: CGFloat,
        targetRadius: CGFloat
    ) -> Bool {
        if let previousCenter {
            let previousDistance = hypot(candidate.x - previousCenter.x, candidate.y - previousCenter.y)
            if previousDistance < targetRadius * 3 {
                return false
            }
        }
        if let ballCenter {
            let ballDistance = hypot(candidate.x - ballCenter.x, candidate.y - ballCenter.y)
            if ballDistance < ballRadius + targetRadius + clearance {
                return false
            }
        }
        return true
    }
}

private struct TargetDrillTarget {
    let center: CGPoint
    let radius: CGFloat
    let spawnedAt: Date
}

private struct TargetDrillScorePopup: Identifiable {
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

private enum TargetDrillStepEvent {
    case hit
    case miss
}

private enum TargetDrillSoundPlayer {
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
                print("Target drill score sound failed to load: \(error.localizedDescription)")
                return
            }
        }

        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}
