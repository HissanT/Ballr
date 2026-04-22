import AVFoundation
import Foundation
import SwiftUI
import UIKit
import Combine

struct LevelOneCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = LevelOneCoordinator()
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

                LevelOneOverlayView(
                    coordinator: coordinator,
                    onNextLevel: { showsNextLevel = true },
                    onTryAgain: { coordinator.reset(in: geometry.size) },
                    onBackToLevels: { dismiss() }
                )
                .ignoresSafeArea()

                if showsTopBar {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                if cameraController.isStarting {
                    LevelOneLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    LevelOneErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.startPhase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                } else if coordinator.startPhase == .readiness, cameraController.errorMessage == nil {
                    BallrDrillReadinessOverlay(
                        ballFoundStartedAt: coordinator.ballFoundStartedAt,
                        requiredLockSeconds: LevelOneCoordinator.requiredBallLockSeconds
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .navigationDestination(isPresented: $showsNextLevel) {
                HandTargetCameraView()
                    .ballrCameraPresentationChrome()
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
                coordinator.prepare(in: newSize)
            }
            .alert("Are you sure you want to quit the tutorial?", isPresented: $showsQuitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive) {
                    dismiss()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LEVEL 1")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(Color.yellow)

                Text("Ball Basics")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))

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
        }
    }

    private var showsTopBar: Bool {
        switch coordinator.tutorialStage {
        case .completionAnimation, .results:
            return false
        default:
            return true
        }
    }
}

private final class LevelOneCoordinator: ObservableObject {
    static let requiredBallLockSeconds: TimeInterval = 2.0

    @Published private(set) var startPhase: BallrDrillStartPhase = .readiness
    @Published private(set) var ballFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var ballDisplayRect: CGRect?
    @Published private(set) var isTracking = false
    @Published private(set) var hasConfidentTracking = false
    @Published private(set) var trackingStatusText = "SEARCHING"
    @Published private(set) var tutorialStage: LevelOneTutorialStage = .idle
    @Published private(set) var xRepsCompleted = 0
    @Published private(set) var yRepsCompleted = 0
    @Published private(set) var zRepsCompleted = 0
    @Published private(set) var completionStartedAt: Date?

    private static let countdownDuration: TimeInterval = 4.0
    private let confidenceThreshold = 0.75
    private let introCardDuration: TimeInterval = 1.8
    private let axisTransitionDelay: TimeInterval = 0.75
    private let completionAnimationDuration: TimeInterval = 1.2
    private let completionButtonRevealDelay: TimeInterval = 0.28

    private var size: CGSize = .zero
    private var motionSampler = LevelOneMotionSampler()
    private var repTracker = LevelOneRepTracker()
    private var yRepTracker = LevelOneYRepTracker()
    private var pendingTransitionWorkItem: DispatchWorkItem?

    func reset(in size: CGSize) {
        cancelPendingTransition()
        self.size = size
        startPhase = .readiness
        ballFoundStartedAt = nil
        countdownStartedAt = nil
        ballDisplayRect = nil
        isTracking = false
        hasConfidentTracking = false
        trackingStatusText = "SEARCHING"
        tutorialStage = .idle
        xRepsCompleted = 0
        yRepsCompleted = 0
        zRepsCompleted = 0
        completionStartedAt = nil
        motionSampler.reset()
        repTracker.reset()
        yRepTracker.reset()
    }

    func tearDown() {
        cancelPendingTransition()
    }

    func prepare(in size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }
        self.size = size
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        let overlayState = frame.overlayState
        let confidence = overlayState.confidence ?? 0
        let isConfidentBall = overlayState.isTracking && confidence >= confidenceThreshold

        ballDisplayRect = displayRect(for: overlayState, cameraController: cameraController)
        updateTrackingStatus(from: overlayState, isConfidentBall: isConfidentBall)
        updateStartGate(isConfidentBall: isConfidentBall, timestamp: frame.timestamp)

        guard startPhase == .live else {
            return
        }

        if tutorialStage == .idle {
            startIntroCards()
            return
        }

        switch tutorialStage {
        case .axis(let axis):
            handleAxis(axis, overlayState: overlayState)
        case .idle, .intro, .completionAnimation, .results:
            break
        }
    }

    func repsCompleted(for axis: LevelOneAxis) -> Int {
        switch axis {
        case .x:
            return xRepsCompleted
        case .y:
            return yRepsCompleted
        case .z:
            return zRepsCompleted
        }
    }

    func shouldShowResultButtons(at date: Date) -> Bool {
        guard let completionStartedAt else {
            return tutorialStage == .results
        }
        let elapsed = date.timeIntervalSince(completionStartedAt)
        return tutorialStage == .results || elapsed >= completionAnimationDuration + completionButtonRevealDelay
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

    private func updateTrackingStatus(from overlayState: BallTrackerOverlayState, isConfidentBall: Bool) {
        if isTracking != overlayState.isTracking {
            isTracking = overlayState.isTracking
        }
        if hasConfidentTracking != isConfidentBall {
            hasConfidentTracking = isConfidentBall
        }

        let statusText: String
        if overlayState.isTracking, !isConfidentBall {
            statusText = "LOCKING ON"
        } else {
            statusText = overlayState.statusText.uppercased()
        }

        if trackingStatusText != statusText {
            trackingStatusText = statusText
        }
    }

    private func updateStartGate(isConfidentBall: Bool, timestamp: Date) {
        if startPhase == .live {
            return
        }

        if startPhase == .countdown {
            if
                let countdownStartedAt,
                timestamp.timeIntervalSince(countdownStartedAt) >= Self.countdownDuration
            {
                startPhase = .live
            }
            return
        }

        guard isConfidentBall else {
            ballFoundStartedAt = nil
            return
        }

        let startedAt = ballFoundStartedAt ?? timestamp
        ballFoundStartedAt = startedAt

        if timestamp.timeIntervalSince(startedAt) >= Self.requiredBallLockSeconds {
            countdownStartedAt = timestamp
            startPhase = .countdown
        }
    }

    private func startIntroCards() {
        cancelPendingTransition()
        motionSampler.reset()
        repTracker.reset()
        transition(to: .intro(0))
        schedule(after: introCardDuration) { [weak self] in
            self?.advanceIntroCard(from: 0)
        }
    }

    private func advanceIntroCard(from currentIndex: Int) {
        guard case .intro(let liveIndex) = tutorialStage, liveIndex == currentIndex else {
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < LevelOneIntroCard.cards.count {
            transition(to: .intro(nextIndex))
            schedule(after: introCardDuration) { [weak self] in
                self?.advanceIntroCard(from: nextIndex)
            }
        } else {
            beginAxis(.x)
        }
    }

    private func beginAxis(_ axis: LevelOneAxis) {
        cancelPendingTransition()
        motionSampler.reset()
        repTracker.reset()
        transition(to: .axis(axis))
    }

    private func handleAxis(_ axis: LevelOneAxis, overlayState: BallTrackerOverlayState) {
        guard
            hasConfidentTracking,
            let ballDisplayRect
        else {
            motionSampler.reset()
            repTracker.reset()
            yRepTracker.reset()
            return
        }

        let center = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
        let diameter = max(ballDisplayRect.width, ballDisplayRect.height)
        let sample = motionSampler.append(center: center, diameter: diameter)
        let didCompleteRep: Bool

        switch axis {
        case .x:
            let threshold = min(max(size.width * 0.045, sample.diameter * 0.30, 28), 68)
            didCompleteRep = repTracker.register(value: sample.center.x, threshold: threshold)
        case .y:
            let threshold = min(max(size.height * 0.055, sample.diameter * 0.24, 22), 52)
            didCompleteRep = yRepTracker.register(value: sample.center.y, threshold: threshold)
        case .z:
            let baseline = repTracker.anchor ?? sample.diameter
            let threshold = min(max(baseline * 0.065, 6), 18)
            didCompleteRep = repTracker.register(value: sample.diameter, threshold: threshold)
        }

        guard didCompleteRep else {
            return
        }

        switch axis {
        case .x:
            xRepsCompleted += 1
            if xRepsCompleted >= 3 {
                LevelOneSoundPlayer.playDing()
                scheduleAxisAdvance(from: .x)
            }
        case .y:
            yRepsCompleted += 1
            if yRepsCompleted >= 3 {
                LevelOneSoundPlayer.playDing()
                scheduleAxisAdvance(from: .y)
            }
        case .z:
            zRepsCompleted += 1
            if zRepsCompleted >= 3 {
                LevelOneSoundPlayer.playDing()
                startCompletionAnimation()
            }
        }
    }

    private func scheduleAxisAdvance(from axis: LevelOneAxis) {
        motionSampler.reset()
        repTracker.reset()
        let nextAxis = axis.nextAxis
        schedule(after: axisTransitionDelay) { [weak self] in
            guard let self else {
                return
            }
            guard let nextAxis else {
                self.startCompletionAnimation()
                return
            }
            self.beginAxis(nextAxis)
        }
    }

    private func startCompletionAnimation() {
        cancelPendingTransition()
        motionSampler.reset()
        repTracker.reset()
        BallrDrillSoundPlayer.playWinner()
        completionStartedAt = Date()
        transition(to: .completionAnimation)
        schedule(after: completionAnimationDuration + completionButtonRevealDelay) { [weak self] in
            self?.transition(to: .results)
        }
    }

    private func transition(to stage: LevelOneTutorialStage) {
        withAnimation(.easeInOut(duration: 0.28)) {
            tutorialStage = stage
        }
    }

    private func schedule(after delay: TimeInterval, action: @escaping () -> Void) {
        cancelPendingTransition()
        let workItem = DispatchWorkItem(block: action)
        pendingTransitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelPendingTransition() {
        pendingTransitionWorkItem?.cancel()
        pendingTransitionWorkItem = nil
    }
}

private struct LevelOneOverlayView: View {
    @ObservedObject var coordinator: LevelOneCoordinator
    let onNextLevel: () -> Void
    let onTryAgain: () -> Void
    let onBackToLevels: () -> Void

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geometry in
                ZStack {
                    if let ballDisplayRect = coordinator.ballDisplayRect {
                        LevelOneBallIndicator(
                            ballDisplayRect: ballDisplayRect,
                            isConfidentTracking: coordinator.hasConfidentTracking
                        )
                    }

                    stageOverlay(in: geometry.size, at: timeline.date)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .allowsHitTesting(shouldAllowHitTesting)
    }

    private var shouldAllowHitTesting: Bool {
        switch coordinator.tutorialStage {
        case .results:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func stageOverlay(in size: CGSize, at date: Date) -> some View {
        switch coordinator.tutorialStage {
        case .idle:
            EmptyView()
        case .intro(let index):
            LevelOneIntroCardView(card: LevelOneIntroCard.cards[index])
                .padding(.horizontal, 28)
        case .axis(let axis):
            VStack(spacing: 0) {
                VStack(spacing: 7) {
                    Text(axis.title)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.85), radius: 8, x: 0, y: 3)

                    Text("\(coordinator.repsCompleted(for: axis))/3")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(Color.yellow)
                        .padding(.top, 2)
                        .shadow(color: .black.opacity(0.9), radius: 8, x: 0, y: 3)
                }
                .padding(.horizontal, 120)
                .frame(maxWidth: min(size.width * 0.82, 660))
                .padding(.top, 22)

                Spacer()
            }
        case .completionAnimation, .results:
            LevelOneCompletionOverlay(
                stage: coordinator.tutorialStage,
                startedAt: coordinator.completionStartedAt,
                date: date,
                buttonsVisible: coordinator.shouldShowResultButtons(at: date),
                onNextLevel: onNextLevel,
                onTryAgain: onTryAgain,
                onBackToLevels: onBackToLevels
            )
        }
    }
}

private struct LevelOneBallIndicator: View {
    let ballDisplayRect: CGRect
    let isConfidentTracking: Bool

    var body: some View {
        let diameter = max(ballDisplayRect.width, ballDisplayRect.height)
        let center = CGPoint(x: ballDisplayRect.midX, y: ballDisplayRect.midY)

        ZStack {
            Circle()
                .stroke(isConfidentTracking ? Color.yellow : .white.opacity(0.75), lineWidth: 4)
                .frame(width: diameter, height: diameter)
                .shadow(color: (isConfidentTracking ? Color.yellow : .white).opacity(0.45), radius: 12)

            Circle()
                .fill(isConfidentTracking ? Color.yellow : .white.opacity(0.8))
                .frame(width: 12, height: 12)
        }
        .position(center)
    }
}

private struct LevelOneIntroCardView: View {
    let card: LevelOneIntroCard

    var body: some View {
        VStack(spacing: 18) {
            Text(card.title)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(Color.yellow)
                .multilineTextAlignment(.center)

            Text(card.subtitle)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.horizontal, 30)
        .frame(maxWidth: 620, minHeight: 260)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.yellow.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct LevelOneCompletionOverlay: View {
    let stage: LevelOneTutorialStage
    let startedAt: Date?
    let date: Date
    let buttonsVisible: Bool
    let onNextLevel: () -> Void
    let onTryAgain: () -> Void
    let onBackToLevels: () -> Void

    var body: some View {
        GeometryReader { geometry in
            let progress = completionProgress
            let showDone = progress >= 0.72

            ZStack {
                if progress >= 1 {
                    Color.yellow
                        .ignoresSafeArea()
                }

                LevelOneWaveFillShape(side: .left, progress: progress, phase: progress)
                    .fill(Color.yellow)
                    .ignoresSafeArea()

                LevelOneWaveFillShape(side: .right, progress: progress, phase: progress + 0.18)
                    .fill(Color.yellow)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    Spacer()

                    Text("DONE")
                        .font(.system(size: 54, weight: .black, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.88))
                        .opacity(showDone ? 1 : 0)
                        .scaleEffect(showDone ? 1 : 0.84)

                    if buttonsVisible {
                        HStack(spacing: 10) {
                            Button(action: onBackToLevels) {
                                Text("BACK TO LEVELS")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 18)
                                    .frame(height: 44)
                                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                            }

                            Button(action: onTryAgain) {
                                Text("TRY AGAIN")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 18)
                                    .frame(height: 44)
                                    .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 12))
                            }

                            Button(action: onNextLevel) {
                                Text("NEXT LEVEL")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 18)
                                    .frame(height: 44)
                                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .padding(.bottom, buttonsVisible ? 8 : 0)
                .animation(.easeInOut(duration: 0.28), value: buttonsVisible)
            }
        }
    }

    private var completionProgress: CGFloat {
        guard let startedAt else {
            return stage == .results ? 1 : 0
        }
        let elapsed = date.timeIntervalSince(startedAt)
        if stage == .results {
            return 1
        }
        return CGFloat(min(max(elapsed / 1.2, 0), 1))
    }
}

private struct LevelOneWaveFillShape: Shape {
    enum Side {
        case left
        case right
    }

    let side: Side
    let progress: CGFloat
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let maxWidth = rect.width * 0.5
        let filledWidth = maxWidth * clampedProgress
        let amplitude = max(10, 28 * (1 - clampedProgress * 0.5))
        let phaseOffset = CGFloat(sin(Double(phase) * .pi * 2)) * amplitude * 0.45

        var path = Path()

        switch side {
        case .left:
            let edgeX = min(rect.midX, filledWidth)
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: edgeX, y: 0))
            path.addCurve(
                to: CGPoint(x: edgeX, y: rect.height),
                control1: CGPoint(x: edgeX - amplitude, y: rect.height * 0.28),
                control2: CGPoint(x: edgeX + amplitude + phaseOffset, y: rect.height * 0.72)
            )
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        case .right:
            let edgeX = max(rect.midX, rect.width - filledWidth)
            path.move(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: edgeX, y: 0))
            path.addCurve(
                to: CGPoint(x: edgeX, y: rect.height),
                control1: CGPoint(x: edgeX + amplitude, y: rect.height * 0.28),
                control2: CGPoint(x: edgeX - amplitude - phaseOffset, y: rect.height * 0.72)
            )
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.closeSubpath()
        }

        return path
    }
}

private struct LevelOneLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)

            Text("Starting level 1...")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LevelOneErrorOverlay: View {
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

private enum LevelOneTutorialStage: Equatable {
    case idle
    case intro(Int)
    case axis(LevelOneAxis)
    case completionAnimation
    case results
}

private enum LevelOneAxis: CaseIterable, Equatable {
    case x
    case y
    case z

    var title: String {
        switch self {
        case .x:
            return "Move left and right"
        case .y:
            return "Move up and down"
        case .z:
            return "Move closer and away"
        }
    }

    var subtitle: String {
        switch self {
        case .x:
            return "Roll the ball side to side three times."
        case .y:
            return "Lift it up and down three times if that feels comfy."
        case .z:
            return "Bring it in and send it back three times."
        }
    }

    var helperText: String {
        switch self {
        case .x:
            return "Go across, then come back."
        case .y:
            return "Go up, then come back down."
        case .z:
            return "Come closer, then move away."
        }
    }

    var nextAxis: LevelOneAxis? {
        switch self {
        case .x:
            return .y
        case .y:
            return .z
        case .z:
            return nil
        }
    }
}

private struct LevelOneIntroCard {
    let title: String
    let subtitle: String

    static let cards: [LevelOneIntroCard] = [
        LevelOneIntroCard(
            title: "Welcome!",
            subtitle: "Let's get comfy with the ball and the screen."
        ),
        LevelOneIntroCard(
            title: "We'll go one step at a time.",
            subtitle: "First side to side, then up and down."
        ),
        LevelOneIntroCard(
            title: "Then one last move.",
            subtitle: "Bring the ball closer and farther. Nice and easy."
        )
    ]
}

private struct LevelOneMotionSample {
    let center: CGPoint
    let diameter: CGFloat
}

private struct LevelOneMotionSampler {
    private var xSamples: [CGFloat] = []
    private var ySamples: [CGFloat] = []
    private var diameterSamples: [CGFloat] = []
    private let sampleWindow = 5

    mutating func append(center: CGPoint, diameter: CGFloat) -> LevelOneMotionSample {
        xSamples.append(center.x)
        ySamples.append(center.y)
        diameterSamples.append(diameter)

        if xSamples.count > sampleWindow {
            xSamples.removeFirst(xSamples.count - sampleWindow)
        }
        if ySamples.count > sampleWindow {
            ySamples.removeFirst(ySamples.count - sampleWindow)
        }
        if diameterSamples.count > sampleWindow {
            diameterSamples.removeFirst(diameterSamples.count - sampleWindow)
        }

        return LevelOneMotionSample(
            center: CGPoint(x: Self.median(of: xSamples), y: Self.median(of: ySamples)),
            diameter: Self.median(of: diameterSamples)
        )
    }

    mutating func reset() {
        xSamples.removeAll(keepingCapacity: true)
        ySamples.removeAll(keepingCapacity: true)
        diameterSamples.removeAll(keepingCapacity: true)
    }

    private static func median(of values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else {
            return 0
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }
        return sorted[middle]
    }
}

private struct LevelOneRepTracker {
    enum Side {
        case negative
        case positive
    }

    var anchor: CGFloat?
    private var terminalSide: Side?
    private var awaySide: Side?
    private var negativeExtreme: CGFloat?
    private var positiveExtreme: CGFloat?

    mutating func register(value: CGFloat, threshold: CGFloat) -> Bool {
        guard threshold > 0 else {
            return false
        }

        guard let anchor else {
            self.anchor = value
            terminalSide = nil
            awaySide = nil
            return false
        }

        let delta = value - anchor
        guard let currentSide = side(for: delta, threshold: threshold) else {
            return false
        }
        recordExtreme(value, on: currentSide)

        if let terminalSide {
            if awaySide == nil {
                if currentSide != terminalSide {
                    awaySide = currentSide
                }
                return false
            }

            guard currentSide == terminalSide else {
                return false
            }

            awaySide = nil
            updateAnchorFromExtremes(maxShift: threshold * 0.45)
            return true
        }

        guard let awaySide else {
            self.awaySide = currentSide
            return false
        }

        guard currentSide != awaySide else {
            return false
        }

        terminalSide = currentSide
        self.awaySide = nil
        updateAnchorFromExtremes(maxShift: threshold * 0.45)
        return true
    }

    mutating func reset() {
        anchor = nil
        terminalSide = nil
        awaySide = nil
        negativeExtreme = nil
        positiveExtreme = nil
    }

    private func side(for delta: CGFloat, threshold: CGFloat) -> Side? {
        if delta >= threshold {
            return .positive
        }
        if delta <= -threshold {
            return .negative
        }
        return nil
    }

    private mutating func recordExtreme(_ value: CGFloat, on side: Side) {
        switch side {
        case .negative:
            negativeExtreme = min(negativeExtreme ?? value, value)
        case .positive:
            positiveExtreme = max(positiveExtreme ?? value, value)
        }
    }

    private mutating func updateAnchorFromExtremes(maxShift: CGFloat) {
        guard
            let anchor,
            let negativeExtreme,
            let positiveExtreme,
            maxShift > 0
        else {
            return
        }

        let midpoint = (negativeExtreme + positiveExtreme) * 0.5
        let shift = min(max(midpoint - anchor, -maxShift), maxShift)
        self.anchor = anchor + shift
        self.negativeExtreme = nil
        self.positiveExtreme = nil
    }
}

private struct LevelOneYRepTracker {
    private enum Direction {
        case decreasing
        case increasing

        var opposite: Direction {
            switch self {
            case .decreasing:
                return .increasing
            case .increasing:
                return .decreasing
            }
        }
    }

    private struct PendingReturn {
        let direction: Direction
        let turnValue: CGFloat
    }

    private var lastValue: CGFloat?
    private var segmentStartValue: CGFloat?
    private var currentDirection: Direction?
    private var armedDirection: Direction?
    private var pendingReturn: PendingReturn?
    private var requiredFirstDirection: Direction?

    mutating func register(value: CGFloat, threshold: CGFloat) -> Bool {
        guard threshold > 0 else {
            return false
        }

        guard let lastValue else {
            self.lastValue = value
            segmentStartValue = value
            currentDirection = nil
            armedDirection = nil
            pendingReturn = nil
            return false
        }

        let delta = value - lastValue
        let noiseFloor = max(threshold * 0.16, 3)
        guard abs(delta) >= noiseFloor else {
            return false
        }

        let newDirection: Direction = delta > 0 ? .increasing : .decreasing
        if currentDirection == nil {
            guard requiredFirstDirection == nil || newDirection == requiredFirstDirection else {
                self.lastValue = value
                segmentStartValue = value
                return false
            }

            currentDirection = newDirection
            segmentStartValue = lastValue
            self.lastValue = value
            return false
        }

        if newDirection == currentDirection {
            self.lastValue = value
            armCurrentSegmentIfNeeded(value: value, threshold: threshold)
            return completePendingReturnIfNeeded(value: value, threshold: threshold)
        }

        let previousDirection = currentDirection
        let turnValue = lastValue
        let previousTravel = abs(turnValue - (segmentStartValue ?? turnValue))
        let canUsePreviousDirection = requiredFirstDirection == nil || previousDirection == requiredFirstDirection
        if canUsePreviousDirection, previousDirection == armedDirection || previousTravel >= threshold {
            pendingReturn = PendingReturn(direction: newDirection, turnValue: turnValue)
        }

        currentDirection = newDirection
        segmentStartValue = turnValue
        armedDirection = nil
        self.lastValue = value
        return completePendingReturnIfNeeded(value: value, threshold: threshold)
    }

    mutating func reset() {
        lastValue = nil
        segmentStartValue = nil
        currentDirection = nil
        armedDirection = nil
        pendingReturn = nil
        requiredFirstDirection = nil
    }

    private mutating func armCurrentSegmentIfNeeded(value: CGFloat, threshold: CGFloat) {
        guard
            let currentDirection,
            let segmentStartValue,
            abs(value - segmentStartValue) >= threshold
        else {
            return
        }
        armedDirection = currentDirection
    }

    private mutating func completePendingReturnIfNeeded(value: CGFloat, threshold: CGFloat) -> Bool {
        guard
            let pendingReturn,
            currentDirection == pendingReturn.direction
        else {
            return false
        }

        let returnThreshold = max(threshold * 0.9, 12)
        guard abs(value - pendingReturn.turnValue) >= returnThreshold else {
            return false
        }

        self.pendingReturn = nil
        self.armedDirection = nil
        self.requiredFirstDirection = pendingReturn.direction.opposite
        self.currentDirection = nil
        self.segmentStartValue = value
        self.lastValue = value
        return true
    }
}

private enum LevelOneSoundPlayer {
    private static var player: AVAudioPlayer?

    static func playDing() {
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
                print("Level 1 sound failed to load: \(error.localizedDescription)")
                return
            }
        }

        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}
