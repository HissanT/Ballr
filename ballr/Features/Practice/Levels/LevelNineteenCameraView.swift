import AVFoundation
import Combine
import Foundation
import SwiftUI

struct LevelNineteenCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = LevelNineteenCoordinator()
    @State private var showsQuitConfirmation = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.18).ignoresSafeArea()

                LevelNineteenOverlay(coordinator: coordinator)
                    .ignoresSafeArea()

                if !coordinator.hasEnded {
                    VStack(spacing: 0) {
                        HStack(alignment: .top) {
                            LevelNineteenHudChip(title: "BALLS", value: "\(coordinator.ballHits)", tint: .yellow)
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
                            HStack(spacing: 10) {
                                LevelNineteenHudChip(title: "HANDS", value: "\(coordinator.handHits)", tint: .green)
                                LevelNineteenHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

                if cameraController.isStarting {
                    LevelNineteenLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    LevelNineteenErrorOverlay(message: errorMessage, onDismiss: { dismiss() })
                }

                if coordinator.phase == .readiness, cameraController.errorMessage == nil {
                    BallrDrillReadinessOverlay(ballFoundStartedAt: coordinator.ballFoundStartedAt)
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                }

                if coordinator.hasEnded {
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.finishStartedAt,
                        buttonsVisible: coordinator.showsFinishButtons,
                        title: "DONE",
                        showsNextLevelButton: true,
                        onNextLevel: { },
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
                cameraController.detectsHands = true
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
                cameraController.detectsHands = false
                cameraController.stop()
                BallrOrientationController.restoreDefaultOrientation()
            }
            .onChange(of: geometry.size) { _, newSize in
                coordinator.prepare(in: newSize, forceRespawn: true)
            }
            .alert("Are you sure you want to quit the drill?", isPresented: $showsQuitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive) { dismiss() }
            }
        }
    }
}

private enum LevelNineteenPhase {
    case readiness
    case countdown
    case live
    case finished
}

private final class LevelNineteenCoordinator: ObservableObject {
    @Published private(set) var phase: LevelNineteenPhase = .readiness
    @Published private(set) var ballFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var timerText = "30"
    @Published private(set) var ballHits = 0
    @Published private(set) var handHits = 0
    @Published private(set) var ballRect: CGRect?
    @Published private(set) var handRects: [CGRect] = []
    @Published private(set) var ballTarget: LevelNineteenTarget?
    @Published private(set) var handTarget: LevelNineteenTarget?
    @Published private(set) var finishStartedAt: Date?
    @Published private(set) var showsFinishButtons = false

    private let requiredBallLockSeconds: TimeInterval = 2.0
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 30.0
    private let finishAnimationDuration: TimeInterval = 2.05
    private let finishButtonRevealDelay: TimeInterval = 0.28
    private let targetSpawnGracePeriod: TimeInterval = 0.18
    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var lastBallHitAt = Date.distantPast
    private var finishWorkItem: DispatchWorkItem?
    private var nextSide: LevelNineteenSide = .left
    private var nextHandSide: LevelNineteenSide = .left

    var hasEnded: Bool { phase == .finished }

    func reset(in size: CGSize) {
        cancelFinishWorkItem()
        self.size = size
        phase = .readiness
        ballFoundStartedAt = nil
        countdownStartedAt = nil
        timerText = "30"
        ballHits = 0
        handHits = 0
        ballRect = nil
        handRects = []
        ballTarget = nil
        handTarget = nil
        finishStartedAt = nil
        showsFinishButtons = false
        liveElapsed = 0
        lastStepAt = nil
        lastBallHitAt = .distantPast
        nextSide = .left
        nextHandSide = .left
    }

    func tearDown() {
        cancelFinishWorkItem()
    }

    func prepare(in size: CGSize, forceRespawn: Bool = false) {
        self.size = size
        if forceRespawn, phase == .live {
            spawnTargets(timestamp: Date())
        }
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        let displayBallRect = frame.overlayState.normalizedRect.flatMap {
            cameraController.displayRect(for: $0)
        }
        ballRect = displayBallRect
        handRects = frame.handOverlayState.hands.compactMap {
            cameraController.displayRect(for: $0.normalizedRect)
        }

        updateStartGate(isTracking: frame.overlayState.isTracking, timestamp: frame.timestamp)
        guard phase == .live else {
            return
        }

        let previousStepAt = lastStepAt ?? frame.timestamp
        let deltaTime = min(max(frame.timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
        lastStepAt = frame.timestamp
        liveElapsed = min(liveElapsed + deltaTime, roundDuration)
        timerText = String(Int(ceil(max(roundDuration - liveElapsed, 0))))

        if ballTarget == nil {
            spawnTargets(timestamp: frame.timestamp)
        }

        if
            let displayBallRect,
            let ballTarget,
            frame.timestamp.timeIntervalSince(lastBallHitAt) > 0.32,
            intersects(circle: ballTarget, rect: displayBallRect)
        {
            ballHits += 1
            lastBallHitAt = frame.timestamp
            LevelNineteenSoundPlayer.playScore()
            spawnBallTarget(timestamp: frame.timestamp)
            if handTarget == nil {
                spawnNextHandTarget(timestamp: frame.timestamp)
            }
        }

        if
            let handTarget,
            handTarget.isExpired(at: frame.timestamp)
        {
            BallrDrillSoundPlayer.playIncorrect()
            spawnNextHandTarget(timestamp: frame.timestamp)
        } else if
            let handTarget,
            frame.timestamp.timeIntervalSince(handTarget.spawnedAt) >= targetSpawnGracePeriod,
            handRects.contains(where: { intersects(circle: handTarget, rect: $0) })
        {
            handHits += 1
            LevelNineteenSoundPlayer.playScore()
            spawnNextHandTarget(timestamp: frame.timestamp)
        }

        if liveElapsed >= roundDuration {
            finish(at: frame.timestamp)
        }
    }

    private func updateStartGate(isTracking: Bool, timestamp: Date) {
        if phase == .live || phase == .finished {
            return
        }
        if phase == .countdown {
            if let countdownStartedAt, timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration {
                phase = .live
                liveElapsed = 0
                lastStepAt = timestamp
                spawnTargets(timestamp: timestamp)
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
            phase = .countdown
        }
    }

    private func spawnTargets(timestamp: Date) {
        let side = spawnBallTarget(timestamp: timestamp)
        spawnHandTarget(for: side, timestamp: timestamp)
    }

    @discardableResult
    private func spawnBallTarget(timestamp: Date) -> LevelNineteenSide {
        guard size.width > 0, size.height > 0 else {
            return nextSide
        }
        let side = nextSide
        nextSide = nextSide.opposite
        let radius = min(max(min(size.width, size.height) * 0.085, 34), 58)
        let x: CGFloat
        switch side {
        case .left:
            x = size.width * 0.24
        case .right:
            x = size.width * 0.78
        }
        let y = size.height * 0.80
        ballTarget = LevelNineteenTarget(center: CGPoint(x: x, y: y), radius: radius, spawnedAt: timestamp, lifetime: nil, side: side)
        return side
    }

    private func spawnHandTarget(for side: LevelNineteenSide, timestamp: Date) {
        let radius = min(max(min(size.width, size.height) * 0.070, 30), 50)
        let x = side == .left ? size.width * 0.24 : size.width * 0.78
        let ballY = ballTarget?.center.y ?? size.height * 0.80
        let y = max(radius + 26, ballY - size.height * 0.40)
        handTarget = LevelNineteenTarget(center: CGPoint(x: x, y: y), radius: radius, spawnedAt: timestamp, lifetime: 3.0, side: side)
        nextHandSide = side.opposite
    }

    private func spawnNextHandTarget(timestamp: Date) {
        let side = handTarget?.side.opposite ?? nextHandSide
        spawnHandTarget(for: side, timestamp: timestamp)
    }

    private func intersects(circle: LevelNineteenTarget, rect: CGRect) -> Bool {
        let clampedX = min(max(circle.center.x, rect.minX), rect.maxX)
        let clampedY = min(max(circle.center.y, rect.minY), rect.maxY)
        return hypot(circle.center.x - clampedX, circle.center.y - clampedY) <= circle.radius
    }

    private func finish(at timestamp: Date) {
        guard phase != .finished else { return }
        phase = .finished
        finishStartedAt = timestamp
        ballTarget = nil
        handTarget = nil
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
}

private enum LevelNineteenSide {
    case left
    case right

    var opposite: LevelNineteenSide {
        self == .left ? .right : .left
    }
}

private struct LevelNineteenTarget: Identifiable {
    let id = UUID()
    let center: CGPoint
    let radius: CGFloat
    let spawnedAt: Date
    let lifetime: TimeInterval?
    let side: LevelNineteenSide

    func progress(at timestamp: Date) -> Double {
        guard let lifetime else { return 0 }
        return min(max(timestamp.timeIntervalSince(spawnedAt) / lifetime, 0), 1)
    }

    func isExpired(at timestamp: Date) -> Bool {
        progress(at: timestamp) >= 1
    }
}

private struct LevelNineteenOverlay: View {
    @ObservedObject var coordinator: LevelNineteenCoordinator

    var body: some View {
        TimelineView(.animation) { timeline in
            ZStack {
                targetView(coordinator.ballTarget, tint: .yellow, date: timeline.date, timed: false)
                targetView(coordinator.handTarget, tint: .green, date: timeline.date, timed: true)

                if let ballRect = coordinator.ballRect {
                    Ellipse()
                        .stroke(.white.opacity(0.85), lineWidth: 2)
                        .frame(width: ballRect.width, height: ballRect.height)
                        .position(x: ballRect.midX, y: ballRect.midY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func targetView(_ target: LevelNineteenTarget?, tint: Color, date: Date, timed: Bool) -> some View {
        Group {
            if let target {
                ZStack {
                    Circle()
                        .fill(.black.opacity(0.22))
                    Circle()
                        .stroke(tint.opacity(0.86), lineWidth: 8)
                        .shadow(color: tint.opacity(0.48), radius: 16)
                    Circle()
                        .stroke(.orange.opacity(tint == .green ? 0.0 : 0.92), lineWidth: 4)
                        .padding(8)
                    if timed {
                        Circle()
                            .trim(from: 0, to: max(0.02, 1 - target.progress(at: date)))
                            .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .padding(16)
                    }
                }
                .frame(width: target.radius * 2, height: target.radius * 2)
                .position(x: target.center.x, y: target.center.y)
            }
        }
    }
}

private struct LevelNineteenHudChip: View {
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

private struct LevelNineteenLoadingOverlay: View {
    var body: some View {
        ProgressView()
            .tint(.white)
            .scaleEffect(1.3)
            .frame(width: 120, height: 90)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LevelNineteenErrorOverlay: View {
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

private enum LevelNineteenSoundPlayer {
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
