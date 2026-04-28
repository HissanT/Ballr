import Combine
import Foundation
import SwiftUI
import UIKit

struct JumpingChallengeCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = JumpingPoseCameraController()
    @StateObject private var coordinator = JumpingChallengeCoordinator()
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

                JumpingChallengeRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                if coordinator.phase == .readiness || coordinator.phase == .countdown || coordinator.phase == .live {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.vertical, 14)
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
                    JumpingChallengeFinishedOverlay(
                        title: "GAME OVER",
                        subtitle: "An obstacle touched your legs.",
                        timeText: coordinator.survivedTimeText,
                        primaryTitle: "PLAY AGAIN",
                        onPrimary: { coordinator.reset(in: geometry.size) },
                        onDone: { dismiss() }
                    )
                }

                if coordinator.phase == .won {
                    JumpingChallengeFinishedOverlay(
                        title: "YOU SURVIVED",
                        subtitle: "60 seconds clear.",
                        timeText: "60s",
                        primaryTitle: "PLAY AGAIN",
                        onPrimary: { coordinator.reset(in: geometry.size) },
                        onDone: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
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
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.58), in: Circle())
            }

            Spacer()

            JumpingChallengeHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
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

    private let requiredLegLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 60.0
    private let lostLegPromptFrameThreshold = 12

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var lostLegFrameCount = 0
    private var lastDetectedLegs: [JumpingDetectedLeg] = []
    private var laneBaselineY: CGFloat?
    private var gameState = JumpingChallengeGameState()
    private weak var renderView: JumpingChallengeRenderView?

    func attach(renderView: JumpingChallengeRenderView) {
        self.renderView = renderView
        renderView.update(
            legs: lastDetectedLegs,
            obstacles: gameState.obstacles,
            prompt: promptText,
            groundLineY: resolvedGroundLine(for: size)
        )
    }

    func tearDown() {}

    func reset(in size: CGSize) {
        self.size = size
        phase = .readiness
        legsFoundStartedAt = nil
        countdownStartedAt = nil
        timerText = "60"
        survivedTimeText = "0s"
        liveElapsed = 0
        lastStepAt = nil
        lostLegFrameCount = 0
        lastDetectedLegs = []
        laneBaselineY = nil
        gameState.reset()
        renderView?.update(
            legs: lastDetectedLegs,
            obstacles: gameState.obstacles,
            prompt: promptText,
            groundLineY: resolvedGroundLine(for: size)
        )
    }

    func prepare(in size: CGSize) {
        self.size = resolvedGameplaySize(fallback: size)
        renderView?.update(
            legs: lastDetectedLegs,
            obstacles: gameState.obstacles,
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
                confidence: CGFloat(legState.confidence)
            )
        }
        lastDetectedLegs = detectedLegs

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
                isTracking: hasTrackedLegs
            )

            liveElapsed = min(liveElapsed + deltaTime, roundDuration)
            timerText = String(Int(ceil(max(roundDuration - liveElapsed, 0))))
            survivedTimeText = "\(Int(liveElapsed.rounded(.down)))s"

            if event == .collision {
                phase = .gameOver
                gameState.finish()
            } else if liveElapsed >= roundDuration {
                phase = .won
                gameState.finish()
                BallrDrillSoundPlayer.playWinner()
            }
        }

        renderView?.update(
            legs: detectedLegs,
            obstacles: gameState.obstacles,
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

    private func updateLaneBaseline(using legs: [JumpingDetectedLeg]) {
        guard let maxBottom = legs.map(\.collisionBounds.maxY).max() else {
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
        return "Find both legs"
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
        prompt: String?,
        groundLineY: CGFloat
    ) {
        self.legs = legs
        self.obstacles = obstacles
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
        drawLegs(in: context)
        drawObstacles(in: context)
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

    private func drawLegs(in context: CGContext) {
        for leg in legs {
            let bounds = leg.collisionBounds

            let path = UIBezierPath()
            guard let first = leg.collisionPolygon.first else {
                continue
            }
            path.move(to: first)
            for point in leg.collisionPolygon.dropFirst() {
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
        let style = obstacle.style
        let bodyPath = UIBezierPath(roundedRect: rect, cornerRadius: rect.height * 0.34)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 10), blur: 18, color: style.shadowColor.cgColor)
        style.fillColor.setFill()
        bodyPath.fill()
        context.restoreGState()

        style.strokeColor.setStroke()
        bodyPath.lineWidth = 4
        bodyPath.stroke()

        let highlightRect = CGRect(
            x: rect.minX + rect.width * 0.08,
            y: rect.minY + rect.height * 0.10,
            width: rect.width * 0.84,
            height: rect.height * 0.24
        )
        let highlightPath = UIBezierPath(roundedRect: highlightRect, cornerRadius: highlightRect.height * 0.5)
        style.highlightColor.setFill()
        highlightPath.fill()

        context.saveGState()
        bodyPath.addClip()
        context.setStrokeColor(style.stripeColor.cgColor)
        context.setLineWidth(6)
        for offset in stride(from: -rect.height, through: rect.width + rect.height, by: rect.width * 0.24) {
            context.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            context.addLine(to: CGPoint(x: rect.minX + offset + rect.height * 0.72, y: rect.minY))
        }
        context.strokePath()
        context.restoreGState()

        let padWidth = rect.width * 0.18
        let padHeight = rect.height * 0.18
        let leftPadRect = CGRect(
            x: rect.minX + rect.width * 0.14,
            y: rect.maxY - padHeight * 0.25,
            width: padWidth,
            height: padHeight
        )
        let rightPadRect = CGRect(
            x: rect.maxX - rect.width * 0.14 - padWidth,
            y: rect.maxY - padHeight * 0.25,
            width: padWidth,
            height: padHeight
        )
        UIColor.black.withAlphaComponent(0.28).setFill()
        UIBezierPath(roundedRect: leftPadRect, cornerRadius: padHeight * 0.4).fill()
        UIBezierPath(roundedRect: rightPadRect, cornerRadius: padHeight * 0.4).fill()

        let boltRadius = rect.height * 0.07
        let boltCenters = [
            CGPoint(x: rect.minX + rect.width * 0.22, y: rect.midY + rect.height * 0.08),
            CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.midY + rect.height * 0.08)
        ]
        UIColor.white.withAlphaComponent(0.20).setFill()
        for center in boltCenters {
            UIBezierPath(
                ovalIn: CGRect(
                    x: center.x - boltRadius,
                    y: center.y - boltRadius,
                    width: boltRadius * 2,
                    height: boltRadius * 2
                )
            )
            .fill()
        }
    }
}

private struct JumpingDetectedLeg: Identifiable {
    let id: Int
    let rect: CGRect
    let collisionPolygon: [CGPoint]
    let confidence: CGFloat

    var collisionBounds: CGRect {
        Self.boundingRect(for: collisionPolygon) ?? rect
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

private enum JumpingChallengeEvent {
    case collision
}

private struct JumpingChallengeGameState {
    private(set) var obstacles: [JumpingObstacle] = []
    private var timeUntilNextSpawn: TimeInterval = 2.0
    private var didStart = false
    private var isFinished = false

    mutating func start(in size: CGSize, groundLineY: CGFloat) {
        obstacles = []
        timeUntilNextSpawn = 2.0
        didStart = true
        isFinished = false
    }

    mutating func reset() {
        obstacles = []
        timeUntilNextSpawn = 2.0
        didStart = false
        isFinished = false
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
        isTracking: Bool
    ) -> JumpingChallengeEvent? {
        guard didStart, !isFinished, size.width > 0, size.height > 0 else {
            return nil
        }

        let progress = min(max(elapsed / 60.0, 0), 1)

        for index in obstacles.indices {
            obstacles[index].rect.origin.x += obstacles[index].speed * deltaTime
        }
        obstacles.removeAll { $0.rect.minX > size.width + 80 }

        timeUntilNextSpawn -= deltaTime
        while timeUntilNextSpawn <= 0 {
            spawnObstacle(in: size, groundLineY: groundLineY, progress: progress)
            timeUntilNextSpawn += nextSpawnInterval(progress: progress)
        }

        guard isTracking else {
            return nil
        }

        if obstacles.contains(where: { obstacleIntersectsLegs($0, legs: legs) }) {
            isFinished = true
            return .collision
        }

        return nil
    }

    private mutating func spawnObstacle(in size: CGSize, groundLineY: CGFloat, progress: CGFloat) {
        let height = size.height * CGFloat.random(in: (0.095 + progress * 0.018)...(0.125 + progress * 0.022))
        let width = height * CGFloat.random(in: 1.05...1.38)
        let startX = -width - 36
        let rect = CGRect(
            x: startX,
            y: JumpingObstacleLane.bottom.originY(in: size, height: height),
            width: width,
            height: height
        )
        let speed = size.width * CGFloat.random(in: (0.28 + progress * 0.11)...(0.34 + progress * 0.13))

        obstacles.append(
            JumpingObstacle(
                rect: rect,
                speed: speed,
                style: JumpingObstacleStyle.allCases.randomElement() ?? .sunburst
            )
        )
    }

    private func nextSpawnInterval(progress: CGFloat) -> TimeInterval {
        let minGap = max(1.28, 1.95 - progress * 0.32)
        let maxGap = max(minGap + 0.28, 2.60 - progress * 0.42)
        return Double.random(in: minGap...maxGap)
    }

    private func obstacleIntersectsLegs(_ obstacle: JumpingObstacle, legs: [JumpingDetectedLeg]) -> Bool {
        let collisionRect = obstacle.rect.insetBy(dx: 12, dy: 10)
        return legs.contains { leg in
            obstacleOverlapExceedsThreshold(collisionRect, leg: leg)
        }
    }

    private func obstacleOverlapExceedsThreshold(_ obstacleRect: CGRect, leg: JumpingDetectedLeg) -> Bool {
        obstacleOverlapExceedsThreshold(
            obstacleRect,
            regionBounds: leg.collisionBounds.insetBy(dx: 4, dy: 4),
            polygon: leg.collisionPolygon,
            minimumOverlapRatio: 0.18
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
    let style: JumpingObstacleStyle
}

private enum JumpingObstacleStyle: CaseIterable {
    case sunburst
    case ember
    case citrus

    var fillColor: UIColor {
        switch self {
        case .sunburst:
            return UIColor(red: 1.0, green: 0.42, blue: 0.18, alpha: 1.0)
        case .ember:
            return UIColor(red: 0.92, green: 0.24, blue: 0.16, alpha: 1.0)
        case .citrus:
            return UIColor(red: 0.98, green: 0.72, blue: 0.12, alpha: 1.0)
        }
    }

    var strokeColor: UIColor {
        UIColor(red: 0.15, green: 0.12, blue: 0.12, alpha: 0.82)
    }

    var highlightColor: UIColor {
        switch self {
        case .sunburst:
            return UIColor(red: 1.0, green: 0.82, blue: 0.36, alpha: 0.72)
        case .ember:
            return UIColor(red: 1.0, green: 0.60, blue: 0.38, alpha: 0.72)
        case .citrus:
            return UIColor(red: 1.0, green: 0.92, blue: 0.50, alpha: 0.72)
        }
    }

    var stripeColor: UIColor {
        UIColor.white.withAlphaComponent(0.18)
    }

    var shadowColor: UIColor {
        fillColor.withAlphaComponent(0.46)
    }
}

private struct JumpingChallengeHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            Text(value)
                .font(.system(size: 26, weight: .black, design: .rounded))
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
                    .font(.system(size: 24, weight: .black, design: .rounded))
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
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("CLOSE")
                        .font(.system(size: 16, weight: .black, design: .rounded))
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
                        Text("Find both legs")
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .foregroundStyle(Color.yellow)

                        Text("Stand sideways with both legs visible, then hold still.")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 18) {
                        Text("Hold still")
                            .font(.system(size: 34, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Starting in \(remainingText(at: timeline.date))")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
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
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                Text(timeText)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    Button(action: onDone) {
                        Text("DONE")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: onPrimary) {
                        Text(primaryTitle)
                            .font(.system(size: 15, weight: .black, design: .rounded))
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
