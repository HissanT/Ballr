import SwiftUI

enum BallrJeffCameraPresentation {
    case standing
    case countdown(startedAt: Date, scoreText: String, timeText: String?)
    case planted(scoreText: String, timeText: String?)
}

struct BallrJeffCameraOverlay: View {
    var horizontalOffset: CGFloat = -10
    var verticalOffset: CGFloat = 0
    var presentation: BallrJeffCameraPresentation = .standing

    @State private var lastPlayedWalkStepIndex: Int?

    var body: some View {
        switch presentation {
        case .standing:
            staticBody
        case .countdown(let startedAt, let scoreText, let timeText):
            TimelineView(.animation) { timeline in
                animatedBody(
                    elapsed: timeline.date.timeIntervalSince(startedAt),
                    scoreText: scoreText,
                    timeText: timeText
                )
            }
        case .planted(let scoreText, let timeText):
            animatedBody(elapsed: 3.0, scoreText: scoreText, timeText: timeText)
        }
    }

    private var staticBody: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let characterWidth = isLandscape ? geometry.size.width * 0.16 : geometry.size.width * 0.30
            let characterHeight = characterWidth * (132.0 / 135.0)

            BallrJeffCharacterShape()
                .frame(width: characterWidth, height: characterHeight)
                .padding(.leading, max(geometry.safeAreaInsets.leading + 18, 22))
                .offset(x: horizontalOffset, y: verticalOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func animatedBody(elapsed: TimeInterval, scoreText: String, timeText: String?) -> some View {
        GeometryReader { geometry in
            let progress = min(max(elapsed / 3.0, 0), 1)
            let isLandscape = geometry.size.width > geometry.size.height
            let characterWidth = isLandscape ? geometry.size.width * 0.16 : geometry.size.width * 0.30
            let characterHeight = characterWidth * (132.0 / 135.0)
            let leadingInset = max(geometry.safeAreaInsets.leading + 18, 22)
            let trailingInset = max(geometry.safeAreaInsets.trailing + 14, 18)
            let startX = horizontalOffset
            let endX = max(startX, geometry.size.width - leadingInset - trailingInset - characterWidth)
            let startHopEnd = 0.18
            let walkEnd = 0.78
            let walkCadence = 3.05
            let startHopProgress = min(max(progress / startHopEnd, 0), 1)
            let walkProgress = min(max((progress - startHopEnd) / (walkEnd - startHopEnd), 0), 1)
            let travelProgress = easeInOut(walkProgress)
            let travelX = startX + (endX - startX) * travelProgress
            let rawWalkStep = elapsed * walkCadence
            let stepIndex = Int(floor(rawWalkStep))
            let stepPhase = CGFloat(rawWalkStep.truncatingRemainder(dividingBy: 1.0))
            let stepPulse = CGFloat(pow(Double(max(sin(stepPhase * CGFloat.pi), 0)), 0.56))
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
            let jumpProgress = min(max((progress - 0.78) / 0.22, 0), 1)
            let jumpArc = sin(CGFloat(jumpProgress) * .pi) * 30.0
            let bodyLift = progress < startHopEnd
                ? startHop
                : (progress < walkEnd ? walkBounce : jumpArc)
            let faceVisibility = 1.0 - easeOut(jumpProgress)
            let metricVisibility = easeInOut((jumpProgress - 0.18) / 0.50)

            BallrJeffCharacterShape(
                walkPhase: stepPhase,
                legVisibility: 1.0 - easeOut(jumpProgress),
                faceInsetProgress: easeOut(jumpProgress),
                faceVisibility: faceVisibility,
                metricVisibility: metricVisibility,
                scoreText: jumpProgress > 0.18 ? scoreText : nil,
                timeText: timeText
            )
            .frame(width: characterWidth, height: characterHeight)
            .padding(.leading, leadingInset)
            .rotationEffect(.degrees(walkTilt), anchor: .bottom)
            .offset(x: travelX + walkShake, y: verticalOffset - bodyLift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .onChange(of: isWalking ? stepIndex : nil) { _, newStepIndex in
                playWalkStepSoundIfNeeded(newStepIndex)
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

private struct BallrJeffCharacterShape: View {
    var walkPhase: CGFloat = 0
    var legVisibility: CGFloat = 1
    var faceInsetProgress: CGFloat = 0
    var faceVisibility: CGFloat = 1
    var metricVisibility: CGFloat = 0
    var scoreText: String?
    var timeText: String?

    private let characterOrange = Color(red: 249.0 / 255.0, green: 155.0 / 255.0, blue: 5.0 / 255.0)
    private let legBlack = Color(red: 35.0 / 255.0, green: 31.0 / 255.0, blue: 32.0 / 255.0)

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
            let legSwing = sin(walkPhase * .pi * 2) * 14.0 * legVisibility
            let mouthWidth = 28.63 * scale
            let mouthHeight = 4.22 * scale
            let mouthCornerRadius = 3.0 * scale
            let mouthLeft = (70.0 - 16.8 * faceInsetProgress) * scale
            let mouthTop = roundedBodyTop + (36.78 - 7.0 * faceInsetProgress) * scale
            let lensWidth = 38.49 * scale
            let lensHeight = 21.12 * scale
            let lensTop = roundedBodyTop + (1.57 - 5.5 * faceInsetProgress) * scale
            let leftLensLeft = (27.78 + 6.8 * faceInsetProgress) * scale
            let rightLensLeft = (79.39 - 6.8 * faceInsetProgress) * scale
            let sunglassesBarWidth = 97.16 * scale
            let sunglassesBarHeight = 13.61 * scale
            let sunglassesBarLeft = 24.0 * scale
            let sunglassesBarTop = (25.0 - 5.5 * faceInsetProgress) * scale
            let sunglassesBridgeWidth = 15.02 * scale
            let sunglassesBridgeHeight = 1.41 * scale
            let sunglassesBridgeLeft = 65.31 * scale
            let sunglassesBridgeTop = roundedBodyTop + (10.96 - 5.5 * faceInsetProgress) * scale

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: legCornerRadius, style: .continuous)
                    .fill(legBlack)
                    .frame(width: legWidth, height: legHeight)
                    .rotationEffect(.degrees(97.65 + legSwing))
                    .offset(x: leftLegLeft, y: leftLegTop)
                    .opacity(legVisibility)

                RoundedRectangle(cornerRadius: legCornerRadius, style: .continuous)
                    .fill(legBlack)
                    .frame(width: legWidth, height: legHeight)
                    .rotationEffect(.degrees(76.06 - legSwing))
                    .offset(x: rightLegLeft, y: rightLegTop)
                    .opacity(legVisibility)

                Ellipse()
                    .fill(characterOrange)
                    .frame(width: bodyWidth, height: ellipseHeight)

                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(characterOrange)
                    .frame(width: bodyWidth, height: roundedBodyHeight)
                    .offset(y: roundedBodyTop)

                Rectangle()
                    .fill(characterOrange)
                    .frame(width: bodyWidth, height: glueHeight)
                    .offset(y: glueTop)

                Ellipse()
                    .fill(legBlack)
                    .frame(width: lensWidth, height: lensHeight)
                    .offset(x: leftLensLeft, y: lensTop)
                    .opacity(faceVisibility)

                Ellipse()
                    .fill(legBlack)
                    .frame(width: lensWidth, height: lensHeight)
                    .offset(x: rightLensLeft, y: lensTop)
                    .opacity(faceVisibility)

                Rectangle()
                    .fill(characterOrange)
                    .frame(width: sunglassesBarWidth, height: sunglassesBarHeight)
                    .offset(x: sunglassesBarLeft, y: sunglassesBarTop)

                Rectangle()
                    .fill(legBlack)
                    .frame(width: sunglassesBridgeWidth, height: sunglassesBridgeHeight)
                    .offset(x: sunglassesBridgeLeft, y: sunglassesBridgeTop)
                    .opacity(faceVisibility)

                RoundedRectangle(cornerRadius: mouthCornerRadius, style: .continuous)
                    .fill(legBlack)
                    .frame(width: mouthWidth, height: mouthHeight)
                    .offset(x: mouthLeft, y: mouthTop)
                    .opacity(faceVisibility)

                if let scoreText {
                    VStack(spacing: -3 * scale) {
                        Text(scoreText)
                            .font(.ballr(size: (timeText == nil ? 54 : 48) * scale, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)

                        if let timeText {
                            Text("\(timeText)s")
                                .font(.ballr(size: 24 * scale, weight: .black))
                                .lineLimit(1)
                                .minimumScaleFactor(0.48)
                        }
                    }
                    .foregroundStyle(legBlack)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(width: 114 * scale, height: 70 * scale)
                    .offset(x: 10.5 * scale, y: roundedBodyTop + 7 * scale)
                    .opacity(metricVisibility)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
        }
    }
}
