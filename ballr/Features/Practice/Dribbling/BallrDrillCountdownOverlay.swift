import SwiftUI

enum BallrDrillStartPhase {
    case readiness
    case countdown
    case live
}

struct BallrDrillCountdownOverlay: View {
    let startedAt: Date

    private let duration: TimeInterval = 4.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let progress = min(max(elapsed / duration, 0), 1)

            ZStack {
                Color.black
                    .opacity(backgroundOpacity(progress: progress))
                    .ignoresSafeArea()

                Text(label(for: elapsed))
                    .font(.system(size: labelSize(for: elapsed), weight: .black, design: .rounded))
                    .foregroundStyle(elapsed < 3 ? Color.yellow : .white)
                    .opacity(textOpacity(for: elapsed))
                    .scaleEffect(textScale(for: elapsed))
            }
            .opacity(elapsed < duration ? 1 : 0)
            .allowsHitTesting(false)
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

struct BallrDrillReadinessOverlay: View {
    let ballFoundStartedAt: Date?

    private let requiredLockSeconds: TimeInterval = 3.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = readinessProgress(at: timeline.date)

            ZStack {
                Color.black.opacity(0.86)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    Text("Put the phone sideways")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Keep the ball in frame.")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.74))

                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.16))

                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.yellow)
                            .frame(width: 220 * progress)
                    }
                    .frame(width: 220, height: 12)

                    Text(ballFoundStartedAt == nil ? "Find the ball" : "Hold still")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(1.6)
                        .foregroundStyle(Color.yellow)
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
