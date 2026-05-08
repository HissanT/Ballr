import SwiftUI

struct PracticeLevelCompletionOverlay: View {
    let startedAt: Date?
    let buttonsVisible: Bool
    var title: String = "DONE"
    var primaryTitle: String = "TRY AGAIN"
    var nextLevelTitle: String = "NEXT LEVEL"
    var showsNextLevelButton: Bool = true
    let onNextLevel: () -> Void
    let onTryAgain: () -> Void
    let onBackToLevels: () -> Void

    var body: some View {
        TimelineView(.animation) { timeline in
            GeometryReader { geometry in
                let progress = completionProgress(at: timeline.date)
                let showDone = progress >= 0.72

                ZStack {
                    if progress >= 1 {
                        Color.yellow
                            .ignoresSafeArea()
                    }

                    PracticeLevelWaveFillShape(side: .left, progress: progress, phase: progress)
                        .fill(Color.yellow)
                        .ignoresSafeArea()

                    PracticeLevelWaveFillShape(side: .right, progress: progress, phase: progress + 0.18)
                        .fill(Color.yellow)
                        .ignoresSafeArea()

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
                                    Text("BACK TO LEVELS")
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
        if buttonsVisible {
            return 1
        }
        return CGFloat(min(max(elapsed / 1.2, 0), 1))
    }
}

struct PracticeLevelWaveFillShape: Shape {
    enum Side {
        case left
        case right
    }

    let side: Side
    let progress: CGFloat
    let phase: CGFloat

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let maxWidth = rect.width * 0.5
        let filledWidth = maxWidth * clampedProgress
        let amplitude = max(10, 28 * (1 - clampedProgress * 0.5))
        let phaseOffset = CGFloat(sin(Double(phase) * .pi * 2)) * amplitude * 0.45

        var path = Path()

        switch side {
        case .left:
            let edgeX = min(rect.midX, filledWidth)
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: edgeX, y: 0))
            path.addCurve(
                to: CGPoint(x: edgeX, y: rect.height),
                control1: CGPoint(x: edgeX - amplitude, y: rect.height * 0.28),
                control2: CGPoint(x: edgeX + amplitude + phaseOffset, y: rect.height * 0.72)
            )
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        case .right:
            let edgeX = max(rect.midX, rect.width - filledWidth)
            path.move(to: CGPoint(x: rect.width, y: 0))
            path.addLine(to: CGPoint(x: edgeX, y: 0))
            path.addCurve(
                to: CGPoint(x: edgeX, y: rect.height),
                control1: CGPoint(x: edgeX + amplitude, y: rect.height * 0.28),
                control2: CGPoint(x: edgeX - amplitude - phaseOffset, y: rect.height * 0.72)
            )
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.closeSubpath()
        }

        return path
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
