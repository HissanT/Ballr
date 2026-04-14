import AVFoundation
import Foundation
import SwiftUI
import UIKit

struct TargetDrillCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @State private var gameState = TargetDrillGameState()
    @State private var ballFoundStartedAt: Date?
    @State private var countdownStartedAt: Date?
    @State private var startPhase: BallrDrillStartPhase = .readiness

    private let requiredBallLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                TargetDrillPlayOverlay(
                    gameState: gameState,
                    ballDisplayRect: ballDisplayRect,
                    overlayState: cameraController.overlayState
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomInstruction
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)

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

                if startPhase == .countdown, let countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                } else if startPhase == .readiness && cameraController.errorMessage == nil {
                    BallrDrillReadinessOverlay(ballFoundStartedAt: ballFoundStartedAt)
                }
            }
            .statusBarHidden(true)
            .onAppear {
                ballFoundStartedAt = nil
                countdownStartedAt = nil
                startPhase = .readiness
                BallrOrientationController.lockDribblingLandscape()
                gameState.prepare(in: geometry.size)
                cameraController.start()
            }
            .onDisappear {
                cameraController.stop()
                BallrOrientationController.restoreDefaultOrientation()
            }
            .onChange(of: geometry.size) { _, newSize in
                gameState.prepare(in: newSize, forceRespawn: true)
            }
            .onReceive(cameraController.$overlayState) { overlayState in
                let timestamp = Date()
                updateStartGate(isTracking: overlayState.isTracking, timestamp: timestamp)

                guard startPhase == .live else {
                    return
                }

                let event = gameState.step(
                    overlayState: overlayState,
                    ballDisplayRect: displayRect(for: overlayState),
                    in: geometry.size,
                    timestamp: timestamp
                )
                if event == .hit {
                    TargetDrillSoundPlayer.playScore()
                }
            }
        }
    }

    private var ballDisplayRect: CGRect? {
        displayRect(for: cameraController.overlayState)
    }

    private func displayRect(for overlayState: BallTrackerOverlayState) -> CGRect? {
        guard let normalizedRect = overlayState.normalizedRect else {
            return nil
        }
        return cameraController.displayRect(for: normalizedRect)
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

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("LEVEL 3")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(Color.yellow)
                Text("BALL BLAST")
                    .font(.system(size: 23, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 8) {
                TargetDrillHudChip(title: "SCORE", value: "\(gameState.score)", tint: .yellow)
                TargetDrillHudChip(title: "STREAK", value: "\(gameState.hitStreak)", tint: .orange)
                TargetDrillHudChip(
                    title: cameraController.overlayState.statusText.uppercased(),
                    value: cameraController.overlayState.isTracking ? "LIVE" : "SCAN",
                    tint: cameraController.overlayState.isTracking ? .green : .white
                )
            }
        }
    }

    private var bottomInstruction: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Hit the target")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Move the ball through the ring before it fades.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))
            }

            Spacer()

            Text(gameState.lastEventText)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(gameState.lastEventIsPositive ? Color.yellow : .white.opacity(0.72))
                .padding(.horizontal, 14)
                .frame(height: 38)
                .background(.black.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TargetDrillPlayOverlay: View {
    let gameState: TargetDrillGameState
    let ballDisplayRect: CGRect?
    let overlayState: BallTrackerOverlayState

    var body: some View {
        TimelineView(.animation) { timeline in
            ZStack(alignment: .topLeading) {
                if let target = gameState.target {
                    TargetRingView(
                        radius: target.radius,
                        alpha: gameState.targetAlpha(at: timeline.date),
                        ageProgress: gameState.targetAgeProgress(at: timeline.date)
                    )
                    .frame(width: target.radius * 2, height: target.radius * 2)
                    .position(target.center)
                }

                ForEach(gameState.scorePopups) { popup in
                    TargetDrillScorePopupView(popup: popup, timestamp: timeline.date)
                }

                if let ballDisplayRect {
                    Circle()
                        .stroke(Color.white, lineWidth: 2.5)
                        .frame(width: ballDisplayRect.width, height: ballDisplayRect.height)
                        .position(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
                        .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 0)

                    Circle()
                        .fill(Color.orange)
                        .frame(width: 10, height: 10)
                        .position(x: ballDisplayRect.midX, y: ballDisplayRect.midY)
                }

                if !overlayState.isTracking {
                    Text("Find the ball")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                        .position(x: 86, y: 92)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct TargetDrillScorePopupView: View {
    let popup: TargetDrillScorePopup
    let timestamp: Date

    var body: some View {
        let progress = popup.progress(at: timestamp)
        let eased = smoothStep(progress)
        let destination = popup.destination
        let x = popup.center.x + (destination.x - popup.center.x) * eased
        let y = popup.center.y + (destination.y - popup.center.y) * eased

        Text(popup.points > 0 ? "+\(popup.points)" : "\(popup.points)")
            .font(.system(size: 38, weight: .black, design: .rounded))
            .foregroundStyle(popup.points > 0 ? Color.yellow : Color.white)
            .shadow(color: .black.opacity(0.7), radius: 7, x: 0, y: 2)
            .scaleEffect(1.0 + CGFloat(1.0 - progress) * 0.18)
            .opacity(1.0 - progress)
            .position(x: x, y: y)
    }

    private func smoothStep(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }
}

private struct TargetRingView: View {
    let radius: CGFloat
    let alpha: Double
    let ageProgress: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.22 * alpha))

            Circle()
                .stroke(Color.yellow.opacity(0.45 * alpha), lineWidth: 12)

            Circle()
                .stroke(Color.orange.opacity(alpha), lineWidth: 5)
                .padding(8)

            Circle()
                .trim(from: 0, to: max(0.02, 1.0 - ageProgress))
                .stroke(
                    Color.white.opacity(alpha),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(16)

            Image(systemName: "scope")
                .font(.system(size: max(24, radius * 0.58), weight: .black))
                .foregroundStyle(Color.yellow.opacity(alpha))
        }
        .shadow(color: Color.yellow.opacity(0.35 * alpha), radius: 16, x: 0, y: 0)
    }
}

private struct TargetDrillHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 11)
        .frame(height: 46)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.86), lineWidth: 1.5)
        )
    }
}

private struct TargetDrillLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting target drill...")
                .font(.system(size: 16, weight: .black, design: .rounded))
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

private struct TargetDrillGameState {
    var target: TargetDrillTarget?
    var scorePopups: [TargetDrillScorePopup] = []
    var score = 0
    var hitStreak = 0
    var misses = 0
    var lastEventText = "READY"
    var lastEventIsPositive = true

    private let targetLifetime: TimeInterval = 4.0
    private let fullValueWindow: TimeInterval = 2.0
    private let scoreStep: TimeInterval = 0.4
    private let scoreValue = 5
    private let comboStreakStep = 10
    private let lowerYFraction: CGFloat = 0.58
    private let clearance: CGFloat = 20

    mutating func prepare(in size: CGSize, forceRespawn: Bool = false) {
        guard size.width > 0, size.height > 0 else {
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
        prepare(in: size)

        guard let currentTarget = target else {
            return nil
        }

        if targetAge(for: currentTarget, at: timestamp) >= targetLifetime {
            misses += 1
            hitStreak = 0
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

        let points = basePoints(for: currentTarget, at: timestamp) * comboMultiplier
        score += points
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
        min(max(targetAge(for: target, at: timestamp) / targetLifetime, 0), 1)
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
