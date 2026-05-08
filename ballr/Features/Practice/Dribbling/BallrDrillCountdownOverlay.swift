import AVFoundation
import SwiftUI

enum BallrDrillStartPhase {
    case readiness
    case countdown
    case live
}

struct BallrDrillCountdownOverlay: View {
    let startedAt: Date

    private let duration: TimeInterval = 4.0
    @State private var currentLabel = "3"

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let progress = min(max(elapsed / duration, 0), 1)
            let label = label(for: elapsed)

            ZStack {
                Color.black
                    .opacity(backgroundOpacity(progress: progress))
                    .ignoresSafeArea()

                Text(label)
                    .font(.ballr(size: labelSize(for: elapsed), weight: .black))
                    .foregroundStyle(elapsed < 3 ? Color.yellow : .white)
                    .opacity(textOpacity(for: elapsed))
                    .scaleEffect(textScale(for: elapsed))
            }
            .opacity(elapsed < duration ? 1 : 0)
            .allowsHitTesting(false)
            .onAppear {
                currentLabel = label
                if label == "START" {
                    BallrDrillSoundPlayer.playWhistle()
                }
            }
            .onChange(of: label) { _, newLabel in
                guard newLabel != currentLabel else {
                    return
                }
                currentLabel = newLabel
                if newLabel == "START" {
                    BallrDrillSoundPlayer.playWhistle()
                }
            }
        }
    }

    private func label(for elapsed: TimeInterval) -> String {
        switch elapsed {
        case ..<1:
            return "3"
        case ..<2:
            return "2"
        case ..<3:
            return "1"
        case ..<4:
            return "START"
        default:
            return ""
        }
    }

    private func labelSize(for elapsed: TimeInterval) -> CGFloat {
        elapsed < 3 ? 96 : 54
    }

    private func textOpacity(for elapsed: TimeInterval) -> Double {
        let phaseProgress = elapsed - floor(elapsed)
        return max(0.15, 1.0 - phaseProgress * 0.55)
    }

    private func textScale(for elapsed: TimeInterval) -> CGFloat {
        let phaseProgress = elapsed - floor(elapsed)
        return 1.0 + CGFloat(phaseProgress) * 0.16
    }

    private func backgroundOpacity(progress: Double) -> Double {
        progress < 0.82 ? 0.86 : max(0, 0.86 * (1.0 - (progress - 0.82) / 0.18))
    }
}

enum BallrDrillSoundPlayer {
    private static let rockDropTargetVolume: Float = 0.7
    private static let rockHitBallTargetVolume: Float = 1.0
    private static var whistlePlayer: AVAudioPlayer?
    private static var winnerPlayer: AVAudioPlayer?
    private static var comboPlayer: AVAudioPlayer?
    private static var incorrectPlayer: AVAudioPlayer?
    private static var jeffWobbleStepPlayer: AVAudioPlayer?
    private static var rockDropLoopPlayer: AVAudioPlayer?
    private static var rockHitBallPlayer: AVAudioPlayer?
    private static var rockDropLoopStopWorkItem: DispatchWorkItem?
    private static var rockHitBallFadeOutWorkItem: DispatchWorkItem?

    static func playWhistle() {
        play(resource: "Whistle", fileExtension: "mp3", player: &whistlePlayer, errorLabel: "Countdown whistle")
    }

    static func playWinner() {
        play(resource: "Winner", fileExtension: "mp3", player: &winnerPlayer, errorLabel: "Winner sound")
    }

    static func playCombo() {
        play(resource: "Combos", fileExtension: "mp3", player: &comboPlayer, errorLabel: "Combo sound")
    }

    static func playIncorrect() {
        play(
            resource: "lesiakower-error-mistake-sound-effect-incorrect-answer-437420",
            fileExtension: "mp3",
            player: &incorrectPlayer,
            errorLabel: "Incorrect sound"
        )
    }

    static func playJeffWobbleStep() {
        play(
            resource: "jeff_wobble_step",
            fileExtension: "wav",
            player: &jeffWobbleStepPlayer,
            errorLabel: "Jeff wobble step sound",
            initialVolume: 0.75
        )
    }

    static func startRockDropLoop() {
        rockDropLoopStopWorkItem?.cancel()
        rockHitBallFadeOutWorkItem?.cancel()
        play(
            resource: "rockDrop1",
            fileExtension: "mp3",
            player: &rockDropLoopPlayer,
            errorLabel: "Rock Drop loop sound",
            loops: true,
            initialVolume: 0
        )
        rockDropLoopPlayer?.setVolume(rockDropTargetVolume, fadeDuration: 3.0)
    }

    static func stopRockDropLoop(fadeOut: Bool = true) {
        rockDropLoopStopWorkItem?.cancel()

        guard let rockDropLoopPlayer else {
            return
        }

        guard fadeOut, rockDropLoopPlayer.isPlaying else {
            rockDropLoopPlayer.stop()
            rockDropLoopPlayer.currentTime = 0
            rockDropLoopPlayer.volume = rockDropTargetVolume
            return
        }

        rockDropLoopPlayer.setVolume(0, fadeDuration: 3.0)
        let stopWorkItem = DispatchWorkItem {
            rockDropLoopPlayer.stop()
            rockDropLoopPlayer.currentTime = 0
            rockDropLoopPlayer.volume = rockDropTargetVolume
        }
        rockDropLoopStopWorkItem = stopWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: stopWorkItem)
    }

    static func playRockHitBall() {
        rockHitBallFadeOutWorkItem?.cancel()
        stopRockDropLoop(fadeOut: false)
        play(
            resource: "rockHitBall",
            fileExtension: "mp3",
            player: &rockHitBallPlayer,
            errorLabel: "Rock hit ball sound",
            initialVolume: 0
        )
        guard let rockHitBallPlayer else {
            return
        }

        let fadeDuration = min(3.0, max(rockHitBallPlayer.duration * 0.5, 0.12))
        let fadeOutDelay = max(rockHitBallPlayer.duration - fadeDuration, 0)
        rockHitBallPlayer.setVolume(rockHitBallTargetVolume, fadeDuration: fadeDuration)

        let fadeOutWorkItem = DispatchWorkItem {
            rockHitBallPlayer.setVolume(0, fadeDuration: fadeDuration)
        }
        rockHitBallFadeOutWorkItem = fadeOutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutDelay, execute: fadeOutWorkItem)
    }

    static func stopRockDropSounds() {
        rockDropLoopStopWorkItem?.cancel()
        rockHitBallFadeOutWorkItem?.cancel()
        stopRockDropLoop(fadeOut: false)
        rockHitBallPlayer?.stop()
        rockHitBallPlayer?.currentTime = 0
        rockHitBallPlayer?.volume = rockHitBallTargetVolume
    }

    private static func play(
        resource: String,
        fileExtension: String,
        player: inout AVAudioPlayer?,
        errorLabel: String,
        loops: Bool = false,
        initialVolume: Float? = nil
    ) {
        if player == nil {
            guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else {
                return
            }

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)

                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.numberOfLoops = loops ? -1 : 0
                audioPlayer.prepareToPlay()
                player = audioPlayer
            } catch {
                print("\(errorLabel) failed to load: \(error.localizedDescription)")
                return
            }
        }

        player?.stop()
        player?.currentTime = 0
        if let initialVolume {
            player?.volume = initialVolume
        }
        player?.play()
    }
}

struct BallrDrillReadinessOverlay: View {
    let ballFoundStartedAt: Date?

    private let requiredLockSeconds: TimeInterval

    init(ballFoundStartedAt: Date?, requiredLockSeconds: TimeInterval = 3.0) {
        self.ballFoundStartedAt = ballFoundStartedAt
        self.requiredLockSeconds = requiredLockSeconds
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = readinessProgress(at: timeline.date)

            ZStack {
                Color.black.opacity(0.86)
                    .ignoresSafeArea()

                if ballFoundStartedAt == nil {
                    VStack(spacing: 14) {
                        Text("Find the ball")
                            .font(.ballr(size: 36, weight: .black))
                            .foregroundStyle(Color.yellow)

                        Text("Put the phone sideways and keep the ball in frame.")
                            .font(.ballr(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 18) {
                        Text("Put the phone sideways")
                            .font(.ballr(size: 28, weight: .black))
                            .foregroundStyle(.white)

                        Text("Keep the ball in frame.")
                            .font(.ballr(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.74))

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.16))

                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.yellow)
                                .frame(width: 220 * progress)
                        }
                        .frame(width: 220, height: 12)

                        Text("Hold still")
                            .font(.ballr(size: 13, weight: .black))
                            .tracking(1.6)
                            .foregroundStyle(Color.yellow)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func readinessProgress(at date: Date) -> CGFloat {
        guard let ballFoundStartedAt else {
            return 0
        }
        return CGFloat(min(max(date.timeIntervalSince(ballFoundStartedAt) / requiredLockSeconds, 0), 1))
    }
}
