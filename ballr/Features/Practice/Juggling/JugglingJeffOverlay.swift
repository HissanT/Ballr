import SwiftUI

struct JugglingJeffStandingOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let characterWidth = isLandscape ? geometry.size.width * 0.16 : geometry.size.width * 0.30
            let characterHeight = characterWidth * (132.0 / 135.0)

            BallrOrangeJeffCharacterShape()
                .frame(width: characterWidth, height: characterHeight)
                .padding(.leading, max(geometry.safeAreaInsets.leading + 18, 22))
                .offset(x: -10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct JugglingJeffHangingOverlay: View {
    var scoreText: String

    var body: some View {
        GeometryReader { geometry in
            let metrics = JugglingJeffMotionMetrics(geometry: geometry)

            JugglingJeffScoredCharacter(
                scoreText: scoreText,
                scoreVisibility: 1,
                flipProgress: 1,
                legVisibility: 1,
                faceInsetProgress: 1,
                faceVisibility: 0
            )
            .frame(width: metrics.characterWidth, height: metrics.characterHeight)
            .padding(.leading, metrics.leadingInset)
            .offset(x: metrics.hangX, y: metrics.hangY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct JugglingJeffCountdownOverlay: View {
    let startedAt: Date
    var scoreText: String

    @State private var lastPlayedWalkStepIndex: Int?

    private let duration: TimeInterval = 3.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)

            GeometryReader { geometry in
                let progress = min(max(elapsed / duration, 0), 1)
                let metrics = JugglingJeffMotionMetrics(geometry: geometry)
                let startHopEnd = 0.18
                let walkEnd = 0.78
                let startHopProgress = min(max(progress / startHopEnd, 0), 1)
                let walkProgress = min(max((progress - startHopEnd) / (walkEnd - startHopEnd), 0), 1)
                let jumpProgress = min(max((progress - walkEnd) / (1.0 - walkEnd), 0), 1)
                let travelProgress = easeInOut(walkProgress)
                let rawWalkStep = elapsed * 3.05
                let stepIndex = Int(floor(rawWalkStep))
                let stepPhase = CGFloat(rawWalkStep.truncatingRemainder(dividingBy: 1.0))
                let stepPulse = CGFloat(pow(Double(max(sin(stepPhase * .pi), 0)), 0.56))
                let stepHopHeight: CGFloat = stepIndex.isMultiple(of: 2) ? 21.0 : 11.0
                let walkBounce = stepPulse * stepHopHeight
                let isWalking = progress >= startHopEnd && progress < walkEnd
                let walkShake = isWalking
                    ? CGFloat(sin(elapsed * 31.0) * 1.7 + sin(elapsed * 53.0) * 0.8)
                    : 0
                let walkTilt = isWalking
                    ? CGFloat(sin(stepPhase * .pi * 2.0) * 5.5 + sin(elapsed * 22.0) * 1.1)
                    : 0
                let startHop = sin(CGFloat(startHopProgress) * .pi) * 20.0
                let baseWalkX = metrics.startX + (metrics.walkX - metrics.startX) * travelProgress
                let baseWalkY = progress < startHopEnd ? -startHop : -walkBounce
                let launchProgress = easeInOut(jumpProgress)
                let jumpArc = sin(CGFloat(jumpProgress) * .pi) * metrics.characterWidth * 0.42
                let finalX = baseWalkX + (metrics.hangX - baseWalkX) * launchProgress
                let finalY = baseWalkY + (metrics.hangY - baseWalkY) * launchProgress - jumpArc
                let faceVisibility = 1.0 - easeOut(jumpProgress)
                let scoreVisibility = easeInOut((jumpProgress - 0.16) / 0.58)

                JugglingJeffScoredCharacter(
                    scoreText: scoreText,
                    scoreVisibility: scoreVisibility,
                    flipProgress: jumpProgress,
                    walkPhase: stepPhase,
                    legVisibility: 1,
                    faceInsetProgress: easeOut(jumpProgress),
                    faceVisibility: faceVisibility
                )
                .frame(width: metrics.characterWidth, height: metrics.characterHeight)
                .padding(.leading, metrics.leadingInset)
                .rotationEffect(.degrees(walkTilt * (1.0 - CGFloat(jumpProgress))), anchor: .bottom)
                .offset(x: finalX + walkShake * (1.0 - CGFloat(jumpProgress)), y: finalY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .onChange(of: isWalking ? stepIndex : nil) { _, newStepIndex in
                    playWalkStepSoundIfNeeded(newStepIndex)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func playWalkStepSoundIfNeeded(_ stepIndex: Int?) {
        guard let stepIndex, stepIndex != lastPlayedWalkStepIndex else {
            return
        }

        lastPlayedWalkStepIndex = stepIndex
        BallrDrillSoundPlayer.playJeffWobbleStep()
    }

    private func easeInOut(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }

    private func easeOut(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(1 - pow(1 - clamped, 3))
    }
}

private struct JugglingJeffScoredCharacter: View {
    var scoreText: String
    var scoreVisibility: CGFloat
    var flipProgress: Double
    var walkPhase: CGFloat = 0
    var legVisibility: CGFloat = 1
    var faceInsetProgress: CGFloat = 0
    var faceVisibility: CGFloat = 1

    private let legBlack = Color(red: 35.0 / 255.0, green: 31.0 / 255.0, blue: 32.0 / 255.0)

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 135.0

            ZStack(alignment: .topLeading) {
                BallrOrangeJeffCharacterShape(
                    walkPhase: walkPhase,
                    legVisibility: legVisibility,
                    faceInsetProgress: faceInsetProgress,
                    faceVisibility: faceVisibility,
                    metricVisibility: 0,
                    scoreText: nil,
                    timeText: nil
                )
                .rotationEffect(.degrees(180.0 * flipProgress), anchor: .center)

                Text(scoreText)
                    .font(.ballr(size: 68 * scale, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(legBlack)
                    .lineLimit(1)
                    .minimumScaleFactor(0.36)
                    .multilineTextAlignment(.center)
                    .frame(width: 118 * scale, height: 72 * scale)
                    .offset(x: 8.5 * scale, y: 50.0 * scale)
                    .opacity(scoreVisibility)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
    }
}

private struct JugglingJeffMotionMetrics {
    let characterWidth: CGFloat
    let characterHeight: CGFloat
    let leadingInset: CGFloat
    let startX: CGFloat
    let walkX: CGFloat
    let hangX: CGFloat
    let hangY: CGFloat

    init(geometry: GeometryProxy) {
        let isLandscape = geometry.size.width > geometry.size.height
        characterWidth = isLandscape ? geometry.size.width * 0.16 : geometry.size.width * 0.30
        characterHeight = characterWidth * (132.0 / 135.0)
        leadingInset = max(geometry.safeAreaInsets.leading + 18, 22)

        let trailingInset = max(geometry.safeAreaInsets.trailing + 14, 18)
        startX = -10
        walkX = max(startX, geometry.size.width - leadingInset - trailingInset - characterWidth + 10)
        hangX = max(startX, geometry.size.width - leadingInset - trailingInset - characterWidth + 8)
        hangY = -(geometry.size.height - characterHeight - geometry.safeAreaInsets.top - 4)
            - characterWidth * (13.5 / 135.0)
    }
}
