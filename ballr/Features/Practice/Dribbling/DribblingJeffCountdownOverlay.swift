import SwiftUI

enum DribblingJeffAnimationMode {
    case classic
    case mouthScore(scoreText: String)
}

struct DribblingJeffCountdownOverlay: View {
    let startedAt: Date
    var mode: DribblingJeffAnimationMode = .classic

    @State private var lastPlayedWalkStepIndex: Int?
    @State private var hasPlayedFallSound = false

    private let duration: TimeInterval = 3.75

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)

            GeometryReader { geometry in
                let progress = min(max(elapsed / duration, 0), 1)
                let isLandscape = geometry.size.width > geometry.size.height
                let characterWidth = isLandscape ? geometry.size.width * 0.16 : geometry.size.width * 0.30
                let characterHeight = characterWidth * (132.0 / 135.0)
                let leadingInset = max(geometry.safeAreaInsets.leading + 18, 22)
                let trailingInset = max(geometry.safeAreaInsets.trailing + 14, 18)
                let startX: CGFloat = -10
                let fastTouchingEndX = max(startX, geometry.size.width - leadingInset - trailingInset - characterWidth + 10)
                let launchX = startX + (fastTouchingEndX - startX) * 0.70
                let exitX = geometry.size.width - leadingInset + characterWidth * 1.10
                let walkEnd = 0.54
                let walkProgress = min(max(progress / walkEnd, 0), 1)
                let diveProgress = min(max((progress - walkEnd) / (1.0 - walkEnd), 0), 1)
                let diveT = CGFloat(diveProgress)
                let rawWalkStep = elapsed * 3.05
                let stepIndex = Int(floor(rawWalkStep))
                let stepPhase = CGFloat(rawWalkStep.truncatingRemainder(dividingBy: 1.0))
                let stepPulse = CGFloat(pow(Double(max(sin(stepPhase * .pi), 0)), 0.56))
                let stepHopHeight: CGFloat = stepIndex.isMultiple(of: 2) ? 21.0 : 11.0
                let walkBounce = stepPulse * stepHopHeight
                let isWalking = progress < walkEnd
                let walkShake = isWalking
                    ? CGFloat(sin(elapsed * 31.0) * 1.7 + sin(elapsed * 53.0) * 0.8)
                    : 0
                let walkTilt = isWalking
                    ? CGFloat(sin(stepPhase * .pi * 2.0) * 5.5 + sin(elapsed * 22.0) * 1.1)
                    : 0
                let travelX = startX + (launchX - startX) * CGFloat(walkProgress)
                let jumpHeight = geometry.size.height * 0.56
                let exitDrop = geometry.size.height * 0.32 + characterHeight
                let diveArcY = -4.0 * jumpHeight * diveT * (1.0 - diveT)
                    + exitDrop * easeIn(diveProgress)
                let diveX = launchX + (exitX - launchX) * diveT
                let diveVelocityX = exitX - launchX
                let diveVelocityY = -4.0 * jumpHeight * (1.0 - 2.0 * diveT)
                    + exitDrop * 2.0 * diveT
                let diveTilt = min(max(atan2(diveVelocityY, diveVelocityX) * 180.0 / .pi * 0.55, -26.0), 38.0)
                let mouthProgress = mode.mouthOpensScore
                    ? easeInOut((diveProgress - 0.14) / 0.52)
                    : 0
                let mouthScoreVisibility = mode.mouthOpensScore
                    ? easeInOut((diveProgress - 0.34) / 0.36)
                    : 0
                let offsetX = isWalking ? travelX + walkShake : diveX
                let offsetY = isWalking ? -walkBounce : diveArcY
                let rotation = isWalking ? walkTilt : diveTilt

                BallrOrangeJeffCharacterShape(
                    walkPhase: stepPhase,
                    mouthOpenProgress: mouthProgress,
                    mouthScoreText: mode.mouthScoreText,
                    mouthScoreVisibility: mouthScoreVisibility
                )
                    .frame(width: characterWidth, height: characterHeight)
                    .padding(.leading, leadingInset)
                    .rotationEffect(.degrees(rotation), anchor: .center)
                    .offset(x: offsetX, y: offsetY)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .opacity(elapsed < duration ? 1 : 0)
                    .onAppear {
                        BallrDrillSoundPlayer.prepareJeffCartoonFall()
                    }
                    .onChange(of: isWalking ? stepIndex : nil) { _, newStepIndex in
                        playWalkStepSoundIfNeeded(newStepIndex)
                    }
                    .onChange(of: isWalking) { _, newIsWalking in
                        playFallSoundIfNeeded(isWalking: newIsWalking, elapsed: elapsed)
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

    private func playFallSoundIfNeeded(isWalking: Bool, elapsed: TimeInterval) {
        guard !isWalking, !hasPlayedFallSound, elapsed < duration else {
            return
        }

        hasPlayedFallSound = true
        BallrDrillSoundPlayer.playJeffCartoonFall()
    }

    private func easeIn(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped)
    }

    private func easeInOut(_ value: Double) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }
}

private extension DribblingJeffAnimationMode {
    var mouthOpensScore: Bool {
        if case .mouthScore = self {
            return true
        }

        return false
    }

    var mouthScoreText: String? {
        if case .mouthScore(let scoreText) = self {
            return scoreText
        }

        return nil
    }
}

struct DribblingJeffReadinessOverlay: View {
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

struct DribblingTwoJeffCountdownOverlay: View {
    let startedAt: Date
    var scoreText: String

    @State private var lastPlayedWalkStepIndex: Int?

    private let duration: TimeInterval = 3.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)

            GeometryReader { geometry in
                let progress = min(max(elapsed / duration, 0), 1)
                let metrics = DribblingTwoJeffMotionMetrics(geometry: geometry)
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
                let mouthExpansionProgress = easeInOut((elapsed - duration - 0.10) / 0.55)
                let scoreVisibility = easeInOut((elapsed - duration - 0.34) / 0.34)

                DribblingTwoJeffScoredCharacter(
                    scoreText: scoreText,
                    scoreVisibility: scoreVisibility,
                    flipProgress: jumpProgress,
                    walkPhase: stepPhase,
                    mouthExpansionProgress: mouthExpansionProgress
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
}

struct DribblingTwoJeffHangingOverlay: View {
    var scoreText: String

    var body: some View {
        GeometryReader { geometry in
            let metrics = DribblingTwoJeffMotionMetrics(geometry: geometry)

            DribblingTwoJeffScoredCharacter(
                scoreText: scoreText,
                scoreVisibility: 1,
                flipProgress: 1,
                mouthExpansionProgress: 1
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

private struct DribblingTwoJeffScoredCharacter: View {
    var scoreText: String
    var scoreVisibility: CGFloat
    var flipProgress: Double
    var walkPhase: CGFloat = 0
    var mouthExpansionProgress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 135.0
            let expansionProgress = min(max(mouthExpansionProgress, 0), 1)
            let silhouetteScale = 0.04 + 0.96 * expansionProgress

            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    BallrOrangeJeffCharacterShape(
                        walkPhase: walkPhase,
                        legVisibility: 1,
                        faceInsetProgress: 0,
                        faceVisibility: 1,
                        metricVisibility: 0,
                        scoreText: nil,
                        timeText: nil,
                        mouthOpenProgress: 0
                    )

                    DribblingTwoJeffMouthExpansionShape(walkPhase: walkPhase)
                        .scaleEffect(x: silhouetteScale, y: silhouetteScale, anchor: UnitPoint(x: 0.63, y: 0.50))
                        .opacity(expansionProgress)
                }
                .rotationEffect(.degrees(180.0 * flipProgress), anchor: .center)

                Text(scoreText)
                    .font(.ballr(size: 86 * scale, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(Color(red: 35.0 / 255.0, green: 31.0 / 255.0, blue: 32.0 / 255.0))
                    .lineLimit(1)
                    .minimumScaleFactor(0.32)
                    .multilineTextAlignment(.center)
                    .frame(width: 122 * scale, height: 78 * scale)
                    .offset(x: 6.5 * scale, y: 34.0 * scale)
                    .opacity(scoreVisibility)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
    }
}

private struct DribblingTwoJeffMouthExpansionShape: View {
    var walkPhase: CGFloat = 0

    private let orange = Color(red: 249.0 / 255.0, green: 155.0 / 255.0, blue: 5.0 / 255.0)

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 135.0
            let bodyWidth = 135.0 * scale
            let ellipseHeight = 61.0 * scale
            let roundedBodyTop = 30.0 * scale
            let roundedBodyHeight = 71.0 * scale
            let glueTop = 32.0 * scale
            let glueHeight = 37.0 * scale
            let cornerRadius = 24.0 * scale
            let legWidth = 39.2 * scale
            let legHeight = 14.97 * scale
            let legCornerRadius = 3.0 * scale
            let leftLegLeft = 24.0 * scale
            let leftLegTop = roundedBodyTop + 73.52 * scale
            let rightLegLeft = 65.85 * scale
            let rightLegTop = roundedBodyTop + 72.53 * scale
            let legSwing = sin(walkPhase * .pi * 2) * 14.0

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: legCornerRadius, style: .continuous)
                    .fill(orange)
                    .frame(width: legWidth, height: legHeight)
                    .rotationEffect(.degrees(97.65 + legSwing))
                    .offset(x: leftLegLeft, y: leftLegTop)

                RoundedRectangle(cornerRadius: legCornerRadius, style: .continuous)
                    .fill(orange)
                    .frame(width: legWidth, height: legHeight)
                    .rotationEffect(.degrees(76.06 - legSwing))
                    .offset(x: rightLegLeft, y: rightLegTop)

                Ellipse()
                    .fill(orange)
                    .frame(width: bodyWidth, height: ellipseHeight)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(orange)
                    .frame(width: bodyWidth, height: roundedBodyHeight)
                    .offset(y: roundedBodyTop)

                Rectangle()
                    .fill(orange)
                    .frame(width: bodyWidth, height: glueHeight)
                    .offset(y: glueTop)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .clipped()
        }
    }
}

private struct DribblingTwoJeffMotionMetrics {
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
