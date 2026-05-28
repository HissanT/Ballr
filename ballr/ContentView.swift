import SwiftUI

struct ContentView: View {
    @State private var isShowingLaunchSplash = true

    var body: some View {
        Group {
            if isShowingLaunchSplash {
                BallrLaunchSplashView {
                    isShowingLaunchSplash = false
                }
            } else {
                MainBallrView()
            }
        }
        .font(.ballr(size: 16, weight: .regular))
        .onChange(of: isShowingLaunchSplash) { _, isShowing in
            guard !isShowing else { return }
            BallrBackgroundAudioController.shared.activateMenuMusic(
                restartTrack: true,
                fadeInFromZero: true
            )
        }
    }
}

private enum BallrTab: Hashable {
    case levels
    case practice
    case profile
}

private struct Drill: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let level: Int?
}

private struct AchievementSlot: Identifiable {
    let id = UUID()
}

private extension Color {
    static let ballrOrange = Color(red: 0.78, green: 0.27, blue: 0.07)
    static let ballrActiveOrange = Color(red: 253.0 / 255.0, green: 86.0 / 255.0, blue: 52.0 / 255.0)
    static let ballrYellow = Color(red: 0.98, green: 0.79, blue: 0.19)
    static let ballrCream = Color(red: 0.99, green: 0.97, blue: 0.91)
    static let ballrBlack = Color(red: 0.08, green: 0.08, blue: 0.08)
}

private struct MainBallrView: View {
    @State private var selectedTab: BallrTab = .practice

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .practice:
                    PracticeHomeView()
                case .levels:
                    LevelsHomeView()
                case .profile:
                    ProfileHomeView()
                }
            }
            .padding(.bottom, 5)

            BallrBottomNavBar(selectedTab: $selectedTab)
        }
    }
}

private struct BallrBottomNavBar: View {
    @Binding var selectedTab: BallrTab
    private let barHeight: CGFloat = 64

    var body: some View {
        GeometryReader { geometry in
            let bottomInset = geometry.safeAreaInsets.bottom

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Image("NavBar")
                        .resizable()
                        .frame(height: barHeight + bottomInset)

                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 5)

                        Spacer()
                    }

                    HStack(spacing: 0) {
                        BallrBottomNavButton(
                            tab: .practice,
                            selectedTab: $selectedTab
                        )

                        BallrBottomNavButton(
                            tab: .levels,
                            selectedTab: $selectedTab
                        )

                        BallrBottomNavButton(
                            tab: .profile,
                            selectedTab: $selectedTab
                        )
                    }
                    .frame(height: barHeight)
                    .padding(.bottom, bottomInset)
                }
                .frame(height: barHeight + bottomInset)
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct BallrBottomNavButton: View {
    let tab: BallrTab
    @Binding var selectedTab: BallrTab

    private var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
        Button {
            selectedTab = tab
        } label: {
            BallrBottomNavIcon(tab: tab, isSelected: isSelected)
                .frame(width: 31, height: 31)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        switch tab {
        case .practice:
            "Home"
        case .levels:
            "Levels"
        case .profile:
            "Profile"
        }
    }
}

private struct BallrBottomNavIcon: View {
    let tab: BallrTab
    let isSelected: Bool

    private var activeColor: Color {
        Color.ballrActiveOrange
    }

    private var inactiveColor: Color {
        Color(red: 0.137, green: 0.122, blue: 0.125)
    }

    private var iconColor: Color {
        isSelected ? activeColor : inactiveColor
    }

    var body: some View {
        switch tab {
        case .practice:
            BallrHomeNavIcon(color: iconColor, isSelected: isSelected)
        case .levels:
            BallrLevelsNavIcon(color: iconColor, isSelected: isSelected)
        case .profile:
            BallrProfileNavIcon(color: iconColor, isSelected: isSelected)
        }
    }
}

private struct BallrHomeNavIcon: View {
    let color: Color
    let isSelected: Bool

    var body: some View {
        Canvas { context, size in
            let iconWidth = 32.5
            let iconHeight = 31.0
            let scale = min(size.width / iconWidth, size.height / iconHeight)
            let xOffset = (size.width - iconWidth * scale) / 2
            let yOffset = (size.height - iconHeight * scale) / 2

            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: xOffset + x * scale, y: yOffset + y * scale)
            }

            if isSelected {
                var fillPath = Path()
                fillPath.addRect(CGRect(
                    x: xOffset + 4.25 * scale,
                    y: yOffset + 12.0 * scale,
                    width: 24.0 * scale,
                    height: 9.0 * scale
                ))
                fillPath.addRect(CGRect(
                    x: xOffset + 4.25 * scale,
                    y: yOffset + 21.0 * scale,
                    width: 8.0 * scale,
                    height: 10.0 * scale
                ))
                fillPath.addRect(CGRect(
                    x: xOffset + 20.25 * scale,
                    y: yOffset + 21.0 * scale,
                    width: 8.0 * scale,
                    height: 10.0 * scale
                ))
                fillPath.addRect(CGRect(
                    x: xOffset + 10.25 * scale,
                    y: yOffset + 19.0 * scale,
                    width: 3.0 * scale,
                    height: 3.0 * scale
                ))
                fillPath.addRect(CGRect(
                    x: xOffset + 19.25 * scale,
                    y: yOffset + 19.0 * scale,
                    width: 2.0 * scale,
                    height: 3.0 * scale
                ))
                fillPath.move(to: point(16.25, 0.0))
                fillPath.addLine(to: point(28.37, 12.0))
                fillPath.addLine(to: point(4.13, 12.0))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(color))
            }

            var strokePath = Path()
            strokePath.move(to: point(0.0, 16.0))
            strokePath.addLine(to: point(14.92, 1.07))
            strokePath.addQuadCurve(to: point(17.58, 1.07), control: point(16.25, 0.0))
            strokePath.addLine(to: point(32.5, 16.0))
            strokePath.move(to: point(3.75, 12.25))
            strokePath.addLine(to: point(3.75, 29.12))
            strokePath.addQuadCurve(to: point(5.62, 31.0), control: point(3.75, 30.16))
            strokePath.addLine(to: point(12.5, 31.0))
            strokePath.addLine(to: point(12.5, 22.87))
            strokePath.addQuadCurve(to: point(14.37, 21.0), control: point(12.5, 21.84))
            strokePath.addLine(to: point(18.12, 21.0))
            strokePath.addQuadCurve(to: point(20.0, 22.87), control: point(20.0, 21.84))
            strokePath.addLine(to: point(20.0, 31.0))
            strokePath.addLine(to: point(26.87, 31.0))
            strokePath.addQuadCurve(to: point(28.75, 29.12), control: point(28.75, 30.16))
            strokePath.addLine(to: point(28.75, 12.25))
            strokePath.move(to: point(10.0, 31.0))
            strokePath.addLine(to: point(23.75, 31.0))

            context.stroke(
                strokePath,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round)
            )
        }
    }
}

private struct BallrLevelsNavIcon: View {
    let color: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.18))
                    .frame(width: 30, height: 18)
                    .offset(y: 7)
            }

            Path { path in
                path.move(to: CGPoint(x: 5.0, y: 7.0))
                path.addLine(to: CGPoint(x: 5.0, y: 5.5))
                path.addQuadCurve(to: CGPoint(x: 8.8, y: 1.8), control: CGPoint(x: 5.0, y: 3.4))
                path.addLine(to: CGPoint(x: 21.2, y: 1.8))
                path.addQuadCurve(to: CGPoint(x: 25.0, y: 5.5), control: CGPoint(x: 25.0, y: 3.4))
                path.addLine(to: CGPoint(x: 25.0, y: 7.0))

                path.move(to: CGPoint(x: 5.0, y: 7.0))
                path.addQuadCurve(to: CGPoint(x: 6.2, y: 6.8), control: CGPoint(x: 5.4, y: 6.8))
                path.addLine(to: CGPoint(x: 23.8, y: 6.8))
                path.addQuadCurve(to: CGPoint(x: 25.0, y: 7.0), control: CGPoint(x: 24.6, y: 6.8))

                path.move(to: CGPoint(x: 5.0, y: 7.0))
                path.addQuadCurve(to: CGPoint(x: 2.5, y: 10.5), control: CGPoint(x: 3.5, y: 7.5))
                path.addLine(to: CGPoint(x: 2.5, y: 12.0))

                path.move(to: CGPoint(x: 25.0, y: 7.0))
                path.addQuadCurve(to: CGPoint(x: 27.5, y: 10.5), control: CGPoint(x: 26.5, y: 7.5))
                path.addLine(to: CGPoint(x: 27.5, y: 12.0))

                path.move(to: CGPoint(x: 2.5, y: 12.0))
                path.addQuadCurve(to: CGPoint(x: 3.8, y: 11.8), control: CGPoint(x: 2.9, y: 11.8))
                path.addLine(to: CGPoint(x: 26.2, y: 11.8))
                path.addQuadCurve(to: CGPoint(x: 27.5, y: 12.0), control: CGPoint(x: 27.1, y: 11.8))

                path.move(to: CGPoint(x: 2.5, y: 12.0))
                path.addQuadCurve(to: CGPoint(x: 0.0, y: 15.5), control: CGPoint(x: 1.0, y: 12.5))
                path.addLine(to: CGPoint(x: 0.0, y: 25.5))
                path.addQuadCurve(to: CGPoint(x: 3.8, y: 29.2), control: CGPoint(x: 0.0, y: 27.6))
                path.addLine(to: CGPoint(x: 26.2, y: 29.2))
                path.addQuadCurve(to: CGPoint(x: 30.0, y: 25.5), control: CGPoint(x: 30.0, y: 27.6))
                path.addLine(to: CGPoint(x: 30.0, y: 15.5))
                path.addQuadCurve(to: CGPoint(x: 27.5, y: 12.0), control: CGPoint(x: 29.0, y: 13.2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct BallrProfileNavIcon: View {
    let color: Color
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.18))
                    .frame(width: 28, height: 29)
            }

            Path { path in
                path.move(to: CGPoint(x: 0.0, y: 7.7))
                path.addLine(to: CGPoint(x: 29.2, y: 7.7))
                path.move(to: CGPoint(x: 0.0, y: 9.2))
                path.addLine(to: CGPoint(x: 29.2, y: 9.2))
                path.move(to: CGPoint(x: 4.5, y: 20.0))
                path.addLine(to: CGPoint(x: 13.5, y: 20.0))
                path.move(to: CGPoint(x: 4.5, y: 24.6))
                path.addLine(to: CGPoint(x: 9.0, y: 24.6))
                path.move(to: CGPoint(x: 3.4, y: 30.7))
                path.addLine(to: CGPoint(x: 25.9, y: 30.7))
                path.addQuadCurve(to: CGPoint(x: 29.2, y: 26.1), control: CGPoint(x: 29.2, y: 30.0))
                path.addLine(to: CGPoint(x: 29.2, y: 4.6))
                path.addQuadCurve(to: CGPoint(x: 25.9, y: 0.0), control: CGPoint(x: 29.2, y: 1.0))
                path.addLine(to: CGPoint(x: 3.4, y: 0.0))
                path.addQuadCurve(to: CGPoint(x: 0.0, y: 4.6), control: CGPoint(x: 0.0, y: 1.0))
                path.addLine(to: CGPoint(x: 0.0, y: 26.1))
                path.addQuadCurve(to: CGPoint(x: 3.4, y: 30.7), control: CGPoint(x: 0.0, y: 30.0))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.55, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct BallrLaunchSplashView: View {
    let onFinished: () -> Void
    @State private var hasJoinedLogo = false
    @State private var lensActivationProgress: CGFloat = 0
    @State private var lensGlowProgress: CGFloat = 0
    @State private var settledLogoOpacity = 0.0
    @State private var isHidingSplitLogo = false
    @State private var isDismissing = false

    var body: some View {
        GeometryReader { geometry in
            let logoHeight = min(geometry.size.width * 0.39, 168)
            let logoWidth = logoHeight * 1.43
            let pieceWidth = logoHeight * 0.80
            let logoOverlap = logoHeight * 0.17
            let travelDistance = geometry.size.width * 0.72

            ZStack {
                BallrAppBackground()

                HStack(spacing: -logoOverlap) {
                    BallrLaunchLogoPiece(assetName: "BallrLaunchLeft")
                        .frame(width: pieceWidth, height: logoHeight)
                        .offset(x: hasJoinedLogo ? 0 : -travelDistance)

                    BallrLaunchLogoPiece(assetName: "BallrLaunchRight")
                        .frame(width: pieceWidth, height: logoHeight)
                        .offset(x: hasJoinedLogo ? 0 : travelDistance)
                }
                .frame(width: logoWidth, height: logoHeight)
                .scaleEffect(hasJoinedLogo ? 1.0 : 0.92)
                .opacity(isHidingSplitLogo || isDismissing ? 0 : 1)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                BallrLaunchLogoPiece(assetName: "Image")
                    .frame(width: logoWidth, height: logoHeight)
                    .opacity(isDismissing ? 0 : settledLogoOpacity)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)

                BallrLaunchLensActivationOverlay(
                    fillProgress: lensActivationProgress,
                    glowProgress: lensGlowProgress
                )
                    .frame(width: logoWidth, height: logoHeight)
                    .opacity(isDismissing ? 0 : 1)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                .onAppear {
                    withAnimation(.spring(response: 1.05, dampingFraction: 0.78).delay(0.20)) {
                        hasJoinedLogo = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.24) {
                        withAnimation(.easeInOut(duration: 0.34)) {
                            settledLogoOpacity = 1
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.42) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            lensActivationProgress = 1
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.00) {
                        withAnimation(.easeInOut(duration: 0.42)) {
                            lensGlowProgress = 1
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.62) {
                        isHidingSplitLogo = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.65) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            isDismissing = true
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        onFinished()
                    }
                }
            }
        }
    }
}

private struct BallrLaunchLensActivationOverlay: View {
    let fillProgress: CGFloat
    let glowProgress: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let lensWidth = size.width * 0.182
            let lensHeight = size.height * 0.124
            let lensY = size.height * 0.70
            let lensPositions = [
                CGPoint(x: size.width * 0.28, y: lensY),
                CGPoint(x: size.width * 0.72, y: lensY)
            ]

            ZStack {
                ForEach(Array(lensPositions.enumerated()), id: \.offset) { _, point in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: lensWidth, height: lensHeight)
                        .opacity(fillProgress)
                        .overlay {
                            Capsule()
                                .fill(Color.white.opacity(0.34 * glowProgress))
                                .blur(radius: 6)
                                .scaleEffect(1.22 + 0.18 * glowProgress)
                        }
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.76 * glowProgress), lineWidth: 1.7)
                                .blur(radius: 0.4)
                        }
                        .shadow(color: .white.opacity(0.38 * glowProgress), radius: 10, x: 0, y: 0)
                        .shadow(color: .white.opacity(0.20 * glowProgress), radius: 18, x: 0, y: 0)
                        .position(point)
                }
            }
        }
    }
}

private struct BallrLaunchLogoPiece: View {
    let assetName: String

    var body: some View {
        Image(assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.yellow)
            .compositingGroup()
            .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 16)
    }
}

private struct LevelsHomeView: View {
    @EnvironmentObject private var authSession: AuthSessionManager
    @State private var selectedDrill: Drill?
    @State private var selectedHunterDifficulty: HunterDifficulty?
    @State private var promptedDrill: Drill?
    @State private var isShowingStreakResetMessage = false
    @AppStorage("levelsDailyStreak") private var dailyStreak = 0
    @AppStorage("levelsLastPlayedAt") private var lastPlayedAt = 0.0

    private let currentLevel = 1
    private let lockedLevels = Set<Int>()

    private let levelDrills = (1...20).map { level in
        Drill(
            title: "Level \(level)",
            subtitle: {
                switch level {
                case 1:
                    return "Ball Basics"
                case 2:
                    return "Ball Targets"
                case 3:
                    return "Ball Targets"
                case 4:
                    return "Rock Drop"
                case 5:
                    return "Timed Ball Targets"
                case 6:
                    return "Agility Challenge"
                case 7:
                    return "Ball Magician"
                case 8:
                    return "Piano Tiles Medium"
                case 9:
                    return "Timed Hand Targets"
                case 10:
                    return "Hunter Easy"
                case 11:
                    return "Rock Drop Medium"
                case 12:
                    return "Toe Touches"
                case 13:
                    return "Jumping Challenge"
                case 14:
                    return "Hunter Hard"
                case 15:
                    return "Piano Tiles Hard"
                case 16:
                    return "Rock Drop Hard"
                case 17:
                    return "Jumping + Hand Targets"
                case 18:
                    return "Toe Touches + Hand Targets"
                case 19:
                    return "Ball + Hand Targets"
                case 20:
                    return "Agility + Ball Targets"
                default:
                    return ["Juggling", "Dribbling", "First Touch"][(level - 1) % 3]
                }
            }(),
            level: level
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BallrAppBackground()

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LevelsMapView(
                            drills: levelDrills,
                            promptedDrill: promptedDrill,
                            currentLevel: currentLevel,
                            lockedLevels: lockedLevels
                        ) { drill in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                if promptedDrill?.id == drill.id {
                                    promptedDrill = nil
                                } else {
                                    promptedDrill = drill
                                }
                            }
                        } onStart: { drill in
                            updateStreakForLevelStart()
                            promptedDrill = nil
                            selectedDrill = drill
                        } onSelectEasy: { drill in
                            updateStreakForLevelStart()
                            promptedDrill = nil
                            if drill.level == 20 {
                                selectedHunterDifficulty = .easy
                            }
                        } onSelectHard: { drill in
                            updateStreakForLevelStart()
                            promptedDrill = nil
                            if drill.level == 20 {
                                selectedHunterDifficulty = .hard
                            }
                        } onCancel: {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                promptedDrill = nil
                            }
                        }
                        .frame(height: 2460)
                        .padding(.top, 78)
                        .padding(.bottom, 28)
                    }
                    .onAppear {
                        proxy.scrollTo(1, anchor: .bottom)
                    }
                }

                VStack(spacing: 0) {
                    HStack {
                        LevelsMapIcon()
                            .frame(width: 64, height: 46)

                        Spacer()
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)

                    Spacer()
                }

                if isShowingStreakResetMessage {
                    LevelsStreakLostOverlay {
                        withAnimation(.easeInOut(duration: 0.20)) {
                            isShowingStreakResetMessage = false
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(20)
                }
            }
            .navigationDestination(item: $selectedDrill) { drill in
                if drill.level == 1 {
                    LevelOneCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 2 {
                    LevelFourCameraView(nextDestination: .levelThreeBallTargets)
                        .ballrCameraPresentationChrome()
                } else if drill.level == 3 {
                    LevelFourCameraView(nextDestination: .rockDropEasy)
                        .ballrCameraPresentationChrome()
                } else if drill.level == 4 {
                    BallBlastRockDropCameraView(difficulty: .easy)
                        .ballrCameraPresentationChrome()
                } else if drill.level == 5 {
                    LevelFiveCameraView(targetPattern: .mixed)
                        .ballrCameraPresentationChrome()
                } else if drill.level == 6 {
                    AgilityChallengeCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 7 {
                    LevelSevenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 8 {
                    PianoTilesCameraView(difficulty: .medium, hudStyle: .tilesLeftOnly)
                        .ballrCameraPresentationChrome()
                } else if drill.level == 9 {
                    HandTargetCameraView(
                        nextDestination: .levelTen,
                        configuration: .levelSevenTimed,
                        showsJeffCountdown: true
                    )
                        .ballrCameraPresentationChrome()
                } else if drill.level == 10 {
                    HunterCameraView(difficulty: .easy)
                        .ballrCameraPresentationChrome()
                } else if drill.level == 11 {
                    LevelElevenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 12 {
                    LevelTwelveCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 13 {
                    LevelThirteenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 14 {
                    LevelFourteenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 15 {
                    LevelFifteenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 16 {
                    LevelSixteenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 17 {
                    LevelSeventeenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 18 {
                    LevelEighteenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 19 {
                    LevelNineteenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 20 {
                    LevelTwentyCameraView()
                        .ballrCameraPresentationChrome()
                } else {
                    DrillPlaceholderView(drill: drill)
                }
            }
            .fullScreenCover(item: $selectedHunterDifficulty) { difficulty in
                HunterCameraView(difficulty: difficulty)
                    .ballrCameraPresentationChrome()
            }
            .onAppear {
                resetMissedStreakIfNeeded()
                syncLocalStreakToSupabaseIfNeeded()
            }
            .onChange(of: authSession.isSignedIn) { _, isSignedIn in
                if isSignedIn {
                    syncLocalStreakToSupabaseIfNeeded()
                }
            }
            .onChange(of: authSession.isLoadingAccount) { _, isLoadingAccount in
                if !isLoadingAccount {
                    syncLocalStreakToSupabaseIfNeeded()
                }
            }
            .animation(.easeInOut(duration: 0.20), value: isShowingStreakResetMessage)
        }
    }

    private func updateStreakForLevelStart() {
        let now = Date()

        guard lastPlayedAt > 0 else {
            dailyStreak = 1
            lastPlayedAt = now.timeIntervalSince1970
            persistDailyStreak()
            return
        }

        let lastPlayedDate = Date(timeIntervalSince1970: lastPlayedAt)
        let calendar = Calendar.current

        if calendar.isDateInToday(lastPlayedDate) {
            return
        }

        if calendar.isDateInYesterday(lastPlayedDate) {
            dailyStreak += 1
        } else {
            dailyStreak = 1
        }

        lastPlayedAt = now.timeIntervalSince1970
        persistDailyStreak()
    }

    private func resetMissedStreakIfNeeded() {
        guard lastPlayedAt > 0, dailyStreak > 0 else {
            return
        }

        let lastPlayedDate = Date(timeIntervalSince1970: lastPlayedAt)
        let calendar = Calendar.current

        if !calendar.isDateInToday(lastPlayedDate) && !calendar.isDateInYesterday(lastPlayedDate) {
            dailyStreak = 0
            persistDailyStreak()
            withAnimation(.easeInOut(duration: 0.20)) {
                isShowingStreakResetMessage = true
            }
        }
    }

    private func persistDailyStreak() {
        let streak = dailyStreak
        Task {
            await authSession.updateDailyStreakCount(streak)
        }
    }

    private func syncLocalStreakToSupabaseIfNeeded() {
        guard dailyStreak > authSession.streakCount else {
            return
        }

        persistDailyStreak()
    }
}

private struct LevelsStreakLostOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.16))
                        .frame(width: 72, height: 72)

                    Image(systemName: "flame.fill")
                        .font(.ballr(size: 32, weight: .black))
                        .foregroundStyle(Color(red: 1.0, green: 0.32, blue: 0.18))
                }

                VStack(spacing: 8) {
                    Text("STREAK LOST")
                        .font(.ballr(size: 30, weight: .black))
                        .foregroundStyle(Color.yellow)

                    Text("You missed a day.\nPlay today to start it again.")
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Button(action: onDismiss) {
                    Text("OK")
                        .font(.ballr(size: 16, weight: .black))
                        .foregroundStyle(Color.ballrBlack)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 360)
            .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.34), lineWidth: 1.5)
            }
            .padding(.horizontal, 28)
        }
    }
}

private struct PracticeHomeView: View {
    @State private var selectedDrill: Drill?
    @State private var isShowingDribbling = false
    @State private var isShowingDribblingTwo = false
    @State private var isShowingJumpingChallenge = false
    @State private var isShowingAgilityChallenge = false
    @State private var isShowingFastTouching = false
    @State private var promptedDifficultyDrill: Drill?
    @State private var selectedRockDropDifficulty: BallBlastRockDropDifficulty?
    @State private var selectedPianoTilesDifficulty: PianoTilesDifficulty?
    @State private var selectedHunterDifficulty: HunterDifficulty?
    @State private var isShowingPrecisionTargets = false
    @State private var isShowingMultiplayerPrecisionTargets = false
    @State private var isShowingShootingZones = false
    @State private var isShowingTicTacToeShootingVS = false
    @State private var isShowingCrossbarChallenge = false
    @State private var isShowingBallMagician = false
    @State private var isShowingPassingCones = false
    @State private var selectedCarouselIndex = 0

    private let drills = [
        Drill(title: "Precision Targets", subtitle: "Hit the wall target", level: nil),
        Drill(title: "Precision VS", subtitle: "Alternate 5 shots each", level: nil),
        Drill(title: "Jumping Challenge", subtitle: "Jump over the hurdles", level: nil),
        Drill(title: "Agility Challenge", subtitle: "Cross side to side fast", level: nil),
        Drill(title: "Fast Touching", subtitle: "Count every toe touch", level: nil),
        Drill(title: "Ball Magician", subtitle: "Follow the arrows", level: nil),
        Drill(title: "Juggling", subtitle: "Keep it up, score points", level: nil),
        Drill(title: "Dribbling", subtitle: "Weave through targets", level: nil),
        Drill(title: "Dribbling 2", subtitle: "Weave with Jeff's score flip", level: nil),
        Drill(title: "Rock Drop", subtitle: "Dodge the falling rocks", level: nil),
        Drill(title: "Shooting Zones", subtitle: "Place a target box and score zones", level: nil),
        Drill(title: "Tic Tac Toe ShootingVS", subtitle: "Shoot tiles to claim Xs and Os", level: nil),
        Drill(title: "Crossbar Challenge", subtitle: "Hit the bar and posts", level: nil),
        Drill(title: "Passing Cones", subtitle: "Pass through the cones", level: nil),
        Drill(title: "Piano Tiles", subtitle: "Hit every tile", level: nil),
        Drill(title: "Hunter", subtitle: "Escape the hunter", level: nil)
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                BallrAppBackground()

                GeometryReader { geometry in
                    PracticeHomeScaffold(
                        drills: drills,
                        selectedIndex: $selectedCarouselIndex,
                        onPlay: startPracticeDrill
                    )
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    if let activePromptDrill = promptedDifficultyDrill {
                        Color.black.opacity(0.42)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                    promptedDifficultyDrill = nil
                                }
                            }

                        PracticeDifficultyPromptView(
                            drill: activePromptDrill,
                            onSelectEasy: {
                                promptedDifficultyDrill = nil
                                if activePromptDrill.title == "Rock Drop" {
                                    selectedRockDropDifficulty = .easy
                                } else if activePromptDrill.title == "Piano Tiles" {
                                    selectedPianoTilesDifficulty = .easy
                                } else if activePromptDrill.title == "Hunter" {
                                    selectedHunterDifficulty = .easy
                                }
                            },
                            onSelectHard: {
                                promptedDifficultyDrill = nil
                                if activePromptDrill.title == "Rock Drop" {
                                    selectedRockDropDifficulty = .hard
                                } else if activePromptDrill.title == "Piano Tiles" {
                                    selectedPianoTilesDifficulty = .hard
                                } else if activePromptDrill.title == "Hunter" {
                                    selectedHunterDifficulty = .hard
                                }
                            },
                            onCancel: {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                    promptedDifficultyDrill = nil
                                }
                            }
                        )
                        .frame(width: min(260, geometry.size.width - 52))
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.48)
                        .transition(.scale(scale: 0.94).combined(with: .opacity))
                        .zIndex(2)
                    }
                }
            }
            .coordinateSpace(name: "PracticeHomeView")
            .fullScreenCover(isPresented: $isShowingJumpingChallenge) {
                JumpingChallengeIntroScreen()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingAgilityChallenge) {
                AgilityChallengeCameraView()
                    .ballrCameraPresentationChrome()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingFastTouching) {
                FastTouchingIntroScreen()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingDribbling) {
                DribblingCameraView()
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(isPresented: $isShowingDribblingTwo) {
                DribblingCameraView(isDribblingTwo: true)
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(isPresented: $isShowingBallMagician) {
                LevelSevenCameraView()
                    .ballrCameraPresentationChrome()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(item: $selectedDrill) { drill in
                if drill.title == "Juggling" {
                    JugglingDrillIntroScreen()
                        .ballrCompletionXPAward(20)
                } else {
                    DrillPlaceholderView(drill: drill)
                }
            }
            .fullScreenCover(item: $selectedRockDropDifficulty) { difficulty in
                BallBlastRockDropIntroScreen(difficulty: difficulty)
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(item: $selectedPianoTilesDifficulty) { difficulty in
                PianoTilesIntroScreen(difficulty: difficulty)
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(item: $selectedHunterDifficulty) { difficulty in
                HunterCameraView(difficulty: difficulty)
                    .ballrCameraPresentationChrome()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingPrecisionTargets) {
                PrecisionTargetIntroScreen()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingMultiplayerPrecisionTargets) {
                MultiplayerPrecisionTargetCameraView()
                    .ballrCameraPresentationChrome()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingShootingZones) {
                ShootingZonesCameraView()
                    .ballrCameraPresentationChrome()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingTicTacToeShootingVS) {
                TicTacToeShootingVSCameraView()
                    .ballrCameraPresentationChrome()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingCrossbarChallenge) {
                CrossbarChallengeCameraView()
                    .ballrCameraPresentationChrome()
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingPassingCones) {
                PassingConesCameraView()
                    .ballrCameraPresentationChrome()
                    .ballrCompletionXPAward(20)
            }
        }
    }

    private func startPracticeDrill(_ drill: Drill) {
        if drill.title == "Jumping Challenge" {
            isShowingJumpingChallenge = true
        } else if drill.title == "Agility Challenge" {
            isShowingAgilityChallenge = true
        } else if drill.title == "Fast Touching" {
            isShowingFastTouching = true
        } else if drill.title == "Ball Magician" {
            isShowingBallMagician = true
        } else if drill.title == "Dribbling" {
            isShowingDribbling = true
        } else if drill.title == "Dribbling 2" {
            isShowingDribblingTwo = true
        } else if drill.title == "Rock Drop" || drill.title == "Piano Tiles" || drill.title == "Hunter" {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                promptedDifficultyDrill = drill
            }
        } else if drill.title == "Precision Targets" {
            isShowingPrecisionTargets = true
        } else if drill.title == "Precision VS" {
            isShowingMultiplayerPrecisionTargets = true
        } else if drill.title == "Shooting Zones" {
            isShowingShootingZones = true
        } else if drill.title == "Tic Tac Toe ShootingVS" {
            isShowingTicTacToeShootingVS = true
        } else if drill.title == "Crossbar Challenge" {
            isShowingCrossbarChallenge = true
        } else if drill.title == "Passing Cones" {
            isShowingPassingCones = true
        } else {
            selectedDrill = drill
        }
    }
}

private struct PracticeHomeScaffold: View {
    @AppStorage("ballrDarkModeEnabled") private var isDarkModeEnabled = true

    let drills: [Drill]
    @Binding var selectedIndex: Int
    let onPlay: (Drill) -> Void

    @State private var dragTranslation: CGFloat = 0
    @State private var isCarouselModeEnabled = true

    private let cardYellow = Color(red: 255.0 / 255.0, green: 216.0 / 255.0, blue: 0.0 / 255.0)
    private let cardSize = CGSize(width: 330, height: 440)
    private let compactCardSize = CGSize(width: 329, height: 127)
    private let cardSpacing: CGFloat = 12
    private let bottomPanelHeight: CGFloat = 102.93
    private let triangleHeight: CGFloat = 212.64
    private let compactTriangleHeight: CGFloat = 87.33

    private var panelGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: cardYellow, location: 1)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var compactDrills: [Drill] {
        let preferredOrder = [
            "Precision Targets",
            "Fast Touching",
            "Shooting Zones",
            "Rock Drop",
            "Hunter",
            "Passing Cones",
            "Piano Tiles",
            "Agility Challenge",
            "Crossbar Challenge",
            "Ball Magician",
            "Jumping Challenge",
            "Precision VS",
            "Tic Tac Toe ShootingVS"
        ]

        let orderedDrills = preferredOrder.compactMap { title in
            drills.first { $0.title == title }
        }
        let remainingDrills = drills.filter { drill in
            !preferredOrder.contains(drill.title)
        }

        return orderedDrills + remainingDrills
    }

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let headerTop = max(10.0, safeTop - 48.0)
            let switchTop = max(28.0, safeTop - 30.0)
            let pageStride = cardSize.width + cardSpacing
            let visibleIndices = drills.indices.filter { abs($0 - selectedIndex) <= 2 }
            let boundedDrag = boundedDragTranslation(dragTranslation, pageStride: pageStride)

            ZStack {
                LevelsMapIcon()
                    .frame(width: 64, height: 46)
                    .position(x: 58, y: headerTop + 27)
                    .zIndex(3)

                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                        isCarouselModeEnabled.toggle()
                        dragTranslation = 0
                    }
                } label: {
                    ZStack(alignment: isCarouselModeEnabled ? .trailing : .leading) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(cardYellow)

                        Circle()
                            .fill(Color(red: 0.137, green: 0.122, blue: 0.125))
                            .frame(width: 17, height: 17)
                            .padding(.trailing, isCarouselModeEnabled ? 5 : 0)
                            .padding(.leading, isCarouselModeEnabled ? 0 : 5)
                    }
                    .frame(width: 52, height: 28)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .position(x: geometry.size.width - 44, y: switchTop + 14)
                .zIndex(3)

                if !isDarkModeEnabled {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 393, y: 0))
                    }
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: 393, height: 1)
                    .position(
                        x: geometry.size.width / 2,
                        y: max(headerTop + 60, switchTop + 42)
                    )
                    .zIndex(2)
                }

                if isCarouselModeEnabled {
                    ZStack {
                        ForEach(visibleIndices, id: \.self) { index in
                            PracticeCarouselCardSlot(
                                drill: drills[index],
                                index: index,
                                selectedIndex: selectedIndex,
                                dragTranslation: dragTranslation,
                                boundedDrag: boundedDrag,
                                center: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2),
                                pageStride: pageStride,
                                cardSize: cardSize,
                                panelGradient: panelGradient,
                                triangleHeight: triangleHeight,
                                bottomPanelHeight: bottomPanelHeight,
                                onPlay: { onPlay(drills[index]) }
                            )
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .transition(.opacity)
                    .gesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { value in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    dragTranslation = value.translation.width
                                }
                            }
                            .onEnded { value in
                                let threshold = pageStride * 0.30
                                let endingDrag = boundedDragTranslation(value.translation.width, pageStride: pageStride)
                                let previousIndex = selectedIndex
                                let nextIndex: Int

                                if value.translation.width < -threshold {
                                    nextIndex = min(selectedIndex + 1, drills.count - 1)
                                } else if value.translation.width > threshold {
                                    nextIndex = max(selectedIndex - 1, 0)
                                } else {
                                    nextIndex = selectedIndex
                                }

                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    selectedIndex = nextIndex
                                    dragTranslation = endingDrag + CGFloat(nextIndex - previousIndex) * pageStride
                                }

                                withAnimation(.interactiveSpring(response: 0.48, dampingFraction: 0.90, blendDuration: 0.12)) {
                                    dragTranslation = 0
                                }
                            }
                    )
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 20) {
                            ForEach(compactDrills) { drill in
                                Button {
                                    onPlay(drill)
                                } label: {
                                    PracticeHomeCompactDrillCard(
                                        drill: drill,
                                        cardSize: compactCardSize,
                                        panelGradient: panelGradient,
                                        triangleHeight: compactTriangleHeight
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, max(headerTop + 100, switchTop + 82))
                        .padding(.bottom, 104)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .accessibilityElement(children: .contain)
        }
    }

    private func boundedDragTranslation(_ translation: CGFloat, pageStride: CGFloat) -> CGFloat {
        if selectedIndex == 0 && translation > 0 {
            return min(translation * 0.28, pageStride * 0.22)
        }

        if selectedIndex == drills.count - 1 && translation < 0 {
            return max(translation * 0.28, -pageStride * 0.22)
        }

        return translation
    }
}

private struct PracticeCarouselCardSlot: View {
    let drill: Drill
    let index: Int
    let selectedIndex: Int
    let dragTranslation: CGFloat
    let boundedDrag: CGFloat
    let center: CGPoint
    let pageStride: CGFloat
    let cardSize: CGSize
    let panelGradient: LinearGradient
    let triangleHeight: CGFloat
    let bottomPanelHeight: CGFloat
    let onPlay: () -> Void

    private var xPosition: CGFloat {
        let distance = CGFloat(index - selectedIndex)
        return center.x + distance * pageStride + boundedDrag
    }

    private var visualDistance: CGFloat {
        abs((xPosition - center.x) / pageStride)
    }

    var body: some View {
        PracticeHomeDrillCard(
            drill: drill,
            cardSize: cardSize,
            panelGradient: panelGradient,
            triangleHeight: triangleHeight,
            bottomPanelHeight: bottomPanelHeight,
            isSelected: index == selectedIndex && abs(dragTranslation) < 8,
            onPlay: onPlay
        )
        .frame(width: cardSize.width, height: cardSize.height)
        .scaleEffect(max(0.955, 1 - visualDistance * 0.035))
        .opacity(max(0.72, 1 - visualDistance * 0.18))
        .position(x: xPosition, y: center.y)
        .zIndex(10 - Double(visualDistance))
    }
}

private struct PracticeHomeCompactDrillCard: View {
    let drill: Drill
    let cardSize: CGSize
    let panelGradient: LinearGradient
    let triangleHeight: CGFloat

    private let cardYellow = Color(red: 255.0 / 255.0, green: 216.0 / 255.0, blue: 0.0 / 255.0)
    private let playCircle = Color(red: 0.244, green: 0.244, blue: 0.244)

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(cardYellow)

            if drill.title == "Precision Targets" {
                Image("green1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 97.48, height: 111)
                    .position(x: 101, y: 55.5)
            } else if drill.title == "Precision VS" {
                Image("green1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 93, height: 110)
                    .position(x: 101, y: 60)
            } else if drill.title == "Fast Touching" {
                Image("orange1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 91.09, height: 109.48)
                    .position(x: 101, y: 58)
            } else if drill.title == "Agility Challenge" {
                Image("purple1")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 108)
                    .position(x: 101, y: 58)
            } else if ["Hunter", "Ball Magician"].contains(drill.title) {
                Image("blue")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 97.48, height: 111)
                    .position(x: 101, y: 58)
            } else if drill.title == "Jumping Challenge" {
                Image("purple")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 108)
                    .position(x: 101, y: 58)
            } else if ["Shooting Zones", "Crossbar Challenge", "Tic Tac Toe ShootingVS", "Passing Cones"].contains(drill.title) {
                Image("yellow")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 104, height: 111)
                    .position(x: 101, y: 58)
            } else if ["Rock Drop", "Piano Tiles"].contains(drill.title) {
                Image("pink")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 106, height: 111)
                    .position(x: 101, y: 58)
            }

            panelGradient
                .frame(width: cardSize.width, height: triangleHeight)
                .mask {
                    PracticeCompactCardTriangleShape()
                }

            Text(drill.title)
                .font(.ballr(size: 20, weight: .black))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .foregroundStyle(Color.black)
                .frame(width: 190, alignment: .leading)
                .position(x: 145, y: 101)

            ZStack {
                Circle()
                    .fill(playCircle)

                Image(systemName: "play.fill")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(cardYellow)
            }
            .frame(width: 72, height: 72)
            .position(x: 261, y: 64)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

private struct PracticeCompactCardTriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.47))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PracticeHomeDrillCard: View {
    @AppStorage("ballrDarkModeEnabled") private var isDarkModeEnabled = true

    let drill: Drill
    let cardSize: CGSize
    let panelGradient: LinearGradient
    let triangleHeight: CGFloat
    let bottomPanelHeight: CGFloat
    let isSelected: Bool
    let onPlay: () -> Void

    private var titleText: String {
        switch drill.title {
        case "Precision Targets":
            "Precision\ntargets"
        case "Precision VS":
            "Precision\nVS"
        case "Tic Tac Toe ShootingVS":
            "Tic Tac Toe\nShootingVS"
        default:
            drill.title
        }
    }

    var body: some View {
        let panelHeight = triangleHeight + bottomPanelHeight

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(red: 1.0, green: 0.847, blue: 0.0))
                .opacity(isDarkModeEnabled ? 0.40 : 1.0)

            Image("cardTile")
                .resizable()
                .frame(width: 268, height: 314)
                .position(x: cardSize.width / 2, y: 199)

            PracticeCharacterView()
                .frame(width: 171, height: 179)
                .position(x: cardSize.width / 2, y: 195)

            panelGradient
                .frame(width: cardSize.width, height: panelHeight)
                .mask {
                    PracticeCardBottomPanelShape(
                        triangleHeight: triangleHeight,
                        rectangleHeight: bottomPanelHeight,
                        cornerRadius: 31
                    )
                }

            PracticeCharacterView()
                .frame(width: 171, height: 179)
                .position(x: cardSize.width / 2, y: 195)
                .mask {
                    PracticeCharacterVisibleMask()
                }

            panelGradient
                .frame(width: cardSize.width, height: cardSize.height)
                .mask {
                    Rectangle()
                        .frame(width: 80.51, height: 25.11)
                        .rotationEffect(.degrees(-32.85))
                        .position(x: 101, y: 287)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(titleText)
                    .font(.ballr(size: 36, weight: .black))
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: 190, alignment: .leading)

                Text(drill.subtitle)
                    .font(.ballr(size: 14, weight: .black))
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: 205, alignment: .leading)
            }
            .position(x: 146, y: 365)

            Button(action: onPlay) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.244, green: 0.244, blue: 0.244))

                    Image(systemName: "play.fill")
                        .font(.system(size: 38, weight: .black))
                        .foregroundStyle(Color(red: 1.0, green: 0.847, blue: 0.0))
                }
                .frame(width: 73, height: 73)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .position(x: 260, y: 344)
            .disabled(!isSelected)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
}

private struct PracticeCardBottomPanelShape: Shape {
    let triangleHeight: CGFloat
    let rectangleHeight: CGFloat
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let panelTopY = rect.minY + triangleHeight
        let radius = min(cornerRadius, rectangleHeight / 2, rect.width / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: panelTopY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: panelTopY))
        path.closeSubpath()
        return path
    }
}

private struct PracticeCharacterView: View {
    private let bodyFill = Color(red: 0.878, green: 0.239, blue: 0.6)
    private let outline = Color(red: 0.580, green: 0.082, blue: 0.365)
    private let eyeWhite = Color(red: 0.929, green: 0.910, blue: 0.910)
    private let faceBlack = Color(red: 0.137, green: 0.122, blue: 0.125)

    var body: some View {
        ZStack {
            PracticeCharacterBodyShape()
                .fill(bodyFill)

            PracticeCharacterBodyShape()
                .strokeBorder(outline, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

            Circle()
                .fill(eyeWhite)
                .frame(width: 41.443, height: 41.443)
                .position(x: 53.396, y: 59.079)

            Circle()
                .fill(eyeWhite)
                .frame(width: 41.443, height: 41.443)
                .position(x: 116.884, y: 59.079)

            Circle()
                .fill(faceBlack)
                .frame(width: 20.281, height: 20.281)
                .position(x: 47.781, y: 66.705)

            Ellipse()
                .fill(faceBlack)
                .frame(width: 21.162, height: 20.281)
                .position(x: 122.71, y: 53.463)

            RoundedRectangle(cornerRadius: 7.495, style: .continuous)
                .fill(faceBlack)
                .frame(width: 42.325, height: 14.99)
                .position(x: 85.237, y: 100.474)
        }
        .frame(width: 171, height: 179)
    }
}

private struct PracticeCharacterBodyShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let drawingRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let scaleX = drawingRect.width / 171.0
        let scaleY = drawingRect.height / 179.0
        let topRadius: CGFloat = 30.0

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: drawingRect.minX + x * scaleX, y: drawingRect.minY + y * scaleY)
        }

        var path = Path()
        path.move(to: point(topRadius, 0))
        path.addLine(to: point(170.477 - topRadius, 0))
        path.addArc(
            center: point(170.477 - topRadius, topRadius),
            radius: topRadius * min(scaleX, scaleY),
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: point(170.477, 179))
        path.addLine(to: point(126.437, 179))
        path.addLine(to: point(126.437, 141.96))
        path.addCurve(
            to: point(119.437, 134.96),
            control1: point(126.436, 138.094),
            control2: point(123.302, 134.96)
        )
        path.addLine(to: point(114.968, 134.96))
        path.addCurve(
            to: point(107.968, 141.96),
            control1: point(111.102, 134.96),
            control2: point(107.968, 138.094)
        )
        path.addLine(to: point(107.968, 179))
        path.addLine(to: point(63.929, 179))
        path.addLine(to: point(63.929, 141.96))
        path.addCurve(
            to: point(56.929, 134.96),
            control1: point(63.929, 138.094),
            control2: point(60.795, 134.96)
        )
        path.addLine(to: point(51.04, 134.96))
        path.addCurve(
            to: point(44.04, 141.96),
            control1: point(47.174, 134.96),
            control2: point(44.04, 138.094)
        )
        path.addLine(to: point(44.04, 179))
        path.addLine(to: point(0, 179))
        path.addLine(to: point(0, 30))
        path.addArc(
            center: point(topRadius, topRadius),
            radius: topRadius * min(scaleX, scaleY),
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct PracticeCharacterVisibleMask: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 171.0
        let scaleY = rect.height / 179.0
        let cutRightX = 44.04

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scaleX, y: rect.minY + y * scaleY)
        }

        var path = Path()

        path.addRect(CGRect(
            x: point(cutRightX, 0).x,
            y: rect.minY,
            width: rect.maxX - point(cutRightX, 0).x,
            height: rect.height
        ))

        path.move(to: point(0, 0))
        path.addLine(to: point(cutRightX, 0))
        path.addLine(to: point(cutRightX, 145.0))
        path.addLine(to: point(0, 173.34))
        path.closeSubpath()

        return path
    }
}

private struct PracticeSwipeDrillCard: View {
    let drill: Drill
    let index: Int
    let onPlay: () -> Void

    private var titleText: String {
        switch drill.title {
        case "Precision VS":
            return "Precision\nTarget VS"
        case "Tic Tac Toe ShootingVS":
            return "Tic Tac Toe\nShooting VS"
        default:
            return drill.title
        }
    }

    private var accentColor: Color {
        let colors: [Color] = [
            Color(red: 0.88, green: 0.24, blue: 0.60),
            Color(red: 0.18, green: 0.48, blue: 0.95),
            Color(red: 0.96, green: 0.32, blue: 0.20),
            Color(red: 0.10, green: 0.64, blue: 0.44),
            Color(red: 0.50, green: 0.30, blue: 0.95)
        ]

        return colors[index % colors.count]
    }

    var body: some View {
        GeometryReader { geometry in
            let cardWidth = geometry.size.width
            let cardHeight = geometry.size.height
            let artHeight = cardHeight * 0.64

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 30)
                    .fill(Color(red: 1.0, green: 0.847, blue: 0.0))

                PracticeSwipeCardArt(accentColor: accentColor)
                    .frame(width: cardWidth * 0.82, height: artHeight)
                    .position(x: cardWidth * 0.5, y: cardHeight * 0.34)

                PracticeSwipeCardBottomPanel(
                    title: titleText,
                    subtitle: drill.subtitle,
                    onPlay: onPlay
                )
                .frame(height: cardHeight * 0.43)
            }
            .contentShape(RoundedRectangle(cornerRadius: 30))
        }
        .aspectRatio(0.75, contentMode: .fit)
    }
}

private struct PracticeSwipeCardArt: View {
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                PracticePaperShape()
                    .fill(Color.black)
                    .frame(width: width * 0.84, height: height * 0.76)
                    .offset(x: width * 0.04, y: height * 0.08)

                PracticePaperShape()
                    .fill(Color(red: 1.0, green: 0.973, blue: 0.890))
                    .frame(width: width * 0.84, height: height * 0.76)
                    .offset(x: width * 0.02, y: height * 0.05)

                Ellipse()
                    .fill(Color(red: 1.0, green: 0.451, blue: 0.0))
                    .frame(width: width * 0.58, height: height * 0.12)
                    .offset(y: -height * 0.28)

                PracticePrecisionCharacter(accentColor: accentColor)
                    .frame(width: width * 0.60, height: height * 0.55)
                    .offset(y: height * 0.06)
            }
        }
    }
}

private struct PracticePrecisionCharacter: View {
    let accentColor: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                RoundedRectangle(cornerRadius: width * 0.18)
                    .fill(accentColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: width * 0.18)
                            .stroke(Color(red: 0.58, green: 0.08, blue: 0.36), lineWidth: max(3, width * 0.025))
                    }

                HStack(spacing: width * 0.12) {
                    PracticeEye(pupilOffset: CGSize(width: -width * 0.018, height: height * 0.028))
                    PracticeEye(pupilOffset: CGSize(width: width * 0.03, height: -height * 0.026))
                }
                .frame(height: height * 0.24)
                .offset(y: -height * 0.16)

                RoundedRectangle(cornerRadius: height * 0.04)
                    .fill(Color(red: 0.137, green: 0.122, blue: 0.125))
                    .frame(width: width * 0.34, height: height * 0.075)
                    .offset(y: height * 0.08)

                HStack(spacing: width * 0.16) {
                    RoundedRectangle(cornerRadius: width * 0.04)
                        .fill(accentColor)
                        .frame(width: width * 0.24, height: height * 0.31)
                    RoundedRectangle(cornerRadius: width * 0.04)
                        .fill(accentColor)
                        .frame(width: width * 0.24, height: height * 0.31)
                }
                .offset(y: height * 0.36)
            }
        }
    }
}

private struct PracticeEye: View {
    let pupilOffset: CGSize

    var body: some View {
        Circle()
            .fill(Color(red: 0.93, green: 0.91, blue: 0.91))
            .overlay {
                Circle()
                    .fill(Color(red: 0.137, green: 0.122, blue: 0.125))
                    .frame(width: 19, height: 19)
                    .offset(pupilOffset)
            }
            .aspectRatio(1, contentMode: .fit)
    }
}

private struct PracticePaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cutSize = min(rect.width, rect.height) * 0.18
        let radius = min(rect.width, rect.height) * 0.10

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cutSize))
        path.addLine(to: CGPoint(x: rect.maxX - cutSize, y: rect.maxY - cutSize))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - cutSize * 1.55, y: rect.maxY), control: CGPoint(x: rect.maxX - cutSize * 1.55, y: rect.maxY - cutSize))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()

        return path
    }
}

private struct PracticeSwipeCardBottomPanel: View {
    let title: String
    let subtitle: String
    let onPlay: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                PracticeCardDiagonalPanel()
                    .fill(
                        LinearGradient(
                            colors: [.white, Color(red: 1.0, green: 0.847, blue: 0.0)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 7) {
                    Text(title)
                        .font(.ballr(size: 33, weight: .black))
                        .lineLimit(2)
                        .minimumScaleFactor(0.64)
                        .foregroundStyle(Color.black)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.ballr(size: 13, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.66))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: geometry.size.width * 0.66, alignment: .leading)
                .position(x: geometry.size.width * 0.27, y: geometry.size.height * 0.58)

                Button(action: onPlay) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.244, green: 0.244, blue: 0.244))

                        Image(systemName: "play.fill")
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(Color(red: 1.0, green: 0.847, blue: 0.0))
                            .offset(x: 2)
                    }
                    .frame(width: 73, height: 73)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, geometry.size.height * 0.24)
                .padding(.trailing, geometry.size.width * 0.10)
            }
        }
    }
}

private struct PracticeCardDiagonalPanel: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.height * 0.30))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct PracticeCarouselPageDots: View {
    let count: Int
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? Color(red: 1.0, green: 0.847, blue: 0.0) : Color.white.opacity(0.30))
                    .frame(width: index == selectedIndex ? 20 : 7, height: 7)
                    .animation(.easeInOut(duration: 0.18), value: selectedIndex)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ProfileHomeView: View {
    @EnvironmentObject private var authSession: AuthSessionManager
    private let slots = (0..<5).map { _ in AchievementSlot() }

    var body: some View {
        NavigationStack {
            ZStack {
                BallrAppBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            LevelsMapIcon()
                                .frame(width: 64, height: 46)

                            Spacer()

                            NavigationLink {
                                BallrSettingsView()
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.ballr(size: 22, weight: .black))
                                    .foregroundStyle(Color.yellow)
                                    .frame(width: 48, height: 48)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                    .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.yellow.opacity(0.24), lineWidth: 1)
                                    }
                            }
                        }
                        .padding(.bottom, 28)

                        ProfilePlayerCard(
                            name: authSession.profileName,
                            accountLabel: authSession.accountLabel,
                            xp: authSession.xp
                        )

                        HStack(spacing: 12) {
                            ProfileStatCard(value: "0", label: "BEST\nJUGGLES", valueColor: Color.yellow)
                            ProfileStatCard(value: "0", label: "DRILLS DONE", valueColor: Color.orange)
                            ProfileStatCard(value: "\(authSession.streakCount)", label: "DAY STREAK", valueColor: .white)
                        }

                        Text("ACHIEVEMENTS")
                            .font(.ballr(size: 16, weight: .black))
                            .tracking(2)
                            .foregroundStyle(Color.yellow.opacity(0.58))
                            .padding(.top, 2)

                        ProfileAchievementRow(slots: slots)

                        NavigationLink {
                            BallrCardDetailView()
                        } label: {
                            HStack {
                                Text("VIEW BALLR CARD")
                                    .font(.ballr(size: 20, weight: .black))
                                    .foregroundStyle(Color.yellow)

                                Spacer()

                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        Image(systemName: "chevron.right")
                                            .font(.ballr(size: 16, weight: .black))
                                            .foregroundStyle(Color.ballrBlack)
                                    }
                            }
                            .padding(.horizontal, 24)
                            .frame(height: 74)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.yellow.opacity(0.32), lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 22)
                    .padding(.bottom, 34)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct JugglingDrillIntroScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isCardPressed = false
    @State private var showsInProgressScreen = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0

    private let characterPurple = Color(red: 0.631, green: 0.427, blue: 0.757)
    private let characterStrokePurple = Color(red: 0.463, green: 0.306, blue: 0.561)
    private let cardPurple = Color(red: 0.463, green: 0.306, blue: 0.561)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let base = min(width, height)
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let bodyWidth = isLandscape ? width * 0.82 : width * 1.05
            let bodyHeight = isLandscape ? height * 2.04 : height * 1.36
            let bodyCenterY = isLandscape ? height * 1.03 : height * 0.74
            let characterStrokeWidth = isLandscape ? 12.0 : 16.0
            let cardWidth = isLandscape ? min(width * 0.30, 270) : width * 0.68
            let cardHeight = isLandscape ? min(height * 0.54, 210) : min(height * 0.34, width * 0.80)
            let characterEntryOffset = hasAnimatedCharacter ? 0 : height * (isLandscape ? 0.78 : 0.62)
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let shapeOffset = characterEntryOffset + (isLaunchingDrill ? -height * (isLandscape ? 0.16 : 0.23) : 0)
            let shapeScaleX = entryScale * (isLaunchingDrill ? 1.20 : 1.0)
            let shapeScaleY = entryScale * (isLaunchingDrill ? 1.46 : 1.0)
            let contentOffset = characterEntryOffset
            let contentOpacity = 1.0
            let faceOpacity = isLaunchingDrill ? 0.0 : 1.0
            let faceScale = isLaunchingDrill ? 0.90 : 1.0
            let faceLift = isLaunchingDrill ? -height * 0.035 : 0.0
            let topContentSpacer = isLandscape ? height * 0.105 : height * 0.285
            let eyeSpacing = isLandscape ? base * 0.16 : width * 0.09
            let mouthTopPadding = isLandscape ? 14.0 : 20.0
            let cardTopPadding = isLandscape ? 22.0 : 30.0
            let faceScaleFactor = isLandscape ? 0.84 : 1.0

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                Group {
                    Capsule()
                        .fill(characterPurple)
                        .frame(width: bodyWidth, height: bodyHeight)
                        .position(x: width * 0.5, y: bodyCenterY)
                        .offset(y: introBounceOffset)

                    Capsule()
                        .stroke(characterStrokePurple, lineWidth: characterStrokeWidth)
                        .frame(width: bodyWidth, height: bodyHeight)
                        .position(x: width * 0.5, y: bodyCenterY)
                        .offset(y: introBounceOffset)

                    VStack(spacing: 0) {
                        Spacer(minLength: height * 0.54)
                        Rectangle()
                            .fill(characterPurple)
                            .frame(maxWidth: .infinity)
                    }
                    .ignoresSafeArea()
                }
                .offset(y: shapeOffset)
                .scaleEffect(x: shapeScaleX, y: shapeScaleY, anchor: .center)
                .animation(.spring(response: 0.72, dampingFraction: 1.00), value: hasAnimatedCharacter)
                .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                .animation(launchAnimation, value: isLaunchingDrill)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, safeTop + 72)
                .padding(.leading, 18)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: topContentSpacer)

                    VStack(spacing: 0) {
                        HStack(spacing: eyeSpacing) {
                            JugglingFaceEyeView()
                            JugglingFaceEyeView()
                        }
                        .padding(.leading, isLandscape ? 0 : width * 0.02)
                        .scaleEffect(faceScaleFactor)

                        Circle()
                            .fill(logoBlack)
                            .frame(width: isLandscape ? base * 0.075 : width * 0.085, height: isLandscape ? base * 0.075 : width * 0.085)
                            .padding(.top, mouthTopPadding)
                    }
                    .opacity(faceOpacity)
                    .scaleEffect(faceScale)
                    .offset(y: faceLift)
                    .animation(.easeOut(duration: 0.42), value: isLaunchingDrill)

                    Button {
                        guard !isLaunchingDrill else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCardPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isCardPressed = false
                            }
                            withAnimation(launchAnimation) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                                showsInProgressScreen = true
                            }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(cardPurple)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay {
                                VStack(spacing: 16) {
                                    Text("JUGGLING")
                                        .font(.ballr(size: min(width * 0.098, 42), weight: .black))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)

                                    Text("KEEP IT UP, JUGGLE THE BALL")
                                        .font(.ballr(size: min(width * 0.040, 18), weight: .semibold))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.white.opacity(0.86))
                                }
                                .tracking(0.8)
                                .padding(.horizontal, 20)
                            }
                            .scaleEffect(isCardPressed ? 0.96 : 1.0)
                            .shadow(color: Color.white.opacity(isCardPressed ? 0.0 : 0.22), radius: isCardPressed ? 0 : 16, x: 0, y: 0)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(isCardPressed ? 0.26 : 0.0), lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, cardTopPadding)
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)

                    Spacer(minLength: safeBottom + 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: contentOffset)
                .opacity(contentOpacity)
                .animation(.spring(response: 0.72, dampingFraction: 0.80), value: hasAnimatedCharacter)
                .animation(.easeOut(duration: 0.18), value: isLaunchingDrill)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsInProgressScreen, onDismiss: {
            resetLaunchState()
        }) {
            JugglingDrillInProgressScreen()
        }
        .onAppear {
            resetLaunchState()
            introBounceOffset = 0
            hasAnimatedCharacter = false
            DispatchQueue.main.async {
                hasAnimatedCharacter = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                withAnimation(.easeOut(duration: 0.24)) {
                    introBounceOffset = 24
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    withAnimation(.spring(response: 0.54, dampingFraction: 0.68)) {
                        introBounceOffset = 0
                    }
                }
            }
        }
    }
}

private struct JugglingDrillInProgressScreen: View {
    var body: some View {
        JugglingCameraView()
    }
}

private struct JumpingChallengeIntroScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0

    private let characterCyan = Color(red: 0.10, green: 0.70, blue: 0.84)
    private let cardTeal = Color(red: 0.13, green: 0.52, blue: 0.60)
    private let faceWhite = Color(red: 0.96, green: 0.95, blue: 0.95)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let base = min(width, height)
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let characterEntryOffset = hasAnimatedCharacter ? 0 : height * (isLandscape ? 0.78 : 0.62)
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let shapeOffset = characterEntryOffset
            let shapeScaleX = entryScale * (isLaunchingDrill ? 1.20 : 1.0)
            let shapeScaleY = entryScale * (isLaunchingDrill ? 1.46 : 1.0)
            let contentOffset = characterEntryOffset
            let faceOpacity = isLaunchingDrill ? 0.0 : 1.0
            let faceScale = isLaunchingDrill ? 0.90 : 1.0
            let faceLift = isLaunchingDrill ? -height * 0.035 : 0.0
            let topContentSpacer = isLandscape ? height * 0.235 : height * 0.292
            let eyeSize = isLandscape ? base * 0.118 : width * 0.205
            let eyeSpacing = isLandscape ? base * 0.098 : width * 0.155
            let eyebrowWidth = eyeSize * 0.72
            let eyebrowHeight = max(7.0, eyeSize * 0.095)
            let mouthWidth = isLandscape ? base * 0.155 : width * 0.305
            let mouthHeight = isLandscape ? base * 0.070 : width * 0.130
            let cardWidth = isLandscape ? min(width * 0.36, 340) : width * 0.72
            let cardHeight = isLandscape ? min(height * 0.44, 230) : min(height * 0.34, width * 0.88)
            let cardTopPadding = isLandscape ? 16.0 : 48.0

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                JumpingChallengeCharacterShape()
                    .fill(characterCyan)
                    .ignoresSafeArea()
                    .offset(y: shapeOffset + introBounceOffset)
                    .scaleEffect(x: shapeScaleX, y: shapeScaleY, anchor: .bottom)
                    .animation(.spring(response: 0.72, dampingFraction: 1.00), value: hasAnimatedCharacter)
                    .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                    .animation(launchAnimation, value: isLaunchingDrill)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, safeTop + 72)
                .padding(.leading, 18)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: topContentSpacer)

                    VStack(spacing: 0) {
                        HStack(spacing: eyeSpacing) {
                            JumpingChallengeAngryEyeView(
                                side: .left,
                                eyeSize: eyeSize,
                                eyebrowWidth: eyebrowWidth,
                                eyebrowHeight: eyebrowHeight,
                                whiteColor: faceWhite,
                                blackColor: logoBlack
                            )

                            JumpingChallengeAngryEyeView(
                                side: .right,
                                eyeSize: eyeSize,
                                eyebrowWidth: eyebrowWidth,
                                eyebrowHeight: eyebrowHeight,
                                whiteColor: faceWhite,
                                blackColor: logoBlack
                            )
                        }

                        JumpingChallengeMouthShape()
                            .stroke(
                                logoBlack,
                                style: StrokeStyle(
                                    lineWidth: max(8.0, mouthWidth * 0.070),
                                    lineCap: .butt,
                                    lineJoin: .round
                                )
                            )
                            .frame(width: mouthWidth, height: mouthHeight)
                            .padding(.top, isLandscape ? 24 : 22)
                            .offset(x: isLandscape ? base * 0.010 : width * 0.010)
                    }
                    .opacity(faceOpacity)
                    .scaleEffect(faceScale)
                    .offset(y: faceLift)
                    .animation(.easeOut(duration: 0.42), value: isLaunchingDrill)

                    Button {
                        guard !isLaunchingDrill else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCardPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isCardPressed = false
                            }
                            withAnimation(launchAnimation) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                                showsCamera = true
                            }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(cardTeal)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay {
                                VStack(spacing: 16) {
                                    Text("JUMPING CHALLENGE")
                                        .font(.ballr(size: min(width * 0.064, 32), weight: .black))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)

                                    Text("JUMP OVER THE OBSTACLES")
                                        .font(.ballr(size: min(width * 0.038, 17), weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.86))
                                        .multilineTextAlignment(.center)
                                }
                                .tracking(0.8)
                                .padding(.horizontal, 20)
                            }
                            .scaleEffect(isCardPressed ? 0.96 : 1.0)
                            .shadow(color: Color.white.opacity(isCardPressed ? 0.0 : 0.16), radius: isCardPressed ? 0 : 16)
                            .overlay {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(isCardPressed ? 0.26 : 0.0), lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, cardTopPadding)
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)
                    .accessibilityLabel("Start Jumping Challenge")

                    Spacer(minLength: safeBottom + 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: contentOffset)
                .animation(.spring(response: 0.72, dampingFraction: 0.80), value: hasAnimatedCharacter)
                .animation(.easeOut(duration: 0.18), value: isLaunchingDrill)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            resetLaunchState()
        }) {
            JumpingChallengeCameraView(targetsFootX: true)
                .ballrCameraPresentationChrome()
        }
        .onAppear {
            resetLaunchState()
            introBounceOffset = 0
            hasAnimatedCharacter = false
            DispatchQueue.main.async {
                hasAnimatedCharacter = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                withAnimation(.easeOut(duration: 0.24)) {
                    introBounceOffset = 24
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    withAnimation(.spring(response: 0.54, dampingFraction: 0.68)) {
                        introBounceOffset = 0
                    }
                }
            }
        }
    }
}

private struct JumpingChallengeCharacterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let topY = h * 0.085
        let sideY = h * 0.305
        let shoulderY = h * 0.115

        path.move(to: CGPoint(x: 0, y: sideY))
        path.addLine(to: CGPoint(x: w * 0.410, y: shoulderY))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.590, y: shoulderY),
            control: CGPoint(x: w * 0.500, y: topY)
        )
        path.addLine(to: CGPoint(x: w, y: sideY))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

private struct JumpingChallengeAngryEyeView: View {
    enum Side {
        case left
        case right
    }

    let side: Side
    let eyeSize: CGFloat
    let eyebrowWidth: CGFloat
    let eyebrowHeight: CGFloat
    let whiteColor: Color
    let blackColor: Color

    private var sideLineRotation: Angle {
        side == .left ? .degrees(45) : .degrees(-45)
    }

    private var eyebrowRotation: Angle {
        side == .left ? .degrees(9) : .degrees(-9)
    }

    private var eyebrowXOffset: CGFloat {
        side == .left ? eyeSize * 0.18 : -eyeSize * 0.18
    }

    private var sideLineXOffset: CGFloat {
        side == .left ? -eyeSize * 0.54 : eyeSize * 0.54
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(blackColor)
                .frame(width: eyeSize * 0.80, height: max(7.0, eyeSize * 0.085))
                .rotationEffect(sideLineRotation)
                .offset(x: sideLineXOffset, y: -eyeSize * 0.58)

            Circle()
                .fill(whiteColor)
                .frame(width: eyeSize, height: eyeSize)
                .overlay {
                    Circle()
                        .stroke(blackColor, lineWidth: max(8.0, eyeSize * 0.120))
                }

            Rectangle()
                .fill(blackColor)
                .frame(width: eyebrowWidth, height: eyebrowHeight)
                .rotationEffect(eyebrowRotation)
                .offset(x: eyebrowXOffset, y: -eyeSize * 0.96)
        }
        .frame(width: eyeSize, height: eyeSize * 1.48)
    }
}

private struct JumpingChallengeMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct AgilityChallengeIntroScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showsCamera = false
    @State private var isLaunchingAgility = false
    @State private var showsFlipPrompt = false

    private let characterOrange = Color(red: 1.0, green: 0.60, blue: 0.0)
    private let cardOrange = Color(red: 1.0, green: 0.76, blue: 0.36)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchDuration = 1.48

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let base = min(width, height)
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let launchProgress: CGFloat = isLaunchingAgility ? 1 : 0
            let characterDrop = height * 0.39 * launchProgress
            let cardDrop = height * 0.72 * launchProgress
            let finalCharacterScaleY: CGFloat = isLaunchingAgility ? 0.78 : 1.0
            let finalFaceDrop = height * 0.13 * launchProgress
            let topContentSpacer = isLandscape ? height * 0.215 : height * 0.275
            let flipPromptTopSpacer = height * 0.42
            let glassesWidth = isLandscape ? base * 0.14 : width * 0.205
            let glassesHeight = glassesWidth * 0.41
            let bridgeWidth = isLandscape ? base * 0.052 : width * 0.072
            let bridgeHeight = max(2.0, glassesHeight * 0.075)
            let mouthWidth = isLandscape ? base * 0.095 : width * 0.155
            let mouthHeight = max(6.0, mouthWidth * 0.16)
            let cardWidth = isLandscape ? min(width * 0.34, 320) : width * 0.72
            let cardHeight = isLandscape ? min(height * 0.44, 230) : min(height * 0.34, width * 0.88)
            let cardTopPadding = isLandscape ? 54.0 : 92.0
            let characterStrokeWidth = 10.0

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                AgilityChallengeCharacterShape()
                    .fill(characterOrange)
                    .ignoresSafeArea()
                    .offset(y: characterDrop)
                    .scaleEffect(x: 1.0, y: finalCharacterScaleY, anchor: .bottom)
                    .animation(.easeInOut(duration: launchDuration), value: isLaunchingAgility)

                AgilityChallengeTopStrokeShape()
                    .stroke(Color(red: 0.706, green: 0.467, blue: 0.078), style: StrokeStyle(lineWidth: characterStrokeWidth, lineCap: .round))
                    .ignoresSafeArea()
                    .offset(y: characterDrop)
                    .scaleEffect(x: 1.0, y: finalCharacterScaleY, anchor: .bottom)
                    .animation(.easeInOut(duration: launchDuration), value: isLaunchingAgility)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, safeTop + 72)
                .padding(.leading, 18)
                .opacity(isLaunchingAgility ? 0 : 1)

                if showsFlipPrompt {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: flipPromptTopSpacer)

                        Text("FLIP THE\nPHONE")
                            .font(.ballr(size: min(width * 0.095, 38), weight: .black))
                            .tracking(1.6)
                            .lineSpacing(12)
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.28), value: showsFlipPrompt)
                }

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: topContentSpacer)

                    VStack(spacing: 0) {
                        HStack(spacing: isLandscape ? -3 : -5) {
                            AgilitySunglassesLensShape()
                                .fill(.black)
                                .frame(width: glassesWidth, height: glassesHeight)

                            Rectangle()
                                .fill(.black)
                                .frame(width: bridgeWidth, height: bridgeHeight)
                                .offset(y: -glassesHeight * 0.30)

                            AgilitySunglassesLensShape()
                                .fill(.black)
                                .frame(width: glassesWidth, height: glassesHeight)
                        }

                        Capsule()
                            .fill(.black)
                            .frame(width: mouthWidth, height: mouthHeight)
                            .padding(.top, isLandscape ? 18 : 30)
                            .offset(x: isLandscape ? base * 0.034 : width * 0.055)
                    }
                    .offset(y: finalFaceDrop)

                    Button {
                        startAgilityLaunch()
                    } label: {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(cardOrange)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay {
                                VStack(spacing: 16) {
                                    Text("AGILITY CHALLENGE")
                                        .font(.ballr(size: min(width * 0.062, 32), weight: .black))
                                        .foregroundStyle(.black)
                                        .multilineTextAlignment(.center)

                                    Text("CROSS SIDE TO SIDE FAST")
                                        .font(.ballr(size: min(width * 0.036, 17), weight: .semibold))
                                        .foregroundStyle(.black.opacity(0.78))
                                        .multilineTextAlignment(.center)
                                }
                                .tracking(0.8)
                                .padding(.horizontal, 20)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, cardTopPadding)
                    .disabled(isLaunchingAgility)
                    .offset(y: cardDrop)
                    .animation(.easeInOut(duration: launchDuration), value: isLaunchingAgility)

                    Spacer(minLength: safeBottom + 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: characterDrop)
                .animation(.easeInOut(duration: launchDuration), value: isLaunchingAgility)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            isLaunchingAgility = false
            showsFlipPrompt = false
        }) {
            AgilityChallengeCameraView()
                .ballrCameraPresentationChrome()
        }
        .onAppear {
            isLaunchingAgility = false
            showsFlipPrompt = false
        }
    }

    private func startAgilityLaunch() {
        guard !isLaunchingAgility else {
            return
        }

        withAnimation(.easeInOut(duration: launchDuration)) {
            isLaunchingAgility = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + launchDuration) {
            withAnimation(.easeInOut(duration: 0.28)) {
                showsFlipPrompt = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + launchDuration + 1.27) {
            BallrOrientationController.lockDribblingLandscape()
            showsCamera = true
        }
    }
}

private struct AgilityChallengeCharacterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let ellipseWidth = w * (423.0 / 393.0)
        let ellipseHeight = ellipseWidth * (189.0 / 423.0)
        let ellipseTopY = h * 0.115
        let ellipseCenterX = w * 0.5
        let ellipseCenterY = ellipseTopY + ellipseHeight * 0.5
        let radiusX = ellipseWidth * 0.5
        let radiusY = ellipseHeight * 0.5
        let samples = 48

        for index in 0...samples {
            let x = w * CGFloat(index) / CGFloat(samples)
            let normalizedX = min(max((x - ellipseCenterX) / radiusX, -1), 1)
            let y = ellipseCenterY - radiusY * sqrt(max(0, 1 - normalizedX * normalizedX))
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()

        return path
    }
}

private struct AgilityChallengeTopStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let ellipseWidth = w * (423.0 / 393.0)
        let ellipseHeight = ellipseWidth * (189.0 / 423.0)
        let ellipseTopY = h * 0.115
        let ellipseCenterX = w * 0.5
        let ellipseCenterY = ellipseTopY + ellipseHeight * 0.5
        let radiusX = ellipseWidth * 0.5
        let radiusY = ellipseHeight * 0.5
        let samples = 48

        for index in 0...samples {
            let x = w * CGFloat(index) / CGFloat(samples)
            let normalizedX = min(max((x - ellipseCenterX) / radiusX, -1), 1)
            let y = ellipseCenterY - radiusY * sqrt(max(0, 1 - normalizedX * normalizedX))
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

private struct AgilitySunglassesLensShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY * 1.18),
            control2: CGPoint(x: rect.minX, y: rect.maxY * 1.18)
        )
        path.closeSubpath()
        return path
    }
}

private struct PianoTilesIntroScreen: View {
    @Environment(\.dismiss) private var dismiss

    let difficulty: PianoTilesDifficulty

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0

    private let characterBlue = Color(red: 0.02, green: 0.44, blue: 0.94)
    private let cardBlue = Color(red: 0.36, green: 0.63, blue: 0.96)
    private let faceWhite = Color(red: 0.93, green: 0.91, blue: 0.91)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let base = min(width, height)
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let characterEntryOffset = hasAnimatedCharacter ? 0 : height * (isLandscape ? 0.78 : 0.62)
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let shapeOffset = characterEntryOffset
            let shapeScaleX = entryScale * (isLaunchingDrill ? 1.20 : 1.0)
            let shapeScaleY = entryScale * (isLaunchingDrill ? 1.46 : 1.0)
            let contentOffset = characterEntryOffset
            let faceOpacity = isLaunchingDrill ? 0.0 : 1.0
            let faceScale = isLaunchingDrill ? 0.90 : 1.0
            let faceLift = isLaunchingDrill ? -height * 0.035 : 0.0
            let topContentSpacer = isLandscape ? height * 0.165 : height * 0.205
            let eyeWidth = isLandscape ? base * 0.125 : width * 0.205
            let eyeHeight = eyeWidth * 0.64
            let pupilSize = eyeWidth * 0.46
            let eyeSpacing = isLandscape ? base * 0.105 : width * 0.045
            let mouthWidth = isLandscape ? base * 0.135 : width * 0.152
            let mouthHeight = mouthWidth * 0.50
            let toothWidth = mouthWidth * 0.14
            let toothHeight = mouthHeight * 0.34
            let cardWidth = isLandscape ? min(width * 0.34, 320) : width * 0.72
            let cardHeight = isLandscape ? min(height * 0.44, 230) : min(height * 0.34, width * 0.88)
            let cardTopPadding = isLandscape ? 26.0 : 92.0

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                PianoTilesCharacterShape()
                    .fill(characterBlue)
                    .ignoresSafeArea()
                    .offset(y: shapeOffset + introBounceOffset)
                    .scaleEffect(x: shapeScaleX, y: shapeScaleY, anchor: .bottom)
                    .animation(.spring(response: 0.72, dampingFraction: 1.00), value: hasAnimatedCharacter)
                    .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                    .animation(launchAnimation, value: isLaunchingDrill)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, safeTop + 72)
                .padding(.leading, 18)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: topContentSpacer)

                    VStack(spacing: 0) {
                        HStack(spacing: eyeSpacing) {
                            PianoTilesEyeView(
                                eyeWidth: eyeWidth,
                                eyeHeight: eyeHeight,
                                pupilSize: pupilSize,
                                pupilOffset: CGSize(width: eyeWidth * 0.10, height: 0),
                                whiteColor: faceWhite,
                                blackColor: logoBlack
                            )

                            PianoTilesEyeView(
                                eyeWidth: eyeWidth,
                                eyeHeight: eyeHeight,
                                pupilSize: pupilSize,
                                pupilOffset: CGSize(width: eyeWidth * 0.10, height: 0),
                                whiteColor: faceWhite,
                                blackColor: logoBlack
                            )
                        }

                        ZStack(alignment: .top) {
                            PianoTilesMouthShape()
                                .fill(logoBlack)
                                .frame(width: mouthWidth, height: mouthHeight)

                            HStack(spacing: toothWidth * 0.22) {
                                RoundedRectangle(cornerRadius: toothWidth * 0.35, style: .continuous)
                                    .fill(faceWhite)
                                    .frame(width: toothWidth, height: toothHeight)

                                RoundedRectangle(cornerRadius: toothWidth * 0.35, style: .continuous)
                                    .fill(faceWhite)
                                    .frame(width: toothWidth, height: toothHeight)
                            }
                            .padding(.top, 1)
                        }
                        .padding(.top, isLandscape ? 18 : 22)
                        .offset(x: isLandscape ? base * 0.018 : width * 0.035)
                    }
                    .opacity(faceOpacity)
                    .scaleEffect(faceScale)
                    .offset(y: faceLift)
                    .animation(.easeOut(duration: 0.42), value: isLaunchingDrill)

                    Button {
                        guard !isLaunchingDrill else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCardPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isCardPressed = false
                            }
                            withAnimation(launchAnimation) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                                showsCamera = true
                            }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(cardBlue)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay {
                                VStack(spacing: 16) {
                                    Text("PIANO TILES")
                                        .font(.ballr(size: min(width * 0.078, 36), weight: .black))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)

                                    Text("HIT EVERY TILE")
                                        .font(.ballr(size: min(width * 0.042, 18), weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.86))
                                        .multilineTextAlignment(.center)
                                }
                                .tracking(0.8)
                                .padding(.horizontal, 20)
                            }
                            .scaleEffect(isCardPressed ? 0.96 : 1.0)
                            .shadow(color: Color.white.opacity(isCardPressed ? 0.0 : 0.18), radius: isCardPressed ? 0 : 16)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(isCardPressed ? 0.26 : 0.0), lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, cardTopPadding)
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)

                    Spacer(minLength: safeBottom + 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: contentOffset)
                .animation(.spring(response: 0.72, dampingFraction: 0.80), value: hasAnimatedCharacter)
                .animation(.easeOut(duration: 0.18), value: isLaunchingDrill)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            resetLaunchState()
        }) {
            PianoTilesCameraView(difficulty: difficulty)
                .ballrCameraPresentationChrome()
        }
        .onAppear {
            resetLaunchState()
            introBounceOffset = 0
            hasAnimatedCharacter = false
            DispatchQueue.main.async {
                hasAnimatedCharacter = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                withAnimation(.easeOut(duration: 0.24)) {
                    introBounceOffset = 24
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    withAnimation(.spring(response: 0.54, dampingFraction: 0.68)) {
                        introBounceOffset = 0
                    }
                }
            }
        }
    }
}

private struct PianoTilesCharacterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let topY = h * 0.105
        let crownBottomY = h * 0.195

        path.move(to: CGPoint(x: 0, y: topY + h * 0.030))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.145, y: topY),
            control: CGPoint(x: w * 0.030, y: topY)
        )
        path.addLine(to: CGPoint(x: w * 0.355, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: w * 0.492, y: crownBottomY),
            control: CGPoint(x: w * 0.462, y: topY)
        )
        path.addQuadCurve(
            to: CGPoint(x: w * 0.640, y: topY),
            control: CGPoint(x: w * 0.526, y: topY)
        )
        path.addLine(to: CGPoint(x: w * 0.855, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: w, y: topY + h * 0.030),
            control: CGPoint(x: w * 0.970, y: topY)
        )
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

private struct PianoTilesEyeView: View {
    let eyeWidth: CGFloat
    let eyeHeight: CGFloat
    let pupilSize: CGFloat
    let pupilOffset: CGSize
    let whiteColor: Color
    let blackColor: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            PianoTilesHalfEllipseShape()
                .fill(whiteColor)
                .frame(width: eyeWidth, height: eyeHeight)

            PianoTilesHalfEllipseShape()
                .fill(blackColor)
                .frame(width: pupilSize, height: pupilSize * 0.74)
                .offset(pupilOffset)
        }
        .frame(width: eyeWidth, height: eyeHeight)
        .clipped()
    }
}

private struct PianoTilesHalfEllipseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control1: CGPoint(x: rect.minX, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct PianoTilesMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private struct FastTouchingIntroScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0
    @State private var didPlayIntroAnimation = false

    private let characterGreen = Color(red: 0.0, green: 0.71, blue: 0.45)
    private let cardGreen = Color(red: 0.12, green: 0.80, blue: 0.02)
    private let stripeWhite = Color(red: 0.95, green: 0.93, blue: 0.93)
    private let stripeRed = Color(red: 1.0, green: 0.18, blue: 0.15)
    private let faceWhite = Color(red: 0.93, green: 0.91, blue: 0.91)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let base = min(width, height)
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let characterEntryOffset = hasAnimatedCharacter ? 0 : height * (isLandscape ? 0.78 : 0.62)
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let characterOffset = characterEntryOffset
            let characterScaleX = entryScale * (isLaunchingDrill ? 1.18 : 1.0)
            let characterScaleY = entryScale * (isLaunchingDrill ? 1.48 : 1.0)
            let eyeWidth = isLandscape ? base * 0.12 : width * 0.20
            let eyeHeight = eyeWidth * 1.02
            let pupilSize = eyeWidth * 0.44
            let eyeSpacing = isLandscape ? base * 0.18 : width * 0.11
            let faceTop = isLandscape ? height * 0.245 : height * 0.255
            let mouthWidth = isLandscape ? base * 0.15 : width * 0.205
            let mouthHeight = isLandscape ? base * 0.042 : width * 0.072
            let cardWidth = isLandscape ? min(width * 0.34, 320) : width * 0.72
            let cardHeight = isLandscape ? min(height * 0.44, 230) : min(height * 0.34, width * 0.88)
            let cardTopPadding = isLandscape ? 28.0 : 58.0

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                FastTouchingCharacterShape()
                    .fill(characterGreen)
                    .ignoresSafeArea()
                    .offset(y: characterOffset + introBounceOffset)
                    .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)
                    .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                    .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                    .animation(launchAnimation, value: isLaunchingDrill)

                FastTouchingHeadbandView(
                    whiteColor: stripeWhite,
                    redColor: stripeRed,
                    topRatio: 0.150
                )
                .ignoresSafeArea()
                .offset(y: characterOffset + introBounceOffset)
                .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)
                .opacity(isLaunchingDrill ? 0.0 : 1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                .animation(.easeOut(duration: 0.18), value: isLaunchingDrill)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, safeTop + 72)
                .padding(.leading, 18)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: faceTop)

                    HStack(spacing: eyeSpacing) {
                        PrecisionTargetEyeView(
                            eyeWidth: eyeWidth,
                            eyeHeight: eyeHeight,
                            pupilSize: pupilSize,
                            pupilOffset: CGSize(width: eyeWidth * 0.18, height: eyeHeight * 0.24),
                            whiteColor: faceWhite,
                            blackColor: logoBlack
                        )

                        PrecisionTargetEyeView(
                            eyeWidth: eyeWidth,
                            eyeHeight: eyeHeight,
                            pupilSize: pupilSize,
                            pupilOffset: CGSize(width: eyeWidth * 0.18, height: eyeHeight * 0.24),
                            whiteColor: faceWhite,
                            blackColor: logoBlack
                        )
                    }
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)
                    .scaleEffect(isLaunchingDrill ? 0.90 : 1.0)
                    .animation(.easeOut(duration: 0.42), value: isLaunchingDrill)

                    Capsule()
                        .fill(logoBlack)
                        .frame(width: mouthWidth, height: mouthHeight)
                        .padding(.top, isLandscape ? 16 : 40)
                        .opacity(isLaunchingDrill ? 0.0 : 1.0)
                        .animation(.easeOut(duration: 0.42), value: isLaunchingDrill)

                    Button {
                        guard !isLaunchingDrill else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCardPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isCardPressed = false
                            }
                            withAnimation(launchAnimation) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                                showsCamera = true
                            }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(cardGreen)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay {
                                VStack(spacing: 16) {
                                    Text("FAST TOUCHING")
                                        .font(.ballr(size: min(width * 0.076, 34), weight: .black))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)

                                    Text("COUNT EVERY TOE TOUCH")
                                        .font(.ballr(size: min(width * 0.040, 18), weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.86))
                                        .multilineTextAlignment(.center)
                                }
                                .tracking(0.8)
                                .padding(.horizontal, 20)
                            }
                            .scaleEffect(isCardPressed ? 0.96 : 1.0)
                            .shadow(color: Color.white.opacity(isCardPressed ? 0.0 : 0.18), radius: isCardPressed ? 0 : 16)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(isCardPressed ? 0.26 : 0.0), lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, cardTopPadding)
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)

                    Spacer(minLength: safeBottom + 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: characterEntryOffset)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeOut(duration: 0.18), value: isLaunchingDrill)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                introBounceOffset = 0
                hasAnimatedCharacter = true
            }
            resetLaunchState()
        }) {
            FastTouchingCameraView()
                .ballrCameraPresentationChrome()
        }
        .onAppear {
            introBounceOffset = 0
            guard !didPlayIntroAnimation else {
                hasAnimatedCharacter = true
                return
            }

            resetLaunchState()
            didPlayIntroAnimation = true
            hasAnimatedCharacter = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.96, dampingFraction: 0.88)) {
                    hasAnimatedCharacter = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
                withAnimation(.easeInOut(duration: 0.34)) {
                    introBounceOffset = 14
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    withAnimation(.spring(response: 0.72, dampingFraction: 0.82)) {
                        introBounceOffset = 0
                    }
                }
            }
        }
    }
}

private struct PrecisionTargetIntroScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0
    @State private var didPlayIntroAnimation = false

    private let characterRed = Color(red: 1.0, green: 0.177, blue: 0.125)
    private let cardRed = Color(red: 0.737, green: 0.145, blue: 0.098)
    private let faceWhite = Color(red: 0.93, green: 0.91, blue: 0.91)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let base = min(width, height)
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let characterEntryOffset = hasAnimatedCharacter ? 0 : height * (isLandscape ? 0.78 : 0.62)
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let characterOffset = characterEntryOffset
            let characterScaleX = entryScale * (isLaunchingDrill ? 1.18 : 1.0)
            let characterScaleY = entryScale * (isLaunchingDrill ? 1.48 : 1.0)
            let eyeWidth = isLandscape ? base * 0.12 : width * 0.20
            let eyeHeight = eyeWidth * 1.02
            let pupilSize = eyeWidth * 0.44
            let eyeSpacing = isLandscape ? base * 0.18 : width * 0.11
            let faceTop = isLandscape ? height * 0.255 : height * 0.300
            let noseSize = isLandscape ? base * 0.065 : width * 0.12
            let cardWidth = isLandscape ? min(width * 0.34, 320) : width * 0.72
            let cardHeight = isLandscape ? min(height * 0.44, 230) : min(height * 0.34, width * 0.88)
            let cardTopPadding = isLandscape ? 28.0 : 38.0

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                PrecisionTargetCharacterShape()
                    .fill(characterRed)
                    .ignoresSafeArea()
                    .offset(y: characterOffset + introBounceOffset)
                    .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)
                    .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                    .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                    .animation(launchAnimation, value: isLaunchingDrill)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, safeTop + 72)
                .padding(.leading, 18)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: faceTop)

                    HStack(spacing: eyeSpacing) {
                        PrecisionTargetEyeView(
                            eyeWidth: eyeWidth,
                            eyeHeight: eyeHeight,
                            pupilSize: pupilSize,
                            pupilOffset: CGSize(width: eyeWidth * 0.20, height: eyeHeight * 0.24),
                            whiteColor: faceWhite,
                            blackColor: logoBlack
                        )

                        PrecisionTargetEyeView(
                            eyeWidth: eyeWidth,
                            eyeHeight: eyeHeight,
                            pupilSize: pupilSize,
                            pupilOffset: CGSize(width: eyeWidth * 0.18, height: eyeHeight * 0.24),
                            whiteColor: faceWhite,
                            blackColor: logoBlack
                        )
                    }
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)
                    .scaleEffect(isLaunchingDrill ? 0.90 : 1.0)
                    .animation(.easeOut(duration: 0.42), value: isLaunchingDrill)

                    Circle()
                        .fill(logoBlack)
                        .frame(width: noseSize, height: noseSize)
                        .padding(.top, isLandscape ? 12 : 38)
                        .offset(x: isLandscape ? base * 0.025 : width * 0.055)
                        .opacity(isLaunchingDrill ? 0.0 : 1.0)
                        .animation(.easeOut(duration: 0.42), value: isLaunchingDrill)

                    Button {
                        guard !isLaunchingDrill else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCardPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isCardPressed = false
                            }
                            withAnimation(launchAnimation) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                                showsCamera = true
                            }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(cardRed)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay {
                                VStack(spacing: 16) {
                                    Text("PRECISION TARGETS")
                                        .font(.ballr(size: min(width * 0.066, 34), weight: .black))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)

                                    Text("HIT THE WALL TARGET")
                                        .font(.ballr(size: min(width * 0.038, 18), weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .multilineTextAlignment(.center)
                                }
                                .tracking(0.8)
                                .padding(.horizontal, 20)
                            }
                            .scaleEffect(isCardPressed ? 0.96 : 1.0)
                            .shadow(color: Color.white.opacity(isCardPressed ? 0.0 : 0.18), radius: isCardPressed ? 0 : 16)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(isCardPressed ? 0.26 : 0.0), lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, cardTopPadding)
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)

                    Spacer(minLength: safeBottom + 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: characterEntryOffset)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeOut(duration: 0.18), value: isLaunchingDrill)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                introBounceOffset = 0
                hasAnimatedCharacter = true
            }
            resetLaunchState()
        }) {
            PrecisionTargetCameraView()
                .ballrCameraPresentationChrome()
        }
        .onAppear {
            introBounceOffset = 0
            guard !didPlayIntroAnimation else {
                hasAnimatedCharacter = true
                return
            }

            resetLaunchState()
            didPlayIntroAnimation = true
            hasAnimatedCharacter = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.96, dampingFraction: 0.88)) {
                    hasAnimatedCharacter = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
                withAnimation(.easeInOut(duration: 0.34)) {
                    introBounceOffset = 14
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    withAnimation(.spring(response: 0.72, dampingFraction: 0.82)) {
                        introBounceOffset = 0
                    }
                }
            }
        }
    }
}

private struct PrecisionTargetCharacterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let topY = h * 0.105
        let valleyY = h * 0.245

        path.move(to: CGPoint(x: 0, y: topY))
        path.addQuadCurve(to: CGPoint(x: w * 0.035, y: topY + h * 0.012), control: CGPoint(x: w * 0.015, y: topY))
        path.addLine(to: CGPoint(x: w * 0.245, y: valleyY))
        path.addLine(to: CGPoint(x: w * 0.455, y: topY + h * 0.004))
        path.addQuadCurve(to: CGPoint(x: w * 0.530, y: topY + h * 0.004), control: CGPoint(x: w * 0.492, y: topY - h * 0.030))
        path.addLine(to: CGPoint(x: w * 0.740, y: valleyY + h * 0.004))
        path.addLine(to: CGPoint(x: w * 0.960, y: topY + h * 0.012))
        path.addQuadCurve(to: CGPoint(x: w, y: topY), control: CGPoint(x: w * 0.985, y: topY))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

private struct PrecisionTargetEyeView: View {
    let eyeWidth: CGFloat
    let eyeHeight: CGFloat
    let pupilSize: CGFloat
    let pupilOffset: CGSize
    let whiteColor: Color
    let blackColor: Color

    var body: some View {
        Ellipse()
            .fill(whiteColor)
            .frame(width: eyeWidth, height: eyeHeight)
            .overlay(alignment: .center) {
                Circle()
                    .fill(blackColor)
                    .frame(width: pupilSize, height: pupilSize)
                    .offset(pupilOffset)
            }
    }
}

private struct BallBlastRockDropIntroScreen: View {
    @Environment(\.dismiss) private var dismiss
    let difficulty: BallBlastRockDropDifficulty

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0
    @State private var didPlayIntroAnimation = false

    private let characterPink = Color(red: 0.93, green: 0.80, blue: 0.96)
    private let cardPurple = Color(red: 0.77, green: 0.50, blue: 0.82)
    private let faceBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let faceWhite = Color(red: 0.96, green: 0.95, blue: 0.95)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let base = min(width, height)
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let characterEntryOffset = hasAnimatedCharacter ? 0 : height * (isLandscape ? 0.78 : 0.62)
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let characterOffset = characterEntryOffset
            let characterScaleX = entryScale * (isLaunchingDrill ? 1.18 : 1.0)
            let characterScaleY = entryScale * (isLaunchingDrill ? 1.48 : 1.0)
            let eyeSize = isLandscape ? base * 0.10 : width * 0.14
            let eyeSpacing = isLandscape ? base * 0.15 : width * 0.08
            let mouthWidth = isLandscape ? base * 0.17 : width * 0.24
            let mouthHeight = mouthWidth * 0.46
            let cardWidth = isLandscape ? min(width * 0.34, 320) : width * 0.72
            let cardHeight = isLandscape ? min(height * 0.44, 230) : min(height * 0.34, width * 0.88)
            let cardTopPadding = isLandscape ? 42.0 : 54.0

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                BallBlastRockDropCharacterShape()
                    .fill(characterPink)
                    .ignoresSafeArea()
                    .offset(y: characterOffset + introBounceOffset)
                    .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)
                    .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                    .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                    .animation(launchAnimation, value: isLaunchingDrill)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.35), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.top, safeTop + 72)
                .padding(.leading, 18)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: isLandscape ? height * 0.30 : height * 0.31)

                    HStack(spacing: eyeSpacing) {
                        BallBlastRockDropEyeView(
                            eyeSize: eyeSize,
                            faceBlack: faceBlack,
                            faceWhite: faceWhite
                        )

                        BallBlastRockDropEyeView(
                            eyeSize: eyeSize,
                            faceBlack: faceBlack,
                            faceWhite: faceWhite
                        )
                    }
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)
                    .scaleEffect(isLaunchingDrill ? 0.90 : 1.0)
                    .animation(.easeOut(duration: 0.42), value: isLaunchingDrill)

                    BallBlastRockDropSmileShape()
                        .fill(faceBlack)
                        .frame(width: mouthWidth, height: mouthHeight)
                    .padding(.top, isLandscape ? 18 : 26)
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)
                    .animation(.easeOut(duration: 0.42), value: isLaunchingDrill)

                    Button {
                        guard !isLaunchingDrill else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCardPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isCardPressed = false
                            }
                            withAnimation(launchAnimation) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.58) {
                                showsCamera = true
                            }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(cardPurple)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay {
                                VStack(spacing: 16) {
                                    Text("ROCK DROP")
                                        .font(.ballr(size: min(width * 0.070, 34), weight: .black))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)

                                    Text("DODGE THE FALLING ROCKS")
                                        .font(.ballr(size: min(width * 0.038, 18), weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.86))
                                        .multilineTextAlignment(.center)
                                }
                                .tracking(0.8)
                                .padding(.horizontal, 20)
                            }
                            .scaleEffect(isCardPressed ? 0.96 : 1.0)
                            .shadow(color: Color.white.opacity(isCardPressed ? 0.0 : 0.18), radius: isCardPressed ? 0 : 16)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(Color.white.opacity(isCardPressed ? 0.26 : 0.0), lineWidth: 3)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, cardTopPadding)
                    .opacity(isLaunchingDrill ? 0.0 : 1.0)

                    Spacer(minLength: safeBottom + 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: characterEntryOffset)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeOut(duration: 0.18), value: isLaunchingDrill)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                introBounceOffset = 0
                hasAnimatedCharacter = true
            }
            resetLaunchState()
        }) {
            BallBlastRockDropCameraView(difficulty: self.difficulty)
                .ballrCameraPresentationChrome()
        }
        .onAppear {
            introBounceOffset = 0
            guard !didPlayIntroAnimation else {
                hasAnimatedCharacter = true
                return
            }

            resetLaunchState()
            didPlayIntroAnimation = true
            hasAnimatedCharacter = false
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.96, dampingFraction: 0.88)) {
                    hasAnimatedCharacter = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.78) {
                withAnimation(.easeInOut(duration: 0.34)) {
                    introBounceOffset = 14
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                    withAnimation(.spring(response: 0.72, dampingFraction: 0.82)) {
                        introBounceOffset = 0
                    }
                }
            }
        }
    }
}

private struct BallBlastRockDropCharacterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let topY = h * 0.215
        let peakY = h * 0.095
        let segment = w / 4.0

        path.move(to: CGPoint(x: 0, y: topY))
        path.addQuadCurve(to: CGPoint(x: segment * 0.48, y: peakY), control: CGPoint(x: segment * 0.20, y: topY))
        path.addQuadCurve(to: CGPoint(x: segment, y: topY), control: CGPoint(x: segment * 0.80, y: topY))
        path.addQuadCurve(to: CGPoint(x: segment * 1.48, y: peakY), control: CGPoint(x: segment * 1.20, y: topY))
        path.addQuadCurve(to: CGPoint(x: segment * 2.0, y: topY), control: CGPoint(x: segment * 1.80, y: topY))
        path.addQuadCurve(to: CGPoint(x: segment * 2.48, y: peakY), control: CGPoint(x: segment * 2.20, y: topY))
        path.addQuadCurve(to: CGPoint(x: segment * 3.0, y: topY), control: CGPoint(x: segment * 2.80, y: topY))
        path.addQuadCurve(to: CGPoint(x: segment * 3.48, y: peakY), control: CGPoint(x: segment * 3.20, y: topY))
        path.addQuadCurve(to: CGPoint(x: w, y: topY), control: CGPoint(x: segment * 3.80, y: topY))
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

private struct BallBlastRockDropEyeView: View {
    let eyeSize: CGFloat
    let faceBlack: Color
    let faceWhite: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(faceBlack)
                .frame(width: eyeSize, height: eyeSize)

            Circle()
                .fill(faceWhite)
                .frame(width: eyeSize * 0.28, height: eyeSize * 0.28)
                .offset(x: -eyeSize * 0.18, y: -eyeSize * 0.10)

            Circle()
                .fill(faceWhite)
                .frame(width: eyeSize * 0.12, height: eyeSize * 0.12)
                .offset(x: -eyeSize * 0.28, y: eyeSize * 0.18)

            HStack(spacing: eyeSize * 0.05) {
                Capsule()
                    .frame(width: eyeSize * 0.10, height: eyeSize * 0.36)
                Capsule()
                    .frame(width: eyeSize * 0.10, height: eyeSize * 0.42)
                Capsule()
                    .frame(width: eyeSize * 0.10, height: eyeSize * 0.34)
            }
            .foregroundStyle(faceBlack)
            .rotationEffect(.degrees(-20))
            .offset(x: -eyeSize * 0.14, y: -eyeSize * 0.47)
        }
    }
}

private struct BallBlastRockDropSmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.minY)
        let radius = rect.width * 0.5

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )
        path.closeSubpath()
        return path
    }
}

private struct FastTouchingCharacterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let topY = h * 0.135
        let humpHeight = h * 0.024
        let scallopWidth = w * 0.235

        path.move(to: CGPoint(x: 0, y: topY))
        var x: CGFloat = 0
        while x < w + scallopWidth {
            path.addQuadCurve(
                to: CGPoint(x: min(x + scallopWidth, w), y: topY),
                control: CGPoint(x: x + scallopWidth * 0.5, y: topY - humpHeight)
            )
            x += scallopWidth
        }
        path.addLine(to: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: 0, y: h))
        path.closeSubpath()
        return path
    }
}

private struct FastTouchingHeadbandView: View {
    let whiteColor: Color
    let redColor: Color
    let topRatio: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let stripeY = height * topRatio
            let stripeHeight = max(height * 0.012, 7)
            let redStripeHeight = max(height * 0.006, 4)
            let segmentWidth = width * 0.225
            let seamWidth = max(width * 0.010, 4)

            ZStack(alignment: .topLeading) {
                ForEach(0..<6, id: \.self) { index in
                    let x = CGFloat(index) * segmentWidth - seamWidth * 0.5

                    Capsule()
                        .fill(whiteColor)
                        .frame(width: segmentWidth + seamWidth, height: stripeHeight)
                        .position(x: x + (segmentWidth + seamWidth) * 0.5, y: stripeY)

                    Capsule()
                        .fill(redColor)
                        .frame(width: segmentWidth + seamWidth, height: redStripeHeight)
                        .position(x: x + (segmentWidth + seamWidth) * 0.5, y: stripeY + stripeHeight * 0.54)
                }
            }
        }
    }
}

private struct JugglingFaceEyeView: View {
    private let faceBlack = Color(red: 0.137, green: 0.122, blue: 0.125)

    var body: some View {
        ZStack {
            Circle()
                .fill(faceBlack)
                .frame(width: 60, height: 60)

            Circle()
                .fill(.white)
                .frame(width: 14, height: 14)
                .offset(x: -8, y: -6)

            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .offset(x: -14, y: 8)

            HStack(spacing: 2) {
                Capsule().frame(width: 4, height: 14)
                Capsule().frame(width: 4, height: 16)
                Capsule().frame(width: 4, height: 13)
            }
            .foregroundStyle(faceBlack)
            .rotationEffect(.degrees(-24))
            .offset(x: -8, y: -30)
        }
    }
}

private struct BallrWordmark: View {
    let size: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Text("Ball")
                .foregroundStyle(Color.yellow)
            Text("r")
                .foregroundStyle(Color.orange)
        }
        .font(.ballr(size: size, weight: .black))
    }
}

private struct ProfilePlayerCard: View {
    let name: String
    let accountLabel: String
    let xp: Int

    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.yellow)
                Image(systemName: "person.fill")
                    .font(.ballr(size: 38, weight: .black))
                    .foregroundStyle(Color.ballrBlack)
            }
            .frame(width: 86, height: 86)
            .overlay(
                Circle()
                    .stroke(Color.orange, lineWidth: 4)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(name)
                    .font(.ballr(size: 25, weight: .black))
                    .foregroundStyle(.white)

                Text("\(xp) XP")
                    .font(.ballr(size: 16, weight: .black))
                    .foregroundStyle(Color.yellow)

                Text(accountLabel)
                    .font(.ballr(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                GeometryReader { geometry in
                    let levelXP = xp % 100
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.12))
                        Capsule()
                            .fill(Color.yellow)
                            .frame(width: geometry.size.width * min(CGFloat(levelXP) / 100.0, 1.0))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.32), lineWidth: 1.5)
        )
    }
}

private struct ProfileStatCard: View {
    let value: String
    let label: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.ballr(size: 34, weight: .black))
                .foregroundStyle(valueColor)

            Text(label)
                .font(.ballr(size: 12, weight: .black))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.48))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 108)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(valueColor.opacity(0.24), lineWidth: 1.5)
        )
    }
}

private struct ProfileAchievementRow: View {
    let slots: [AchievementSlot]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, _ in
                AchievementBadgeSlot(index: index)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.18), lineWidth: 1)
        }
    }
}

private struct AchievementBadgeSlot: View {
    let index: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(fillColor)
                .frame(width: 50, height: 62)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(borderColor, style: StrokeStyle(lineWidth: 2, dash: index < 2 ? [] : [6, 4]))
                )

            if index == 0 {
                Image(systemName: "soccerball")
                    .font(.ballr(size: 24, weight: .black))
                    .foregroundStyle(.white)
            } else if index == 1 {
                Text("🔥")
                    .font(.ballr(size: 26))
            }
        }
    }

    private var fillColor: Color {
        switch index {
        case 0:
            Color.yellow
        case 1:
            Color.orange
        default:
            Color.clear
        }
    }

    private var borderColor: Color {
        index < 2 ? .clear : .white.opacity(0.22)
    }
}

private struct BallrCardDetailView: View {
    var body: some View {
        ZStack {
            BallrAppBackground()

            VStack(spacing: 22) {
                BallrEliteCard()

                HStack(spacing: 16) {
                    Button {
                    } label: {
                        Text("SHARE")
                            .font(.ballr(size: 18, weight: .black))
                            .foregroundStyle(Color.yellow)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(Color.black.opacity(0.56), in: Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(Color.yellow.opacity(0.28), lineWidth: 1.5)
                            )
                    }

                    Button {
                    } label: {
                        Text("UPGRADE")
                            .font(.ballr(size: 18, weight: .black))
                            .foregroundStyle(Color.ballrBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 64)
                            .background(Color.yellow, in: Capsule())
                    }
                }
                .padding(.horizontal, 44)
            }
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .frame(maxHeight: .infinity, alignment: .center)
            .minimumScaleFactor(0.92)
            .lineLimit(1)
            .dynamicTypeSize(.medium)
            .ignoresSafeArea(.keyboard)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct BallrEliteCard: View {
    @EnvironmentObject private var authSession: AuthSessionManager

    private var playerName: String {
        authSession.profileName.uppercased()
    }

    private var position: String {
        authSession.profile?.preferredPosition ?? "ST"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("60")
                            .font(.ballr(size: 54, weight: .black))
                            .foregroundStyle(.white)

                        Text(position)
                            .font(.ballr(size: 18, weight: .black))
                            .foregroundStyle(.white)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 40, height: 48)
                            .overlay {
                                Image(systemName: "soccerball")
                                    .font(.ballr(size: 22, weight: .black))
                                    .foregroundStyle(.white)
                            }
                            .padding(.top, 10)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        Text("BALLR")
                            .font(.ballr(size: 20, weight: .black))
                            .tracking(3)
                            .foregroundStyle(.white)

                        Text("STARTER")
                            .font(.ballr(size: 13, weight: .black))
                            .foregroundStyle(.white.opacity(0.78))

                        HStack(spacing: 8) {
                            Circle()
                                .fill(.white.opacity(0.25))
                                .frame(width: 28, height: 28)
                            Circle()
                                .fill(.white.opacity(0.25))
                                .frame(width: 28, height: 28)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 24)
                .frame(height: 132)

                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .frame(height: 78)
                    .overlay(alignment: .bottom) {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 94, height: 94)
                            .overlay(
                                Circle()
                                    .stroke(.white, lineWidth: 6)
                            )
                            .overlay {
                                ZStack {
                                    Image(systemName: "person.fill")
                                        .font(.ballr(size: 40, weight: .black))
                                        .foregroundStyle(Color.ballrBlack)
                                }
                            }
                            .offset(y: 20)
                    }

                VStack(spacing: 14) {
                    Text(playerName)
                        .font(.ballr(size: playerName.count > 10 ? 15 : 18, weight: .black))
                        .tracking(6)
                        .foregroundStyle(Color.yellow)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)
                        .padding(.horizontal, 16)
                        .padding(.top, 38)

                    VStack(spacing: 12) {
                        HStack {
                            BallrCardStat(value: "60", label: "PAC")
                            BallrCardStat(value: "60", label: "SHO")
                            BallrCardStat(value: "60", label: "PAS")
                        }

                        Rectangle()
                            .fill(.white.opacity(0.22))
                            .frame(height: 2)

                        HStack {
                            BallrCardStat(value: "60", label: "DRI")
                            BallrCardStat(value: "60", label: "DEF")
                            BallrCardStat(value: "60", label: "PHY")
                        }
                    }
                    .padding(.horizontal, 20)

                    Text("BALLR STARTER")
                        .font(.ballr(size: 18, weight: .black))
                        .tracking(6)
                        .foregroundStyle(Color.yellow)
                        .padding(.top, 4)
                        .padding(.bottom, 18)
                }
                .frame(height: 220)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.73, green: 0.63, blue: 0.03),
                        Color(red: 0.49, green: 0.45, blue: 0.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.yellow.opacity(0.7), lineWidth: 3)
            )
        }
    }
}

private struct BallrCardStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.ballr(size: 27, weight: .black))
                .foregroundStyle(Color.yellow)

            Text(label)
                .font(.ballr(size: 12, weight: .black))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BallrSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authSession: AuthSessionManager
    @AppStorage("ballrDarkModeEnabled") private var isDarkModeEnabled = true
    @State private var soundEnabled = true
    @State private var notificationsEnabled = false
    @State private var isShowingNameEditor = false
    @State private var draftName = ""
    @State private var noticeClearTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            BallrAppBackground()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    Button {
                        dismiss()
                    } label: {
                        Circle()
                            .stroke(Color.yellow.opacity(0.35), lineWidth: 2)
                            .frame(width: 46, height: 46)
                            .overlay {
                                Image(systemName: "chevron.left")
                                    .font(.ballr(size: 18, weight: .black))
                                    .foregroundStyle(Color.yellow)
                            }
                    }

                    Text("Settings")
                        .font(.ballr(size: 28, weight: .black))
                        .foregroundStyle(Color.yellow)

                    Spacer()
                }
                .padding(.top, 18)
                .padding(.bottom, 10)

                VStack(spacing: 0) {
                    Button {
                        draftName = authSession.profile?.username ?? authSession.profileName
                        isShowingNameEditor = true
                    } label: {
                        SettingsNavigationRow(
                            icon: "pencil",
                            title: authSession.isWorking ? "Saving name..." : "Change name",
                            subtitle: authSession.profileName,
                            iconBackground: Color.yellow.opacity(0.16),
                            iconColor: Color.yellow
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(authSession.isWorking)

                    SettingsDivider()

                    SettingsToggleRow(
                        icon: "moon.fill",
                        title: "Dark mode",
                        iconBackground: Color.yellow.opacity(0.12),
                        iconColor: Color.yellow.opacity(0.78),
                        isOn: $isDarkModeEnabled
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        icon: "speaker.wave.2.fill",
                        title: "Sound",
                        iconBackground: Color.yellow.opacity(0.12),
                        iconColor: Color.yellow.opacity(0.75),
                        isOn: $soundEnabled
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        icon: "bell.fill",
                        title: "Notifications",
                        iconBackground: Color.yellow.opacity(0.10),
                        iconColor: Color.yellow.opacity(0.72),
                        isOn: $notificationsEnabled
                    )
                }
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))

                if let message = authSession.errorMessage {
                    SettingsStatusMessage(message: message, color: Color.orange)
                }

                if let message = authSession.noticeMessage {
                    SettingsStatusMessage(message: message, color: Color.yellow)
                }

                Button {
                } label: {
                    SettingsNavigationRow(
                        icon: "trash",
                        title: "Reset progress",
                        subtitle: nil,
                        iconBackground: Color.yellow.opacity(0.10),
                        iconColor: Color.orange,
                        titleColor: Color.orange
                    )
                }
                .buttonStyle(.plain)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))
                .padding(.top, 2)

                Button {
                    Task {
                        await authSession.signOut()
                    }
                } label: {
                    SettingsNavigationRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: authSession.isWorking ? "Signing out..." : "Sign out",
                        subtitle: nil,
                        iconBackground: Color.orange.opacity(0.12),
                        iconColor: Color.orange,
                        titleColor: Color.orange
                    )
                }
                .buttonStyle(.plain)
                .disabled(authSession.isWorking)
                .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))

                Spacer()

                HStack(spacing: 5) {
                    Text("Ballr v1.0 · Made with")
                    Text("⚽")
                }
                .font(.ballr(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.22))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 24)

            if isShowingNameEditor {
                SettingsNameEditorOverlay(
                    name: $draftName,
                    isSaving: authSession.isWorking,
                    onCancel: {
                        isShowingNameEditor = false
                    },
                    onSave: {
                        isShowingNameEditor = false
                        Task {
                            await authSession.updateUsername(draftName)
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: isShowingNameEditor)
        .onAppear {
            authSession.clearAccountMessages()
        }
        .onDisappear {
            noticeClearTask?.cancel()
            noticeClearTask = nil
        }
        .onChange(of: authSession.noticeMessage) { _, message in
            noticeClearTask?.cancel()
            guard message != nil else {
                noticeClearTask = nil
                return
            }

            noticeClearTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                authSession.clearAccountMessages()
                noticeClearTask = nil
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SettingsNameEditorOverlay: View {
    @Binding var name: String
    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    private var canSave: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 && !isSaving
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    SettingsIcon(
                        icon: "pencil",
                        background: Color.yellow.opacity(0.16),
                        color: Color.yellow
                    )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Change name")
                                .font(.ballr(size: 26, weight: .black))
                                .foregroundStyle(Color.yellow)
                        }

                    Spacer()
                }

                TextField("Username", text: $name)
                    .font(.ballr(size: 22, weight: .black))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .padding(.horizontal, 16)
                    .frame(height: 58)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.yellow.opacity(0.32), lineWidth: 1.5)
                    }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(.ballr(size: 15, weight: .black))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: onSave) {
                        Text(isSaving ? "SAVING..." : "SAVE")
                            .font(.ballr(size: 15, weight: .black))
                            .foregroundStyle(Color.ballrBlack)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(canSave ? Color.yellow : Color.yellow.opacity(0.34), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                }
            }
            .padding(22)
            .frame(maxWidth: 430)
            .background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.34), lineWidth: 1.5)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct SettingsStatusMessage: View {
    let message: String
    let color: Color

    var body: some View {
        Text(message)
            .font(.ballr(size: 14, weight: .black))
            .foregroundStyle(color)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.30), lineWidth: 1)
            }
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let iconBackground: Color
    let iconColor: Color
    var titleColor: Color = .white

    var body: some View {
        HStack(spacing: 16) {
            SettingsIcon(icon: icon, background: iconBackground, color: iconColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ballr(size: 19, weight: .black))
                    .foregroundStyle(titleColor)

                if let subtitle {
                    Text(subtitle)
                        .font(.ballr(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.ballr(size: 14, weight: .black))
                .foregroundStyle(Color.yellow)
        }
        .padding(.horizontal, 24)
        .frame(height: 92)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let iconBackground: Color
    let iconColor: Color
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            SettingsIcon(icon: icon, background: iconBackground, color: iconColor)

            Text(title)
                .font(.ballr(size: 19, weight: .black))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(Color.yellow)
        }
        .padding(.horizontal, 24)
        .frame(height: 92)
    }
}

private struct SettingsIcon: View {
    let icon: String
    let background: Color
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(background)
            .frame(width: 52, height: 52)
            .overlay {
                Image(systemName: icon)
                    .font(.ballr(size: 22, weight: .black))
                    .foregroundStyle(color)
            }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 92)
    }
}

private struct LevelsHeaderStatChip: View {
    let systemImage: String
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.ballr(size: 13, weight: .black))
                .foregroundStyle(Color(red: 1.0, green: 0.32, blue: 0.18))

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.ballr(size: 12, weight: .black))
                    .foregroundStyle(Color.yellow)

                Text(label.uppercased())
                    .font(.ballr(size: 7, weight: .black))
                    .foregroundStyle(.white.opacity(0.46))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct LevelsScreenBackground: View {
    var body: some View {
        BallrAppBackground()
    }
}

private struct LevelsMapIcon: View {
    var fillColor: Color = .yellow

    var body: some View {
        Image("Image")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(fillColor)
    }
}

private struct LevelStartPromptView: View {
    let drill: Drill
    let onStart: () -> Void
    let onSelectEasy: (() -> Void)?
    let onSelectHard: (() -> Void)?
    let onCancel: () -> Void

    private var promptText: String {
        if drill.level == 1 {
            return "Tutorial - Learn how to use the ball tracker"
        }

        return "\(drill.title) - \(drill.subtitle)"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 10) {
                    Text(promptText)
                        .font(.ballr(size: 15, weight: .black))
                        .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 26)

                    Button(action: onStart) {
                        Text("START")
                            .font(.ballr(size: 15, weight: .black))
                            .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(red: 1.0, green: 0.29, blue: 0.18), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .id(drill.id)
                .transition(.opacity)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.ballr(size: 13, weight: .black))
                        .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .padding(.trailing, 4)
            }
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.78, green: 0.64, blue: 0.00))
                    .frame(height: 8)
                    .offset(y: 6)
            }

            TrianglePointer()
                .fill(Color(red: 0.78, green: 0.64, blue: 0.00))
                .frame(width: 18, height: 12)
        }
        .animation(.easeInOut(duration: 0.18), value: drill.id)
    }
}

private struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct LevelsMapView: View {
    let drills: [Drill]
    let promptedDrill: Drill?
    let currentLevel: Int
    let lockedLevels: Set<Int>
    let onSelect: (Drill) -> Void
    let onStart: (Drill) -> Void
    let onSelectEasy: (Drill) -> Void
    let onSelectHard: (Drill) -> Void
    let onCancel: () -> Void

    private var nodePositions: [CGPoint] {
        drills.indices.map { index in
            let xPattern: [CGFloat] = [0.68, 0.32, 0.68, 0.32]
            return CGPoint(
                x: xPattern[index % xPattern.count],
                y: 0.95 - CGFloat(index) * 0.049
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LevelPathShape(points: nodePositions)
                    .stroke(
                        Color.white.opacity(0.25),
                        style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                    )

                ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
                    let point = nodePositions[index]
                    let level = index + 1
                    let isLocked = lockedLevels.contains(level)

                    Button {
                        if !isLocked {
                            onSelect(drill)
                        }
                    } label: {
                        LevelNodeView(
                            level: level,
                            isOnLeftSide: point.x < 0.5,
                            isLocked: isLocked,
                            isCurrent: level == currentLevel
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked)
                    .id(level)
                    .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
                }

                if
                    let promptedDrill,
                    let promptedIndex = drills.firstIndex(where: { $0.id == promptedDrill.id })
                {
                    let point = nodePositions[promptedIndex]
                    let nodeX = point.x * geometry.size.width
                    let nodeY = point.y * geometry.size.height
                    let promptWidth = min(230, max(200, geometry.size.width * 0.58))

                    LevelStartPromptView(
                        drill: promptedDrill,
                        onStart: { onStart(promptedDrill) },
                        onSelectEasy: { onSelectEasy(promptedDrill) },
                        onSelectHard: { onSelectHard(promptedDrill) },
                        onCancel: onCancel
                    )
                    .id("level-start-prompt")
                    .frame(width: promptWidth)
                    .position(
                        x: nodeX,
                        y: max(nodeY - 78, 82)
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.88), value: promptedDrill.id)
                    .zIndex(2)
                }
            }
        }
    }
}

private struct SoccerFieldBackground: View {
    var showsStadiumLabels = true

    var body: some View {
        BallrAppBackground()
    }
}

private struct LevelNodeView: View {
    let level: Int
    let isOnLeftSide: Bool
    let isLocked: Bool
    let isCurrent: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let pulse = CGFloat((sin(timeline.date.timeIntervalSinceReferenceDate * 2.2) + 1) / 2)
            let ringScale = 1.0 + pulse * 0.14

            ZStack {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 38)
                        .stroke(Color.yellow.opacity(0.34 - pulse * 0.12), lineWidth: 5)
                        .frame(width: 74, height: 69)
                        .offset(x: isOnLeftSide ? -1.5 : 1.5, y: 2)
                        .scaleEffect(ringScale)

                    RoundedRectangle(cornerRadius: 34)
                        .stroke(Color.white.opacity(0.13 + pulse * 0.10), lineWidth: 2)
                        .frame(width: 66, height: 63)
                        .offset(x: isOnLeftSide ? -1.5 : 1.5, y: 2)
                        .scaleEffect(1.0 + pulse * 0.08)
                }

                Circle()
                    .fill(isLocked ? Color.black.opacity(0.54) : Color(red: 1.0, green: 0.20, blue: 0.18))
                    .frame(width: 58, height: 58)
                    .offset(x: isOnLeftSide ? -3 : 3, y: 4)
                    .shadow(color: .black.opacity(0.30), radius: 8, x: 0, y: 8)

                Circle()
                    .fill(isLocked ? Color.white.opacity(0.12) : Color.yellow)
                    .frame(width: 58, height: 58)
                    .overlay {
                        if isLocked {
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 2)
                        }
                }

                VStack(spacing: 1) {
                    Text("\(level)")
                        .font(.ballr(size: level > 9 ? 16 : 20, weight: .black))
                        .foregroundStyle(isLocked ? .white.opacity(0.40) : Color(red: 0.11, green: 0.10, blue: 0.11))

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.ballr(size: 10, weight: .black))
                            .foregroundStyle(.white.opacity(0.40))
                    }
                }
            }
        }
        .frame(width: 76, height: 76)
        .contentShape(Circle())
        .accessibilityLabel(isLocked ? "Level \(level), locked" : "Level \(level)")
    }
}

private struct LevelPathShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }

        let resolvedPoints = points.map { point in
            CGPoint(x: point.x * rect.width, y: point.y * rect.height)
        }

        path.move(to: CGPoint(x: first.x * rect.width, y: first.y * rect.height))

        for index in 1..<resolvedPoints.count {
            let current = resolvedPoints[index]
            path.addLine(to: current)
        }

        return path
    }
}

private struct DrillCardView: View {
    let drill: Drill

    var body: some View {
        HStack(spacing: 16) {
            DiamondIcon()
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(drill.title)
                    .font(.ballr(size: 17, weight: .black))
                    .foregroundStyle(Color.ballrBlack)

                Text(drill.subtitle)
                    .font(.ballr(size: 15, weight: .medium))
                    .foregroundStyle(Color.ballrBlack.opacity(0.7))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.ballr(size: 17, weight: .black))
                .foregroundStyle(Color.ballrOrange)
        }
        .padding(18)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.ballrBlack, lineWidth: 2)
        )
    }
}

private struct PracticeDrillStyle {
    let iconColor: Color
    let iconForeground: Color
    let accentColor: Color
    let symbol: String
    let playOpacity: Double

    init(index: Int) {
        switch index {
        case 0:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "figure.jump"
            playOpacity = 0.28
        case 1:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "figure.run"
            playOpacity = 0.28
        case 2:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "shoeprints.fill"
            playOpacity = 0.28
        case 3:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "snowflake"
            playOpacity = 0.28
        case 4:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "circle.fill"
            playOpacity = 1
        case 5:
            iconColor = .orange
            iconForeground = .white
            accentColor = .orange
            symbol = "play.fill"
            playOpacity = 0.28
        case 6:
            iconColor = .orange
            iconForeground = .white
            accentColor = .orange
            symbol = "play.fill"
            playOpacity = 0.28
        case 7:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "scope"
            playOpacity = 0.28
        case 8:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "person.2.fill"
            playOpacity = 0.28
        case 9:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "rectangle.split.3x1"
            playOpacity = 0.28
        case 10:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "rectangle.grid.3x3.fill"
            playOpacity = 0.28
        case 11:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "soccerball"
            playOpacity = 0.28
        case 12:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "figure.soccer"
            playOpacity = 0.28
        case 13:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "pianokeys"
            playOpacity = 0.28
        case 14:
            iconColor = .orange
            iconForeground = .white
            accentColor = .orange
            symbol = "scope"
            playOpacity = 0.28
        default:
            iconColor = Color.white.opacity(0.10)
            iconForeground = Color.white.opacity(0.38)
            accentColor = Color.white.opacity(0.32)
            symbol = "square.grid.2x2.fill"
            playOpacity = 0.18
        }
    }
}

private struct PracticeDrillFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct PracticeDifficultyPromptView: View {
    let drill: Drill
    let onSelectEasy: () -> Void
    let onSelectHard: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    Text("\(drill.title) - Choose difficulty")
                        .font(.ballr(size: 15, weight: .black))
                        .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)

                    Text(drill.subtitle)
                        .font(.ballr(size: 12, weight: .black))
                        .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11).opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 24)

                    HStack(spacing: 10) {
                        Button(action: onSelectEasy) {
                            Text("EASY")
                                .font(.ballr(size: 14, weight: .black))
                                .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button(action: onSelectHard) {
                            Text("HARD")
                                .font(.ballr(size: 14, weight: .black))
                                .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color(red: 1.0, green: 0.29, blue: 0.18), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.top, 14)
                .padding(.bottom, 14)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.ballr(size: 13, weight: .black))
                        .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .padding(.trailing, 4)
            }
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.78, green: 0.64, blue: 0.00))
                    .frame(height: 8)
                    .offset(y: 6)
            }

            TrianglePointer()
                .fill(Color(red: 0.78, green: 0.64, blue: 0.00))
                .frame(width: 18, height: 12)
        }
    }
}

private struct PracticeDrillCardView: View {
    let drill: Drill
    let style: PracticeDrillStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(style.iconColor)
                        .frame(width: 46, height: 46)

                    Image(systemName: style.symbol)
                        .font(.ballr(size: 21, weight: .black))
                        .foregroundStyle(style.iconForeground)
                }

                Spacer()

                Circle()
                    .fill(.white.opacity(style.playOpacity))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.ballr(size: 14, weight: .black))
                            .foregroundStyle(style.accentColor)
                            .offset(x: 1.5)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(drill.title)
                    .font(.ballr(size: 17, weight: .black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .fixedSize(horizontal: false, vertical: true)

                Text(drill.subtitle)
                    .font(.ballr(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .background(Color.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .stroke(style.accentColor.opacity(0.8), lineWidth: 2)
                .mask(
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct DrillPlaceholderView: View {
    let drill: Drill

    var body: some View {
        ZStack {
            BallrBackground()

            VStack(spacing: 20) {
                DiamondIcon()
                    .frame(width: 96, height: 96)

                Text(drill.title)
                    .font(.ballr(size: 34, weight: .black))

                Text("Camera drill view coming soon.")
                    .font(.ballr(size: 20, weight: .bold))
                    .foregroundStyle(Color.ballrBlack.opacity(0.75))

                Text("This placeholder screen keeps the navigation flow ready for the future camera experience.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ballrBlack.opacity(0.65))
                    .padding(.horizontal, 28)
            }
            .padding(24)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BallCardView: View {
    var body: some View {
        VStack(spacing: 16) {
            CrestShape()
                .fill(.white)
                .overlay(
                    CrestShape()
                        .stroke(Color.ballrBlack, lineWidth: 3)
                )
                .frame(height: 240)
                .overlay {
                    VStack(spacing: 12) {
                        Text("BALLR CARD")
                            .font(.ballr(size: 17, weight: .black))
                            .foregroundStyle(Color.ballrOrange)

                        ZStack {
                            Circle()
                                .fill(Color.ballrCream)
                                .frame(width: 96, height: 96)

                            Image(systemName: "figure.soccer")
                                .font(.ballr(size: 48, weight: .black))
                                .foregroundStyle(Color.ballrOrange)
                        }

                        Text("Rookie Striker")
                            .font(.ballr(size: 20, weight: .black))
                    }
                    .padding(.bottom, 14)
                }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 26))
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Color.ballrBlack, lineWidth: 2)
        )
    }
}

private struct BallrBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Color.ballrCream, Color.yellow.opacity(0.55), .white],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(Color.ballrYellow.opacity(0.22))
                .frame(width: 180, height: 180)
                .offset(x: 50, y: -30)
        }
        .overlay(alignment: .bottomLeading) {
            Circle()
                .fill(Color.ballrOrange.opacity(0.14))
                .frame(width: 220, height: 220)
                .offset(x: -60, y: 70)
        }
        .ignoresSafeArea()
    }
}

private struct BallrLogo: View {
    var body: some View {
        Text("Ballr")
            .font(.ballr(size: 36, weight: .black))
            .foregroundStyle(Color.ballrOrange)
    }
}

private struct TutorialCard: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.ballr(size: 22, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.ballrOrange, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.ballr(size: 17, weight: .black))

                Text(description)
                    .font(.ballr(size: 15, weight: .medium))
                    .foregroundStyle(Color.ballrBlack.opacity(0.75))
            }

            Spacer()
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.ballrBlack, lineWidth: 2)
        )
    }
}

private struct DiamondIcon: View {
    var body: some View {
        DiamondShape()
            .fill(Color.ballrOrange)
            .overlay(
                DiamondShape()
                    .stroke(.white, lineWidth: 3)
            )
    }
}

private struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct CrestShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18),
            control: CGPoint(x: rect.maxX * 0.78, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX * 0.86, y: rect.maxY * 0.72))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX * 0.76, y: rect.maxY * 0.94)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.14, y: rect.maxY * 0.72),
            control: CGPoint(x: rect.maxX * 0.24, y: rect.maxY * 0.94)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.18))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.maxX * 0.22, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

#Preview {
    ContentView()
}
