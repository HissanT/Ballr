import AVFoundation
import Combine
import SwiftUI

struct LevelEighteenCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = FastTouchingCameraController()
    @StateObject private var coordinator = LevelEighteenCoordinator()
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

                LevelEighteenOverlayView(coordinator: coordinator)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if coordinator.phase != .finished {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

                if cameraController.isStarting {
                    LevelEighteenLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    LevelEighteenErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.phase == .readiness, cameraController.errorMessage == nil {
                    LevelEighteenReadinessOverlay(readyStartedAt: coordinator.readyStartedAt)
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                }

                if coordinator.phase == .finished {
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
            .alert("Are you sure you want to quit the level?", isPresented: $showsQuitConfirmation) {
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
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 10) {
                LevelEighteenHudChip(title: "TOUCHES", value: "\(coordinator.touchCount)", tint: .yellow)
                LevelEighteenHudChip(title: "HITS", value: "\(coordinator.handHits)", tint: .green)
                LevelEighteenHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 18)
    }
}

private enum LevelEighteenPhase {
    case readiness
    case countdown
    case live
    case finished
}

private final class LevelEighteenCoordinator: ObservableObject {
    @Published private(set) var phase: LevelEighteenPhase = .readiness
    @Published private(set) var readyStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var timerText = "60"
    @Published private(set) var touchCount = 0
    @Published private(set) var handHits = 0
    @Published private(set) var ballRect: CGRect?
    @Published private(set) var footRects: [LevelEighteenTrackedRect] = []
    @Published private(set) var leftContactZone: CGRect?
    @Published private(set) var rightContactZone: CGRect?
    @Published private(set) var highlightedFootSide: LevelEighteenTouchSide?
    @Published private(set) var handRects: [LevelEighteenTrackedRect] = []
    @Published private(set) var handTarget: LevelEighteenTarget?
    @Published private(set) var promptText = "GET BALL, FEET, AND A HAND IN FRAME"
    @Published private(set) var completionStartedAt: Date?
    @Published private(set) var showsCompletionButtons = false

    private let requiredReadyLockSeconds: TimeInterval = 1.4
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 60.0
    private let targetLifetime: TimeInterval = 3.0
    private let targetSpawnGracePeriod: TimeInterval = 0.18
    private let completionAnimationDuration: TimeInterval = 2.05
    private let completionButtonRevealDelay: TimeInterval = 0.28
    private let lostBallPromptFrameThreshold = 8
    private let lostFootPromptFrameThreshold = 8

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var lostBallFrameCount = 0
    private var lostFootFrameCount = 0
    private var detectedFeet: [LevelEighteenDetectedFoot] = []
    private var ballStability = LevelEighteenBallStabilityTracker()
    private var toeTouchState = LevelEighteenToeTouchGameState()
    private var completionWorkItem: DispatchWorkItem?
    private var nextHandTargetSide: LevelEighteenTouchSide = .left

    func tearDown() {
        cancelCompletionWorkItem()
    }

    func reset(in size: CGSize) {
        cancelCompletionWorkItem()
        self.size = size
        phase = .readiness
        readyStartedAt = nil
        countdownStartedAt = nil
        timerText = "60"
        touchCount = 0
        handHits = 0
        ballRect = nil
        footRects = []
        leftContactZone = nil
        rightContactZone = nil
        highlightedFootSide = nil
        handRects = []
        handTarget = nil
        promptText = "GET BALL, FEET, AND A HAND IN FRAME"
        completionStartedAt = nil
        showsCompletionButtons = false
        liveElapsed = 0
        lastStepAt = nil
        lostBallFrameCount = 0
        lostFootFrameCount = 0
        detectedFeet = []
        nextHandTargetSide = .left
        ballStability.reset()
        toeTouchState.reset()
    }

    func prepare(in size: CGSize) {
        self.size = size
        if phase == .live, handTarget == nil {
            spawnHandTarget(at: Date())
        }
    }

    func handle(frame: FastTouchingFrame, cameraController: FastTouchingCameraController) {
        detectedFeet = frame.footOverlayState.feet.compactMap { footState -> LevelEighteenDetectedFoot? in
            guard let displayRect = cameraController.displayRect(for: footState.normalizedRect) else {
                return nil
            }
            let displayPoints = footState.normalizedPoints.compactMap {
                cameraController.displayPoint(for: $0)
            }
            return LevelEighteenDetectedFoot(
                id: footState.id,
                rect: displayRect,
                collisionPolygon: LevelEighteenDetectedFoot.collisionPolygon(from: displayPoints, fallbackRect: displayRect),
                toePolygon: LevelEighteenDetectedFoot.toePolygon(from: displayPoints, fallbackRect: displayRect)
            )
        }
        footRects = detectedFeet.map { LevelEighteenTrackedRect(id: $0.id, rect: $0.rect) }

        let rawBallRect = displayRect(for: frame.ballOverlayState, cameraController: cameraController)
        let ballState = ballStability.update(
            ballDisplayRect: rawBallRect,
            overlayState: frame.ballOverlayState,
            timestamp: frame.timestamp
        )
        ballRect = ballState.smoothedRect ?? rawBallRect
        updateContactZones()
        highlightedFootSide = phase == .live ? toeTouchState.highlightedSide(at: frame.timestamp) : nil

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

        handRects = frame.handOverlayState.hands.compactMap { hand in
            cameraController.displayRect(for: hand.normalizedRect).map {
                LevelEighteenTrackedRect(id: hand.id, rect: $0)
            }
        }

        updateStartGate(
            isReady: ballState.isStable && !detectedFeet.isEmpty && !handRects.isEmpty,
            timestamp: frame.timestamp
        )

        guard phase == .live else {
            updatePrompt()
            return
        }

        updateRoundTimer(at: frame.timestamp)
        countToeTouches(at: frame.timestamp, isBallTracked: ballState.isTracked)
        updateHandTarget(at: frame.timestamp)
        updatePrompt()
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
        guard phase != .live, phase != .finished else {
            return
        }

        if phase == .countdown {
            if
                let countdownStartedAt,
                timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration
            {
                phase = .live
                liveElapsed = 0
                lastStepAt = timestamp
                readyStartedAt = nil
                self.countdownStartedAt = nil
                timerText = "60"
                toeTouchState.start()
                spawnHandTarget(at: timestamp)
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

    private func updateRoundTimer(at timestamp: Date) {
        let previousStepAt = lastStepAt ?? timestamp
        let deltaTime = min(max(timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
        lastStepAt = timestamp
        liveElapsed = min(liveElapsed + deltaTime, roundDuration)
        let remaining = max(roundDuration - liveElapsed, 0)
        timerText = "\(Int(ceil(remaining)))"
        if remaining <= 0 {
            complete(at: timestamp)
        }
    }

    private func countToeTouches(at timestamp: Date, isBallTracked: Bool) {
        if toeTouchState.step(
            ballDisplayRect: ballRect,
            feet: detectedFeet,
            timestamp: timestamp,
            isBallTracked: isBallTracked
        ) != nil {
            touchCount += 1
            highlightedFootSide = toeTouchState.highlightedSide(at: timestamp)
            if touchCount.isMultiple(of: 10) {
                BallrDrillSoundPlayer.playCombo()
            }
            LevelEighteenSoundPlayer.playScore()
        }
    }

    private func updateContactZones() {
        guard let ballRect else {
            leftContactZone = nil
            rightContactZone = nil
            return
        }

        let zones = LevelEighteenToeTouchGameState.contactZones(for: ballRect)
        leftContactZone = zones.left
        rightContactZone = zones.right
    }

    private func updateHandTarget(at timestamp: Date) {
        guard var target = handTarget else {
            spawnHandTarget(at: timestamp)
            return
        }

        if timestamp.timeIntervalSince(target.spawnedAt) >= targetLifetime {
            spawnHandTarget(at: timestamp)
            return
        }

        let targetRect = CGRect(
            x: target.center.x - target.radius,
            y: target.center.y - target.radius,
            width: target.radius * 2,
            height: target.radius * 2
        )

        if timestamp.timeIntervalSince(target.spawnedAt) >= targetSpawnGracePeriod,
           handRects.contains(where: { $0.rect.intersects(targetRect) }) {
            handHits += 1
            target.wasHit = true
            LevelEighteenSoundPlayer.playScore()
            if handHits.isMultiple(of: 10) {
                BallrDrillSoundPlayer.playCombo()
            }
            spawnHandTarget(at: timestamp)
        }
    }

    private func spawnHandTarget(at timestamp: Date) {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let radius = max(34, min(width, height) * 0.07)
        let side = nextHandTargetSide
        nextHandTargetSide = side == .left ? .right : .left
        let minY = radius + 72
        let maxY = max(minY, height * 0.40)
        let xRange: ClosedRange<CGFloat>
        switch side {
        case .left:
            xRange = (radius + 28)...max(radius + 28, width * 0.40)
        case .right:
            xRange = min(width - radius - 28, width * 0.60)...max(width * 0.60, width - radius - 28)
        }

        let center = nonOverlappingHandTargetCenter(
            xRange: xRange,
            yRange: minY...maxY,
            radius: radius
        )

        handTarget = LevelEighteenTarget(
            center: center,
            radius: radius,
            spawnedAt: timestamp,
            lifetime: targetLifetime
        )
    }

    private func nonOverlappingHandTargetCenter(
        xRange: ClosedRange<CGFloat>,
        yRange: ClosedRange<CGFloat>,
        radius: CGFloat
    ) -> CGPoint {
        let fallback = CGPoint(x: (xRange.lowerBound + xRange.upperBound) * 0.5, y: (yRange.lowerBound + yRange.upperBound) * 0.5)
        guard !handRects.isEmpty else {
            return CGPoint(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange))
        }

        var bestCenter = fallback
        var bestClearance = CGFloat.leastNormalMagnitude
        for _ in 0..<24 {
            let candidate = CGPoint(x: CGFloat.random(in: xRange), y: CGFloat.random(in: yRange))
            let candidateRect = CGRect(
                x: candidate.x - radius,
                y: candidate.y - radius,
                width: radius * 2,
                height: radius * 2
            ).insetBy(dx: -12, dy: -12)
            let clearance = handRects
                .map { distance(from: candidate, to: $0.rect) }
                .min() ?? CGFloat.greatestFiniteMagnitude

            if !handRects.contains(where: { $0.rect.intersects(candidateRect) }) {
                return candidate
            }

            if clearance > bestClearance {
                bestClearance = clearance
                bestCenter = candidate
            }
        }
        return bestCenter
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        return hypot(point.x - clampedX, point.y - clampedY)
    }

    private func updatePrompt() {
        if phase == .readiness {
            promptText = "GET BALL, FEET, AND A HAND IN FRAME"
        } else if phase == .live {
            if lostBallFrameCount >= lostBallPromptFrameThreshold {
                promptText = "FIND BALL"
            } else if lostFootFrameCount >= lostFootPromptFrameThreshold {
                promptText = "FIND FEET"
            } else if handRects.isEmpty {
                promptText = "FIND HAND"
            } else {
                promptText = "TOE TOUCHES + HAND TARGETS"
            }
        }
    }

    private func complete(at timestamp: Date) {
        guard phase != .finished else {
            return
        }

        phase = .finished
        completionStartedAt = timestamp
        handTarget = nil
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
}

private struct LevelEighteenTrackedRect: Identifiable {
    let id: Int
    let rect: CGRect
}

private enum LevelEighteenTouchSide: Equatable {
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

private struct LevelEighteenDetectedFoot: Identifiable {
    let id: Int
    let rect: CGRect
    let collisionPolygon: [CGPoint]
    let toePolygon: [CGPoint]

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

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) * 0.5, y: (a.y + b.y) * 0.5)
    }
}

private struct LevelEighteenBallStabilityState {
    let smoothedRect: CGRect?
    let isTracked: Bool
    let isStable: Bool
}

private struct LevelEighteenBallStabilityTracker {
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
    ) -> LevelEighteenBallStabilityState {
        let isTracked = overlayState.isTracking && overlayState.confirmedFrames >= 4 && ballDisplayRect != nil

        guard isTracked, let ballDisplayRect else {
            samples.removeAll()
            return LevelEighteenBallStabilityState(
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
            return LevelEighteenBallStabilityState(
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

        return LevelEighteenBallStabilityState(
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

private struct LevelEighteenToeTouchGameState {
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
        LevelEighteenTouchSide.left.footID: FootContactState(),
        LevelEighteenTouchSide.right.footID: FootContactState()
    ]
    private var lastTouchSide: LevelEighteenTouchSide?
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
        feet: [LevelEighteenDetectedFoot],
        timestamp: Date,
        isBallTracked: Bool
    ) -> LevelEighteenTouchSide? {
        guard isBallTracked, let ballDisplayRect else {
            pauseContacts()
            return nil
        }

        let zones = Self.contactZones(for: ballDisplayRect)
        var scores: [LevelEighteenTouchSide: CGFloat] = [.left: 0, .right: 0]

        if let leftFoot = feet.first(where: { $0.id == LevelEighteenTouchSide.left.footID }) {
            scores[.left] = contactScore(for: leftFoot, zone: zones.left, ballRect: ballDisplayRect)
        }
        if let rightFoot = feet.first(where: { $0.id == LevelEighteenTouchSide.right.footID }) {
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

        var countedSide: LevelEighteenTouchSide?
        for side in [LevelEighteenTouchSide.left, .right] {
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

    func highlightedSide(at date: Date) -> LevelEighteenTouchSide? {
        guard let lastTouchSide, let lastTouchAt else {
            return nil
        }
        return date.timeIntervalSince(lastTouchAt) <= highlightDuration ? lastTouchSide : nil
    }

    static func contactZones(for ballRect: CGRect) -> (left: CGRect, right: CGRect) {
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

    private mutating func pauseContacts() {
        resetContactStates()
    }

    private mutating func resetContactStates() {
        footStates = [
            LevelEighteenTouchSide.left.footID: FootContactState(),
            LevelEighteenTouchSide.right.footID: FootContactState()
        ]
    }

    private func contactScore(for foot: LevelEighteenDetectedFoot, zone: CGRect, ballRect: CGRect) -> CGFloat {
        let toeBounds = foot.toeBounds.insetBy(dx: toeBoundsInsetX(for: foot), dy: toeBoundsInsetY(for: foot))
        let intersection = toeBounds.intersection(zone)
        guard !intersection.isNull, !intersection.isEmpty else {
            return 0
        }

        let toeArea = max(toeBounds.width * toeBounds.height, 1)
        let zoneArea = max(zone.width * zone.height, 1)
        let overlapArea = intersection.width * intersection.height
        let overlapRatio = overlapArea / min(toeArea, zoneArea)
        let verticalBias: CGFloat = toeBounds.midY <= ballRect.midY + ballRect.height * 0.08 ? 1 : 0.45
        return overlapRatio * verticalBias
    }

    private func toeBoundsInsetX(for foot: LevelEighteenDetectedFoot) -> CGFloat {
        foot.toeBounds.width * 0.18
    }

    private func toeBoundsInsetY(for foot: LevelEighteenDetectedFoot) -> CGFloat {
        foot.toeBounds.height * 0.10
    }
}

private struct LevelEighteenTarget: Identifiable {
    let id = UUID()
    var center: CGPoint
    var radius: CGFloat
    var spawnedAt: Date
    var lifetime: TimeInterval
    var wasHit = false

    func progress(at date: Date) -> Double {
        min(max(date.timeIntervalSince(spawnedAt) / lifetime, 0), 1)
    }
}

private struct LevelEighteenOverlayView: View {
    @ObservedObject var coordinator: LevelEighteenCoordinator

    var body: some View {
        ZStack {
            if let target = coordinator.handTarget {
                TimelineView(.animation) { timeline in
                    let pulse = CGFloat((sin(timeline.date.timeIntervalSinceReferenceDate * 7.0) + 1) / 2)
                    let remaining = max(0.02, 1 - target.progress(at: timeline.date))
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.28))
                            .frame(width: target.radius * 2.0, height: target.radius * 2.0)

                        Circle()
                            .stroke(Color.white.opacity(0.82), lineWidth: 5)
                            .frame(width: target.radius * (1.35 + pulse * 0.22), height: target.radius * (1.35 + pulse * 0.22))

                        Circle()
                            .stroke(Color.green, lineWidth: 6)
                            .frame(width: target.radius * 2.0, height: target.radius * 2.0)

                        Circle()
                            .trim(from: 0, to: remaining)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: target.radius * 1.62, height: target.radius * 1.62)
                    }
                    .shadow(color: Color.green.opacity(0.58), radius: 16)
                    .position(target.center)
                }
            }

            VStack {
                Spacer()

                Text(coordinator.promptText)
                    .font(.ballr(size: 13, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 22)
            }
        }
    }
}

private struct LevelEighteenHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.ballr(size: 10, weight: .black))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.68))

            Text(value)
                .font(.ballr(size: 22, weight: .black))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(minWidth: 72)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LevelEighteenReadinessOverlay: View {
    let readyStartedAt: Date?

    var body: some View {
        TimelineView(.animation) { timeline in
            VStack(spacing: 12) {
                Text("LEVEL 18")
                    .font(.ballr(size: 16, weight: .black))
                    .tracking(2)
                    .foregroundStyle(.yellow)

                Text(readyStartedAt == nil ? "Get the ball, feet, and a hand in frame" : "Starting in \(remainingText(at: timeline.date))")
                    .font(.ballr(size: 22, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func remainingText(at date: Date) -> String {
        guard let readyStartedAt else {
            return "2"
        }
        let remaining = max(ceil(1.4 - date.timeIntervalSince(readyStartedAt)), 0)
        return "\(Int(remaining))"
    }
}

private struct LevelEighteenLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.82)
                .ignoresSafeArea()

            ProgressView()
                .tint(.yellow)
                .scaleEffect(1.2)
        }
    }
}

private struct LevelEighteenErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(permissionDenied ? "CAMERA ACCESS NEEDED" : "CAMERA ERROR")
                .font(.ballr(size: 20, weight: .black))
                .tracking(1.2)
                .foregroundStyle(.yellow)

            Text(message)
                .font(.ballr(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)

            Button("BACK") {
                onDismiss()
            }
            .font(.ballr(size: 15, weight: .black))
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(.yellow, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(22)
        .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 28)
    }
}

private enum LevelEighteenSoundPlayer {
    private static var scorePlayer: AVAudioPlayer?

    static func playScore() {
        guard let url = Bundle.main.url(forResource: "target_scored_sound_effect", withExtension: "wav") else {
            return
        }

        do {
            scorePlayer = try AVAudioPlayer(contentsOf: url)
            scorePlayer?.prepareToPlay()
            scorePlayer?.play()
        } catch {
            #if DEBUG
            print("Level 18 score sound failed: \(error.localizedDescription)")
            #endif
        }
    }
}
