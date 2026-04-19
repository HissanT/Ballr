import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct LevelTenCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = LevelTenCoordinator()
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

                LevelTenRenderSurface(coordinator: coordinator)
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
                    LevelTenLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    LevelTenErrorOverlay(
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
                        showsNextLevelButton: false,
                        onNextLevel: {},
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }
            }
            .statusBarHidden(true)
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
            LevelTenHudChip(
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
            LevelTenHudChip(
                title: "HITS",
                value: "\(coordinator.successfulHits)/25",
                tint: .yellow,
                alignment: .trailing
            )
        }
    }
}

private final class LevelTenCoordinator: ObservableObject {
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

    private let requiredBallLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let requiredSuccessfulHits = 25
    private let allowedMisses = 5
    private let finishAnimationDuration: TimeInterval = 1.2
    private let finishButtonRevealDelay: TimeInterval = 0.28

    private var gameState = LevelTenGameState()
    private var size: CGSize = .zero
    private weak var renderView: LevelTenRenderView?
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

    func attach(renderView: LevelTenRenderView) {
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
        gameState = LevelTenGameState()
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
                LevelTenSoundPlayer.playScore()
                if successfulHits >= requiredSuccessfulHits {
                    finish(.completed, at: frame.timestamp)
                }
            case .miss:
                misses += 1
                if misses >= allowedMisses {
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

private struct LevelTenRenderSurface: UIViewRepresentable {
    let coordinator: LevelTenCoordinator

    func makeUIView(context: Context) -> LevelTenRenderView {
        let view = LevelTenRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: LevelTenRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class LevelTenRenderView: UIView {
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
    private var target: LevelTenTarget?
    private var scorePopups: [LevelTenScorePopup] = []

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
        target: LevelTenTarget?,
        scorePopups: [LevelTenScorePopup]
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

        let alpha = CGFloat(1.0 - targetAgeProgress(for: target, at: date)) * 0.5
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
        targetProgressLayer.opacity = Float(1.0 - targetAgeProgress(for: target, at: date))
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

    private func makePopupLayer(for popup: LevelTenScorePopup) -> CATextLayer {
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

    private func targetAgeProgress(for target: LevelTenTarget, at date: Date) -> Double {
        min(max(date.timeIntervalSince(target.spawnedAt) / LevelTenGameState.targetLifetime, 0), 1)
    }

    private func smoothStep(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }
}

private struct LevelTenHudChip: View {
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

private struct LevelTenLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting level 10...")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LevelTenErrorOverlay: View {
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

private struct LevelTenGameState {
    static let targetLifetime: TimeInterval = 4.0

    var target: LevelTenTarget?
    var scorePopups: [LevelTenScorePopup] = []
    var hitStreak = 0
    var misses = 0

    private let popupValue = 5
    private let spawnTopFraction: CGFloat = 0.45
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

    mutating func finish() {
        target = nil
    }

    mutating func step(
        overlayState: BallTrackerOverlayState,
        ballDisplayRect: CGRect?,
        in size: CGSize,
        timestamp: Date
    ) -> LevelTenStepEvent? {
        scorePopups.removeAll { !$0.isActive(at: timestamp) }
        prepare(in: size)

        guard let currentTarget = target else {
            return nil
        }

        if targetAge(for: currentTarget, at: timestamp) >= Self.targetLifetime {
            misses += 1
            hitStreak = 0
            scorePopups.append(
                LevelTenScorePopup(
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
            LevelTenScorePopup(
                points: popupValue,
                center: currentTarget.center,
                destination: CGPoint(x: max(size.width - 104, 40), y: 40),
                startedAt: timestamp
            )
        )
        spawnTarget(in: size, timestamp: timestamp, previousCenter: currentTarget.center, avoiding: ballDisplayRect)
        return .hit
    }

    private func targetAge(for target: LevelTenTarget, at timestamp: Date) -> TimeInterval {
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
                target = LevelTenTarget(center: candidate, radius: radius, spawnedAt: timestamp)
                return
            }
        }

        target = LevelTenTarget(center: bestCandidate, radius: radius, spawnedAt: timestamp)
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

private struct LevelTenTarget {
    let center: CGPoint
    let radius: CGFloat
    let spawnedAt: Date
}

private struct LevelTenScorePopup: Identifiable {
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

private enum LevelTenStepEvent {
    case hit
    case miss
}

private enum LevelTenSoundPlayer {
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
                print("Level 10 score sound failed to load: \(error.localizedDescription)")
                return
            }
        }

        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}
