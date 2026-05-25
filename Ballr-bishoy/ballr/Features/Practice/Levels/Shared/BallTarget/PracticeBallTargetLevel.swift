import Foundation
import SwiftUI
import UIKit

struct PracticeBallTargetConfiguration {
    let loadingMessage: String
    let requiredBallLockSeconds: TimeInterval
    let countdownDuration: TimeInterval
    let requiredSuccessfulHits: Int
    let allowedMisses: Int?
    let targetLifetime: TimeInterval?
    let spawnTopFraction: CGFloat
    let addsRadiusToSpawnTop: Bool
    let spawnBottomFraction: CGFloat?
    let showsNextLevelButton: Bool

    static let levelFour = PracticeBallTargetConfiguration(
        loadingMessage: "Starting level 4...",
        requiredBallLockSeconds: 3.0,
        countdownDuration: 4.0,
        requiredSuccessfulHits: 25,
        allowedMisses: nil,
        targetLifetime: nil,
        spawnTopFraction: 0.75,
        addsRadiusToSpawnTop: true,
        spawnBottomFraction: nil,
        showsNextLevelButton: true
    )

    static let levelFive = PracticeBallTargetConfiguration(
        loadingMessage: "Starting level 5...",
        requiredBallLockSeconds: 3.0,
        countdownDuration: 4.0,
        requiredSuccessfulHits: 25,
        allowedMisses: 5,
        targetLifetime: 4.0,
        spawnTopFraction: 0.75,
        addsRadiusToSpawnTop: true,
        spawnBottomFraction: nil,
        showsNextLevelButton: true
    )

    static let levelTen = PracticeBallTargetConfiguration(
        loadingMessage: "Starting level 10...",
        requiredBallLockSeconds: 3.0,
        countdownDuration: 4.0,
        requiredSuccessfulHits: 25,
        allowedMisses: 5,
        targetLifetime: 4.0,
        spawnTopFraction: 0.55,
        addsRadiusToSpawnTop: false,
        spawnBottomFraction: 0.75,
        showsNextLevelButton: false
    )
}

struct PracticeBallTargetLevelView<NextDestination: View>: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator: PracticeBallTargetCoordinator
    @State private var showsQuitConfirmation = false
    @State private var showsNextLevel = false

    private let nextLevelDestination: () -> NextDestination

    init(
        configuration: PracticeBallTargetConfiguration,
        @ViewBuilder nextLevelDestination: @escaping () -> NextDestination
    ) {
        _coordinator = StateObject(wrappedValue: PracticeBallTargetCoordinator(configuration: configuration))
        self.nextLevelDestination = nextLevelDestination
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

                PracticeBallTargetRenderSurface(coordinator: coordinator)
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
                    PracticeLevelLoadingOverlay(message: coordinator.loadingMessage)
                }

                if let errorMessage = cameraController.errorMessage {
                    PracticeLevelErrorOverlay(
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
                        showsNextLevelButton: coordinator.showsNextLevelButton,
                        onNextLevel: { showsNextLevel = true },
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }
            }
            .statusBarHidden(true)
            .navigationDestination(isPresented: $showsNextLevel) {
                nextLevelDestination()
                    .navigationBarBackButtonHidden(true)
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
            PracticeLevelHudChip(
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
            PracticeLevelHudChip(
                title: "HITS",
                value: "\(coordinator.successfulHits)/\(coordinator.requiredSuccessfulHits)",
                tint: .yellow,
                alignment: .trailing
            )
        }
    }
}

private final class PracticeBallTargetCoordinator: ObservableObject {
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
    @Published private(set) var misses = 0
    @Published private(set) var finishStartedAt: Date?
    @Published private(set) var showsFinishButtons = false
    @Published private(set) var finishState: FinishState = .none

    private let finishAnimationDuration: TimeInterval = 1.2
    private let finishButtonRevealDelay: TimeInterval = 0.28
    private let configuration: PracticeBallTargetConfiguration

    private var gameState: PracticeBallTargetGameState
    private var size: CGSize = .zero
    private weak var renderView: PracticeBallTargetRenderView?
    private var finishWorkItem: DispatchWorkItem?

    init(configuration: PracticeBallTargetConfiguration) {
        self.configuration = configuration
        gameState = PracticeBallTargetGameState(configuration: configuration)
    }

    var hasEnded: Bool {
        finishState != .none
    }

    var didComplete: Bool {
        finishState == .completed
    }

    var finishTitle: String {
        didComplete ? "DONE" : "TRY AGAIN"
    }

    var showsNextLevelButton: Bool {
        didComplete && configuration.showsNextLevelButton
    }

    var requiredSuccessfulHits: Int {
        configuration.requiredSuccessfulHits
    }

    var loadingMessage: String {
        configuration.loadingMessage
    }

    func attach(renderView: PracticeBallTargetRenderView) {
        self.renderView = renderView
        renderView.update(
            ballDisplayRect: nil,
            isTracking: isTracking,
            target: gameState.target,
            scorePopups: gameState.scorePopups
        )
    }

    func reset(in size: CGSize) {
        cancelFinishWorkItem()
        gameState = PracticeBallTargetGameState(configuration: configuration)
        startPhase = .readiness
        ballFoundStartedAt = nil
        countdownStartedAt = nil
        hitStreak = 0
        isTracking = false
        trackingStatusText = "SEARCHING"
        successfulHits = 0
        misses = 0
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
            target: gameState.target,
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
            case .hit:
                successfulHits += 1
                PracticeTargetScoreSoundPlayer.playScore(failureContext: "Ball target score")
                if successfulHits >= configuration.requiredSuccessfulHits {
                    finish(.completed, at: frame.timestamp)
                }
            case .miss:
                misses += 1
                if let allowedMisses = configuration.allowedMisses, misses >= allowedMisses {
                    finish(.failed, at: frame.timestamp)
                }
            case nil:
                break
            }

            syncHudFromGameState()
        }

        renderView?.update(
            ballDisplayRect: ballDisplayRect,
            isTracking: overlayState.isTracking,
            target: gameState.target,
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
                timestamp.timeIntervalSince(countdownStartedAt) >= configuration.countdownDuration
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

        if timestamp.timeIntervalSince(startedAt) >= configuration.requiredBallLockSeconds {
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
            target: gameState.target,
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

private struct PracticeBallTargetRenderSurface: UIViewRepresentable {
    let coordinator: PracticeBallTargetCoordinator

    func makeUIView(context: Context) -> PracticeBallTargetRenderView {
        let view = PracticeBallTargetRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: PracticeBallTargetRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class PracticeBallTargetRenderView: UIView {
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
    private var target: PracticeBallTargetTarget?
    private var scorePopups: [PracticeBallTargetScorePopup] = []

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
        target: PracticeBallTargetTarget?,
        scorePopups: [PracticeBallTargetScorePopup]
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

        [
            targetFillLayer,
            targetOuterLayer,
            targetInnerLayer,
            targetProgressLayer,
            ballRingLayer,
            ballCenterLayer
        ].forEach(layer.addSublayer)

        ballRingLayer.fillColor = UIColor.clear.cgColor
        ballRingLayer.strokeColor = UIColor.white.cgColor
        ballRingLayer.lineWidth = 2.5
        ballRingLayer.shadowColor = UIColor.black.cgColor
        ballRingLayer.shadowOpacity = 0.45
        ballRingLayer.shadowRadius = 6
        ballRingLayer.shadowOffset = .zero
        ballCenterLayer.fillColor = UIColor.orange.cgColor

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

        let rect = CGRect(
            x: target.center.x - target.radius,
            y: target.center.y - target.radius,
            width: target.radius * 2,
            height: target.radius * 2
        )
        let innerRect = rect.insetBy(dx: 8, dy: 8)

        targetFillLayer.isHidden = false
        targetOuterLayer.isHidden = false
        targetInnerLayer.isHidden = false
        targetFillLayer.path = UIBezierPath(ovalIn: rect).cgPath
        targetOuterLayer.path = UIBezierPath(ovalIn: rect).cgPath
        targetInnerLayer.path = UIBezierPath(ovalIn: innerRect).cgPath

        if let lifetime = target.lifetime {
            let ageProgress = min(max(date.timeIntervalSince(target.spawnedAt) / lifetime, 0), 1)
            let alpha = CGFloat(1.0 - ageProgress) * 0.5
            let progressRadius = max(target.radius - 16, 1)
            let remainingProgress = max(CGFloat(0.02), 1.0 - CGFloat(ageProgress))

            targetProgressLayer.isHidden = false
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
            targetProgressLayer.opacity = Float(1.0 - ageProgress)
        } else {
            targetProgressLayer.isHidden = true
            targetProgressLayer.path = nil
            targetFillLayer.opacity = 1
            targetOuterLayer.opacity = 1
            targetInnerLayer.opacity = 1
        }
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

    private func makePopupLayer(for popup: PracticeBallTargetScorePopup) -> CATextLayer {
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

    private func smoothStep(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }
}

private struct PracticeBallTargetGameState {
    let configuration: PracticeBallTargetConfiguration

    var target: PracticeBallTargetTarget?
    var scorePopups: [PracticeBallTargetScorePopup] = []
    var hitStreak = 0

    private let popupValue = 5
    private let clearance: CGFloat = 20

    init(configuration: PracticeBallTargetConfiguration) {
        self.configuration = configuration
    }

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

    mutating func finish() {
        target = nil
    }

    mutating func step(
        overlayState: BallTrackerOverlayState,
        ballDisplayRect: CGRect?,
        in size: CGSize,
        timestamp: Date
    ) -> PracticeBallTargetStepEvent? {
        scorePopups.removeAll { !$0.isActive(at: timestamp) }
        prepare(in: size)

        guard let currentTarget = target else {
            return nil
        }

        if hasExpired(currentTarget, at: timestamp) {
            hitStreak = 0
            scorePopups.append(
                PracticeBallTargetScorePopup(
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

        hitStreak += 1
        scorePopups.append(
            PracticeBallTargetScorePopup(
                points: popupValue,
                center: currentTarget.center,
                destination: CGPoint(x: max(size.width - 104, 40), y: 40),
                startedAt: timestamp
            )
        )
        spawnTarget(in: size, timestamp: timestamp, previousCenter: currentTarget.center, avoiding: ballDisplayRect)
        return .hit
    }

    private func hasExpired(_ target: PracticeBallTargetTarget, at timestamp: Date) -> Bool {
        guard let lifetime = configuration.targetLifetime else {
            return false
        }
        return max(0, timestamp.timeIntervalSince(target.spawnedAt)) >= lifetime
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
                target = PracticeBallTargetTarget(
                    center: candidate,
                    radius: radius,
                    spawnedAt: timestamp,
                    lifetime: configuration.targetLifetime
                )
                return
            }
        }

        target = PracticeBallTargetTarget(
            center: bestCandidate,
            radius: radius,
            spawnedAt: timestamp,
            lifetime: configuration.targetLifetime
        )
    }

    private func targetRadius(for size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.091, 36), 62)
    }

    private func spawnBounds(in size: CGSize, radius: CGFloat) -> CGRect {
        let horizontalPadding = radius + 26
        let rawTop = size.height * configuration.spawnTopFraction + (configuration.addsRadiusToSpawnTop ? radius : 0)
        let top = max(rawTop, radius + 76)
        let preferredBottom = configuration.spawnBottomFraction.map { size.height * $0 } ?? (size.height - radius - 58)
        let cappedBottom = min(preferredBottom, size.height - radius - 58)
        let bottom = max(top, cappedBottom)
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

private struct PracticeBallTargetTarget {
    let center: CGPoint
    let radius: CGFloat
    let spawnedAt: Date
    let lifetime: TimeInterval?
}

private struct PracticeBallTargetScorePopup: Identifiable {
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

private enum PracticeBallTargetStepEvent {
    case hit
    case miss
}
