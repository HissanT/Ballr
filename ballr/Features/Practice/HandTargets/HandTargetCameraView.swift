import AVFoundation
import Foundation
import SwiftUI
import UIKit
import Combine

enum HandTargetNextDestination {
    case footTargets
    case levelEight
}

struct HandTargetConfiguration {
    let requiredHandLockSeconds: TimeInterval
    let requiredSuccessfulHits: Int
    let targetLifetime: TimeInterval?
    let allowedMisses: Int?
    let targetRadiusScale: CGFloat
    let fullValueWindow: TimeInterval
    let scoreStep: TimeInterval
    let scoreValue: Int
    let comboStreakStep: Int
    let spawnTopFraction: CGFloat
    let previousTargetDistanceMultiplier: CGFloat

    static let levelTwo = HandTargetConfiguration(
        requiredHandLockSeconds: 3.0,
        requiredSuccessfulHits: 20,
        targetLifetime: nil,
        allowedMisses: nil,
        targetRadiusScale: 1.0,
        fullValueWindow: 2.0,
        scoreStep: 0.4,
        scoreValue: 5,
        comboStreakStep: 10,
        spawnTopFraction: 0.20,
        previousTargetDistanceMultiplier: 4.0
    )

    static let levelSevenTimed = HandTargetConfiguration(
        requiredHandLockSeconds: 2.0,
        requiredSuccessfulHits: 25,
        targetLifetime: 3.0,
        allowedMisses: 5,
        targetRadiusScale: 0.82,
        fullValueWindow: 1.0,
        scoreStep: 0.32,
        scoreValue: 5,
        comboStreakStep: 8,
        spawnTopFraction: 0.16,
        previousTargetDistanceMultiplier: 4.6
    )
}

struct HandTargetCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = HandPoseCameraController()
    @StateObject private var coordinator: HandTargetCoordinator
    @State private var showsQuitConfirmation = false
    @State private var showsNextLevel = false
    private let nextDestination: HandTargetNextDestination

    init(
        nextDestination: HandTargetNextDestination = .footTargets,
        configuration: HandTargetConfiguration = .levelTwo
    ) {
        self.nextDestination = nextDestination
        _coordinator = StateObject(wrappedValue: HandTargetCoordinator(configuration: configuration))
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

                HandTargetRenderSurface(coordinator: coordinator)
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
                    HandTargetLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    HandTargetErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.startPhase == .readiness && cameraController.errorMessage == nil {
                    HandTargetReadinessOverlay(
                        handFoundStartedAt: coordinator.handFoundStartedAt,
                        requiredLockSeconds: coordinator.requiredHandLockSeconds
                    )
                }

                if coordinator.hasEnded {
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.completionStartedAt,
                        buttonsVisible: coordinator.showsCompletionButtons,
                        title: coordinator.finishTitle,
                        showsNextLevelButton: coordinator.didComplete,
                        onNextLevel: { showsNextLevel = true },
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .navigationDestination(isPresented: $showsNextLevel) {
                switch nextDestination {
                case .footTargets:
                    FootTargetCameraView()
                        .ballrCameraPresentationChrome()
                case .levelEight:
                    LevelEightCameraView()
                        .ballrCameraPresentationChrome()
                }
            }
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(in: geometry.size)
                cameraController.publishesTrackingFramesToSwiftUI = false
                cameraController.onTrackingFrame = { [weak coordinator] frame in
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
            HandTargetHudChip(
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

            HandTargetHudChip(
                title: "HITS",
                value: "\(coordinator.successfulHits)/\(coordinator.requiredSuccessfulHits)",
                tint: .yellow,
                alignment: .trailing
            )
        }
    }
}

private final class HandTargetCoordinator: ObservableObject {
    enum FinishState {
        case none
        case completed
        case failed
    }

    @Published private(set) var startPhase: BallrDrillStartPhase = .readiness
    @Published private(set) var handFoundStartedAt: Date?
    @Published private(set) var score = 0
    @Published private(set) var hitStreak = 0
    @Published private(set) var successfulHits = 0
    @Published private(set) var misses = 0
    @Published private(set) var lastEventText = "READY"
    @Published private(set) var lastEventIsPositive = true
    @Published private(set) var isTracking = false
    @Published private(set) var trackingStatusText = "SEARCHING"
    @Published private(set) var completionStartedAt: Date?
    @Published private(set) var showsCompletionButtons = false
    @Published private(set) var finishState: FinishState = .none

    private let completionAnimationDuration: TimeInterval = 1.2
    private let completionButtonRevealDelay: TimeInterval = 0.28
    private let configuration: HandTargetConfiguration

    private var gameState: HandTargetGameState
    private var size: CGSize = .zero
    private weak var renderView: HandTargetRenderView?
    private var lastDetectedHands: [HandTargetDetectedHand] = []
    private var completionWorkItem: DispatchWorkItem?

    init(configuration: HandTargetConfiguration = .levelTwo) {
        self.configuration = configuration
        gameState = HandTargetGameState(configuration: configuration)
    }

    var isCompleted: Bool {
        finishState == .completed
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

    var requiredSuccessfulHits: Int {
        configuration.requiredSuccessfulHits
    }

    private var allowedMisses: Int? {
        configuration.allowedMisses
    }

    var requiredHandLockSeconds: TimeInterval {
        configuration.requiredHandLockSeconds
    }

    func attach(renderView: HandTargetRenderView) {
        if self.renderView !== renderView {
            self.renderView = renderView
            renderView.onBoundsChange = { [weak self] size in
                self?.prepare(in: size)
            }
        }

        let renderSize = renderView.bounds.size
        if renderSize.width > 0, renderSize.height > 0 {
            size = renderSize
        }

        renderView.update(
            hands: lastDetectedHands,
            isTracking: isTracking,
            target: gameState.target,
            scorePopups: gameState.scorePopups
        )
    }

    func reset(in size: CGSize) {
        gameState = HandTargetGameState(configuration: configuration)
        startPhase = .readiness
        handFoundStartedAt = nil
        score = 0
        hitStreak = 0
        successfulHits = 0
        misses = 0
        lastEventText = "READY"
        lastEventIsPositive = true
        isTracking = false
        trackingStatusText = "SEARCHING"
        completionStartedAt = nil
        showsCompletionButtons = false
        finishState = .none
        lastDetectedHands = []
        cancelCompletionWorkItem()
        prepare(in: size, forceRespawn: true)
    }

    func tearDown() {
        cancelCompletionWorkItem()
    }

    func prepare(in size: CGSize, forceRespawn: Bool = false) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        self.size = resolvedGameplaySize(fallback: size)
        gameState.prepare(in: self.size, forceRespawn: forceRespawn, allowSpawn: startPhase == .live && !hasEnded)
        renderView?.update(
            hands: lastDetectedHands,
            isTracking: isTracking,
            target: gameState.target,
            scorePopups: gameState.scorePopups
        )
    }

    func handle(frame: HandPoseFrame, cameraController: HandPoseCameraController) {
        let detectedHands = frame.overlayState.hands.compactMap { handState -> HandTargetDetectedHand? in
            guard let displayRect = cameraController.displayRect(for: handState.normalizedRect) else {
                return nil
            }
            let displayPoints = handState.normalizedPoints.compactMap {
                cameraController.displayPoint(for: $0)
            }
            return HandTargetDetectedHand(
                id: handState.id,
                rect: displayRect,
                collisionPolygon: HandTargetDetectedHand.collisionPolygon(
                    from: displayPoints,
                    fallbackRect: displayRect
                ),
                confidence: CGFloat(handState.confidence)
            )
        }
        lastDetectedHands = detectedHands

        updateTrackingStatus(from: frame.overlayState)
        updateStartGate(isTracking: frame.overlayState.isTracking, timestamp: frame.timestamp)

        if startPhase == .live, !hasEnded {
            let event = gameState.step(
                hands: detectedHands,
                isTracking: frame.overlayState.isTracking,
                in: size,
                timestamp: frame.timestamp
            )
            switch event {
            case .hit:
                if gameState.didStartComboOnLastHit {
                    BallrDrillSoundPlayer.playCombo()
                } else {
                    HandTargetSoundPlayer.playScore()
                }
                successfulHits += 1
                if successfulHits >= configuration.requiredSuccessfulHits {
                    finish(.completed, at: frame.timestamp)
                }
            case .miss:
                misses = gameState.misses
                if let allowedMisses, misses >= allowedMisses {
                    finish(.failed, at: frame.timestamp)
                }
            case nil:
                break
            }
            syncHudFromGameState()
        }

        renderView?.update(
            hands: detectedHands,
            isTracking: frame.overlayState.isTracking,
            target: gameState.target,
            scorePopups: gameState.scorePopups
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

    private func updateTrackingStatus(from overlayState: HandPoseOverlayState) {
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

        guard isTracking else {
            handFoundStartedAt = nil
            return
        }

        let startedAt = handFoundStartedAt ?? timestamp
        handFoundStartedAt = startedAt

        if timestamp.timeIntervalSince(startedAt) >= requiredHandLockSeconds {
            startPhase = .live
            lastEventText = "GO"
            lastEventIsPositive = true
        }
    }

    private func syncHudFromGameState() {
        if score != gameState.score {
            score = gameState.score
        }
        if hitStreak != gameState.hitStreak {
            hitStreak = gameState.hitStreak
        }
        if misses != gameState.misses {
            misses = gameState.misses
        }
        if lastEventText != gameState.lastEventText {
            lastEventText = gameState.lastEventText
        }
        if lastEventIsPositive != gameState.lastEventIsPositive {
            lastEventIsPositive = gameState.lastEventIsPositive
        }
    }

    private func finish(_ state: FinishState, at timestamp: Date) {
        guard finishState == .none else {
            return
        }

        if state == .completed {
            BallrDrillSoundPlayer.playWinner()
        }

        finishState = state
        completionStartedAt = timestamp
        showsCompletionButtons = false
        gameState.finish()
        renderView?.update(
            hands: lastDetectedHands,
            isTracking: isTracking,
            target: gameState.target,
            scorePopups: gameState.scorePopups
        )

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
}

private struct HandTargetRenderSurface: UIViewRepresentable {
    let coordinator: HandTargetCoordinator

    func makeUIView(context: Context) -> HandTargetRenderView {
        let view = HandTargetRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: HandTargetRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class HandTargetRenderView: UIView {
    private let targetFillLayer = CAShapeLayer()
    private let targetOuterLayer = CAShapeLayer()
    private let targetInnerLayer = CAShapeLayer()
    private let targetProgressLayer = CAShapeLayer()
    private let promptLabel = UILabel()

    private var popupLayers: [UUID: CATextLayer] = [:]
    private var displayLink: CADisplayLink?
    private var hands: [HandTargetDetectedHand] = []
    private var isTracking = false
    private var target: HandTargetTarget?
    private var scorePopups: [HandTargetScorePopup] = []
    private var missingHandFrameCount = 0
    var onBoundsChange: ((CGSize) -> Void)?
    private var lastReportedBoundsSize: CGSize = .zero
    private let missingHandPromptFrameThreshold = 12

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
        hands: [HandTargetDetectedHand],
        isTracking: Bool,
        target: HandTargetTarget?,
        scorePopups: [HandTargetScorePopup]
    ) {
        self.hands = hands
        self.isTracking = isTracking
        self.target = target
        self.scorePopups = scorePopups
        missingHandFrameCount = isTracking ? 0 : missingHandFrameCount + 1
        render(date: Date())
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportBoundsIfNeeded()
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
            targetProgressLayer
        ].forEach(layer.addSublayer)

        promptLabel.text = "Find your hand"
        promptLabel.font = .systemFont(ofSize: 15, weight: .black)
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        promptLabel.layer.cornerRadius = 8
        promptLabel.layer.masksToBounds = true
        addSubview(promptLabel)
    }

    private func reportBoundsIfNeeded() {
        guard bounds.size != lastReportedBoundsSize else {
            return
        }

        lastReportedBoundsSize = bounds.size
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        onBoundsChange?(bounds.size)
    }

    @objc private func renderFrame() {
        render(date: Date())
    }

    private func render(date: Date) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderTarget(date: date)
        renderHands()
        renderPopups(date: date)
        promptLabel.isHidden = isTracking || missingHandFrameCount < missingHandPromptFrameThreshold || target == nil
        let promptSize = CGSize(width: 180, height: 42)
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
        let targetProgress = targetAgeProgress(for: target, at: date)
        let progressRadius = max(target.radius - 16, 1)
        let remainingProgress = max(CGFloat(0.02), 1.0 - CGFloat(targetProgress))

        targetFillLayer.isHidden = false
        targetOuterLayer.isHidden = false
        targetInnerLayer.isHidden = false
        targetFillLayer.path = UIBezierPath(ovalIn: rect).cgPath
        targetOuterLayer.path = UIBezierPath(ovalIn: rect).cgPath
        targetInnerLayer.path = UIBezierPath(ovalIn: innerRect).cgPath
        targetFillLayer.opacity = 1
        targetOuterLayer.opacity = 1
        targetInnerLayer.opacity = 1

        if target.lifetime == nil {
            targetProgressLayer.isHidden = true
            targetProgressLayer.path = nil
            targetProgressLayer.opacity = 0
        } else {
            targetProgressLayer.isHidden = false
            targetProgressLayer.path = UIBezierPath(
                arcCenter: target.center,
                radius: progressRadius,
                startAngle: -.pi / 2,
                endAngle: -.pi / 2 + (.pi * 2 * remainingProgress),
                clockwise: true
            ).cgPath
            targetProgressLayer.opacity = Float(1.0 - targetProgress)
        }
    }

    private func renderHands() {
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

    private func makePopupLayer(for popup: HandTargetScorePopup) -> CATextLayer {
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

    private func targetAgeProgress(for target: HandTargetTarget, at date: Date) -> Double {
        guard let lifetime = target.lifetime else {
            return 0
        }
        return min(max(date.timeIntervalSince(target.spawnedAt) / lifetime, 0), 1)
    }
}

private struct HandTargetDetectedHand: Identifiable {
    let id: Int
    let rect: CGRect
    let collisionPolygon: [CGPoint]
    let confidence: CGFloat

    var collisionBounds: CGRect {
        Self.boundingRect(for: collisionPolygon) ?? rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)
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
        let sortedPoints = points
            .sorted {
                if abs($0.x - $1.x) > 0.001 {
                    return $0.x < $1.x
                }
                return $0.y < $1.y
            }
            .reduce(into: [CGPoint]()) { result, point in
                guard !result.contains(where: { hypot($0.x - point.x, $0.y - point.y) < 0.5 }) else {
                    return
                }
                result.append(point)
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
        guard !points.isEmpty else {
            return []
        }

        let center = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        let centroid = CGPoint(
            x: center.x / CGFloat(points.count),
            y: center.y / CGFloat(points.count)
        )

        return points.map {
            CGPoint(
                x: centroid.x + ($0.x - centroid.x) * factor,
                y: centroid.y + ($0.y - centroid.y) * factor
            )
        }
    }

    private static func boundingRect(for points: [CGPoint]) -> CGRect? {
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

private struct HandTargetHudChip: View {
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

private struct HandTargetReadinessOverlay: View {
    let handFoundStartedAt: Date?

    private let requiredLockSeconds: TimeInterval

    init(handFoundStartedAt: Date?, requiredLockSeconds: TimeInterval = 3.0) {
        self.handFoundStartedAt = handFoundStartedAt
        self.requiredLockSeconds = requiredLockSeconds
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = readinessProgress(at: timeline.date)

            ZStack {
                Color.black.opacity(0.86)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Text(handFoundStartedAt == nil ? "Find your hand" : "Hold your hand still")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(handFoundStartedAt == nil ? Color.yellow : .white)

                    Text(handFoundStartedAt == nil ? "Put your hand in frame to start." : "Starting in \(remainingText(at: timeline.date))")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.16))

                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.yellow)
                            .frame(width: 220 * progress)
                    }
                    .frame(width: 220, height: 12)
                    .opacity(handFoundStartedAt == nil ? 0 : 1)
                }
                .padding(.horizontal, 24)
            }
            .allowsHitTesting(false)
        }
    }

    private func readinessProgress(at date: Date) -> CGFloat {
        guard let handFoundStartedAt else {
            return 0
        }
        return CGFloat(min(max(date.timeIntervalSince(handFoundStartedAt) / requiredLockSeconds, 0), 1))
    }

    private func remainingText(at date: Date) -> String {
        guard let handFoundStartedAt else {
            return "3"
        }
        let remaining = max(ceil(requiredLockSeconds - date.timeIntervalSince(handFoundStartedAt)), 0)
        return "\(Int(remaining))"
    }
}

private struct HandTargetLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting hand targets...")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HandTargetErrorOverlay: View {
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

private struct HandTargetGameState {
    let configuration: HandTargetConfiguration
    var target: HandTargetTarget?
    var scorePopups: [HandTargetScorePopup] = []
    var score = 0
    var hitStreak = 0
    var misses = 0
    var lastEventText = "READY"
    var lastEventIsPositive = true
    private(set) var didStartComboOnLastHit = false
    private var lastAnnouncedComboMultiplier = 1

    private let baseClearance: CGFloat = 24

    init(configuration: HandTargetConfiguration = .levelTwo) {
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
        hands: [HandTargetDetectedHand],
        isTracking: Bool,
        in size: CGSize,
        timestamp: Date
    ) -> HandTargetStepEvent? {
        scorePopups.removeAll { !$0.isActive(at: timestamp) }
        didStartComboOnLastHit = false
        prepare(in: size)

        guard let currentTarget = target else {
            return nil
        }

        if hasExpired(currentTarget, at: timestamp) {
            misses += 1
            hitStreak = 0
            lastAnnouncedComboMultiplier = 1
            lastEventText = "MISS"
            lastEventIsPositive = false
            scorePopups.append(
                HandTargetScorePopup(
                    points: -1,
                    center: currentTarget.center,
                    destination: CGPoint(x: 104, y: 40),
                    startedAt: timestamp
                )
            )
            spawnTarget(in: size, timestamp: timestamp, previousCenter: currentTarget.center, avoiding: hands)
            return .miss
        }

        guard isTracking, !hands.isEmpty else {
            return nil
        }

        if hands.contains(where: { handIntersectsTarget($0, target: currentTarget) }) {
            let awardedComboMultiplier = comboMultiplier
            let points = basePoints(for: currentTarget, at: timestamp) * awardedComboMultiplier
            score += points
            didStartComboOnLastHit = awardedComboMultiplier > lastAnnouncedComboMultiplier
            lastAnnouncedComboMultiplier = awardedComboMultiplier
            hitStreak += 1
            lastEventText = "+\(points)"
            lastEventIsPositive = true
            scorePopups.append(
                HandTargetScorePopup(
                    points: points,
                    center: currentTarget.center,
                    destination: CGPoint(x: max(size.width - 104, 40), y: 40),
                    startedAt: timestamp
                )
            )
            spawnTarget(in: size, timestamp: timestamp, previousCenter: currentTarget.center, avoiding: hands)
            return .hit
        }

        return nil
    }

    private var comboMultiplier: Int {
        1 + max(hitStreak, 0) / configuration.comboStreakStep
    }

    private func basePoints(for target: HandTargetTarget, at timestamp: Date) -> Int {
        let age = targetAge(for: target, at: timestamp)
        guard age > configuration.fullValueWindow else {
            return configuration.scoreValue
        }

        let elapsedAfterFullValue = age - configuration.fullValueWindow
        let steps = Int(floor(elapsedAfterFullValue / configuration.scoreStep)) + 1
        return max(1, configuration.scoreValue - steps)
    }

    private func targetAge(for target: HandTargetTarget, at timestamp: Date) -> TimeInterval {
        max(0, timestamp.timeIntervalSince(target.spawnedAt))
    }

    private func hasExpired(_ target: HandTargetTarget, at timestamp: Date) -> Bool {
        guard let lifetime = target.lifetime else {
            return false
        }
        return targetAge(for: target, at: timestamp) >= lifetime
    }

    private mutating func spawnTarget(
        in size: CGSize,
        timestamp: Date,
        previousCenter: CGPoint? = nil,
        avoiding hands: [HandTargetDetectedHand] = []
    ) {
        let radius = targetRadius(for: size)
        let bounds = spawnBounds(in: size, radius: radius)

        var bestCandidate = CGPoint(x: bounds.midX, y: bounds.midY)
        var bestQuality = CGFloat.leastNonzeroMagnitude

        for _ in 0..<72 {
            let candidate = CGPoint(
                x: CGFloat.random(in: bounds.minX...bounds.maxX),
                y: CGFloat.random(in: bounds.minY...bounds.maxY)
            )
            let quality = candidateQuality(
                candidate,
                previousCenter: previousCenter,
                hands: hands,
                targetRadius: radius
            )
            if quality > bestQuality {
                bestCandidate = candidate
                bestQuality = quality
            }
            if isCandidateValid(
                candidate,
                previousCenter: previousCenter,
                hands: hands,
                targetRadius: radius
            ) {
                target = HandTargetTarget(
                    center: candidate,
                    radius: radius,
                    spawnedAt: timestamp,
                    lifetime: configuration.targetLifetime
                )
                return
            }
        }

        target = HandTargetTarget(
            center: bestCandidate,
            radius: radius,
            spawnedAt: timestamp,
            lifetime: configuration.targetLifetime
        )
    }

    private func targetRadius(for size: CGSize) -> CGFloat {
        min(max(min(size.width, size.height) * 0.091 * configuration.targetRadiusScale, 30), 62)
    }

    private func spawnBounds(in size: CGSize, radius: CGFloat) -> CGRect {
        let horizontalPadding = radius + 26
        let top = max(size.height * configuration.spawnTopFraction + radius, radius + 86)
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
        hands: [HandTargetDetectedHand],
        targetRadius: CGFloat
    ) -> CGFloat {
        var quality = targetRadius * 10

        if let previousCenter {
            quality += hypot(candidate.x - previousCenter.x, candidate.y - previousCenter.y)
        }

        if let farthestHandDistance = hands.map({ distance(from: candidate, to: $0) }).min() {
            quality += max(farthestHandDistance - targetRadius, 0)
        }

        return quality
    }

    private func isCandidateValid(
        _ candidate: CGPoint,
        previousCenter: CGPoint?,
        hands: [HandTargetDetectedHand],
        targetRadius: CGFloat
    ) -> Bool {
        if let previousCenter {
            let previousDistance = hypot(candidate.x - previousCenter.x, candidate.y - previousCenter.y)
            if previousDistance < targetRadius * configuration.previousTargetDistanceMultiplier {
                return false
            }
        }

        for hand in hands {
            let bounds = hand.collisionBounds
            let requiredClearance = targetRadius + max(baseClearance, min(bounds.width, bounds.height) * 0.2)
            if distance(from: candidate, to: hand) < requiredClearance {
                return false
            }
        }

        return true
    }

    private func handIntersectsTarget(_ hand: HandTargetDetectedHand, target: HandTargetTarget) -> Bool {
        distance(from: target.center, to: hand) <= target.radius
    }

    private func distance(from point: CGPoint, to hand: HandTargetDetectedHand) -> CGFloat {
        let polygon = hand.collisionPolygon
        guard polygon.count >= 3 else {
            return distance(from: point, to: hand.collisionBounds)
        }

        if polygonContains(point, polygon: polygon) {
            return 0
        }

        var minimumDistance = CGFloat.greatestFiniteMagnitude
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            minimumDistance = min(minimumDistance, distance(from: point, toSegmentFrom: start, to: end))
        }
        return minimumDistance
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        return hypot(point.x - clampedX, point.y - clampedY)
    }

    private func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        let projected = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projected.x, point.y - projected.y)
    }

    private func polygonContains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        var contains = false
        var previousIndex = polygon.count - 1

        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[previousIndex]
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            let denominator = previous.y - current.y
            if crossesY, abs(denominator) > 0.000001 {
                let intersectionX = (previous.x - current.x) * (point.y - current.y) / denominator + current.x
                if point.x < intersectionX {
                    contains.toggle()
                }
            }
            previousIndex = index
        }

        return contains
    }
}

private struct HandTargetTarget {
    let center: CGPoint
    let radius: CGFloat
    let spawnedAt: Date
    let lifetime: TimeInterval?
}

private struct HandTargetScorePopup: Identifiable {
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

private enum HandTargetStepEvent {
    case hit
    case miss
}

private enum HandTargetSoundPlayer {
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
                print("Hand target score sound failed to load: \(error.localizedDescription)")
                return
            }
        }

        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}
