import AVFoundation
import SwiftUI

struct PracticeTrackedTargetReadinessOverlay: View {
    let lockStartedAt: Date?
    let requiredLockSeconds: TimeInterval
    let searchingTitle: String
    let lockedTitle: String
    let searchingSubtitle: String

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = readinessProgress(at: timeline.date)

            ZStack {
                Color.black.opacity(0.86)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    Text(lockStartedAt == nil ? searchingTitle : lockedTitle)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(lockStartedAt == nil ? Color.yellow : .white)

                    Text(lockStartedAt == nil ? searchingSubtitle : "Starting in \(remainingText(at: timeline.date))")
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
                    .opacity(lockStartedAt == nil ? 0 : 1)
                }
                .padding(.horizontal, 24)
            }
            .allowsHitTesting(false)
        }
    }

    private func readinessProgress(at date: Date) -> CGFloat {
        guard let lockStartedAt else {
            return 0
        }
        return CGFloat(min(max(date.timeIntervalSince(lockStartedAt) / requiredLockSeconds, 0), 1))
    }

    private func remainingText(at date: Date) -> String {
        guard let lockStartedAt else {
            return "3"
        }
        let remaining = max(ceil(requiredLockSeconds - date.timeIntervalSince(lockStartedAt)), 0)
        return "\(Int(remaining))"
    }
}

enum PracticeTargetScoreSoundPlayer {
    private static var player: AVAudioPlayer?

    static func playScore(failureContext: String) {
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
                print("\(failureContext) sound failed to load: \(error.localizedDescription)")
                return
            }
        }

        player?.stop()
        player?.currentTime = 0
        player?.play()
    }
}
