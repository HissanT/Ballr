import AVFoundation
import Combine
import Foundation
import SwiftUI

struct LevelTwentyCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = LevelTwentyCoordinator()
    @State private var showsQuitConfirmation = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.18).ignoresSafeArea()

                LevelTwentyOverlay(coordinator: coordinator)
                    .ignoresSafeArea()

                if !coordinator.hasEnded {
                    VStack(spacing: 0) {
                        HStack(alignment: .top) {
                            LevelTwentyHudChip(title: "BALLS", value: "\(coordinator.ballScore)", tint: .yellow)
                            LevelTwentyHudChip(title: "AGILITY", value: "\(coordinator.agilityScore)", tint: .green)
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
                            LevelTwentyHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

                if cameraController.isStarting {
                    LevelTwentyLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    LevelTwentyErrorOverlay(message: errorMessage, onDismiss: { dismiss() })
                }

                if coordinator.phase == .readiness, cameraController.errorMessage == nil {
                    LevelTwentyReadinessOverlay(readyStartedAt: coordinator.readyStartedAt)
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                }

                if coordinator.hasEnded {
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
            .ballrAwardsXPOnSuccess(coordinator.hasEnded)
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(in: geometry.size)
                cameraController.detectsBody = true
                cameraController.publishesTrackingFramesToSwiftUI = false
                cameraController.onTrackingFrame = { [weak coordinator, weak cameraController] frame in
                    guard let cameraController else { return }
                    coordinator?.handle(frame: frame, cameraController: cameraController)
                }
                cameraController.start()
            }
            .onDisappear {
                coordinator.tearDown()
                cameraController.onTrackingFrame = nil
                cameraController.publishesTrackingFramesToSwiftUI = true
                cameraController.detectsBody = false
                cameraController.stop()
                BallrOrientationController.restoreDefaultOrientation()
            }
            .onChange(of: geometry.size) { _, newSize in
                coordinator.prepare(in: newSize)
            }
            .alert("Are you sure you want to quit the drill?", isPresented: $showsQuitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive) { dismiss() }
            }
        }
    }
}

private enum LevelTwentyPhase {
    case readiness
    case countdown
    case live
    case finished
}

private enum LevelTwentySide {
    case left
    case right

    var opposite: LevelTwentySide {
        self == .left ? .right : .left
    }
}

private struct LevelTwentyTarget: Identifiable {
    let id = UUID()
    let center: CGPoint
    let radius: CGFloat
    let side: LevelTwentySide
}

private final class LevelTwentyCoordinator: ObservableObject {
    @Published private(set) var phase: LevelTwentyPhase = .readiness
    @Published private(set) var readyStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var timerText = "30"
    @Published private(set) var ballScore = 0
    @Published private(set) var agilityScore = 0
    @Published private(set) var ballRect: CGRect?
    @Published private(set) var bodyCenter: CGPoint?
    @Published private(set) var target: LevelTwentyTarget?
    @Published private(set) var agilitySide: LevelTwentySide = .left
    @Published private(set) var hitFlashSide: LevelTwentySide?
    @Published private(set) var hitFlashStartedAt: Date?
    @Published private(set) var finishStartedAt: Date?
    @Published private(set) var showsFinishButtons = false

    private let requiredReadyLockSeconds: TimeInterval = 2.0
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 30.0
    private let finishAnimationDuration: TimeInterval = 2.05
    private let finishButtonRevealDelay: TimeInterval = 0.28
    private let leftLineFraction: CGFloat = 0.14
    private let rightLineFraction: CGFloat = 0.86

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var finishWorkItem: DispatchWorkItem?
    private var nextBallSide: LevelTwentySide = .left

    var hasEnded: Bool { phase == .finished }

    func reset(in size: CGSize) {
        cancelFinishWorkItem()
        self.size = size
        phase = .readiness
        readyStartedAt = nil
        countdownStartedAt = nil
        timerText = "30"
        ballScore = 0
        agilityScore = 0
        ballRect = nil
        bodyCenter = nil
        target = nil
        agilitySide = .left
        hitFlashSide = nil
        hitFlashStartedAt = nil
        finishStartedAt = nil
        showsFinishButtons = false
        liveElapsed = 0
        lastStepAt = nil
        nextBallSide = .left
    }

    func tearDown() {
        cancelFinishWorkItem()
    }

    func prepare(in size: CGSize) {
        self.size = size
        if phase == .live, target == nil {
            spawnTarget()
        }
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        let displayBallRect = frame.overlayState.normalizedRect.flatMap {
            cameraController.displayRect(for: $0)
        }
        ballRect = displayBallRect

        if let trackedBody = frame.bodyOverlayState.trackedBody {
            bodyCenter = cameraController.displayPoint(forTrackerPoint: trackedBody.normalizedCenter)
        } else {
            bodyCenter = nil
        }

        updateStartGate(
            isReady: frame.overlayState.isTracking && frame.bodyOverlayState.isTracking,
            timestamp: frame.timestamp
        )

        guard phase == .live else {
            return
        }

        let previousStepAt = lastStepAt ?? frame.timestamp
        let deltaTime = min(max(frame.timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
        lastStepAt = frame.timestamp
        liveElapsed = min(liveElapsed + deltaTime, roundDuration)
        timerText = String(Int(ceil(max(roundDuration - liveElapsed, 0))))

        if target == nil {
            spawnTarget()
        }

        if let target, let displayBallRect, intersects(circle: target, rect: displayBallRect) {
            ballScore += 1
            LevelTwentySoundPlayer.playScore()
            nextBallSide = target.side.opposite
            spawnTarget()
        }

        if let bodyCenter, isBodyInTargetSide(bodyCenter.x, side: agilitySide) {
            agilityScore += 1
            registerHitFlash(side: agilitySide)
            LevelTwentySoundPlayer.playScore()
            agilitySide = agilitySide.opposite
        }

        if liveElapsed >= roundDuration {
            finish(at: frame.timestamp)
        }
    }

    private func updateStartGate(isReady: Bool, timestamp: Date) {
        if phase == .live || phase == .finished {
            return
        }
        if phase == .countdown {
            if let countdownStartedAt, timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration {
                phase = .live
                liveElapsed = 0
                lastStepAt = timestamp
                timerText = "30"
                ballScore = 0
                agilityScore = 0
                agilitySide = .left
                nextBallSide = .left
                spawnTarget()
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

    private func spawnTarget() {
        guard size.width > 0, size.height > 0 else {
            return
        }
        let side = nextBallSide
        let radius = min(max(min(size.width, size.height) * 0.092, 36), 62)
        let x = side == .left ? size.width * 0.18 : size.width * 0.82
        let y = size.height * 0.72
        target = LevelTwentyTarget(center: CGPoint(x: x, y: y), radius: radius, side: side)
    }

    private func isBodyInTargetSide(_ x: CGFloat, side: LevelTwentySide) -> Bool {
        switch side {
        case .left:
            return x <= leftLineX + 24
        case .right:
            return x >= rightLineX - 24
        }
    }

    private func intersects(circle: LevelTwentyTarget, rect: CGRect) -> Bool {
        let clampedX = min(max(circle.center.x, rect.minX), rect.maxX)
        let clampedY = min(max(circle.center.y, rect.minY), rect.maxY)
        return hypot(circle.center.x - clampedX, circle.center.y - clampedY) <= circle.radius
    }

    private func registerHitFlash(side: LevelTwentySide) {
        hitFlashSide = side
        hitFlashStartedAt = Date()
    }

    private func finish(at timestamp: Date) {
        guard phase != .finished else { return }
        phase = .finished
        finishStartedAt = timestamp
        target = nil
        BallrDrillSoundPlayer.playWinner()
        let workItem = DispatchWorkItem { [weak self] in
            self?.showsFinishButtons = true
        }
        finishWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + finishAnimationDuration + finishButtonRevealDelay, execute: workItem)
    }

    private func cancelFinishWorkItem() {
        finishWorkItem?.cancel()
        finishWorkItem = nil
    }

    var leftLineX: CGFloat { size.width * leftLineFraction }
    var rightLineX: CGFloat { size.width * rightLineFraction }
}

private struct LevelTwentyOverlay: View {
    @ObservedObject var coordinator: LevelTwentyCoordinator

    var body: some View {
        TimelineView(.animation) { timeline in
            ZStack {
                sideZone(.left, date: timeline.date)
                sideZone(.right, date: timeline.date)
                targetView(coordinator.target)

                if let ballRect = coordinator.ballRect {
                    Ellipse()
                        .stroke(.white.opacity(0.82), lineWidth: 2)
                        .frame(width: ballRect.width, height: ballRect.height)
                        .position(x: ballRect.midX, y: ballRect.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func sideZone(_ side: LevelTwentySide, date: Date) -> some View {
        GeometryReader { geometry in
            let isActive = coordinator.agilitySide == side
            let flashProgress = hitFlashProgress(for: side, at: date)
            let width = geometry.size.width * 0.20
            let gradient = LinearGradient(
                colors: side == .left
                    ? [.green.opacity(isActive ? 0.28 + flashProgress * 0.26 : 0.10), .green.opacity(0)]
                    : [.green.opacity(0), .green.opacity(isActive ? 0.28 + flashProgress * 0.26 : 0.10)],
                startPoint: .leading,
                endPoint: .trailing
            )

            Rectangle()
                .fill(gradient)
                .frame(width: width)
                .shadow(color: .green.opacity(isActive ? 0.45 + flashProgress * 0.35 : 0.12), radius: isActive ? 24 : 10)
                .position(
                    x: side == .left ? width * 0.5 : geometry.size.width - width * 0.5,
                    y: geometry.size.height * 0.5
                )
        }
    }

    private func targetView(_ target: LevelTwentyTarget?) -> some View {
        Group {
            if let target {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.24))
                    Circle()
                        .stroke(.yellow.opacity(0.92), lineWidth: 9)
                        .shadow(color: .yellow.opacity(0.52), radius: 18)
                    Circle()
                        .stroke(.orange.opacity(0.95), lineWidth: 4)
                        .padding(9)
                }
                .frame(width: target.radius * 2, height: target.radius * 2)
                .position(x: target.center.x, y: target.center.y)
            }
        }
    }

    private func hitFlashProgress(for side: LevelTwentySide, at date: Date) -> CGFloat {
        guard coordinator.hitFlashSide == side, let startedAt = coordinator.hitFlashStartedAt else {
            return 0
        }
        return CGFloat(max(0, 1 - min(date.timeIntervalSince(startedAt) / 0.55, 1)))
    }
}

private struct LevelTwentyHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.ballr(size: 14, weight: .black))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.ballr(size: 30, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .frame(minWidth: 104, minHeight: 68)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.86), lineWidth: 2))
    }
}

private struct LevelTwentyReadinessOverlay: View {
    let readyStartedAt: Date?

    var body: some View {
        TimelineView(.animation) { timeline in
            VStack(spacing: 12) {
                Text(readyStartedAt == nil ? "Find the ball and body" : "Hold still")
                    .font(.ballr(size: 24, weight: .black))
                    .foregroundStyle(readyStartedAt == nil ? Color.yellow : .white)
                Text(readyStartedAt == nil ? "Keep both in frame to start." : "Starting in \(remainingText(at: timeline.date))")
                    .font(.ballr(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
            .padding(24)
        }
    }

    private func remainingText(at date: Date) -> String {
        guard let readyStartedAt else { return "" }
        return "\(Int(max(ceil(2.0 - date.timeIntervalSince(readyStartedAt)), 0)))"
    }
}

private struct LevelTwentyLoadingOverlay: View {
    var body: some View {
        ProgressView()
            .tint(.white)
            .scaleEffect(1.3)
            .frame(width: 120, height: 90)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LevelTwentyErrorOverlay: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Camera Unavailable")
                .font(.ballr(size: 24, weight: .black))
            Text(message)
                .font(.ballr(size: 15, weight: .bold))
                .multilineTextAlignment(.center)
            Button("CLOSE", action: onDismiss)
                .font(.ballr(size: 15, weight: .black))
        }
        .foregroundStyle(.white)
        .padding(24)
        .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
        .padding(24)
    }
}

private enum LevelTwentySoundPlayer {
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
                return
            }
        }
        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}
