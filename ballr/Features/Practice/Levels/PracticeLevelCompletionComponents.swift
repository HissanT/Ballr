import SwiftUI

struct PracticeLevelCompletionOverlay: View {
    let startedAt: Date?
    let buttonsVisible: Bool
    var title: String = "DONE"
    var primaryTitle: String = "TRY AGAIN"
    var nextLevelTitle: String = "NEXT LEVEL"
    var backButtonTitle: String = "BACK TO LEVELS"
    var showsNextLevelButton: Bool = true
    let onNextLevel: () -> Void
    let onTryAgain: () -> Void
    let onBackToLevels: () -> Void

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geometry in
                let progress = completionProgress(at: timeline.date)
                let showDone = progress >= 0.98

                ZStack {
                    PracticeLevelCompletionWaveBackground(
                        progress: progress,
                        phase: timeline.date.timeIntervalSinceReferenceDate
                    )

                    VStack(spacing: 18) {
                        Spacer()

                        Text(title)
                            .font(.ballr(size: 54, weight: .black))
                            .foregroundStyle(Color.black.opacity(0.88))
                            .opacity(showDone ? 1 : 0)
                            .scaleEffect(showDone ? 1 : 0.84)

                        if buttonsVisible {
                            HStack(spacing: 10) {
                                Button(action: onBackToLevels) {
                                    Text(backButtonTitle)
                                        .font(.ballr(size: 14, weight: .black))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 18)
                                        .frame(height: 44)
                                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                                }

                                Button(action: onTryAgain) {
                                    Text(primaryTitle)
                                        .font(.ballr(size: 14, weight: .black))
                                        .foregroundStyle(.black)
                                        .padding(.horizontal, 18)
                                        .frame(height: 44)
                                        .background(.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 12))
                                }

                                if showsNextLevelButton {
                                    Button(action: onNextLevel) {
                                        Text(nextLevelTitle)
                                            .font(.ballr(size: 14, weight: .black))
                                            .foregroundStyle(.black)
                                            .padding(.horizontal, 18)
                                            .frame(height: 44)
                                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .padding(.bottom, buttonsVisible ? 8 : 0)
                    .animation(.easeInOut(duration: 0.28), value: buttonsVisible)
                }
            }
        }
    }

    private func completionProgress(at date: Date) -> CGFloat {
        guard let startedAt else {
            return buttonsVisible ? 1 : 0
        }

        let elapsed = date.timeIntervalSince(startedAt)
        return CGFloat(min(max(elapsed / 2.05, 0), 1))
    }
}

struct PracticeLevelCompletionWaveBackground: View {
    let progress: CGFloat
    let phase: TimeInterval

    var body: some View {
        ZStack {
            PracticeLevelBottomWaveShape(
                progress: waveProgress(start: 0.00, end: 0.70),
                phase: phase,
                amplitude: 20,
                cycles: 1.35
            )
            .fill(Color(red: 1.00, green: 0.96, blue: 0.42))
            .ignoresSafeArea()

            PracticeLevelBottomWaveShape(
                progress: waveProgress(start: 0.16, end: 0.84),
                phase: phase + 0.22,
                amplitude: 26,
                cycles: 1.65
            )
            .fill(Color(red: 1.00, green: 0.82, blue: 0.10))
            .ignoresSafeArea()

            PracticeLevelBottomWaveShape(
                progress: waveProgress(start: 0.32, end: 1.00),
                phase: phase + 0.44,
                amplitude: 32,
                cycles: 1.95
            )
            .fill(Color(red: 0.95, green: 0.62, blue: 0.00))
            .ignoresSafeArea()

            PracticeLevelWaveFoamShape(
                progress: waveProgress(start: 0.10, end: 0.88),
                phase: phase + 0.08
            )
            .stroke(Color.white.opacity(0.18), lineWidth: 3)
            .ignoresSafeArea()
        }
    }

    private func waveProgress(start: CGFloat, end: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        guard end > start else {
            return clamped >= end ? 1 : 0
        }
        return min(max((clamped - start) / (end - start), 0), 1)
    }
}

struct PracticeLevelBottomWaveShape: Shape {
    let progress: CGFloat
    let phase: TimeInterval
    let amplitude: CGFloat
    let cycles: CGFloat

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let fillHeight = rect.height * (0.02 + clampedProgress * 1.12)
        let baseY = rect.maxY - fillHeight
        let resolvedAmplitude = amplitude * (1 - clampedProgress * 0.28)
        let phaseOffset = CGFloat(phase).truncatingRemainder(dividingBy: 1) * .pi * 2
        let step = max(rect.width / 48, 8)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: waveY(x: rect.minX, rect: rect, baseY: baseY, amplitude: resolvedAmplitude, phaseOffset: phaseOffset)))

        var x = rect.minX
        while x <= rect.maxX {
            path.addLine(to: CGPoint(x: x, y: waveY(x: x, rect: rect, baseY: baseY, amplitude: resolvedAmplitude, phaseOffset: phaseOffset)))
            x += step
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    private func waveY(x: CGFloat, rect: CGRect, baseY: CGFloat, amplitude: CGFloat, phaseOffset: CGFloat) -> CGFloat {
        let normalizedX = (x - rect.minX) / max(rect.width, 1)
        let primary = sin((normalizedX * cycles * .pi * 2) + phaseOffset)
        let secondary = sin((normalizedX * (cycles + 0.65) * .pi * 2) - phaseOffset * 0.72) * 0.34
        return baseY + (primary + secondary) * amplitude
    }
}

struct PracticeLevelWaveFoamShape: Shape {
    let progress: CGFloat
    let phase: TimeInterval

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let fillHeight = rect.height * (0.02 + clampedProgress * 1.04)
        let baseY = rect.maxY - fillHeight
        let amplitude = CGFloat(18 * (1 - clampedProgress * 0.25))
        let phaseOffset = CGFloat(phase).truncatingRemainder(dividingBy: 1) * .pi * 2
        let step = max(rect.width / 42, 8)

        var path = Path()
        var x = rect.minX
        path.move(to: CGPoint(x: x, y: foamY(x: x, rect: rect, baseY: baseY, amplitude: amplitude, phaseOffset: phaseOffset)))

        while x <= rect.maxX {
            path.addLine(to: CGPoint(x: x, y: foamY(x: x, rect: rect, baseY: baseY, amplitude: amplitude, phaseOffset: phaseOffset)))
            x += step
        }

        return path
    }

    private func foamY(x: CGFloat, rect: CGRect, baseY: CGFloat, amplitude: CGFloat, phaseOffset: CGFloat) -> CGFloat {
        let normalizedX = (x - rect.minX) / max(rect.width, 1)
        return baseY + sin((normalizedX * 1.55 * .pi * 2) + phaseOffset) * amplitude
    }
}

struct PracticeLevelPlaceholderView: View {
    let level: Int

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("LEVEL \(level)")
                    .font(.ballr(size: 18, weight: .black))
                    .tracking(2)
                    .foregroundStyle(Color.yellow)

                Text("Coming Soon")
                    .font(.ballr(size: 36, weight: .black))
                    .foregroundStyle(.white)

                Text("This level has not been built yet.")
                    .font(.ballr(size: 18, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
        }
        .statusBarHidden(true)
    }
}
