import SwiftUI

private struct BallrCompletionXPAwardEnvironmentKey: EnvironmentKey {
    static let defaultValue = 50
}

extension EnvironmentValues {
    fileprivate var ballrCompletionXPAward: Int {
        get { self[BallrCompletionXPAwardEnvironmentKey.self] }
        set { self[BallrCompletionXPAwardEnvironmentKey.self] = newValue }
    }
}

struct BallrCameraPresentationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .statusBarHidden(true)
            .navigationBarBackButtonHidden(true)
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .onAppear {
                BallrOrientationController.beginCameraPresentation()
                BallrBackgroundAudioController.shared.enterGameplayScene()
            }
            .onDisappear {
                BallrBackgroundAudioController.shared.exitGameplayScene()
                BallrOrientationController.endCameraPresentation()
            }
    }
}

private struct BallrCompletionXPAwardModifier: ViewModifier {
    @EnvironmentObject private var authSession: AuthSessionManager
    @Environment(\.ballrCompletionXPAward) private var environmentXPAward
    @State private var hasAwarded = false

    let isSuccessful: Bool
    let xpAward: Int?

    func body(content: Content) -> some View {
        ZStack {
            content

            if let levelUpEvent = authSession.levelUpEvent {
                BallrLevelUpEventOverlay(event: levelUpEvent)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    .zIndex(50)
            }
        }
        .animation(.easeInOut(duration: 0.24), value: authSession.levelUpEvent)
        .onAppear {
            awardIfNeeded()
        }
        .onChange(of: isSuccessful) { _, newValue in
            if newValue {
                awardIfNeeded()
            } else {
                hasAwarded = false
            }
        }
        .task(id: authSession.levelUpEvent?.id) {
            guard authSession.levelUpEvent != nil else { return }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            authSession.dismissLevelUpEvent()
        }
    }

    private func awardIfNeeded() {
        guard isSuccessful, !hasAwarded else {
            return
        }

        hasAwarded = true
        Task {
            await authSession.awardSuccessfulDrillCompletion(xpAward: xpAward ?? environmentXPAward)
        }
    }
}

private struct BallrLevelUpEventOverlay: View {
    let event: BallrLevelUpEvent
    @State private var showsNewLevel = false
    @State private var pulses = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.70)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.18))
                        .frame(width: 84, height: 84)
                        .scaleEffect(pulses ? 1.18 : 0.88)
                        .opacity(pulses ? 0.32 : 0.86)

                    Image(systemName: "bolt.fill")
                        .font(.ballr(size: 34, weight: .black))
                        .foregroundStyle(Color.yellow)
                }

                Text("LEVEL UP")
                    .font(.ballr(size: 18, weight: .black))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.55))

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("LEVEL")
                        .font(.ballr(size: 32, weight: .black))
                        .foregroundStyle(Color.yellow)

                    Text("\(showsNewLevel ? event.newLevel : event.previousLevel)")
                        .font(.ballr(size: 68, weight: .black))
                        .foregroundStyle(Color.yellow)
                        .contentTransition(.numericText())
                        .scaleEffect(showsNewLevel ? 1.0 : 0.82)
                }

                Text("+\(event.xpAward) XP")
                    .font(.ballr(size: 22, weight: .black))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 40)
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(26)
            .frame(maxWidth: 340)
            .background(Color.black.opacity(0.90), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.38), lineWidth: 1.5)
            }
            .padding(.horizontal, 28)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.50).repeatCount(3, autoreverses: true)) {
                pulses = true
            }

            withAnimation(.spring(response: 0.42, dampingFraction: 0.58).delay(0.42)) {
                showsNewLevel = true
            }
        }
    }
}

extension View {
    func ballrCameraPresentationChrome() -> some View {
        modifier(BallrCameraPresentationModifier())
    }

    func ballrAwardsXPOnSuccess(_ isSuccessful: Bool, xpAward: Int? = nil) -> some View {
        modifier(BallrCompletionXPAwardModifier(isSuccessful: isSuccessful, xpAward: xpAward))
    }

    func ballrCompletionXPAward(_ xpAward: Int) -> some View {
        environment(\.ballrCompletionXPAward, xpAward)
    }
}
