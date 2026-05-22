import Combine
import Foundation
import SwiftUI
import UIKit

struct FastTouchingCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = FastTouchingCameraController()
    @StateObject private var coordinator = FastTouchingCoordinator()
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

                FastTouchingRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                if coordinator.phase == .readiness {
                    FastTouchingJeffStandingOverlay()
                        .zIndex(90)
                } else if coordinator.phase == .live {
                    FastTouchingJeffPlantedOverlay(
                        scoreText: "\(coordinator.touchCount)",
                        timeText: coordinator.timerText
                    )
                    .zIndex(90)
                }

                if coordinator.phase == .readiness || coordinator.phase == .countdown || coordinator.phase == .live {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

                if cameraController.isStarting {
                    FastTouchingLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    FastTouchingErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.phase == .readiness, cameraController.errorMessage == nil {
                    FastTouchingReadinessOverlay(readyStartedAt: coordinator.readyStartedAt)
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)

                    FastTouchingJeffCountdownOverlay(
                        startedAt: countdownStartedAt,
                        scoreText: "\(coordinator.touchCount)",
                        timeText: coordinator.timerText
                    )
                    .zIndex(90)
                }

                if coordinator.phase == .finished {
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
            .ballrAwardsXPOnSuccess(coordinator.phase == .finished)
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
                FastTouchingHudChip(title: "TOUCHES", value: "\(coordinator.touchCount)", tint: .yellow)
                FastTouchingHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 18)
    }
}

private enum FastTouchingPhase {
    case readiness
    case countdown
    case live
    case finished
}

private enum FastTouchingTouchSide {
    case left
    case right

    var footID: Int {
        switch self {
        case .left:
            return 0
        case .right:
            return 1
        }
    }
}

private final class FastTouchingCoordinator: ObservableObject {
    @Published private(set) var phase: FastTouchingPhase = .readiness
    @Published private(set) var readyStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var timerText = "30"
    @Published private(set) var touchCount = 0
    @Published private(set) var finishStartedAt: Date?
    @Published private(set) var showsFinishButtons = false

    private let requiredReadyLockSeconds: TimeInterval = 1.6
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 30.0
    private let finishAnimationDuration: TimeInterval = 2.05
    private let finishButtonRevealDelay: TimeInterval = 0.28
    private let lostBallPromptFrameThreshold = 8
    private let lostFootPromptFrameThreshold = 8

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var lostBallFrameCount = 0
    private var lostFootFrameCount = 0
    private var lastDetectedFeet: [FastTouchingDetectedFoot] = []
    private var ballDisplayRect: CGRect?
    private var ballStability = FastTouchingBallStabilityTracker()
    private var gameState = FastTouchingGameState()
    private var finishWorkItem: DispatchWorkItem?
    private weak var renderView: FastTouchingRenderView?

    func attach(renderView: FastTouchingRenderView) {
        self.renderView = renderView
        renderView.update(
            ballDisplayRect: ballDisplayRect,
            feet: lastDetectedFeet,
            leftContactZone: leftContactZone,
            rightContactZone: rightContactZone,
            highlightedSide: highlightedSide,
            prompt: promptText
        )
    }

    func tearDown() {
        cancelFinishWorkItem()
    }

    func reset(in size: CGSize) {
        cancelFinishWorkItem()
        self.size = size
        phase = .readiness
        readyStartedAt = nil
        countdownStartedAt = nil
        timerText = "30"
        touchCount = 0
        finishStartedAt = nil
        showsFinishButtons = false
        liveElapsed = 0
        lastStepAt = nil
        lostBallFrameCount = 0
        lostFootFrameCount = 0
        lastDetectedFeet = []
        ballDisplayRect = nil
        ballStability.reset()
        gameState.reset()
        renderView?.update(
            ballDisplayRect: ballDisplayRect,
            feet: lastDetectedFeet,
            leftContactZone: leftContactZone,
            rightContactZone: rightContactZone,
            highlightedSide: highlightedSide,
            prompt: promptText
        )
    }

    func prepare(in size: CGSize) {
        self.size = resolvedGameplaySize(fallback: size)
        renderView?.update(
            ballDisplayRect: ballDisplayRect,
            feet: lastDetectedFeet,
            leftContactZone: leftContactZone,
            rightContactZone: rightContactZone,
            highlightedSide: highlightedSide,
            prompt: promptText
        )
    }

    func handle(frame: FastTouchingFrame, cameraController: FastTouchingCameraController) {
        let detectedFeet = frame.footOverlayState.feet.compactMap { footState -> FastTouchingDetectedFoot? in
            guard let displayRect = cameraController.displayRect(for: footState.normalizedRect) else {
                return nil
            }
            let displayPoints = footState.normalizedPoints.compactMap {
                cameraController.displayPoint(for: $0)
            }
            return FastTouchingDetectedFoot(
                id: footState.id,
                rect: displayRect,
                collisionPolygon: FastTouchingDetectedFoot.collisionPolygon(from: displayPoints, fallbackRect: displayRect),
                toePolygon: FastTouchingDetectedFoot.toePolygon(from: displayPoints, fallbackRect: displayRect),
                confidence: CGFloat(footState.confidence)
            )
        }
        lastDetectedFeet = detectedFeet

        let rawBallRect = displayRect(for: frame.ballOverlayState, cameraController: cameraController)
        let ballState = ballStability.update(
            ballDisplayRect: rawBallRect,
            overlayState: frame.ballOverlayState,
            timestamp: frame.timestamp
        )
        ballDisplayRect = ballState.smoothedRect ?? rawBallRect

        if ballState.isTracked {
            lostBallFrameCount = 0
        } else if phase == .live {
            lostBallFrameCount += 1
        }

        if detectedFeet.isEmpty {
            if phase == .live {
                lostFootFrameCount += 1
            }
        } else {
            lostFootFrameCount = 0
        }

        updateStartGate(
            isReady: ballState.isStable && !detectedFeet.isEmpty,
            timestamp: frame.timestamp
        )

        if phase == .live {
            let previousStepAt = lastStepAt ?? frame.timestamp
            let deltaTime = min(max(frame.timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
            lastStepAt = frame.timestamp
            liveElapsed = min(liveElapsed + deltaTime, roundDuration)
            timerText = String(Int(ceil(max(roundDuration - liveElapsed, 0))))

            if let touchSide = gameState.step(
                ballDisplayRect: ballDisplayRect,
                feet: detectedFeet,
                timestamp: frame.timestamp,
                isBallTracked: ballState.isTracked
            ) {
                touchCount += 1
                if touchCount.isMultiple(of: 10) {
                    BallrDrillSoundPlayer.playCombo()
                }
            }

            if liveElapsed >= roundDuration {
                finish(at: frame.timestamp)
            }
        }

        renderView?.update(
            ballDisplayRect: ballDisplayRect,
            feet: detectedFeet,
            leftContactZone: leftContactZone,
            rightContactZone: rightContactZone,
            highlightedSide: highlightedSide,
            prompt: promptText
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

    private func displayRect(
        for overlayState: BallTrackerOverlayState,
        cameraController: FastTouchingCameraController
    ) -> CGRect? {
        guard let normalizedRect = overlayState.normalizedRect else {
            return nil
        }
        return cameraController.displayRect(for: normalizedRect)
    }

    private func updateStartGate(isReady: Bool, timestamp: Date) {
        if phase == .live || phase == .finished {
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
                timerText = "30"
                gameState.start()
            }
            return
        }

        guard isReady else {
            readyStartedAt = nil
            return
        }

        let startedAt = readyStartedAt ?? timestamp
        readyStartedAt = startedAt

        if timestamp.timeIntervalSince(startedAt) >= requiredReadyLockSeconds {
            countdownStartedAt = timestamp
            phase = .countdown
        }
    }

    private func finish(at timestamp: Date) {
        guard phase != .finished else {
            return
        }

        phase = .finished
        finishStartedAt = timestamp
        BallrDrillSoundPlayer.playWinner()

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

    private var contactZones: (left: CGRect?, right: CGRect?) {
        guard let ballDisplayRect else {
            return (nil, nil)
        }

        let horizontalInset = ballDisplayRect.width * 0.12
        let zoneY = ballDisplayRect.minY - ballDisplayRect.height * 0.06
        let zoneHeight = ballDisplayRect.height * 0.42
        let gap = max(ballDisplayRect.width * 0.04, 6)
        let fullZone = CGRect(
            x: ballDisplayRect.minX + horizontalInset,
            y: zoneY,
            width: max(ballDisplayRect.width - horizontalInset * 2, 1),
            height: zoneHeight
        )

        let halfWidth = max((fullZone.width - gap) * 0.5, 1)
        let leftZone = CGRect(x: fullZone.minX, y: fullZone.minY, width: halfWidth, height: fullZone.height)
        let rightZone = CGRect(x: fullZone.maxX - halfWidth, y: fullZone.minY, width: halfWidth, height: fullZone.height)
        return (leftZone, rightZone)
    }

    private var leftContactZone: CGRect? {
        contactZones.left
    }

    private var rightContactZone: CGRect? {
        contactZones.right
    }

    private var highlightedSide: FastTouchingTouchSide? {
        guard phase == .live else {
            return nil
        }
        return gameState.highlightedSide(at: Date())
    }

    private var promptText: String? {
        switch phase {
        case .readiness:
            return nil
        case .countdown:
            return nil
        case .live:
            if lostBallFrameCount >= lostBallPromptFrameThreshold {
                return "Find the ball"
            }
            if lostFootFrameCount >= lostFootPromptFrameThreshold {
                return "Find your foot"
            }
            return nil
        case .finished:
            return nil
        }
    }
}

private struct FastTouchingRenderSurface: UIViewRepresentable {
    let coordinator: FastTouchingCoordinator

    func makeUIView(context: Context) -> FastTouchingRenderView {
        let view = FastTouchingRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: FastTouchingRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class FastTouchingRenderView: UIView {
    private var ballDisplayRect: CGRect?
    private var feet: [FastTouchingDetectedFoot] = []
    private var leftContactZone: CGRect?
    private var rightContactZone: CGRect?
    private var highlightedSide: FastTouchingTouchSide?
    private var prompt: String?

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
        ballDisplayRect: CGRect?,
        feet: [FastTouchingDetectedFoot],
        leftContactZone: CGRect?,
        rightContactZone: CGRect?,
        highlightedSide: FastTouchingTouchSide?,
        prompt: String?
    ) {
        self.ballDisplayRect = ballDisplayRect
        self.feet = feet
        self.leftContactZone = leftContactZone
        self.rightContactZone = rightContactZone
        self.highlightedSide = highlightedSide
        self.prompt = prompt
        promptLabel.text = prompt
        promptLabel.isHidden = prompt == nil
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        promptLabel.frame = CGRect(
            x: max((bounds.width - 220) * 0.5, 16),
            y: 84,
            width: min(220, bounds.width - 32),
            height: 38
        )
    }

    override func draw(_ rect: CGRect) {
        return
    }

    private func drawContactZones(in context: CGContext) {
        drawContactZone(
            leftContactZone,
            side: .left,
            in: context,
            baseColor: UIColor.systemYellow
        )
        drawContactZone(
            rightContactZone,
            side: .right,
            in: context,
            baseColor: UIColor.systemOrange
        )
    }

    private func drawContactZone(
        _ rect: CGRect?,
        side: FastTouchingTouchSide,
        in context: CGContext,
        baseColor: UIColor
    ) {
        guard let rect else {
            return
        }

        let isHighlighted = highlightedSide == side
        let fillAlpha: CGFloat = isHighlighted ? 0.34 : 0.12
        let strokeAlpha: CGFloat = isHighlighted ? 0.95 : 0.52
        let roundedRect = UIBezierPath(roundedRect: rect, cornerRadius: min(rect.height * 0.42, 18))

        context.saveGState()
        context.setShadow(
            offset: .zero,
            blur: isHighlighted ? 18 : 10,
            color: baseColor.withAlphaComponent(isHighlighted ? 0.56 : 0.22).cgColor
        )
        baseColor.withAlphaComponent(fillAlpha).setFill()
        roundedRect.fill()
        context.restoreGState()

        baseColor.withAlphaComponent(strokeAlpha).setStroke()
        roundedRect.lineWidth = isHighlighted ? 3.5 : 2.5
        roundedRect.stroke()
    }

    private func drawBall(in context: CGContext) {
        guard let ballDisplayRect else {
            return
        }

        context.saveGState()
        context.setShadow(offset: .zero, blur: 16, color: UIColor.white.withAlphaComponent(0.28).cgColor)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: ballDisplayRect)
        context.restoreGState()

        let centerDotRect = CGRect(
            x: ballDisplayRect.midX - 5,
            y: ballDisplayRect.midY - 5,
            width: 10,
            height: 10
        )
        UIColor.systemYellow.setFill()
        UIBezierPath(ovalIn: centerDotRect).fill()
    }

    private func drawFeet(in context: CGContext) {
        for foot in feet {
            drawFoot(foot, in: context)
        }
    }

    private func drawFoot(_ foot: FastTouchingDetectedFoot, in context: CGContext) {
        let footPath = UIBezierPath()
        if let first = foot.collisionPolygon.first {
            footPath.move(to: first)
            for point in foot.collisionPolygon.dropFirst() {
                footPath.addLine(to: point)
            }
            footPath.close()
        }

        context.saveGState()
        context.setFillColor(UIColor.white.withAlphaComponent(0.08).cgColor)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.34).cgColor)
        context.setLineWidth(2.5)
        context.addPath(footPath.cgPath)
        context.drawPath(using: .fillStroke)
        context.restoreGState()

        let toePath = UIBezierPath()
        if let first = foot.toePolygon.first {
            toePath.move(to: first)
            for point in foot.toePolygon.dropFirst() {
                toePath.addLine(to: point)
            }
            toePath.close()
        }

        let toeColor = foot.id == FastTouchingTouchSide.left.footID
            ? UIColor.systemYellow
            : UIColor.systemOrange

        context.saveGState()
        context.setShadow(offset: .zero, blur: 14, color: toeColor.withAlphaComponent(0.30).cgColor)
        context.setFillColor(toeColor.withAlphaComponent(0.18).cgColor)
        context.setStrokeColor(toeColor.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(2.5)
        context.addPath(toePath.cgPath)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }
}

private struct FastTouchingDetectedFoot: Identifiable {
    let id: Int
    let rect: CGRect
    let collisionPolygon: [CGPoint]
    let toePolygon: [CGPoint]
    let confidence: CGFloat

    var collisionBounds: CGRect {
        Self.boundingRect(for: collisionPolygon) ?? rect
    }

    var toeBounds: CGRect {
        Self.boundingRect(for: toePolygon) ?? rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.30)
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

    static func toePolygon(from points: [CGPoint], fallbackRect: CGRect) -> [CGPoint] {
        guard points.count >= 4 else {
            let toeRect = CGRect(
                x: fallbackRect.minX + fallbackRect.width * 0.12,
                y: fallbackRect.minY,
                width: fallbackRect.width * 0.76,
                height: fallbackRect.height * 0.46
            )
            return [
                CGPoint(x: toeRect.minX, y: toeRect.minY),
                CGPoint(x: toeRect.maxX, y: toeRect.minY),
                CGPoint(x: toeRect.maxX, y: toeRect.maxY),
                CGPoint(x: toeRect.minX, y: toeRect.maxY)
            ]
        }

        let frontLeft = points[0]
        let frontRight = points[1]
        let backRight = points[2]
        let backLeft = points[3]
        let midRight = midpoint(frontRight, backRight)
        let midLeft = midpoint(frontLeft, backLeft)
        return [frontLeft, frontRight, midRight, midLeft]
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

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }
}

private struct FastTouchingBallStabilityState {
    let smoothedRect: CGRect?
    let isTracked: Bool
    let isStable: Bool
}

private struct FastTouchingBallStabilityTracker {
    private struct Sample {
        let rect: CGRect
        let timestamp: Date
    }

    private var samples: [Sample] = []

    mutating func reset() {
        samples.removeAll()
    }

    mutating func update(
        ballDisplayRect: CGRect?,
        overlayState: BallTrackerOverlayState,
        timestamp: Date
    ) -> FastTouchingBallStabilityState {
        let isTracked = overlayState.isTracking && overlayState.confirmedFrames >= 4 && ballDisplayRect != nil

        guard isTracked, let ballDisplayRect else {
            samples.removeAll()
            return FastTouchingBallStabilityState(
                smoothedRect: ballDisplayRect,
                isTracked: false,
                isStable: false
            )
        }

        samples.append(Sample(rect: ballDisplayRect, timestamp: timestamp))
        samples.removeAll { timestamp.timeIntervalSince($0.timestamp) > 0.35 }
        if samples.count > 10 {
            samples.removeFirst(samples.count - 10)
        }

        let smoothedRect = averagedRect()
        guard let smoothedRect else {
            return FastTouchingBallStabilityState(
                smoothedRect: ballDisplayRect,
                isTracked: true,
                isStable: false
            )
        }

        let diameters = samples.map { max($0.rect.width, $0.rect.height) }
        let centerXs = samples.map(\.rect.midX)
        let centerYs = samples.map(\.rect.midY)
        let meanDiameter = diameters.reduce(0, +) / CGFloat(max(diameters.count, 1))
        let xRange = (centerXs.max() ?? 0) - (centerXs.min() ?? 0)
        let yRange = (centerYs.max() ?? 0) - (centerYs.min() ?? 0)
        let diameterRange = (diameters.max() ?? 0) - (diameters.min() ?? 0)

        let isStable =
            samples.count >= 6
            && xRange <= max(meanDiameter * 0.20, 18)
            && yRange <= max(meanDiameter * 0.16, 12)
            && diameterRange <= max(meanDiameter * 0.14, 8)

        return FastTouchingBallStabilityState(
            smoothedRect: smoothedRect,
            isTracked: true,
            isStable: isStable
        )
    }

    private func averagedRect() -> CGRect? {
        guard !samples.isEmpty else {
            return nil
        }

        let total = samples.reduce((x: CGFloat.zero, y: CGFloat.zero, width: CGFloat.zero, height: CGFloat.zero)) {
            partial, sample in
            (
                x: partial.x + sample.rect.origin.x,
                y: partial.y + sample.rect.origin.y,
                width: partial.width + sample.rect.width,
                height: partial.height + sample.rect.height
            )
        }
        let count = CGFloat(samples.count)
        return CGRect(
            x: total.x / count,
            y: total.y / count,
            width: total.width / count,
            height: total.height / count
        )
    }
}

private struct FastTouchingGameState {
    private struct FootContactState {
        var isInside = false
        var pendingFrames = 0
        var releaseFrames = 0
        var lastCountedAt: Date?
    }

    private let minimumContactFrames = 2
    private let minimumReleaseFrames = 2
    private let touchCooldown: TimeInterval = 0.5
    private let minimumOverlapRatio: CGFloat = 0.16
    private let highlightDuration: TimeInterval = 0.16

    private var footStates: [Int: FootContactState] = [
        FastTouchingTouchSide.left.footID: FootContactState(),
        FastTouchingTouchSide.right.footID: FootContactState()
    ]
    private var lastTouchSide: FastTouchingTouchSide?
    private var lastTouchAt: Date?

    mutating func start() {
        resetContactStates()
    }

    mutating func reset() {
        resetContactStates()
        lastTouchSide = nil
        lastTouchAt = nil
    }

    mutating func step(
        ballDisplayRect: CGRect?,
        feet: [FastTouchingDetectedFoot],
        timestamp: Date,
        isBallTracked: Bool
    ) -> FastTouchingTouchSide? {
        guard isBallTracked, let ballDisplayRect else {
            pauseContacts()
            return nil
        }

        let zones = contactZones(for: ballDisplayRect)
        var scores: [FastTouchingTouchSide: CGFloat] = [.left: 0, .right: 0]

        if let leftFoot = feet.first(where: { $0.id == FastTouchingTouchSide.left.footID }) {
            scores[.left] = contactScore(for: leftFoot, zone: zones.left, ballRect: ballDisplayRect)
        }
        if let rightFoot = feet.first(where: { $0.id == FastTouchingTouchSide.right.footID }) {
            scores[.right] = contactScore(for: rightFoot, zone: zones.right, ballRect: ballDisplayRect)
        }

        let leftScore = scores[.left] ?? 0
        let rightScore = scores[.right] ?? 0
        if leftScore >= minimumOverlapRatio, rightScore >= minimumOverlapRatio {
            if leftScore >= rightScore {
                scores[.right] = 0
            } else {
                scores[.left] = 0
            }
        }

        var countedSide: FastTouchingTouchSide?
        for side in [FastTouchingTouchSide.left, .right] {
            let isContacting = (scores[side] ?? 0) >= minimumOverlapRatio
            var state = footStates[side.footID] ?? FootContactState()

            if isContacting {
                state.releaseFrames = 0
                if !state.isInside {
                    state.pendingFrames += 1
                }

                if !state.isInside,
                   state.pendingFrames >= minimumContactFrames,
                   timestamp.timeIntervalSince(state.lastCountedAt ?? .distantPast) >= touchCooldown {
                    state.isInside = true
                    state.pendingFrames = minimumContactFrames
                    state.lastCountedAt = timestamp
                    countedSide = side
                }
            } else {
                state.pendingFrames = 0
                if state.isInside {
                    state.releaseFrames += 1
                    if state.releaseFrames >= minimumReleaseFrames {
                        state.isInside = false
                    }
                } else {
                    state.releaseFrames = 0
                }
            }

            footStates[side.footID] = state
        }

        if let countedSide {
            lastTouchSide = countedSide
            lastTouchAt = timestamp
        }

        return countedSide
    }

    func highlightedSide(at date: Date) -> FastTouchingTouchSide? {
        guard let lastTouchSide, let lastTouchAt else {
            return nil
        }
        return date.timeIntervalSince(lastTouchAt) <= highlightDuration ? lastTouchSide : nil
    }

    private mutating func pauseContacts() {
        resetContactStates()
    }

    private mutating func resetContactStates() {
        footStates = [
            FastTouchingTouchSide.left.footID: FootContactState(),
            FastTouchingTouchSide.right.footID: FootContactState()
        ]
    }

    private func contactZones(for ballRect: CGRect) -> (left: CGRect, right: CGRect) {
        let horizontalInset = ballRect.width * 0.12
        let zoneY = ballRect.minY - ballRect.height * 0.06
        let zoneHeight = ballRect.height * 0.42
        let gap = max(ballRect.width * 0.04, 6)
        let fullZone = CGRect(
            x: ballRect.minX + horizontalInset,
            y: zoneY,
            width: max(ballRect.width - horizontalInset * 2, 1),
            height: zoneHeight
        )

        let halfWidth = max((fullZone.width - gap) * 0.5, 1)
        return (
            left: CGRect(x: fullZone.minX, y: fullZone.minY, width: halfWidth, height: fullZone.height),
            right: CGRect(x: fullZone.maxX - halfWidth, y: fullZone.minY, width: halfWidth, height: fullZone.height)
        )
    }

    private func contactScore(for foot: FastTouchingDetectedFoot, zone: CGRect, ballRect: CGRect) -> CGFloat {
        let toeBounds = foot.toeBounds.insetBy(dx: toeBoundsInsetX(for: foot), dy: toeBoundsInsetY(for: foot))
        let intersection = toeBounds.intersection(zone)
        guard !intersection.isNull, !intersection.isEmpty else {
            return 0
        }

        let toeArea = max(toeBounds.width * toeBounds.height, 1)
        let zoneArea = max(zone.width * zone.height, 1)
        let overlapArea = intersection.width * intersection.height
        let overlapRatio = overlapArea / min(toeArea, zoneArea)
        let verticalBias = toeBounds.midY <= ballRect.midY + ballRect.height * 0.08 ? 1 : 0.45
        return overlapRatio * verticalBias
    }

    private func toeBoundsInsetX(for foot: FastTouchingDetectedFoot) -> CGFloat {
        foot.toeBounds.width * 0.18
    }

    private func toeBoundsInsetY(for foot: FastTouchingDetectedFoot) -> CGFloat {
        foot.toeBounds.height * 0.10
    }
}

private struct FastTouchingHudChip: View {
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

private struct FastTouchingLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.84)
                .ignoresSafeArea()

            ProgressView()
                .tint(.yellow)
                .scaleEffect(1.4)
        }
    }
}

private struct FastTouchingErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(permissionDenied ? "Camera Needed" : "Unable to Start")
                    .font(.ballr(size: 30, weight: .black))
                    .foregroundStyle(.yellow)

                Text(message)
                    .font(.ballr(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button("DONE", action: onDismiss)
                    .font(.ballr(size: 20, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 160, height: 54)
                    .background(.yellow, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(30)
        }
    }
}

private struct FastTouchingReadinessOverlay: View {
    let readyStartedAt: Date?

    private let requiredLockSeconds: TimeInterval = 1.6

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = readinessProgress(at: timeline.date)

            ZStack {
                Color.black.opacity(0.84)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    Text(readyStartedAt == nil ? "Place the ball" : "Hold still")
                        .font(.ballr(size: 34, weight: .black))
                        .foregroundStyle(.yellow)

                    Text("Put the ball on the ground and stand over it. We’ll count every toe touch for 30 seconds.")
                        .font(.ballr(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    if readyStartedAt != nil {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999)
                                .fill(.white.opacity(0.12))
                                .frame(width: 240, height: 16)

                            RoundedRectangle(cornerRadius: 999)
                                .fill(Color.yellow)
                                .frame(width: 240 * progress, height: 16)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func readinessProgress(at date: Date) -> CGFloat {
        guard let readyStartedAt else {
            return 0
        }
        return min(max(date.timeIntervalSince(readyStartedAt) / requiredLockSeconds, 0), 1)
    }
}

private struct FastTouchingFinishedOverlay: View {
    let touchCount: Int
    let onPrimary: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.90)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("TIME")
                    .font(.ballr(size: 36, weight: .black))
                    .foregroundStyle(.yellow)

                Text("You finished with \(touchCount) toe touches.")
                    .font(.ballr(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                HStack(spacing: 14) {
                    Button("DONE", action: onDone)
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 130, height: 56)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    Button("PLAY AGAIN", action: onPrimary)
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 170, height: 56)
                        .background(.yellow, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(30)
        }
    }
}
