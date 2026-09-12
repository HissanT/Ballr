import SwiftUI

enum BallrJeffCameraPresentation {
    case standing
    case countdown(startedAt: Date, scoreText: String?, timeText: String?)
    case planted(scoreText: String?, timeText: String?)
}

struct BallrJeffCameraOverlay: View {
    var horizontalOffset: CGFloat = -10
    var verticalOffset: CGFloat = 0
    var presentation: BallrJeffCameraPresentation = .standing

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
            .onAppear {
                scheduleBounceSounds(startedAt: startedAt)
            }
            .onChange(of: startedAt) { _, newStartedAt in
                scheduleBounceSounds(startedAt: newStartedAt)
            }
            .onDisappear {
                cancelScheduledBounceSounds()
            }
        case .planted(let scoreText, let timeText):
            animatedBody(elapsed: 4.0, scoreText: scoreText, timeText: timeText)
        }
    }

    private var staticBody: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            let characterWidth = isLandscape ? geometry.size.width * 0.14 : geometry.size.width * 0.26
            let characterHeight = characterWidth

            BallrJeffCharacterShape()
                .frame(width: characterWidth, height: characterHeight)
                .padding(.leading, max(geometry.safeAreaInsets.leading + 18, 22))
                .offset(x: horizontalOffset, y: verticalOffset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func animatedBody(elapsed: TimeInterval, scoreText _: String?, timeText: String?) -> some View {
        GeometryReader { geometry in
            let clampedElapsed = min(max(elapsed, 0), 4.0)
            let isLandscape = geometry.size.width > geometry.size.height
            let characterWidth = isLandscape ? geometry.size.width * 0.14 : geometry.size.width * 0.26
            let characterHeight = characterWidth
            let leadingInset = max(geometry.safeAreaInsets.leading + 18, 22)
            let motion = bounceMotion(
                elapsed: clampedElapsed,
                canvasSize: geometry.size,
                characterWidth: characterWidth,
                leadingInset: leadingInset
            )

            BallrJeffCharacterShape(
                faceInsetProgress: 0,
                faceVisibility: 1,
                metricVisibility: 0,
                scoreText: nil,
                timeText: timeText
            )
            .frame(width: characterWidth, height: characterHeight)
            .padding(.leading, leadingInset)
            .rotationEffect(.degrees(motion.rotation), anchor: .center)
            .offset(x: motion.x, y: verticalOffset - motion.lift)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func bounceMotion(
        elapsed: TimeInterval,
        canvasSize: CGSize,
        characterWidth: CGFloat,
        leadingInset: CGFloat
    ) -> (x: CGFloat, lift: CGFloat, rotation: Double) {
        let firstBounceTime: TimeInterval = 1.05
        let secondBounceTime: TimeInterval = 2.35
        let startX = -leadingInset - characterWidth * 0.92 + horizontalOffset
        let firstBounceX = canvasSize.width * 0.18 - leadingInset
        let secondBounceX = canvasSize.width * 0.52 - leadingInset
        let exitX = canvasSize.width - leadingInset + characterWidth * 0.82
        let midScreenLift = max((canvasSize.height - characterWidth) * 0.50, characterWidth * 1.20)
        let firstBounceLift = characterWidth * 0.98
        let secondBounceLift = max(canvasSize.height * 0.33, characterWidth * 1.70)

        let x: CGFloat
        let lift: CGFloat

        if elapsed < firstBounceTime {
            let segmentProgress = CGFloat(elapsed / firstBounceTime)
            x = lerp(startX, firstBounceX, segmentProgress)
            lift = midScreenLift * (1 - segmentProgress * segmentProgress)
        } else if elapsed < secondBounceTime {
            let segmentProgress = CGFloat((elapsed - firstBounceTime) / (secondBounceTime - firstBounceTime))
            x = lerp(firstBounceX, secondBounceX, segmentProgress)
            lift = sin(segmentProgress * .pi) * firstBounceLift
        } else {
            let segmentProgress = CGFloat((elapsed - secondBounceTime) / (4.0 - secondBounceTime))
            x = lerp(secondBounceX, exitX, segmentProgress)
            lift = sin(segmentProgress * .pi * 0.72) * secondBounceLift + segmentProgress * segmentProgress * characterWidth * 0.28
        }

        let rotation = Double(lerp(-34, 420, CGFloat(elapsed / 4.0)))
        return (x, lift, rotation)
    }

    private func scheduleBounceSounds(startedAt: Date) {
        BallrDrillSoundPlayer.scheduleJeffBounceSounds(
            startedAt: startedAt,
            bounceTimes: [1.05, 2.35]
        )
    }

    private func cancelScheduledBounceSounds() {
        BallrDrillSoundPlayer.stopScheduledJeffBounceSounds()
    }

    private func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * min(max(progress, 0), 1)
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

    private let ballGreen = Color(red: 8.0 / 255.0, green: 183.0 / 255.0, blue: 117.0 / 255.0)
    private let seamGreen = Color(red: 36.0 / 255.0, green: 124.0 / 255.0, blue: 36.0 / 255.0)
    private let faceBlack = Color(red: 35.0 / 255.0, green: 31.0 / 255.0, blue: 32.0 / 255.0)
    private let eyeWhite = Color(red: 244.0 / 255.0, green: 240.0 / 255.0, blue: 240.0 / 255.0)

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 135.0
            let point: (CGFloat, CGFloat) -> CGPoint = { x, y in
                CGPoint(x: x * scale, y: y * scale)
            }
            let seamStyle = StrokeStyle(
                lineWidth: 2.35 * scale,
                lineCap: .butt,
                lineJoin: .round
            )
            let faceOffset = -5.5 * faceInsetProgress * scale

            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(ballGreen)

                Path { path in
                    path.move(to: point(42.0, 7.2))
                    path.addLine(to: point(56.7, 30.9))
                    path.addLine(to: point(78.7, 30.9))
                    path.addLine(to: point(94.0, 7.8))

                    path.move(to: point(56.7, 30.9))
                    path.addLine(to: point(45.6, 51.6))
                    path.addLine(to: point(47.1, 67.2))
                    path.addLine(to: point(45.5, 85.5))

                    path.move(to: point(78.7, 30.9))
                    path.addLine(to: point(89.5, 51.3))
                    path.addLine(to: point(86.5, 66.8))
                    path.addLine(to: point(89.0, 83.8))

                    path.move(to: point(45.5, 85.5))
                    path.addLine(to: point(56.1, 105.0))
                    path.addLine(to: point(39.0, 136.0))

                    path.move(to: point(89.0, 83.8))
                    path.addLine(to: point(78.9, 104.7))
                    path.addLine(to: point(96.0, 136.0))

                    path.move(to: point(56.1, 105.0))
                    path.addLine(to: point(78.9, 104.7))

                    path.move(to: point(47.1, 67.2))
                    path.addLine(to: point(87.0, 67.1))

                    path.move(to: point(17.1, 48.5))
                    path.addLine(to: point(45.6, 51.6))
                    path.move(to: point(17.1, 48.5))
                    path.addLine(to: point(11.0, 34.0))
                    path.move(to: point(17.1, 48.5))
                    path.addLine(to: point(1.5, 59.0))
                    path.move(to: point(19.4, 87.4))
                    path.addLine(to: point(45.5, 85.5))
                    path.move(to: point(19.4, 87.4))
                    path.addLine(to: point(1.5, 72.3))
                    path.move(to: point(19.4, 87.4))
                    path.addLine(to: point(10.6, 99.9))
                    path.move(to: point(10.6, 99.9))
                    path.addLine(to: point(39.0, 136.0))

                    path.move(to: point(123.2, 34.1))
                    path.addLine(to: point(118.5, 47.4))
                    path.move(to: point(118.5, 47.4))
                    path.addLine(to: point(132.5, 58.2))
                    path.move(to: point(89.5, 51.3))
                    path.addLine(to: point(118.5, 47.4))
                    path.move(to: point(89.0, 83.8))
                    path.addLine(to: point(114.9, 88.8))
                    path.addLine(to: point(132.0, 84.0))
                    path.move(to: point(114.9, 88.8))
                    path.addLine(to: point(121.4, 105.1))
                    path.move(to: point(121.4, 105.1))
                    path.addLine(to: point(96.0, 136.0))
                }
                .stroke(seamGreen, style: seamStyle)
                .clipShape(Circle())

                Circle()
                    .stroke(seamGreen, lineWidth: 2.8 * scale)

                Group {
                    EyeShape()
                        .fill(eyeWhite)
                        .frame(width: 45.2 * scale, height: 46.4 * scale)
                        .overlay {
                            EyeShape()
                                .stroke(faceBlack, lineWidth: 2.0 * scale)
                        }
                        .offset(x: 19.5 * scale + 3.6 * faceInsetProgress * scale, y: 34.7 * scale + faceOffset)

                    EyeShape()
                        .fill(eyeWhite)
                        .frame(width: 45.9 * scale, height: 46.4 * scale)
                        .overlay {
                            EyeShape()
                                .stroke(faceBlack, lineWidth: 2.0 * scale)
                        }
                        .offset(x: 73.6 * scale - 3.6 * faceInsetProgress * scale, y: 34.7 * scale + faceOffset)

                    Ellipse()
                        .fill(faceBlack)
                        .frame(width: 23.1 * scale, height: 23.9 * scale)
                        .offset(x: 27.4 * scale + 3.6 * faceInsetProgress * scale, y: 56.9 * scale + faceOffset)

                    Ellipse()
                        .fill(faceBlack)
                        .frame(width: 23.2 * scale, height: 23.9 * scale)
                        .offset(x: 81.8 * scale - 3.6 * faceInsetProgress * scale, y: 56.9 * scale + faceOffset)

                    RoundedRectangle(cornerRadius: 6.6 * scale, style: .continuous)
                        .fill(faceBlack)
                        .frame(width: 36.9 * scale, height: 13.4 * scale)
                        .offset(x: 49.5 * scale, y: 87.2 * scale + faceOffset)
                }
                .opacity(faceVisibility)

                if let scoreText {
                    VStack(spacing: -3 * scale) {
                        Text(scoreText)
                            .font(.ballr(size: (timeText == nil ? 58 : 49) * scale, weight: .black))
                            .lineLimit(1)
                            .minimumScaleFactor(0.42)

                        if let timeText {
                            Text("\(timeText)s")
                                .font(.ballr(size: 25 * scale, weight: .black))
                                .lineLimit(1)
                                .minimumScaleFactor(0.48)
                        }
                    }
                    .foregroundStyle(faceBlack)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .frame(width: 110 * scale, height: 78 * scale)
                    .offset(x: 12.5 * scale, y: 40 * scale)
                    .opacity(metricVisibility)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            .clipped()
        }
    }

    private struct EyeShape: Shape {
        func path(in rect: CGRect) -> Path {
            Path(ellipseIn: rect)
        }
    }
}
