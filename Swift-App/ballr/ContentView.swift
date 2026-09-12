import AVFoundation
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

private extension Drill {
    var displayTitle: String {
        switch title {
        case "Hunter":
            return "The Hunter"
        case "Tic Tac Toe ShootingVS":
            return "Tic Tac Toe Shooting"
        default:
            return title
        }
    }
}

private struct AchievementSlot: Identifiable {
    let id = UUID()
}

private extension Color {
    static let ballrOrange = Color(red: 0.78, green: 0.27, blue: 0.07)
    static let ballrActiveOrange = Color(red: 253.0 / 255.0, green: 86.0 / 255.0, blue: 52.0 / 255.0)
    static let ballrNavYellow = Color(red: 1.0, green: 216.0 / 255.0, blue: 0.0)
    static let ballrYellow = Color(red: 0.98, green: 0.79, blue: 0.19)
    static let ballrCream = Color(red: 0.99, green: 0.97, blue: 0.91)
    static let ballrBlack = Color(red: 0.08, green: 0.08, blue: 0.08)
}

private struct MainBallrView: View {
    @State private var selectedTab: BallrTab = .practice
    @State private var hidesBottomNav = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .practice:
                    PracticeHomeView()
                case .levels:
                    LevelsHomeView(hidesBottomNav: $hidesBottomNav)
                case .profile:
                    ProfileHomeView()
                }
            }
            .padding(.bottom, 5)

            if !hidesBottomNav {
                BallrBottomNavBar(selectedTab: $selectedTab)
            }
        }
        .onChange(of: selectedTab) { _, _ in
            hidesBottomNav = false
        }
        .onAppear {
            BallrBackgroundAudioController.shared.activateMenuMusic(
                restartTrack: true,
                fadeInFromZero: true
            )
        }
    }
}

private struct BallrBottomNavBar: View {
    @Binding var selectedTab: BallrTab
    private let barSize = CGSize(width: 393, height: 82)

    var body: some View {
        GeometryReader { geometry in
            let bottomInset = geometry.safeAreaInsets.bottom

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Rectangle()
                        .fill(Color.ballrNavYellow)
                        .frame(width: barSize.width, height: barSize.height + bottomInset)

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
                    .frame(width: barSize.width, height: barSize.height)
                    .padding(.bottom, bottomInset)
                }
                .frame(height: barSize.height + bottomInset)
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

            }
            .onAppear {
                    withAnimation(.spring(response: 1.05, dampingFraction: 0.78).delay(0.20)) {
                        hasJoinedLogo = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.24) {
                        withAnimation(.easeInOut(duration: 0.34)) {
                            settledLogoOpacity = 1
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.62) {
                        isHidingSplitLogo = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.70) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            isDismissing = true
                        }
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        onFinished()
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
    @Binding private var hidesBottomNav: Bool
    @State private var selectedDrill: Drill?
    @State private var selectedHunterDifficulty: HunterDifficulty?
    @State private var promptedDrill: Drill?
    @State private var isShowingStreakResetMessage = false
    @State private var areMascotEntrancesEnabled = false
    @AppStorage("levelsDailyStreak") private var dailyStreak = 0
    @AppStorage("levelsLastPlayedAt") private var lastPlayedAt = 0.0

    private let currentLevel = 1
    private let lockedLevels = Set<Int>()

    init(hidesBottomNav: Binding<Bool> = .constant(false)) {
        _hidesBottomNav = hidesBottomNav
    }

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
                    return "The Hunter Easy"
                case 11:
                    return "Rock Drop Medium"
                case 12:
                    return "Toe Touches"
                case 13:
                    return "Jumping Challenge"
                case 14:
                    return "The Hunter Hard"
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
                    return ["Ball Targets", "First Touch", "Toe Touches"][(level - 1) % 3]
                }
            }(),
            level: level
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BallrAppBackground()

                GeometryReader { viewportProxy in
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LevelsMapView(
                                drills: levelDrills,
                                promptedDrill: promptedDrill,
                                currentLevel: currentLevel,
                                lockedLevels: lockedLevels,
                                viewportSize: viewportProxy.size,
                                entrancesEnabled: areMascotEntrancesEnabled
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
                                hidesBottomNav = true
                                selectedDrill = drill
                            } onSelectEasy: { drill in
                                updateStreakForLevelStart()
                                promptedDrill = nil
                                if drill.level == 20 {
                                    hidesBottomNav = true
                                    selectedHunterDifficulty = .easy
                                }
                            } onSelectHard: { drill in
                                updateStreakForLevelStart()
                                promptedDrill = nil
                                if drill.level == 20 {
                                    hidesBottomNav = true
                                    selectedHunterDifficulty = .hard
                                }
                            } onCancel: {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                    promptedDrill = nil
                                }
                            }
                            .frame(height: 2460)
                            .padding(.top, 136)
                            .padding(.bottom, 28)
                        }
                        .coordinateSpace(name: "levelsScrollViewport")
                        .onAppear {
                            areMascotEntrancesEnabled = false
                            proxy.scrollTo(1, anchor: .bottom)

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                areMascotEntrancesEnabled = true
                            }
                        }
                    }
                }

                BallrTopScreenHeader()
                    .zIndex(10)

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
            .fullScreenCover(item: $selectedDrill, onDismiss: {
                hidesBottomNav = false
            }) { drill in
                NavigationStack {
                    levelCameraView(for: drill)
                        .environment(\.ballrCountdownMascot, countdownMascot(for: drill.level))
                }
                .ballrCameraPresentationChrome()
            }
            .fullScreenCover(item: $selectedHunterDifficulty) { difficulty in
                HunterCameraView(difficulty: difficulty)
                    .ballrCameraPresentationChrome()
                    .environment(\.ballrCountdownMascot, BallrCountdownMascot.green)
            }
            .onChange(of: selectedDrill) { _, drill in
                hidesBottomNav = drill != nil
            }
            .onChange(of: selectedHunterDifficulty) { _, difficulty in
                hidesBottomNav = difficulty != nil
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

    @ViewBuilder
    private func levelCameraView(for drill: Drill) -> some View {
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

    private func countdownMascot(for level: Int?) -> BallrCountdownMascot? {
        guard let level else {
            return nil
        }

        switch level {
        case 1...3:
            return .pink
        case 4...6:
            return .orange
        case 7...9:
            return .purple
        case 10...12:
            return .blue
        case 13...15:
            return .yellow
        case 16...20:
            return .green
        default:
            return nil
        }
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
        Drill(title: "Fast Touching", subtitle: "Count every toe touch", level: nil),
        Drill(title: "Shooting Zones", subtitle: "Place a target box and score zones", level: nil),
        Drill(title: "Rock Drop", subtitle: "Dodge the falling rocks", level: nil),
        Drill(title: "Hunter", subtitle: "Escape the hunter", level: nil),
        Drill(title: "Passing Cones", subtitle: "Pass through the cones", level: nil),
        Drill(title: "Piano Tiles", subtitle: "Hit every tile", level: nil),
        Drill(title: "Agility Challenge", subtitle: "Cross side to side fast", level: nil),
        Drill(title: "Crossbar Challenge", subtitle: "Hit the bar and posts", level: nil),
        Drill(title: "Ball Magician", subtitle: "Follow the arrows", level: nil),
        Drill(title: "Jumping Challenge", subtitle: "Jump over the hurdles", level: nil),
        Drill(title: "Precision VS", subtitle: "Alternate 5 shots each", level: nil),
        Drill(title: "Tic Tac Toe ShootingVS", subtitle: "Shoot tiles to claim Xs and Os", level: nil)
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
                PurpleCircleDrillIntroScreen(
                    title: "Jumping Challenge",
                    subtitle: "Jump over the hurdles",
                    onBeforeCamera: {}
                ) {
                    JumpingChallengeCameraView(targetsFootX: true)
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.purple)
                }
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingAgilityChallenge) {
                PurpleCircleDrillIntroScreen(
                    title: "Agility Challenge",
                    subtitle: "Cross side to side fast",
                    onBeforeCamera: {
                        BallrOrientationController.lockDribblingLandscape()
                    }
                ) {
                    AgilityChallengeCameraView()
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.purple)
                }
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingFastTouching) {
                FastTouchingIntroScreen()
                    .environment(\.ballrCountdownMascot, BallrCountdownMascot.orange)
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingBallMagician) {
                PurpleCircleDrillIntroScreen(
                    title: "Ball Magician",
                    subtitle: "Follow the arrows",
                    characterColor: Color(red: 0x11 / 255.0, green: 0xB9 / 255.0, blue: 0xEC / 255.0),
                    strokeColor: Color(red: 0x08 / 255.0, green: 0x71 / 255.0, blue: 0x91 / 255.0),
                    cardColor: Color(red: 0x08 / 255.0, green: 0x71 / 255.0, blue: 0x91 / 255.0),
                    onBeforeCamera: {}
                ) {
                    LevelSevenCameraView()
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.blue)
                }
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(item: $selectedDrill) { drill in
                DrillPlaceholderView(drill: drill)
            }
            .fullScreenCover(item: $selectedRockDropDifficulty) { difficulty in
                PinkRoundedDrillIntroScreen(
                    title: "Rock Drop",
                    subtitle: "Dodge the falling rocks"
                ) {
                    BallBlastRockDropCameraView(difficulty: difficulty)
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.pink)
                        .ballrCompletionXPAward(20)
                }
            }
            .fullScreenCover(item: $selectedPianoTilesDifficulty) { difficulty in
                PinkRoundedDrillIntroScreen(
                    title: "Piano Tiles",
                    subtitle: "Hit every tile"
                ) {
                    PianoTilesCameraView(difficulty: difficulty)
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.pink)
                        .ballrCompletionXPAward(20)
                }
            }
            .fullScreenCover(item: $selectedHunterDifficulty) { difficulty in
                PurpleCircleDrillIntroScreen(
                    title: "The Hunter",
                    subtitle: "Escape the hunter",
                    characterColor: Color(red: 0x11 / 255.0, green: 0xB9 / 255.0, blue: 0xEC / 255.0),
                    strokeColor: Color(red: 0x08 / 255.0, green: 0x71 / 255.0, blue: 0x91 / 255.0),
                    cardColor: Color(red: 0x08 / 255.0, green: 0x71 / 255.0, blue: 0x91 / 255.0),
                    onBeforeCamera: {}
                ) {
                    HunterCameraView(difficulty: difficulty)
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.blue)
                }
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingPrecisionTargets) {
                PrecisionTargetIntroScreen(
                    title: "Precision Target",
                    subtitle: "Hit the wall Target"
                ) {
                    PrecisionTargetCameraView()
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.green)
                }
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingMultiplayerPrecisionTargets) {
                PrecisionTargetIntroScreen(
                    title: "Precision VS",
                    subtitle: "Alternate 5 shots each"
                ) {
                    MultiplayerPrecisionTargetCameraView()
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.green)
                }
                    .ballrCompletionXPAward(20)
            }
            .fullScreenCover(isPresented: $isShowingShootingZones) {
                YellowDrillIntroScreen(
                    title: "Shooting Zones",
                    subtitle: "Place a target box and score zones"
                ) {
                    ShootingZonesCameraView()
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.yellow)
                        .ballrCompletionXPAward(20)
                }
            }
            .fullScreenCover(isPresented: $isShowingTicTacToeShootingVS) {
                YellowDrillIntroScreen(
                    title: "Tic Tac Toe Shooting",
                    subtitle: "Shoot tiles to claim Xs and Os",
                    showsFlipPromptText: false
                ) {
                    TicTacToeShootingVSCameraView()
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.yellow)
                        .ballrCompletionXPAward(20)
                }
            }
            .fullScreenCover(isPresented: $isShowingCrossbarChallenge) {
                YellowDrillIntroScreen(
                    title: "Crossbar Challenge",
                    subtitle: "Hit the bar and posts"
                ) {
                    CrossbarChallengeCameraView()
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.yellow)
                        .ballrCompletionXPAward(20)
                }
            }
            .fullScreenCover(isPresented: $isShowingPassingCones) {
                YellowDrillIntroScreen(
                    title: "Passing Cones",
                    subtitle: "Pass through the cones"
                ) {
                    PassingConesCameraView()
                        .ballrCameraPresentationChrome()
                        .environment(\.ballrCountdownMascot, BallrCountdownMascot.yellow)
                        .ballrCompletionXPAward(20)
                }
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
    @Environment(\.colorScheme) private var colorScheme

    let drills: [Drill]
    @Binding var selectedIndex: Int
    let onPlay: (Drill) -> Void

    @State private var dragTranslation: CGFloat = 0
    @State private var isCarouselModeEnabled = true

    private let cardYellow = Color(red: 255.0 / 255.0, green: 216.0 / 255.0, blue: 0.0 / 255.0)
    private let inactiveCardSize = CGSize(width: 330, height: 440)
    private let activeCardSize = CGSize(width: 330, height: 476)
    private let compactCardSize = CGSize(width: 329, height: 127)
    private let cardSpacing: CGFloat = 12
    private let inactiveBottomPanelHeight: CGFloat = 102.93
    private let activeBottomPanelHeight: CGFloat = 126.93
    private let triangleHeight: CGFloat = 212.64
    private let compactTriangleHeight: CGFloat = 87.33

    private var isDarkModeEnabled: Bool {
        colorScheme == .dark
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .ballrDarkModeBackground : .ballrLightModeBackground
    }

    private var cardShadowColor: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 215.0 / 255.0, blue: 0.0) : .black
    }

    private var cardShadowOpacity: Double {
        colorScheme == .dark ? 0.30 : 0.22
    }

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
            let headerLift: CGFloat = 18
            let switchSize = CGSize(width: 52, height: 28)
            let headerDividerY = max(headerTop + 60, switchTop + 42) - headerLift
            let listHeight = max(0, geometry.size.height - headerDividerY)
            let listTopPadding = max(0, max(headerTop + 100, switchTop + 82) - headerLift - headerDividerY)
            let pageStride = inactiveCardSize.width + cardSpacing
            let visibleOffsets = carouselVisibleOffsets
            let boundedDrag = boundedDragTranslation(dragTranslation, pageStride: pageStride)
            let isShowingCarouselScreen = isCarouselModeEnabled
            let isShowingCompactScreen = !isCarouselModeEnabled

            ZStack {
                if isShowingCarouselScreen {
                    ZStack {
                        ForEach(visibleOffsets, id: \.self) { offset in
                            let index = wrappedCarouselIndex(selectedIndex + offset)

                            PracticeCarouselCardSlot(
                                drill: drills[index],
                                slotOffset: offset,
                                dragTranslation: dragTranslation,
                                boundedDrag: boundedDrag,
                                center: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2),
                                pageStride: pageStride,
                                inactiveCardSize: inactiveCardSize,
                                activeCardSize: activeCardSize,
                                panelGradient: panelGradient,
                                triangleHeight: triangleHeight,
                                inactiveBottomPanelHeight: inactiveBottomPanelHeight,
                                activeBottomPanelHeight: activeBottomPanelHeight,
                                shadowColor: cardShadowColor,
                                shadowOpacity: cardShadowOpacity,
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
                                let direction: Int
                                let nextIndex: Int

                                if value.translation.width < -threshold {
                                    direction = 1
                                    nextIndex = wrappedCarouselIndex(selectedIndex + 1)
                                } else if value.translation.width > threshold {
                                    direction = -1
                                    nextIndex = wrappedCarouselIndex(selectedIndex - 1)
                                } else {
                                    direction = 0
                                    nextIndex = selectedIndex
                                }

                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    selectedIndex = nextIndex
                                    dragTranslation = endingDrag + CGFloat(direction) * pageStride
                                }

                                withAnimation(.interactiveSpring(response: 0.48, dampingFraction: 0.90, blendDuration: 0.12)) {
                                    dragTranslation = 0
                                }
                            }
                    )
                } else if isShowingCompactScreen {
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
                                        triangleHeight: compactTriangleHeight,
                                        shadowColor: cardShadowColor,
                                        shadowOpacity: cardShadowOpacity
                                    )
                                }
                                .buttonStyle(NoPressedAppearanceButtonStyle())
                            }
                        }
                        .padding(.top, listTopPadding)
                        .padding(.bottom, 104)
                    }
                    .frame(width: geometry.size.width, height: listHeight)
                    .clipped()
                    .position(x: geometry.size.width / 2, y: headerDividerY + listHeight / 2)
                    .transition(.opacity)
                    .zIndex(0)
                }

                BallrTopScreenHeader(showsCover: isShowingCompactScreen) {
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
                        .frame(width: switchSize.width, height: switchSize.height)
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .zIndex(5)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .accessibilityElement(children: .contain)
        }
    }

    private func boundedDragTranslation(_ translation: CGFloat, pageStride: CGFloat) -> CGFloat {
        drills.count > 1 ? translation : 0
    }

    private var carouselVisibleOffsets: [Int] {
        let largestOffset = min(2, max(drills.count - 1, 0))
        return Array((-largestOffset)...largestOffset)
    }

    private func wrappedCarouselIndex(_ index: Int) -> Int {
        guard !drills.isEmpty else { return 0 }
        return (index % drills.count + drills.count) % drills.count
    }
}

private struct PracticeCarouselCardSlot: View {
    let drill: Drill
    let slotOffset: Int
    let dragTranslation: CGFloat
    let boundedDrag: CGFloat
    let center: CGPoint
    let pageStride: CGFloat
    let inactiveCardSize: CGSize
    let activeCardSize: CGSize
    let panelGradient: LinearGradient
    let triangleHeight: CGFloat
    let inactiveBottomPanelHeight: CGFloat
    let activeBottomPanelHeight: CGFloat
    let shadowColor: Color
    let shadowOpacity: Double
    let onPlay: () -> Void

    private var xPosition: CGFloat {
        center.x + CGFloat(slotOffset) * pageStride + boundedDrag
    }

    private var visualDistance: CGFloat {
        abs((xPosition - center.x) / pageStride)
    }

    private var activeProgress: CGFloat {
        max(0, min(1, 1 - visualDistance))
    }

    private var cardSize: CGSize {
        CGSize(
            width: inactiveCardSize.width,
            height: inactiveCardSize.height + (activeCardSize.height - inactiveCardSize.height) * activeProgress
        )
    }

    private var bottomPanelHeight: CGFloat {
        inactiveBottomPanelHeight + (activeBottomPanelHeight - inactiveBottomPanelHeight) * activeProgress
    }

    var body: some View {
        PracticeHomeDrillCard(
            drill: drill,
            cardSize: cardSize,
            panelGradient: panelGradient,
            triangleHeight: triangleHeight,
            bottomPanelHeight: bottomPanelHeight,
            isSelected: slotOffset == 0 && abs(dragTranslation) < 8,
            shadowColor: shadowColor,
            shadowOpacity: shadowOpacity,
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
    let shadowColor: Color
    let shadowOpacity: Double

    private let cardYellow = Color(red: 255.0 / 255.0, green: 216.0 / 255.0, blue: 0.0 / 255.0)
    private let playCircle = Color(red: 0.244, green: 0.244, blue: 0.244)
    private let characterTopPadding: CGFloat = 2

    private var characterAssetName: String? {
        if ["Precision Targets", "Precision VS"].contains(drill.title) {
            return "green1"
        } else if drill.title == "Fast Touching" {
            return "orange1"
        } else if drill.title == "Agility Challenge" {
            return "purple1"
        } else if drill.title == "Jumping Challenge" {
            return "purple"
        } else if ["Hunter", "Ball Magician"].contains(drill.title) {
            return "blue"
        } else if ["Shooting Zones", "Crossbar Challenge", "Tic Tac Toe ShootingVS", "Passing Cones"].contains(drill.title) {
            return "yellow"
        } else if ["Rock Drop", "Piano Tiles"].contains(drill.title) {
            return "pink"
        }

        return nil
    }

    private var characterSize: CGSize {
        switch drill.title {
        case "Precision Targets":
            CGSize(width: 97.48, height: 111)
        case "Precision VS":
            CGSize(width: 93, height: 110)
        case "Fast Touching":
            CGSize(width: 91.09, height: 109.48)
        case "Agility Challenge", "Jumping Challenge":
            CGSize(width: 104, height: 108)
        case "Hunter", "Ball Magician":
            CGSize(width: 97.48, height: 111)
        case "Shooting Zones", "Crossbar Challenge", "Tic Tac Toe ShootingVS", "Passing Cones":
            CGSize(width: 104, height: 111)
        case "Rock Drop", "Piano Tiles":
            CGSize(width: 106, height: 111)
        default:
            .zero
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(cardYellow)

            if let characterAssetName {
                Image(characterAssetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: characterSize.width, height: characterSize.height)
                    .position(x: 101, y: characterTopPadding + characterSize.height / 2)
            }

            panelGradient
                .frame(width: cardSize.width, height: triangleHeight)
                .mask {
                    PracticeCompactCardTriangleShape()
                }

            Text(drill.displayTitle)
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
        .shadow(
            color: shadowColor.opacity(shadowOpacity),
            radius: 12,
            x: 0,
            y: 8
        )
    }
}

private struct NoPressedAppearanceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
    let drill: Drill
    let cardSize: CGSize
    let panelGradient: LinearGradient
    let triangleHeight: CGFloat
    let bottomPanelHeight: CGFloat
    let isSelected: Bool
    let shadowColor: Color
    let shadowOpacity: Double
    let onPlay: () -> Void

    @State private var isCardPressed = false

    private var titleText: String {
        switch drill.title {
        case "Precision Targets":
            "Precision\ntargets"
        case "Fast Touching":
            "Fast\nTouching"
        case "Shooting Zones":
            "Shooting\nZones"
        case "Rock Drop":
            "Rock\nDrop"
        case "Hunter":
            "The\nHunter"
        case "Passing Cones":
            "Passing\nCones"
        case "Piano Tiles":
            "Piano\nTiles"
        case "Agility Challenge":
            "Agility\nChallenge"
        case "Crossbar Challenge":
            "Crossbar\nChallenge"
        case "Ball Magician":
            "Ball\nMagician"
        case "Jumping Challenge":
            "Jumping\nChallenge"
        case "Precision VS":
            "Precision\nVS"
        case "Tic Tac Toe ShootingVS":
            "Tic Tac Toe\nShooting"
        default:
            drill.displayTitle
        }
    }

    private var usesPink2Character: Bool {
        drill.title == "Rock Drop" || drill.title == "Piano Tiles"
    }

    private var usesOrangeCutCharacter: Bool {
        drill.title == "Fast Touching"
    }

    private var usesPurpleCutCharacter: Bool {
        drill.title == "Agility Challenge" || drill.title == "Jumping Challenge"
    }

    private var usesYellowCutCharacter: Bool {
        drill.title == "Shooting Zones"
            || drill.title == "Passing Cones"
            || drill.title == "Crossbar Challenge"
            || drill.title == "Tic Tac Toe ShootingVS"
    }

    private var usesGreenCutCharacter: Bool {
        drill.title == "Precision Targets" || drill.title == "Precision VS"
    }

    private var usesBlueCutCharacter: Bool {
        drill.title == "Hunter" || drill.title == "Ball Magician"
    }

    private var characterCenterY: CGFloat {
        if usesPink2Character {
            return 216
        }

        if usesOrangeCutCharacter {
            return 213
        }

        if usesPurpleCutCharacter {
            return 238
        }

        if usesYellowCutCharacter {
            return 217
        }

        if usesGreenCutCharacter {
            return 219
        }

        if usesBlueCutCharacter {
            return 219
        }

        return 201
    }

    private func playSelectedCard() {
        guard isSelected, !isCardPressed else { return }

        withAnimation(.easeInOut(duration: 0.10)) {
            isCardPressed = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                isCardPressed = false
            }
            onPlay()
        }
    }

    var body: some View {
        let panelHeight = triangleHeight + bottomPanelHeight
        let titleCenterY = cardSize.height - 100
        let subtitleCenterY = cardSize.height - 30
        let playButtonCenterY = cardSize.height - 100
        let textCenterX: CGFloat = 138
        let textWidth: CGFloat = 205

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(red: 1.0, green: 0.847, blue: 0.0))

            Image("cardTile")
                .resizable()
                .frame(width: 268, height: 314)
                .position(x: cardSize.width / 2, y: 199)

            PracticeHomeLargeCharacterView(drillTitle: drill.title)
                .frame(width: 171, height: 179)
                .position(x: cardSize.width / 2, y: characterCenterY)

            panelGradient
                .frame(width: cardSize.width, height: panelHeight)
                .mask {
                    PracticeCardBottomPanelShape(
                        triangleHeight: triangleHeight,
                        rectangleHeight: bottomPanelHeight,
                        cornerRadius: 31,
                        rightTopInset: 34
                    )
                }

            PracticeHomeLargeCharacterView(drillTitle: drill.title)
                .frame(width: 171, height: 179)
                .position(x: cardSize.width / 2, y: characterCenterY)
                .mask {
                    if usesPink2Character {
                        PracticePink2CharacterVisibleMask()
                    } else if usesOrangeCutCharacter {
                        PracticeOrangeCutCharacterVisibleMask()
                    } else if usesPurpleCutCharacter {
                        PracticePurpleCutCharacterVisibleMask()
                    } else if usesYellowCutCharacter {
                        PracticeYellowCutCharacterVisibleMask()
                    } else if usesGreenCutCharacter {
                        PracticeGreenCutCharacterVisibleMask()
                    } else if usesBlueCutCharacter {
                        PracticeBlueCutCharacterVisibleMask()
                    } else {
                        PracticeCharacterVisibleMask()
                    }
                }

            Text(titleText)
                .font(.ballr(size: 36, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.58)
                .foregroundStyle(Color.black)
                .frame(width: textWidth, alignment: .leading)
                .position(x: textCenterX, y: titleCenterY)

            Text(drill.subtitle)
                .font(.ballr(size: 14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
                .foregroundStyle(Color.black)
                .frame(width: textWidth, alignment: .leading)
                .position(x: textCenterX, y: subtitleCenterY)

            ZStack {
                Circle()
                    .fill(Color(red: 0.244, green: 0.244, blue: 0.244))

                Image(systemName: "play.fill")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(Color(red: 1.0, green: 0.847, blue: 0.0))
            }
            .frame(width: 73, height: 73)
            .position(x: 260, y: playButtonCenterY)
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .scaleEffect(isCardPressed ? 0.972 : 1.0)
        .offset(y: isCardPressed ? 4 : 0)
        .shadow(
            color: shadowColor.opacity(isCardPressed ? shadowOpacity * 0.72 : shadowOpacity),
            radius: isCardPressed ? 7 : 18,
            x: 0,
            y: isCardPressed ? 3 : 12
        )
        .animation(.easeInOut(duration: 0.10), value: isCardPressed)
        .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .onTapGesture {
            playSelectedCard()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Start \(drill.displayTitle)")
    }
}

private struct PracticeHomeLargeCharacterView: View {
    let drillTitle: String

    private var usesPink2Asset: Bool {
        drillTitle == "Rock Drop" || drillTitle == "Piano Tiles"
    }

    private var usesOrangeCutAsset: Bool {
        drillTitle == "Fast Touching"
    }

    private var usesPurpleCutAsset: Bool {
        drillTitle == "Agility Challenge" || drillTitle == "Jumping Challenge"
    }

    private var usesYellowCutAsset: Bool {
        drillTitle == "Shooting Zones"
            || drillTitle == "Passing Cones"
            || drillTitle == "Crossbar Challenge"
            || drillTitle == "Tic Tac Toe ShootingVS"
    }

    private var usesGreenCutAsset: Bool {
        drillTitle == "Precision Targets" || drillTitle == "Precision VS"
    }

    private var usesBlueCutAsset: Bool {
        drillTitle == "Hunter" || drillTitle == "Ball Magician"
    }

    var body: some View {
        if usesPink2Asset {
            Image("pink2")
                .resizable()
                .scaledToFit()
        } else if usesOrangeCutAsset {
            Image("orangecu")
                .resizable()
                .scaledToFit()
        } else if usesPurpleCutAsset {
            Image("purplecut")
                .resizable()
                .scaledToFit()
        } else if usesYellowCutAsset {
            Image("yellowcut")
                .resizable()
                .scaledToFit()
        } else if usesGreenCutAsset {
            Image("greencut")
                .resizable()
                .scaledToFit()
        } else if usesBlueCutAsset {
            Image("bluecut")
                .resizable()
                .scaledToFit()
        } else {
            PracticeCharacterView()
        }
    }
}

private struct PracticeCardBottomPanelShape: Shape {
    let triangleHeight: CGFloat
    let rectangleHeight: CGFloat
    let cornerRadius: CGFloat
    let rightTopInset: CGFloat

    func path(in rect: CGRect) -> Path {
        let panelTopY = rect.minY + triangleHeight
        let radius = min(cornerRadius, rectangleHeight / 2, rect.width / 2)
        let rightTopY = rect.minY + min(max(0, rightTopInset), triangleHeight * 0.45)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: panelTopY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rightTopY))
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

private struct PracticePink2CharacterVisibleMask: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 171.0
        let scaleY = rect.height / 179.0
        let cutRightX: CGFloat = 44.04

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
        path.addLine(to: point(cutRightX, 156.574))
        path.addLine(to: point(0, 175.728))
        path.closeSubpath()

        return path
    }
}

private struct PracticeOrangeCutCharacterVisibleMask: Shape {
    func path(in rect: CGRect) -> Path {
        let sourceWidth: CGFloat = 154
        let sourceHeight: CGFloat = 192
        let fittedWidth = rect.height * sourceWidth / sourceHeight
        let xInset = max(0, (rect.width - fittedWidth) / 2)
        let scale = rect.height / sourceHeight
        let cutRightSourceX: CGFloat = 40
        let cutRightSourceY: CGFloat = 138

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + xInset + x * scale,
                y: rect.minY + y * scale
            )
        }

        var path = Path()
        let cutRightX = point(cutRightSourceX, 0).x

        path.addRect(CGRect(
            x: cutRightX,
            y: rect.minY,
            width: rect.maxX - cutRightX,
            height: rect.height
        ))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: cutRightX, y: rect.minY))
        path.addLine(to: point(cutRightSourceX, cutRightSourceY))
        path.addLine(to: point(0, 192))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private struct PracticePurpleCutCharacterVisibleMask: Shape {
    func path(in rect: CGRect) -> Path {
        let sourceWidth: CGFloat = 175
        let sourceHeight: CGFloat = 181
        let scale = min(rect.width / sourceWidth, rect.height / sourceHeight)
        let fittedWidth = sourceWidth * scale
        let fittedHeight = sourceHeight * scale
        let xInset = max(0, (rect.width - fittedWidth) / 2)
        let yInset = max(0, (rect.height - fittedHeight) / 2)
        let cutRightSourceX: CGFloat = 42.007
        let cutRightSourceY: CGFloat = 137.681
        let cutLeftSourceY: CGFloat = 155.902

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + xInset + x * scale,
                y: rect.minY + yInset + y * scale
            )
        }

        var path = Path()
        let cutRightX = point(cutRightSourceX, 0).x

        path.addRect(CGRect(
            x: cutRightX,
            y: rect.minY,
            width: rect.maxX - cutRightX,
            height: rect.height
        ))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: cutRightX, y: rect.minY))
        path.addLine(to: point(cutRightSourceX, cutRightSourceY))
        path.addLine(to: point(0, cutLeftSourceY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private struct PracticeYellowCutCharacterVisibleMask: Shape {
    func path(in rect: CGRect) -> Path {
        let sourceWidth: CGFloat = 175
        let sourceHeight: CGFloat = 188
        let scale = min(rect.width / sourceWidth, rect.height / sourceHeight)
        let fittedWidth = sourceWidth * scale
        let fittedHeight = sourceHeight * scale
        let xInset = max(0, (rect.width - fittedWidth) / 2)
        let yInset = max(0, (rect.height - fittedHeight) / 2)
        let cutRightSourceX: CGFloat = 43.9
        let cutRightSourceY: CGFloat = 161.4
        let cutLeftSourceY: CGFloat = 180.6

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + xInset + x * scale,
                y: rect.minY + yInset + y * scale
            )
        }

        var path = Path()
        let cutRightX = point(cutRightSourceX, 0).x

        path.addRect(CGRect(
            x: cutRightX,
            y: rect.minY,
            width: rect.maxX - cutRightX,
            height: rect.height
        ))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: cutRightX, y: rect.minY))
        path.addLine(to: point(cutRightSourceX, cutRightSourceY))
        path.addLine(to: point(0, cutLeftSourceY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private struct PracticeGreenCutCharacterVisibleMask: Shape {
    func path(in rect: CGRect) -> Path {
        let sourceWidth: CGFloat = 157
        let sourceHeight: CGFloat = 189
        let scale = min(rect.width / sourceWidth, rect.height / sourceHeight)
        let fittedWidth = sourceWidth * scale
        let fittedHeight = sourceHeight * scale
        let xInset = max(0, (rect.width - fittedWidth) / 2)
        let yInset = max(0, (rect.height - fittedHeight) / 2)
        let cutRightSourceX: CGFloat = 32.582
        let cutRightSourceY: CGFloat = 162.615
        let cutLeftSourceY: CGFloat = 184.0

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + xInset + x * scale,
                y: rect.minY + yInset + y * scale
            )
        }

        var path = Path()
        let cutRightX = point(cutRightSourceX, 0).x

        path.addRect(CGRect(
            x: cutRightX,
            y: rect.minY,
            width: rect.maxX - cutRightX,
            height: rect.height
        ))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: cutRightX, y: rect.minY))
        path.addLine(to: point(cutRightSourceX, cutRightSourceY))
        path.addLine(to: point(0, cutLeftSourceY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private struct PracticeBlueCutCharacterVisibleMask: Shape {
    func path(in rect: CGRect) -> Path {
        let sourceWidth: CGFloat = 171
        let sourceHeight: CGFloat = 194
        let scale = min(rect.width / sourceWidth, rect.height / sourceHeight)
        let fittedWidth = sourceWidth * scale
        let fittedHeight = sourceHeight * scale
        let xInset = max(0, (rect.width - fittedWidth) / 2)
        let yInset = max(0, (rect.height - fittedHeight) / 2)
        let cutRightSourceX: CGFloat = 38.365
        let cutRightSourceY: CGFloat = 166.075
        let cutLeftSourceY: CGFloat = 189.0

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + xInset + x * scale,
                y: rect.minY + yInset + y * scale
            )
        }

        var path = Path()
        let cutRightX = point(cutRightSourceX, 0).x

        path.addRect(CGRect(
            x: cutRightX,
            y: rect.minY,
            width: rect.maxX - cutRightX,
            height: rect.height
        ))

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: cutRightX, y: rect.minY))
        path.addLine(to: point(cutRightSourceX, cutRightSourceY))
        path.addLine(to: point(0, cutLeftSourceY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
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
        case "Hunter":
            return "The Hunter"
        case "Tic Tac Toe ShootingVS":
            return "Tic Tac Toe\nShooting"
        default:
            return drill.displayTitle
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
                        .font(.ballr(size: 33, weight: .bold))
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
                    .padding(.top, 96)
                    .padding(.bottom, 34)
                }

                BallrTopScreenHeader {
                    NavigationLink {
                        BallrSettingsView()
                    } label: {
                        ProfileSettingsMenuIcon()
                    }
                    .buttonStyle(.plain)
                }
                .zIndex(10)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

private struct ProfileSettingsMenuIcon: View {
    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.yellow)
                    .frame(width: 49, height: 6)
            }
        }
        .frame(width: 49, height: 26)
        .contentShape(Rectangle())
    }
}

private struct DrillIntroFlipPromptView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var promptColor: Color {
        colorScheme == .dark ? .white : .black
    }

    var body: some View {
        GeometryReader { geometry in
            Text("FLIP THE\nPHONE")
                .font(.ballr(size: 38, weight: .black))
                .tracking(1.6)
                .lineSpacing(10)
                .foregroundStyle(promptColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

private struct JumpingChallengeIntroScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = true
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0
    @State private var showsFlipPrompt = false
    @State private var hasFlippedPhone = false

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
            showsFlipPrompt = false
                hasFlippedPhone = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        showsFlipPrompt = false
                hasFlippedPhone = false
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
            let characterEntryOffset = hasAnimatedCharacter ? 0 : height * (isLandscape ? 0.96 : 0.94)
            let launchDropOffset = isLaunchingDrill ? height * (isLandscape ? 0.52 : 0.62) : 0
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let shapeOffset = characterEntryOffset + launchDropOffset
            let shapeScaleX = entryScale
            let shapeScaleY = entryScale
            let contentOffset = characterEntryOffset + launchDropOffset
            let faceOpacity: CGFloat = 1.0
            let faceScale: CGFloat = 1.0
            let faceLift: CGFloat = 0.0
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
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

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
                .padding(.top, max(0, safeTop - 48))
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
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                    Button {
                        guard !isLaunchingDrill else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCardPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isCardPressed = false
                            }
                            withAnimation(.easeInOut(duration: 1.05)) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    showsFlipPrompt = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
                                withAnimation(.easeInOut(duration: 0.58)) {
                                    hasFlippedPhone = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
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
                    .opacity(1.0)
                    .accessibilityLabel("Start Jumping Challenge")

                    Spacer(minLength: safeBottom + 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: contentOffset)
                .animation(.spring(response: 0.72, dampingFraction: 0.80), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                if showsFlipPrompt {
                    DrillIntroFlipPromptView()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.28), value: showsFlipPrompt)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            resetLaunchState()
        }) {
            JumpingChallengeCameraView(targetsFootX: true)
                .ballrCameraPresentationChrome()
                .environment(\.ballrCountdownMascot, BallrCountdownMascot.purple)
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
    @State private var hasFlippedPhone = false

    private let characterOrange = Color(red: 1.0, green: 0.60, blue: 0.0)
    private let cardOrange = Color(red: 1.0, green: 0.76, blue: 0.36)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchDuration = 1.05

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let base = min(width, height)
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let launchProgress: CGFloat = isLaunchingAgility ? 1 : 0
            let characterDrop = height * (isLandscape ? 0.45 : 0.53) * launchProgress
            let cardDrop: CGFloat = 0
            let finalCharacterScaleY: CGFloat = 1.0
            let finalFaceDrop: CGFloat = 0
            let topContentSpacer = isLandscape ? height * 0.215 : height * 0.275
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
                .padding(.top, max(0, safeTop - 48))
                .padding(.leading, 18)
                .opacity(isLaunchingAgility ? 0 : 1)

                if showsFlipPrompt {
                    DrillIntroFlipPromptView()
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
            hasFlippedPhone = false
        }) {
            AgilityChallengeCameraView()
                .ballrCameraPresentationChrome()
                .environment(\.ballrCountdownMascot, BallrCountdownMascot.purple)
        }
        .onAppear {
            isLaunchingAgility = false
            showsFlipPrompt = false
            hasFlippedPhone = false
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

        DispatchQueue.main.asyncAfter(deadline: .now() + launchDuration + 0.25) {
            withAnimation(.easeInOut(duration: 0.58)) {
                hasFlippedPhone = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + launchDuration + 0.50) {
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

private struct PurpleCircleDrillIntroScreen<CameraContent: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    var characterColor = Color(red: 0xA1 / 255.0, green: 0x70 / 255.0, blue: 0xC5 / 255.0)
    var strokeColor = Color(red: 0x76 / 255.0, green: 0x4E / 255.0, blue: 0x8F / 255.0)
    var cardColor = Color(red: 0x7D / 255.0, green: 0x54 / 255.0, blue: 0x97 / 255.0)
    let onBeforeCamera: () -> Void
    @ViewBuilder let cameraContent: () -> CameraContent

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0
    @State private var didPlayIntroAnimation = false
    @State private var showsFlipPrompt = false
    @State private var hasFlippedPhone = false

    private let eyeWhite = Color(red: 0.96, green: 0.95, blue: 0.95)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            showsFlipPrompt = false
                hasFlippedPhone = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        showsFlipPrompt = false
                hasFlippedPhone = false
            }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let base = min(width, height)
            let characterEntryOffset = hasAnimatedCharacter ? 0 : height * (isLandscape ? 0.96 : 0.94)
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let characterScaleX = 1.0
            let characterScaleY = entryScale
            let circleWidth = isLandscape ? min(width * 0.60, 426.0) : 426.0
            let circleHeight = isLandscape ? min(height * 0.84, 406.0) : 406.0
            let circleTopY = isLandscape ? max(safeTop + 8, height * 0.035) : 60.0
            let circleCenterY = circleTopY + circleHeight / 2
            let strokeMaskHeight = circleHeight * 0.52
            let bodyRectTopY = circleTopY + (isLandscape ? circleHeight * 0.50 : 217.0)
            let bodyRectWidth = isLandscape ? min(width + 48, 568.0) : width + 48
            let bodyRectHeight = isLandscape ? height : max(574.0, height - bodyRectTopY + 2)
            let eyeSize = isLandscape ? base * 0.14 : 94.0
            let eyeCenterY = circleTopY + (isLandscape ? circleHeight * 0.42 : 181.0)
            let eyeSpacing = isLandscape ? base * 0.19 : 137.0
            let leftEyeX = width / 2 - eyeSpacing / 2
            let rightEyeX = width / 2 + eyeSpacing / 2
            let mouthSize = isLandscape ? base * 0.075 : 53.0
            let mouthCenterY = circleTopY + (isLandscape ? circleHeight * 0.64 : 276.0)
            let cardWidth = isLandscape ? min(width * 0.34, 320) : 281.0
            let cardHeight = isLandscape ? min(height * 0.44, 230) : 277.0
            let cardTopY = bodyRectTopY + (isLandscape ? height * 0.16 : 138.0)
            let cardCenterY = cardTopY + cardHeight / 2
            let launchDropOffset = isLaunchingDrill ? max(0, height - cardTopY + (isLandscape ? 42.0 : 52.0)) : 0
            let contentOffsetY = characterEntryOffset + introBounceOffset + launchDropOffset

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                ZStack {
                    Rectangle()
                        .fill(characterColor)
                        .frame(width: bodyRectWidth, height: bodyRectHeight)
                        .position(x: width / 2, y: bodyRectTopY + bodyRectHeight / 2)

                    Ellipse()
                        .fill(characterColor)
                        .frame(width: circleWidth, height: circleHeight)
                        .position(x: width / 2, y: circleCenterY)

                    Ellipse()
                        .strokeBorder(strokeColor, lineWidth: 10)
                        .frame(width: circleWidth, height: circleHeight)
                        .mask(alignment: .top) {
                            Rectangle()
                                .frame(width: circleWidth + 20, height: strokeMaskHeight)
                        }
                        .position(x: width / 2, y: circleCenterY)
                }
                .frame(width: width, height: height)
                .offset(y: contentOffsetY)
                .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

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
                .padding(.top, max(0, safeTop - 48))
                .padding(.leading, 18)

                PurpleLashEyeView(
                    eyeSize: eyeSize,
                    blackColor: logoBlack,
                    highlightColor: eyeWhite
                )
                .position(x: leftEyeX, y: eyeCenterY)
                .offset(y: contentOffsetY)
                .opacity(1.0)
                .scaleEffect(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                PurpleLashEyeView(
                    eyeSize: eyeSize,
                    blackColor: logoBlack,
                    highlightColor: eyeWhite
                )
                .position(x: rightEyeX, y: eyeCenterY)
                .offset(y: contentOffsetY)
                .opacity(1.0)
                .scaleEffect(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                Circle()
                    .fill(logoBlack)
                    .frame(width: mouthSize, height: mouthSize)
                    .position(x: width / 2 + (isLandscape ? base * 0.01 : 12.0), y: mouthCenterY)
                    .offset(y: contentOffsetY)
                    .opacity(1.0)
                    .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                Button {
                    guard !isLaunchingDrill else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isCardPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            isCardPressed = false
                        }
                        withAnimation(.easeInOut(duration: 1.05)) {
                            isLaunchingDrill = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                            withAnimation(.easeInOut(duration: 0.28)) {
                                showsFlipPrompt = true
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
                            withAnimation(.easeInOut(duration: 0.58)) {
                                hasFlippedPhone = true
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                            onBeforeCamera()
                            showsCamera = true
                        }
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(cardColor)
                        .frame(width: cardWidth, height: cardHeight)
                        .overlay {
                            VStack(spacing: 16) {
                                Text(title)
                                    .font(.ballr(size: min(width * 0.064, 31), weight: .black))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.68)

                                Text(subtitle)
                                    .font(.ballr(size: min(width * 0.038, 18), weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.76)
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
                .accessibilityLabel("Start \(title)")
                .position(x: width / 2, y: cardCenterY)
                .offset(y: contentOffsetY)
                .opacity(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                if showsFlipPrompt {
                    DrillIntroFlipPromptView()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.28), value: showsFlipPrompt)
                }

                Color.clear
                    .frame(height: safeBottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                introBounceOffset = 0
            }

            DispatchQueue.main.async {
                resetLaunchState(animated: true)
                withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                    introBounceOffset = -18
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.62, dampingFraction: 0.70)) {
                        introBounceOffset = 0
                    }
                }
            }
        }) {
            cameraContent()
        }
        .onAppear {
            resetLaunchState()
            guard !didPlayIntroAnimation else { return }
            didPlayIntroAnimation = true

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hasAnimatedCharacter = false
                introBounceOffset = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.spring(response: 0.96, dampingFraction: 0.88)) {
                    hasAnimatedCharacter = true
                }
            }
        }
    }
}

private struct PurpleLashEyeView: View {
    let eyeSize: CGFloat
    let blackColor: Color
    let highlightColor: Color
    private let largeHighlightSize: CGFloat = 21.69

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(blackColor)
                    .frame(width: eyeSize * 0.105, height: eyeSize * 0.38)
                    .rotationEffect(.degrees(-31 + Double(index) * 10))
                    .offset(
                        x: -eyeSize * 0.39 + CGFloat(index) * eyeSize * 0.145 + (index == 0 ? eyeSize * 0.02 : 0),
                        y: -eyeSize * 0.42 - CGFloat(index) * eyeSize * 0.018 + (index == 0 ? eyeSize * 0.025 : 0) - (index == 2 ? eyeSize * 0.035 : 0)
                    )
            }

            Circle()
                .fill(blackColor)
                .frame(width: eyeSize, height: eyeSize)

            Circle()
                .fill(highlightColor)
                .frame(width: largeHighlightSize, height: largeHighlightSize)
                .offset(x: -eyeSize * 0.14, y: -eyeSize * 0.12)

            Circle()
                .fill(highlightColor)
                .frame(width: eyeSize * 0.16, height: eyeSize * 0.16)
                .offset(x: -eyeSize * 0.26, y: eyeSize * 0.11)
        }
        .frame(width: eyeSize * 1.24, height: eyeSize * 1.28)
    }
}

private struct PinkRoundedDrillIntroScreen<CameraContent: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    @ViewBuilder let cameraContent: () -> CameraContent

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0
    @State private var didPlayIntroAnimation = false
    @State private var showsFlipPrompt = false
    @State private var hasFlippedPhone = false

    private let characterPink = Color(red: 0.86, green: 0.23, blue: 0.58)
    private let strokeMagenta = Color(red: 0x94 / 255.0, green: 0x15 / 255.0, blue: 0x5D / 255.0)
    private let cardMagenta = Color(red: 0x9A / 255.0, green: 0x14 / 255.0, blue: 0x5D / 255.0)
    private let eyeWhite = Color(red: 0.93, green: 0.91, blue: 0.91)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            showsFlipPrompt = false
                hasFlippedPhone = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        showsFlipPrompt = false
                hasFlippedPhone = false
            }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let base = min(width, height)
            let characterEntryOffset: CGFloat = 0
            let launchDropOffset = isLaunchingDrill ? height * (isLandscape ? 0.45 : 0.53) : 0
            let entryScale: CGFloat = 1.0
            let characterScaleX = entryScale
            let characterScaleY = entryScale
            let characterFillWidth = isLandscape ? min(width + 48, 568) : width + 48
            let characterStrokeWidth = isLandscape ? min(width, 520) : 393.0
            let characterHeight = isLandscape ? height * 1.02 : 740.0
            let characterSideFillWidth = max(0, (characterFillWidth - characterStrokeWidth) / 2)
            let characterSideFillTopInset = 60.0
            let characterSideFillHeight = max(0, characterHeight - characterSideFillTopInset)
            let characterBottomY = isLandscape ? height + 18 : height + 52
            let characterTopY = characterBottomY - characterHeight
            let characterCenterY = characterTopY + characterHeight / 2
            let eyeSize = isLandscape ? base * 0.13 : 94.0
            let pupilSize = eyeSize * 0.49
            let eyeCenterY = characterTopY + (isLandscape ? characterHeight * 0.27 : 162.0)
            let eyeSpacing = isLandscape ? base * 0.20 : 146.0
            let leftEyeX = width / 2 - eyeSpacing / 2
            let rightEyeX = width / 2 + eyeSpacing / 2
            let mouthWidth = isLandscape ? base * 0.16 : 97.0
            let mouthHeight = isLandscape ? base * 0.052 : 34.0
            let mouthCenterY = eyeCenterY + (isLandscape ? base * 0.14 : 94.0)
            let cardWidth = isLandscape ? min(width * 0.34, 320) : 281.0
            let cardHeight = isLandscape ? min(height * 0.44, 230) : 277.0
            let cardBottomY = isLandscape ? height - safeBottom - 24 : height - 80
            let cardCenterY = cardBottomY - cardHeight / 2
            let contentOffsetY = characterEntryOffset + introBounceOffset + launchDropOffset

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                ZStack {
                    PinkRoundedCharacterFillShape(cornerRadius: 60, sideBleed: 8)
                        .fill(characterPink)
                        .frame(width: characterStrokeWidth, height: characterHeight)

                    if characterSideFillWidth > 0 {
                        Rectangle()
                            .fill(characterPink)
                            .frame(width: characterSideFillWidth, height: characterSideFillHeight)
                            .offset(
                                x: -(characterStrokeWidth / 2 + characterSideFillWidth / 2),
                                y: characterSideFillTopInset / 2
                            )

                        Rectangle()
                            .fill(characterPink)
                            .frame(width: characterSideFillWidth, height: characterSideFillHeight)
                            .offset(
                                x: characterStrokeWidth / 2 + characterSideFillWidth / 2,
                                y: characterSideFillTopInset / 2
                            )
                    }

                    Color.clear
                        .frame(width: characterStrokeWidth, height: characterHeight)
                        .overlay {
                        PinkRoundedCharacterTopStrokeShape(cornerRadius: 60)
                            .stroke(
                                strokeMagenta,
                                style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }
                    .frame(width: characterFillWidth, height: characterHeight)
                    .position(x: width / 2, y: characterCenterY)
                    .offset(y: contentOffsetY)
                    .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)
                    .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                    .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

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
                .padding(.top, max(0, safeTop - 48))
                .padding(.leading, 18)

                ZStack {
                    Circle()
                        .fill(eyeWhite)
                        .frame(width: eyeSize, height: eyeSize)

                    Circle()
                        .fill(logoBlack)
                        .frame(width: pupilSize, height: pupilSize)
                                .offset(x: -eyeSize * 0.12, y: eyeSize * 0.16)
                }
                .position(x: leftEyeX, y: eyeCenterY)
                .offset(y: contentOffsetY)
                .opacity(1.0)
                .scaleEffect(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                ZStack {
                    Circle()
                        .fill(eyeWhite)
                        .frame(width: eyeSize, height: eyeSize)

                    Circle()
                        .fill(logoBlack)
                        .frame(width: pupilSize, height: pupilSize)
                        .offset(x: eyeSize * 0.15, y: -eyeSize * 0.16 + 1.5)
                }
                .position(x: rightEyeX, y: eyeCenterY)
                .offset(y: contentOffsetY)
                .opacity(1.0)
                .scaleEffect(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(logoBlack)
                    .frame(width: mouthWidth, height: mouthHeight)
                    .position(x: width / 2 + (isLandscape ? 0 : 2), y: mouthCenterY)
                    .offset(y: contentOffsetY)
                    .opacity(1.0)
                    .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                Button {
                    guard !isLaunchingDrill else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isCardPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            isCardPressed = false
                        }
                        withAnimation(.easeInOut(duration: 1.05)) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    showsFlipPrompt = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
                                withAnimation(.easeInOut(duration: 0.58)) {
                                    hasFlippedPhone = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                                showsCamera = true
                            }
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(cardMagenta)
                        .frame(width: cardWidth, height: cardHeight)
                        .overlay {
                            VStack(spacing: 16) {
                                Text(title)
                                    .font(.ballr(size: min(width * 0.064, 31), weight: .black))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.68)

                                Text(subtitle)
                                    .font(.ballr(size: min(width * 0.038, 18), weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.76)
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
                .accessibilityLabel("Start \(title)")
                .position(x: width / 2, y: cardCenterY)
                .offset(y: contentOffsetY)
                .opacity(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                if showsFlipPrompt {
                    DrillIntroFlipPromptView()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.28), value: showsFlipPrompt)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                introBounceOffset = 0
            }

            DispatchQueue.main.async {
                resetLaunchState(animated: true)
                withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                    introBounceOffset = -18
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.62, dampingFraction: 0.70)) {
                        introBounceOffset = 0
                    }
                }
            }
        }) {
            cameraContent()
        }
        .onAppear {
            resetLaunchState()
            guard !didPlayIntroAnimation else { return }
            didPlayIntroAnimation = true

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hasAnimatedCharacter = false
                introBounceOffset = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.spring(response: 0.96, dampingFraction: 0.88)) {
                    hasAnimatedCharacter = true
                }
            }
        }
    }
}

private struct PinkRoundedCharacterFillShape: Shape {
    let cornerRadius: CGFloat
    let sideBleed: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        let leftX = rect.minX - sideBleed
        let rightX = rect.maxX + sideBleed
        var path = Path()

        path.move(to: CGPoint(x: leftX, y: rect.minY + radius))
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control1: CGPoint(x: rect.minX + radius * 0.08, y: rect.minY + radius * 0.46),
            control2: CGPoint(x: rect.minX + radius * 0.42, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rightX, y: rect.minY + radius),
            control1: CGPoint(x: rect.maxX - radius * 0.42, y: rect.minY),
            control2: CGPoint(x: rect.maxX - radius * 0.08, y: rect.minY + radius * 0.46)
        )
        path.addLine(to: CGPoint(x: rightX, y: rect.maxY))
        path.addLine(to: CGPoint(x: leftX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private struct PinkRoundedCharacterTopStrokeShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX - 8, y: rect.minY + radius))
        path.addCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control1: CGPoint(x: rect.minX + radius * 0.08, y: rect.minY + radius * 0.46),
            control2: CGPoint(x: rect.minX + radius * 0.42, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX + 8, y: rect.minY + radius),
            control1: CGPoint(x: rect.maxX - radius * 0.42, y: rect.minY),
            control2: CGPoint(x: rect.maxX - radius * 0.08, y: rect.minY + radius * 0.46)
        )

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
    @State private var showsFlipPrompt = false
    @State private var hasFlippedPhone = false

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
            showsFlipPrompt = false
                hasFlippedPhone = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        showsFlipPrompt = false
                hasFlippedPhone = false
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
            let launchDropOffset = isLaunchingDrill ? height * (isLandscape ? 0.45 : 0.53) : 0
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let shapeOffset = characterEntryOffset + launchDropOffset
            let shapeScaleX = entryScale
            let shapeScaleY = entryScale
            let contentOffset = characterEntryOffset + launchDropOffset
            let faceOpacity: CGFloat = 1.0
            let faceScale: CGFloat = 1.0
            let faceLift: CGFloat = 0.0
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
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

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
                .padding(.top, max(0, safeTop - 48))
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
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                    Button {
                        guard !isLaunchingDrill else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCardPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isCardPressed = false
                            }
                            withAnimation(.easeInOut(duration: 1.05)) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    showsFlipPrompt = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
                                withAnimation(.easeInOut(duration: 0.58)) {
                                    hasFlippedPhone = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
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
                    .opacity(1.0)

                    Spacer(minLength: safeBottom + 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: contentOffset)
                .animation(.spring(response: 0.72, dampingFraction: 0.80), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                if showsFlipPrompt {
                    DrillIntroFlipPromptView()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.28), value: showsFlipPrompt)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            resetLaunchState()
        }) {
            PianoTilesCameraView(difficulty: difficulty)
                .ballrCameraPresentationChrome()
                .environment(\.ballrCountdownMascot, BallrCountdownMascot.pink)
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
    @State private var hasAnimatedCharacter = true
    @State private var isLaunchingDrill = false
    @State private var showsFlipPrompt = false
    @State private var hasFlippedPhone = false

    private let characterOrange = Color(red: 1.0, green: 0.29, blue: 0.07)
    private let characterStroke = Color(red: 0xB3 / 255.0, green: 0x39 / 255.0, blue: 0x0D / 255.0)
    private let cardCoral = Color(red: 1.0, green: 0.50, blue: 0.42)
    private let faceWhite = Color(red: 0.97, green: 0.96, blue: 0.95)
    private let toothWhite = Color(red: 0.96, green: 0.96, blue: 0.93)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            showsFlipPrompt = false
                hasFlippedPhone = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        showsFlipPrompt = false
                hasFlippedPhone = false
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
            let characterEntryOffset: CGFloat = 0
            let launchDropOffset = isLaunchingDrill ? height * (isLandscape ? 0.45 : 0.53) : 0
            let entryScale: CGFloat = 1.0
            let characterOffset = characterEntryOffset + launchDropOffset
            let characterScaleX = entryScale
            let characterScaleY = entryScale
            let characterTopY = height * 0.158
            let eyeWidth = isLandscape ? base * 0.12 : 107.96
            let eyeHeight = isLandscape ? eyeWidth * (54.91 / 107.96) : 54.91
            let eyeLift = isLandscape ? base * 0.030 : 12.0
            let eyeTopY = characterTopY + (isLandscape ? base * (114.0 / 393.0) : 114.0) - eyeLift
            let topLineY = eyeTopY + eyeHeight
            let pupilWidth = isLandscape ? eyeWidth * (48.39 / 107.96) : 48.39
            let pupilHeight = isLandscape ? eyeHeight * (25.12 / 54.91) : 25.12
            let pupilLeading = isLandscape ? eyeWidth * (40.02 / 107.96) : 40.02
            let eyeCenterY = isLandscape ? topLineY - eyeHeight * 0.5 : topLineY - eyeHeight * 0.5
            let eyeSpacing = isLandscape ? eyeWidth + base * 0.035 : eyeWidth + 28.85
            let leftEyeX = width / 2 - eyeSpacing / 2
            let rightEyeX = width / 2 + eyeSpacing / 2
            let mouthSize = isLandscape ? base * 0.12 : 96.0
            let mouthCenterY = isLandscape ? topLineY + mouthSize * 0.56 : 315.0
            let cardWidth = isLandscape ? min(width * 0.34, 320) : width * 0.72
            let cardHeight = isLandscape ? min(height * 0.44, 230) : min(height * 0.34, width * 0.88)
            let cardCenterY = isLandscape ? height * 0.69 : 554.0

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                FastTouchingCharacterShape()
                    .fill(characterOrange)
                    .ignoresSafeArea()
                    .offset(y: characterOffset)
                    .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)

                FastTouchingCharacterTopStrokeShape()
                    .stroke(characterStroke, style: StrokeStyle(lineWidth: 10, lineCap: .butt, lineJoin: .round))
                    .ignoresSafeArea()
                    .offset(y: characterOffset)
                    .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)

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
                .padding(.top, max(0, safeTop - 48))
                .padding(.leading, 18)

                ZStack {
                    FastTouchingPeekEyeView(
                        eyeWidth: eyeWidth,
                        eyeHeight: eyeHeight,
                        pupilWidth: pupilWidth,
                        pupilHeight: pupilHeight,
                        pupilLeading: pupilLeading,
                        whiteColor: faceWhite,
                        blackColor: logoBlack
                    )
                    .position(x: leftEyeX, y: eyeCenterY)

                    FastTouchingPeekEyeView(
                        eyeWidth: eyeWidth,
                        eyeHeight: eyeHeight,
                        pupilWidth: pupilWidth,
                        pupilHeight: pupilHeight,
                        pupilLeading: pupilLeading,
                        whiteColor: faceWhite,
                        blackColor: logoBlack
                    )
                    .position(x: rightEyeX, y: eyeCenterY)

                    Circle()
                        .fill(logoBlack)
                        .frame(width: mouthSize, height: mouthSize)
                        .mask(alignment: .bottom) {
                            Rectangle()
                                .frame(width: mouthSize, height: mouthSize * 0.5)
                        }
                        .overlay(alignment: .top) {
                            HStack(spacing: 4) {
                                FastTouchingToothView()
                                    .fill(toothWhite)
                                    .frame(width: 15, height: 23)
                                FastTouchingToothView()
                                    .fill(toothWhite)
                                    .frame(width: 15, height: 23)
                            }
                            .padding(.top, mouthSize * 0.50)
                        }
                        .position(x: width / 2 + 9, y: mouthCenterY)
                }
                .frame(width: width, height: height)
                .offset(y: characterOffset)
                .opacity(1.0)
                .scaleEffect(1.0)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                    Button {
                        guard !isLaunchingDrill else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            isCardPressed = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                                isCardPressed = false
                            }
                            withAnimation(.easeInOut(duration: 1.05)) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    showsFlipPrompt = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
                                withAnimation(.easeInOut(duration: 0.58)) {
                                    hasFlippedPhone = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                                showsCamera = true
                            }
                        }
                    } label: {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(cardCoral)
                            .frame(width: cardWidth, height: cardHeight)
                            .overlay {
                                VStack(spacing: 16) {
                                    Text("Fast Touching")
                                        .font(.ballr(size: min(width * 0.076, 34), weight: .black))
                                        .foregroundStyle(.white)
                                        .multilineTextAlignment(.center)

                                    Text("Count every toe touch")
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
                    .position(x: width / 2, y: cardCenterY)
                    .offset(y: characterOffset)
                    .opacity(1.0)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                if showsFlipPrompt {
                    DrillIntroFlipPromptView()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.28), value: showsFlipPrompt)
                }

                Color.clear
                    .frame(height: safeBottom)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hasAnimatedCharacter = true
            }
            resetLaunchState()
        }) {
            FastTouchingCameraView()
                .ballrCameraPresentationChrome()
                .environment(\.ballrCountdownMascot, BallrCountdownMascot.orange)
        }
        .onAppear {
            resetLaunchState()
            hasAnimatedCharacter = true
        }
    }
}

private struct YellowDrillIntroScreen<CameraContent: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    let showsFlipPromptText: Bool
    @ViewBuilder let cameraContent: () -> CameraContent

    init(
        title: String,
        subtitle: String,
        showsFlipPromptText: Bool = true,
        @ViewBuilder cameraContent: @escaping () -> CameraContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsFlipPromptText = showsFlipPromptText
        self.cameraContent = cameraContent
    }

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0
    @State private var didPlayIntroAnimation = false
    @State private var showsFlipPrompt = false
    @State private var hasFlippedPhone = false

    private let characterYellow = Color(red: 1.0, green: 0.84, blue: 0.0)
    private let darkYellow = Color(red: 165.0 / 255.0, green: 139.0 / 255.0, blue: 10.0 / 255.0)
    private let lensBlack = Color(red: 0.02, green: 0.02, blue: 0.02)
    private let reflectionGray = Color(red: 0.72, green: 0.72, blue: 0.70)
    private let toothWhite = Color(red: 0.96, green: 0.96, blue: 0.93)
    private let logoBlack = Color(red: 0.02, green: 0.02, blue: 0.02)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            showsFlipPrompt = false
                hasFlippedPhone = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        showsFlipPrompt = false
                hasFlippedPhone = false
            }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let isLandscape = width > height
            let safeTop = geometry.safeAreaInsets.top
            let safeBottom = geometry.safeAreaInsets.bottom
            let base = min(width, height)
            let characterEntryOffset = hasAnimatedCharacter ? 0 : height * (isLandscape ? 0.78 : 0.62)
            let launchDropOffset = isLaunchingDrill ? height * (isLandscape ? 0.48 : 0.56) : 0
            let entryScale = hasAnimatedCharacter ? 1.0 : 0.94
            let characterScaleX = entryScale
            let characterScaleY = entryScale
            let characterWidth = isLandscape ? min(width, 520) : 405.0
            let characterHeight = isLandscape ? height : 848.0
            let characterTopInset = characterHeight * 0.105
            let cardWidth = isLandscape ? min(width * 0.34, 320) : 281.0
            let cardHeight = isLandscape ? min(height * 0.44, 230) : 277.0
            let cardBottomY = isLandscape ? height - safeBottom - 24 : height - 160
            let cardCenterY = cardBottomY - cardHeight / 2
            let cardTopY = cardBottomY - cardHeight
            let mouthWidth = isLandscape ? base * 0.13 : width * 0.20
            let mouthHeight = isLandscape ? base * 0.035 : width * 0.035
            let toothWidth = mouthWidth * 0.20
            let toothHeight = mouthHeight * 1.85
            let mouthCenterY = cardTopY - (isLandscape ? 46 : 78)
            let mouthCenterX = width / 2 + (isLandscape ? 26 : 38)
            let glassesWidth = isLandscape ? base * 0.46 : width * 0.775
            let lensWidth = glassesWidth * 0.46
            let lensHeight = isLandscape ? base * 0.105 : width * 0.12
            let bridgeWidth = 27.95
            let glassesCenterY = mouthCenterY - (isLandscape ? base * 0.18 : width * 0.22)
            let characterVisibleTopY = isLandscape ? characterTopInset : glassesCenterY - width * 0.44
            let characterCenterY = characterVisibleTopY - characterTopInset + characterHeight / 2
            let wholeCharacterShiftY = isLandscape ? 0 : max(58.0, height - (characterCenterY + characterHeight / 2) + 30)

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                YellowDrillCharacterShape()
                    .fill(characterYellow)
                    .overlay {
                        YellowDrillCharacterTopStrokeShape()
                            .stroke(
                                darkYellow,
                                style: StrokeStyle(
                                    lineWidth: isLandscape ? 8 : 10,
                                    lineCap: .round,
                                    lineJoin: .round
                                )
                            )
                    }
                    .frame(width: characterWidth, height: characterHeight)
                    .position(x: width / 2, y: characterCenterY)
                    .offset(y: characterEntryOffset + launchDropOffset + wholeCharacterShiftY + introBounceOffset)
                    .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)
                    .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                    .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

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
                .padding(.top, max(0, safeTop - 48))
                .padding(.leading, 18)

                YellowDrillGlassesView(
                    lensWidth: lensWidth,
                    lensHeight: lensHeight,
                    bridgeWidth: bridgeWidth,
                    lensColor: lensBlack,
                    reflectionColor: reflectionGray
                )
                .frame(width: glassesWidth, height: lensHeight)
                .position(x: width / 2, y: glassesCenterY)
                .offset(y: characterEntryOffset + launchDropOffset + wholeCharacterShiftY)
                .opacity(1.0)
                .scaleEffect(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(logoBlack)
                        .frame(width: mouthWidth, height: mouthHeight)

                    HStack(spacing: 2) {
                        YellowDrillToothShape(cornerRadius: toothWidth * 0.58)
                            .fill(toothWhite)
                            .frame(width: toothWidth, height: toothHeight)
                        YellowDrillToothShape(cornerRadius: toothWidth * 0.58)
                            .fill(toothWhite)
                            .frame(width: toothWidth, height: toothHeight)
                    }
                    .offset(y: mouthHeight * 0.36 - 2)
                }
                .position(x: mouthCenterX, y: mouthCenterY)
                .offset(y: characterEntryOffset + launchDropOffset + wholeCharacterShiftY)
                .opacity(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                Button {
                    guard !isLaunchingDrill else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isCardPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            isCardPressed = false
                        }
                        withAnimation(.easeInOut(duration: 1.05)) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    showsFlipPrompt = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
                                withAnimation(.easeInOut(duration: 0.58)) {
                                    hasFlippedPhone = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                                showsCamera = true
                            }
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(darkYellow)
                        .frame(width: cardWidth, height: cardHeight)
                        .overlay {
                            VStack(spacing: 16) {
                                Text(title)
                                    .font(.ballr(size: min(width * 0.064, 31), weight: .black))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.68)

                                Text(subtitle)
                                    .font(.ballr(size: min(width * 0.038, 18), weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.76)
                            }
                            .tracking(0.8)
                            .padding(.horizontal, 20)
                        }
                        .scaleEffect(isCardPressed ? 0.96 : 1.0)
                        .shadow(color: Color.white.opacity(isCardPressed ? 0.0 : 0.16), radius: isCardPressed ? 0 : 16)
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(isCardPressed ? 0.26 : 0.0), lineWidth: 3)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Start \(title)")
                .position(x: width / 2, y: cardCenterY)
                .offset(y: characterEntryOffset + launchDropOffset + wholeCharacterShiftY)
                .opacity(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                if showsFlipPrompt && showsFlipPromptText {
                    DrillIntroFlipPromptView()
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.28), value: showsFlipPrompt)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                introBounceOffset = 0
            }

            DispatchQueue.main.async {
                resetLaunchState(animated: true)
                withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) {
                    introBounceOffset = -18
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.spring(response: 0.62, dampingFraction: 0.70)) {
                        introBounceOffset = 0
                    }
                }
            }
        }) {
            cameraContent()
        }
        .onAppear {
            resetLaunchState()
            guard !didPlayIntroAnimation else { return }
            didPlayIntroAnimation = true

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hasAnimatedCharacter = false
                introBounceOffset = 0
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.spring(response: 0.96, dampingFraction: 0.88)) {
                    hasAnimatedCharacter = true
                }
            }
        }
    }
}

private struct YellowDrillGlassesView: View {
    let lensWidth: CGFloat
    let lensHeight: CGFloat
    let bridgeWidth: CGFloat
    let lensColor: Color
    let reflectionColor: Color

    var body: some View {
        HStack(spacing: 0) {
            YellowDrillLensView(
                lensWidth: lensWidth,
                lensHeight: lensHeight,
                reflectionColor: reflectionColor,
                lensColor: lensColor
            )

            YellowDrillGlassesBridgeShape()
                .stroke(
                    lensColor,
                    style: StrokeStyle(lineWidth: lensHeight * 0.13, lineCap: .round)
                )
                .frame(width: bridgeWidth, height: lensHeight)

            YellowDrillLensView(
                lensWidth: lensWidth,
                lensHeight: lensHeight,
                reflectionColor: reflectionColor,
                lensColor: lensColor
            )
        }
    }
}

private struct YellowDrillGlassesBridgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.height * 0.32

        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: y),
            control: CGPoint(x: rect.midX, y: rect.height * 0.28)
        )

        return path
    }
}

private struct YellowDrillToothShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, rect.width / 2, rect.height / 2)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
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
        path.closeSubpath()

        return path
    }
}

private struct YellowDrillLensView: View {
    let lensWidth: CGFloat
    let lensHeight: CGFloat
    let reflectionColor: Color
    let lensColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(lensColor)
            .frame(width: lensWidth, height: lensHeight)
            .overlay {
                HStack(spacing: lensWidth * 0.055) {
                    YellowDrillGlareShape(topScale: 0.66)
                        .fill(reflectionColor)
                        .frame(width: lensWidth * 0.14, height: lensHeight * 1.62)
                        .rotationEffect(.degrees(33))
                    Rectangle()
                        .fill(reflectionColor)
                        .frame(width: lensWidth * 0.05, height: lensHeight * 1.30)
                        .rotationEffect(.degrees(33))
                }
                .offset(x: -lensWidth * 0.08)
            }
            .clipped()
    }
}

private struct YellowDrillGlareShape: Shape {
    let topScale: CGFloat

    func path(in rect: CGRect) -> Path {
        let clampedTopScale = min(max(topScale, 0.1), 1.0)
        let topWidth = rect.width * clampedTopScale
        let topInset = (rect.width - topWidth) / 2
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + topInset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topInset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

private struct YellowDrillCharacterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = YellowDrillCharacterTopStrokeShape().path(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct YellowDrillCharacterTopStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let topY = h * 0.105
        let sideY = topY + h * 0.108

        path.move(to: CGPoint(x: 0, y: sideY))
        path.addCurve(
            to: CGPoint(x: w, y: sideY),
            control1: CGPoint(x: w * 0.24, y: topY),
            control2: CGPoint(x: w * 0.76, y: topY)
        )

        return path
    }
}

private struct PrecisionTargetIntroScreen<CameraContent: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String
    @ViewBuilder let cameraContent: () -> CameraContent

    @State private var isCardPressed = false
    @State private var showsCamera = false
    @State private var hasAnimatedCharacter = false
    @State private var isLaunchingDrill = false
    @State private var introBounceOffset: CGFloat = 0
    @State private var didPlayIntroAnimation = false
    @State private var showsFlipPrompt = false
    @State private var hasFlippedPhone = false

    private let characterGreen = Color(red: 4.0 / 255.0, green: 178.0 / 255.0, blue: 111.0 / 255.0)
    private let characterOutline = Color(red: 11.0 / 255.0, green: 81.0 / 255.0, blue: 54.0 / 255.0)
    private let cardGreen = Color(red: 11.0 / 255.0, green: 81.0 / 255.0, blue: 54.0 / 255.0)
    private let faceWhite = Color(red: 0.93, green: 0.91, blue: 0.91)
    private let logoBlack = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let launchAnimation = Animation.spring(response: 0.86, dampingFraction: 0.88)
    private let resetAnimation = Animation.spring(response: 0.50, dampingFraction: 0.90)

    private func resetLaunchState(animated: Bool = false) {
        if animated {
            withAnimation(resetAnimation) {
                isCardPressed = false
                isLaunchingDrill = false
            showsFlipPrompt = false
                hasFlippedPhone = false
            }
            return
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isCardPressed = false
            isLaunchingDrill = false
        showsFlipPrompt = false
                hasFlippedPhone = false
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
            let launchDropOffset = isLaunchingDrill ? height * (isLandscape ? 0.48 : 0.57) : 0
            let characterOffset = characterEntryOffset + launchDropOffset
            let characterScaleX: CGFloat = 1.0
            let characterScaleY: CGFloat = 1.0
            let characterWidth = isLandscape ? min(width, 520) : 393.0
            let characterHeight = isLandscape ? height : max(680.0, height + 36.0)
            let characterTopInset = characterHeight * 0.104
            let eyeWidth = isLandscape ? base * 0.12 : width * 0.24
            let eyeHeight = eyeWidth
            let pupilSize = eyeWidth * 0.49
            let eyeSpacing = isLandscape ? base * 0.18 : width * 0.13
            let mouthWidth = isLandscape ? base * 0.15 : width * 0.245
            let mouthHeight = isLandscape ? base * 0.050 : width * 0.086
            let cardWidth = isLandscape ? min(width * 0.34, 320) : 281.0
            let cardHeight = isLandscape ? min(height * 0.44, 230) : 277.0
            let faceAndCardLiftY: CGFloat = isLandscape ? 0 : -82
            let cardBottomY = isLandscape ? height - safeBottom - 24 : height - 162
            let cardCenterY = cardBottomY - cardHeight / 2
            let cardTopY = cardBottomY - cardHeight
            let mouthBottomY = isLandscape ? cardTopY - 28 : cardTopY - 51
            let mouthCenterY = mouthBottomY - mouthHeight / 2
            let eyeBottomY = mouthBottomY - mouthHeight - (isLandscape ? 16 : 46)
            let eyeTopY = eyeBottomY - eyeHeight
            let eyeCenterY = eyeTopY + eyeHeight / 2
            let characterVisibleTopY = isLandscape ? characterTopInset : eyeTopY - 96
            let characterCenterY = characterVisibleTopY - characterTopInset + characterHeight / 2
            let wholeCharacterShiftY = isLandscape ? 0 : max(75.0, height - (characterCenterY + characterHeight / 2) + 25) + 72

            ZStack(alignment: .topLeading) {
                BallrAppBackground()

                PrecisionTargetCharacterShape()
                    .fill(characterGreen)
                    .overlay {
                        PrecisionTargetCharacterTopStrokeShape()
                            .stroke(
                                characterOutline,
                                style: StrokeStyle(
                                    lineWidth: isLandscape ? 8 : 10,
                                    lineCap: .round,
                                    lineJoin: .miter,
                                    miterLimit: 12
                                )
                            )
                    }
                    .frame(width: characterWidth, height: characterHeight)
                    .position(x: width / 2, y: characterCenterY)
                    .offset(y: characterOffset + wholeCharacterShiftY + introBounceOffset)
                    .scaleEffect(x: characterScaleX, y: characterScaleY, anchor: .bottom)
                    .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                    .animation(.spring(response: 0.54, dampingFraction: 0.68), value: introBounceOffset)
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

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
                .padding(.top, max(0, safeTop - 48))
                .padding(.leading, 18)

                HStack(spacing: eyeSpacing) {
                    PrecisionTargetEyeView(
                        eyeWidth: eyeWidth,
                        eyeHeight: eyeHeight,
                        pupilSize: pupilSize,
                        pupilOffset: CGSize(width: -eyeWidth * 0.11, height: eyeHeight * 0.20),
                        whiteColor: faceWhite,
                        blackColor: logoBlack
                    )

                    PrecisionTargetEyeView(
                        eyeWidth: eyeWidth,
                        eyeHeight: eyeHeight,
                        pupilSize: pupilSize,
                        pupilOffset: CGSize(width: -eyeWidth * 0.08, height: eyeHeight * 0.20),
                        whiteColor: faceWhite,
                        blackColor: logoBlack
                    )
                }
                .position(x: width / 2, y: eyeCenterY)
                .offset(y: characterOffset + wholeCharacterShiftY + faceAndCardLiftY)
                .opacity(1.0)
                .scaleEffect(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                Capsule()
                    .fill(logoBlack)
                    .frame(width: mouthWidth, height: mouthHeight)
                    .position(x: width / 2, y: mouthCenterY)
                    .offset(y: characterOffset + wholeCharacterShiftY + faceAndCardLiftY)
                    .opacity(1.0)
                    .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                    .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                Button {
                    guard !isLaunchingDrill else { return }
                    withAnimation(.easeInOut(duration: 0.12)) {
                        isCardPressed = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            isCardPressed = false
                        }
                        withAnimation(.easeInOut(duration: 1.05)) {
                                isLaunchingDrill = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
                                withAnimation(.easeInOut(duration: 0.28)) {
                                    showsFlipPrompt = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.30) {
                                withAnimation(.easeInOut(duration: 0.58)) {
                                    hasFlippedPhone = true
                                }
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
                                showsCamera = true
                            }
                    }
                } label: {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(cardGreen)
                        .frame(width: cardWidth, height: cardHeight)
                        .overlay {
                            VStack(spacing: 16) {
                                Text(title)
                                    .font(.ballr(size: min(width * 0.066, 34), weight: .black))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)

                                Text(subtitle)
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
                .accessibilityLabel("Start \(title)")
                .position(x: width / 2, y: cardCenterY)
                .offset(y: characterOffset + wholeCharacterShiftY + faceAndCardLiftY)
                .opacity(1.0)
                .animation(.spring(response: 0.96, dampingFraction: 0.88), value: hasAnimatedCharacter)
                .animation(.easeInOut(duration: 1.05), value: isLaunchingDrill)

                EmptyView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsCamera, onDismiss: {
            introBounceOffset = 0
            hasAnimatedCharacter = true
            DispatchQueue.main.async {
                resetLaunchState(animated: true)
            }
        }) {
            cameraContent()
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
        }
    }
}

private struct PrecisionTargetCharacterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 393.0
        let scaleY = min(rect.height, 560.0) / 760.0
        let lobeWidth = 98.25 * scaleX
        let lobeHeight = 365.24 * scaleY
        let lobeRadius = 46.0 * min(scaleX, scaleY)
        let bodyY = rect.minY + 321.0 * scaleY
        let bodyHeight = max(439.0 * scaleY, rect.maxY - bodyY)
        let sideStrokeFillY = rect.minY + lobeRadius * 0.88

        path.addRect(CGRect(
            x: rect.minX,
            y: rect.minY + lobeRadius,
            width: rect.width,
            height: rect.maxY - (rect.minY + lobeRadius)
        ))

        path.addRect(CGRect(
            x: rect.minX,
            y: sideStrokeFillY,
            width: lobeRadius * 0.34,
            height: max(0, rect.minY + lobeRadius - sideStrokeFillY)
        ))

        path.addRect(CGRect(
            x: rect.maxX - lobeRadius * 0.34,
            y: sideStrokeFillY,
            width: lobeRadius * 0.34,
            height: max(0, rect.minY + lobeRadius - sideStrokeFillY)
        ))

        for index in 0..<4 {
            path.addRoundedRect(
                in: CGRect(
                    x: rect.minX + CGFloat(index) * lobeWidth,
                    y: rect.minY,
                    width: lobeWidth,
                    height: lobeHeight
                ),
                cornerSize: CGSize(width: lobeRadius, height: lobeRadius)
            )
        }

        path.addRect(CGRect(
            x: rect.minX,
            y: bodyY,
            width: rect.width,
            height: max(bodyHeight, rect.maxY - bodyY)
        ))

        return path
    }
}

private struct PrecisionTargetCharacterTopStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 393.0
        let scaleY = min(rect.height, 560.0) / 760.0
        let lobeWidth = 98.25 * scaleX
        let lobeRadius = 46.0 * min(scaleX, scaleY)
        let sideExit = 4.0 * scaleX
        let sideExitY = rect.minY + lobeRadius * 0.96

        for index in 0..<4 {
            let minX = rect.minX + CGFloat(index) * lobeWidth
            let maxX = minX + lobeWidth
            let minY = rect.minY
            path.move(to: CGPoint(
                x: index == 0 ? minX - sideExit : minX,
                y: index == 0 ? sideExitY : minY + lobeRadius
            ))
            path.addQuadCurve(
                to: CGPoint(x: minX + lobeRadius, y: minY),
                control: CGPoint(x: minX, y: minY)
            )
            path.addLine(to: CGPoint(x: maxX - lobeRadius, y: minY))
            path.addQuadCurve(
                to: CGPoint(
                    x: index == 3 ? maxX + sideExit : maxX,
                    y: index == 3 ? sideExitY : minY + lobeRadius
                ),
                control: CGPoint(x: maxX, y: minY)
            )
        }

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

private struct FastTouchingCharacterShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let scale = w / 393.0
        let topY = h * 0.158
        let leftWidth = 198.35 * scale
        let rightWidth = max(0, w - leftWidth)
        let squareHeight = 188.35 * scale
        let lowerHeight = 609.0 * scale
        let cornerRadius = 50.0 * scale
        let lowerTop = topY + squareHeight - cornerRadius

        path.addRoundedRect(
            in: CGRect(x: 0, y: topY, width: leftWidth, height: squareHeight),
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )
        path.addRoundedRect(
            in: CGRect(x: leftWidth, y: topY, width: rightWidth, height: squareHeight),
            cornerSize: CGSize(width: cornerRadius, height: cornerRadius),
            style: .continuous
        )
        path.addRect(CGRect(x: leftWidth - cornerRadius, y: topY + cornerRadius, width: cornerRadius * 2, height: squareHeight - cornerRadius))
        path.addRect(CGRect(x: 0, y: lowerTop, width: w, height: max(h - lowerTop, lowerHeight)))
        return path
    }
}

private struct FastTouchingCharacterTopStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let scale = w / 393.0
        let topY = h * 0.158
        let leftWidth = 198.35 * scale
        let centerCorner = 65.0 * scale
        let sideArcReach = 70 * scale
        let sideArcOutside = 30.0 * scale
        let sideArcDrop = 210.0 * scale
        let sideArcEndInset = 3.0 * scale
        path.move(to: CGPoint(x: -sideArcOutside, y: topY + sideArcDrop))
        path.addCurve(
            to: CGPoint(x: sideArcReach, y: topY),
            control1: CGPoint(x: -sideArcOutside * 0.42, y: topY + sideArcDrop * 0.06),
            control2: CGPoint(x: sideArcReach * 0.22, y: topY)
        )
        path.addLine(to: CGPoint(x: leftWidth - centerCorner, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: leftWidth, y: topY + centerCorner),
            control: CGPoint(x: leftWidth, y: topY)
        )
        path.addQuadCurve(
            to: CGPoint(x: leftWidth + centerCorner, y: topY),
            control: CGPoint(x: leftWidth, y: topY)
        )
        path.addLine(to: CGPoint(x: w - sideArcReach, y: topY))
        path.addCurve(
            to: CGPoint(x: w + sideArcOutside, y: topY + sideArcDrop),
            control1: CGPoint(x: w - sideArcReach * 0.22, y: topY),
            control2: CGPoint(x: w + sideArcEndInset, y: topY + sideArcDrop * 0.06)
        )
        return path
    }
}

private struct FastTouchingPeekEyeView: View {
    let eyeWidth: CGFloat
    let eyeHeight: CGFloat
    let pupilWidth: CGFloat
    let pupilHeight: CGFloat
    let pupilLeading: CGFloat
    let whiteColor: Color
    let blackColor: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse()
                .fill(whiteColor)
                .frame(width: eyeWidth, height: eyeHeight * 2)
                .frame(width: eyeWidth, height: eyeHeight, alignment: .top)
                .clipped()

            Ellipse()
                .fill(blackColor)
                .frame(width: pupilWidth, height: pupilHeight * 2)
                .frame(width: pupilWidth, height: pupilHeight, alignment: .top)
                .clipped()
                .offset(x: pupilLeading, y: eyeHeight - pupilHeight)
        }
        .frame(width: eyeWidth, height: eyeHeight)
    }
}

private struct FastTouchingToothView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(rect.width * 0.5, rect.height * 0.34)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
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
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authSession: AuthSessionManager
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

                    SettingsAppearanceRow(
                        icon: "moon.fill",
                        title: "Appearance",
                        subtitle: colorScheme == .dark ? "Dark" : "Light",
                        iconBackground: Color.yellow.opacity(0.12),
                        iconColor: Color.yellow.opacity(0.78)
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

private struct SettingsAppearanceRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconBackground: Color
    let iconColor: Color

    var body: some View {
        HStack(spacing: 16) {
            SettingsIcon(icon: icon, background: iconBackground, color: iconColor)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.ballr(size: 19, weight: .black))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.ballr(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.38))
            }

            Spacer()
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

private struct BallrTopScreenHeader<TrailingContent: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let showsCover: Bool
    @ViewBuilder let trailingContent: () -> TrailingContent

    private var backgroundColor: Color {
        colorScheme == .dark ? .ballrDarkModeBackground : .ballrLightModeBackground
    }

    init(showsCover: Bool = true, @ViewBuilder trailingContent: @escaping () -> TrailingContent) {
        self.showsCover = showsCover
        self.trailingContent = trailingContent
    }

    var body: some View {
        GeometryReader { geometry in
            let safeTop = geometry.safeAreaInsets.top
            let headerTop = max(10.0, safeTop - 48.0)
            let switchTop = max(28.0, safeTop - 30.0)
            let headerLift: CGFloat = 18
            let logoSize = CGSize(width: 64, height: 46)
            let logoCenterY = headerTop + 27 - headerLift
            let switchCenterY = switchTop + 14 - headerLift
            let headerDividerY = max(headerTop + 60, switchTop + 42) - headerLift
            let headerCoverBottomY = headerDividerY + 58

            ZStack {
                if showsCover {
                    Rectangle()
                        .fill(backgroundColor)
                        .frame(width: geometry.size.width, height: headerCoverBottomY + safeTop + 1)
                        .offset(y: -safeTop)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                        .zIndex(3)
                }

                if colorScheme != .dark {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: 393, y: 0))
                    }
                    .stroke(Color.black, lineWidth: 1)
                    .frame(width: 393, height: 1)
                    .position(x: geometry.size.width / 2, y: headerDividerY)
                    .allowsHitTesting(false)
                    .zIndex(4)
                }

                LevelsMapIcon()
                    .frame(width: logoSize.width, height: logoSize.height)
                    .position(x: 58, y: logoCenterY)
                    .allowsHitTesting(false)
                    .zIndex(5)

                trailingContent()
                    .position(x: geometry.size.width - 44, y: switchCenterY)
                    .zIndex(5)
            }
        }
    }
}

private extension BallrTopScreenHeader where TrailingContent == EmptyView {
    init() {
        self.showsCover = true
        self.trailingContent = { EmptyView() }
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

    private let promptCornerRadius: CGFloat = 20
    private let yellowShadow = Color(red: 0xC8 / 255.0, green: 0xAA / 255.0, blue: 0x00 / 255.0)

    private var promptText: String {
        if drill.level == 1 {
            return "Tutorial - Learn how to use the ball tracker"
        }

        return "\(drill.displayTitle) - \(drill.subtitle)"
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
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: promptCornerRadius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: promptCornerRadius, style: .continuous)
                    .fill(yellowShadow)
                    .offset(y: 7)
            }

            TrianglePointer()
                .fill(yellowShadow)
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
    @Environment(\.colorScheme) private var colorScheme

    let drills: [Drill]
    let promptedDrill: Drill?
    let currentLevel: Int
    let lockedLevels: Set<Int>
    let viewportSize: CGSize
    let entrancesEnabled: Bool
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

    private var mascotAnchorPairs: [(lowerLevelIndex: Int, upperLevelIndex: Int)] {
        stride(from: 0, to: drills.count - 2, by: 3).map { startIndex in
            (lowerLevelIndex: startIndex, upperLevelIndex: startIndex + 2)
        }
    }

    private var pathColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.25) : Color(red: 0x12 / 255.0, green: 0x14 / 255.0, blue: 0x1C / 255.0)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LevelPathShape(points: nodePositions)
                    .stroke(
                        pathColor,
                        style: StrokeStyle(lineWidth: 1.35, lineCap: .round, lineJoin: .round)
                    )

                ForEach(Array(mascotAnchorPairs.enumerated()), id: \.offset) { _, pair in
                    let lowerPoint = nodePositions[pair.lowerLevelIndex]
                    let upperPoint = nodePositions[pair.upperLevelIndex]
                    let isRightSide = lowerPoint.x > 0.5
                    let anchorX = (isRightSide ? 0.78 : 0.22) * geometry.size.width
                    let anchorY = ((lowerPoint.y + upperPoint.y) / 2) * geometry.size.height
                    let shadowColor = colorScheme == .dark ? Color.white : Color.black
                    let characterAssetName: String = if pair.lowerLevelIndex == 3 && pair.upperLevelIndex == 5 {
                        "orange1"
                    } else if pair.lowerLevelIndex == 6 && pair.upperLevelIndex == 8 {
                        "purplecut"
                    } else if pair.lowerLevelIndex == 9 && pair.upperLevelIndex == 11 {
                        "bluecap"
                    } else if pair.lowerLevelIndex == 12 && pair.upperLevelIndex == 14 {
                        "yellowcool"
                    } else if pair.lowerLevelIndex == 15 && pair.upperLevelIndex == 17 {
                        "greenquad"
                    } else {
                        "pink"
                    }

                    LevelsMascotMarker(
                        assetName: characterAssetName,
                        shadowColor: shadowColor,
                        entersFromRight: isRightSide,
                        viewportSize: viewportSize,
                        entrancesEnabled: entrancesEnabled
                    )
                        .frame(width: 104, height: 94)
                        .position(x: anchorX, y: anchorY)
                        .zIndex(0.4)
                }

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

private struct LevelsMascotMarker: View {
    let assetName: String
    let shadowColor: Color
    let entersFromRight: Bool
    let viewportSize: CGSize
    let entrancesEnabled: Bool
    @State private var hasEntered = false
    @State private var tapPhase = 0
    @State private var lastViewportFrame: CGRect?

    private var entranceXOffset: CGFloat {
        hasEntered ? 0 : (entersFromRight ? viewportSize.width + 140 : -viewportSize.width - 140)
    }

    private var tapYOffset: CGFloat {
        switch tapPhase {
        case 1:
            return 3
        case 2:
            return -11
        default:
            return 0
        }
    }

    private var characterScale: CGSize {
        switch tapPhase {
        case 1:
            return CGSize(width: 1.08, height: 0.90)
        case 2:
            return CGSize(width: 0.96, height: 1.06)
        default:
            return CGSize(width: 1, height: 1)
        }
    }

    private var shadowScale: CGSize {
        switch tapPhase {
        case 1:
            return CGSize(width: 1.08, height: 0.92)
        case 2:
            return CGSize(width: 0.88, height: 1.04)
        default:
            return CGSize(width: 1, height: 1)
        }
    }

    private var characterSize: CGSize {
        switch assetName {
        case "orange1":
            return CGSize(width: 78, height: 88)
        case "purplecut":
            return CGSize(width: 82, height: 86)
        case "bluecap":
            return CGSize(width: 84, height: 86)
        case "yellowcool":
            return CGSize(width: 84, height: 86)
        case "greenquad":
            return CGSize(width: 84, height: 86)
        default:
            return CGSize(width: 76, height: 86)
        }
    }

    private var characterYOffset: CGFloat {
        switch assetName {
        case "pink":
            return -2
        case "orange1":
            return -2
        case "purplecut":
            return -2
        case "bluecap":
            return -2
        case "yellowcool":
            return -2
        case "greenquad":
            return -2
        default:
            return -1
        }
    }

    @ViewBuilder
    private var characterView: some View {
        switch assetName {
        case "pink":
            LevelsPinkSwiftUICharacter()
        case "orange1":
            LevelsOrangeSwiftUICharacter()
        case "purplecut":
            LevelsPurpleSwiftUICharacter()
        case "bluecap":
            LevelsBlueSwiftUICharacter()
        case "yellowcool":
            LevelsYellowCoolSwiftUICharacter()
        case "greenquad":
            LevelsGreenQuadSwiftUICharacter()
        default:
            Image(assetName)
                .resizable()
                .scaledToFit()
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            markerContent(fidgetYOffset: idleFidgetYOffset(at: timeline.date))
        }
        .frame(width: 104, height: 94)
        .contentShape(Rectangle())
        .offset(x: entranceXOffset)
        .background(
            GeometryReader { markerProxy in
                let markerFrame = markerProxy.frame(in: .named("levelsScrollViewport"))
                Color.clear
                    .onAppear {
                        lastViewportFrame = markerFrame
                        triggerEntranceIfNeeded(for: markerFrame)
                    }
                    .onChange(of: markerFrame) { _, newFrame in
                        lastViewportFrame = newFrame
                        triggerEntranceIfNeeded(for: newFrame)
                    }
            }
        )
        .onChange(of: entrancesEnabled) { _, _ in
            if let lastViewportFrame {
                triggerEntranceIfNeeded(for: lastViewportFrame)
            }
        }
        .onTapGesture {
            playTapAnimation()
        }
    }

    private func idleFidgetYOffset(at date: Date) -> CGFloat {
        guard hasEntered else {
            return 1
        }

        let period: TimeInterval = 1.64
        let progress = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return -1 + CGFloat(cos(progress * 2 * .pi)) * 2
    }

    @ViewBuilder
    private func markerContent(fidgetYOffset: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(shadowColor.opacity(0.82))
                .frame(width: 98, height: 21)
                .scaleEffect(x: shadowScale.width, y: shadowScale.height)
                .offset(y: 3)

            characterView
                .frame(width: characterSize.width, height: characterSize.height)
                .scaleEffect(x: characterScale.width, y: characterScale.height, anchor: .bottom)
                .offset(y: characterYOffset + fidgetYOffset + tapYOffset)
        }
    }

    private func triggerEntranceIfNeeded(for frame: CGRect) {
        guard entrancesEnabled, !hasEntered, viewportSize.height > 0 else { return }

        let verticalPadding: CGFloat = 24
        let isVerticallyVisible = frame.maxY >= -verticalPadding && frame.minY <= viewportSize.height + verticalPadding
        guard isVerticallyVisible else { return }

        DispatchQueue.main.async {
            guard !hasEntered else { return }
            withAnimation(.spring(response: 0.74, dampingFraction: 0.84)) {
                hasEntered = true
            }
        }
    }

    private func playTapAnimation() {
        LevelsMascotSoundPlayer.playJump()

        withAnimation(.easeOut(duration: 0.10)) {
            tapPhase = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.48)) {
                tapPhase = 2
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.62)) {
                tapPhase = 0
            }
        }
    }
}

private enum LevelsMascotSoundPlayer {
    private static var jumpPlayer: AVAudioPlayer?

    static func playJump() {
        if jumpPlayer == nil {
            prepareJumpPlayer()
        }

        jumpPlayer?.stop()
        jumpPlayer?.currentTime = 0
        jumpPlayer?.volume = 0.72
        jumpPlayer?.play()
    }

    private static func prepareJumpPlayer() {
        guard let url = Bundle.main.url(forResource: "jeff_ball_bounce", withExtension: "wav") else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.72
            player.prepareToPlay()
            jumpPlayer = player
        } catch {
            print("Levels mascot jump sound failed to load: \(error.localizedDescription)")
        }
    }
}

struct LevelsPinkSwiftUICharacter: View {
    private let bodyFill = Color(red: 0.86, green: 0.22, blue: 0.62)
    private let bodyStroke = Color(red: 0.55, green: 0.06, blue: 0.32)
    private let faceBlack = Color(red: 0.13, green: 0.12, blue: 0.13)
    private let eyeWhite = Color(red: 0.95, green: 0.93, blue: 0.93)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let designHeight: CGFloat = 102.35
            let scale = min(width / 97.48, height / designHeight)
            let drawSize = CGSize(width: 97.48 * scale, height: designHeight * scale)
            let origin = CGPoint(
                x: (width - drawSize.width) / 2,
                y: (height - drawSize.height) / 2
            )

            ZStack {
                PinkCharacterBodyShape()
                    .fill(bodyFill)
                    .overlay {
                        PinkCharacterBodyShape()
                            .strokeBorder(bodyStroke, style: StrokeStyle(lineWidth: 4 * scale, lineJoin: .round))
                    }

                Circle()
                    .fill(eyeWhite)
                    .frame(width: 25 * scale, height: 25 * scale)
                    .position(x: origin.x + 32.5 * scale, y: origin.y + 32.5 * scale)

                Circle()
                    .fill(eyeWhite)
                    .frame(width: 25 * scale, height: 25 * scale)
                    .position(x: origin.x + 68.3 * scale, y: origin.y + 32.5 * scale)

                Circle()
                    .fill(faceBlack)
                    .frame(width: 12.5 * scale, height: 12.5 * scale)
                    .position(x: origin.x + 28.8 * scale, y: origin.y + 37.5 * scale)

                Circle()
                    .fill(faceBlack)
                    .frame(width: 12.5 * scale, height: 12.5 * scale)
                    .position(x: origin.x + 72.4 * scale, y: origin.y + 27.0 * scale)

                RoundedRectangle(cornerRadius: 5.5 * scale, style: .continuous)
                    .fill(faceBlack)
                    .frame(width: 25 * scale, height: 9 * scale)
                    .position(x: origin.x + 49.7 * scale, y: origin.y + 54.0 * scale)
            }
            .frame(width: drawSize.width, height: drawSize.height)
            .position(x: width / 2, y: height / 2)
        }
    }
}

private struct PinkCharacterBodyShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> PinkCharacterBodyShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let x = { rect.minX + $0 * rect.width / 97.48 }
        let designHeight: CGFloat = 102.35
        let y = { rect.minY + $0 * rect.height / designHeight }

        let topRadius: CGFloat = 30
        let topHeight: CGFloat = 70.67
        let totalHeight: CGFloat = designHeight
        let leftLegRight: CGFloat = 25.18
        let middleLegLeft: CGFloat = 36.55
        let middleLegRight: CGFloat = 61.73
        let rightLegLeft: CGFloat = 72.29
        let cutShoulderY: CGFloat = 75.8

        var path = Path()
        path.move(to: CGPoint(x: x(0), y: y(totalHeight)))
        path.addLine(to: CGPoint(x: x(0), y: y(topRadius)))
        path.addCurve(
            to: CGPoint(x: x(topRadius), y: y(0)),
            control1: CGPoint(x: x(0), y: y(13.43)),
            control2: CGPoint(x: x(13.43), y: y(0))
        )
        path.addLine(to: CGPoint(x: x(67.48), y: y(0)))
        path.addCurve(
            to: CGPoint(x: x(97.48), y: y(topRadius)),
            control1: CGPoint(x: x(84.05), y: y(0)),
            control2: CGPoint(x: x(97.48), y: y(13.43))
        )
        path.addLine(to: CGPoint(x: x(97.48), y: y(totalHeight)))
        path.addLine(to: CGPoint(x: x(rightLegLeft), y: y(totalHeight)))
        path.addLine(to: CGPoint(x: x(rightLegLeft), y: y(cutShoulderY)))
        path.addQuadCurve(
            to: CGPoint(x: x(middleLegRight), y: y(cutShoulderY)),
            control: CGPoint(x: x((rightLegLeft + middleLegRight) / 2), y: y(topHeight))
        )
        path.addLine(to: CGPoint(x: x(middleLegRight), y: y(totalHeight)))
        path.addLine(to: CGPoint(x: x(middleLegLeft), y: y(totalHeight)))
        path.addLine(to: CGPoint(x: x(middleLegLeft), y: y(cutShoulderY)))
        path.addQuadCurve(
            to: CGPoint(x: x(leftLegRight), y: y(cutShoulderY)),
            control: CGPoint(x: x((middleLegLeft + leftLegRight) / 2), y: y(topHeight))
        )
        path.addLine(to: CGPoint(x: x(leftLegRight), y: y(totalHeight)))
        path.closeSubpath()
        return path
    }
}

struct LevelsPurpleSwiftUICharacter: View {
    private let bodyFill = Color(red: 0.62, green: 0.42, blue: 0.75)
    private let bodyStroke = Color(red: 0.45, green: 0.30, blue: 0.56)
    private let faceBlack = Color(red: 0.13, green: 0.12, blue: 0.13)
    private let highlightWhite = Color(red: 0.95, green: 0.94, blue: 0.94)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let designSize = CGSize(width: 104, height: 96)
            let scale = min(width / designSize.width, height / designSize.height)
            let drawSize = CGSize(width: designSize.width * scale, height: designSize.height * scale)
            let origin = CGPoint(
                x: (width - drawSize.width) / 2,
                y: (height - drawSize.height) / 2
            )

            ZStack {
                PurpleGhostBodyShape()
                    .stroke(bodyStroke, style: StrokeStyle(lineWidth: 8 * scale, lineJoin: .round))

                PurpleGhostBodyShape()
                    .fill(bodyFill)

                PurpleGhostEyeView(faceBlack: faceBlack, highlightWhite: highlightWhite)
                    .frame(width: 24 * scale, height: 28 * scale)
                    .position(x: origin.x + 40 * scale, y: origin.y + 33.5 * scale)

                PurpleGhostEyeView(faceBlack: faceBlack, highlightWhite: highlightWhite)
                    .frame(width: 24 * scale, height: 28 * scale)
                    .position(x: origin.x + 66 * scale, y: origin.y + 33.5 * scale)

                Circle()
                    .fill(faceBlack)
                    .frame(width: 11.5 * scale, height: 11.5 * scale)
                    .position(x: origin.x + 55 * scale, y: origin.y + 51.5 * scale)
            }
            .frame(width: drawSize.width, height: drawSize.height)
            .position(x: width / 2, y: height / 2)
        }
    }
}

private struct PurpleGhostBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = { rect.minX + $0 * rect.width / 104 }
        let y = { rect.minY + $0 * rect.height / 96 }

        var path = Path()
        path.move(to: CGPoint(x: x(52), y: y(2)))
        path.addCurve(
            to: CGPoint(x: x(91), y: y(32)),
            control1: CGPoint(x: x(73), y: y(2)),
            control2: CGPoint(x: x(91), y: y(14))
        )
        path.addCurve(
            to: CGPoint(x: x(91), y: y(58)),
            control1: CGPoint(x: x(91), y: y(43)),
            control2: CGPoint(x: x(90), y: y(51))
        )
        path.addCurve(
            to: CGPoint(x: x(94), y: y(77)),
            control1: CGPoint(x: x(92), y: y(65)),
            control2: CGPoint(x: x(94), y: y(70))
        )
        path.addCurve(
            to: CGPoint(x: x(83), y: y(92)),
            control1: CGPoint(x: x(95), y: y(88)),
            control2: CGPoint(x: x(90), y: y(94))
        )
        path.addCurve(
            to: CGPoint(x: x(74), y: y(79)),
            control1: CGPoint(x: x(77), y: y(91)),
            control2: CGPoint(x: x(75), y: y(85))
        )
        path.addCurve(
            to: CGPoint(x: x(62), y: y(70)),
            control1: CGPoint(x: x(74), y: y(66)),
            control2: CGPoint(x: x(68), y: y(60))
        )
        path.addLine(to: CGPoint(x: x(62), y: y(82)))
        path.addCurve(
            to: CGPoint(x: x(52), y: y(94)),
            control1: CGPoint(x: x(62), y: y(90)),
            control2: CGPoint(x: x(57), y: y(94))
        )
        path.addCurve(
            to: CGPoint(x: x(42), y: y(82)),
            control1: CGPoint(x: x(47), y: y(94)),
            control2: CGPoint(x: x(42), y: y(90))
        )
        path.addCurve(
            to: CGPoint(x: x(30), y: y(78)),
            control1: CGPoint(x: x(42), y: y(66)),
            control2: CGPoint(x: x(36), y: y(60))
        )
        path.addCurve(
            to: CGPoint(x: x(21), y: y(92)),
            control1: CGPoint(x: x(29), y: y(85)),
            control2: CGPoint(x: x(27), y: y(91))
        )
        path.addCurve(
            to: CGPoint(x: x(10), y: y(77)),
            control1: CGPoint(x: x(14), y: y(94)),
            control2: CGPoint(x: x(9), y: y(88))
        )
        path.addCurve(
            to: CGPoint(x: x(12), y: y(58)),
            control1: CGPoint(x: x(10), y: y(70)),
            control2: CGPoint(x: x(11), y: y(66))
        )
        path.addCurve(
            to: CGPoint(x: x(13), y: y(32)),
            control1: CGPoint(x: x(14), y: y(51)),
            control2: CGPoint(x: x(13), y: y(44))
        )
        path.addCurve(
            to: CGPoint(x: x(52), y: y(2)),
            control1: CGPoint(x: x(13), y: y(14)),
            control2: CGPoint(x: x(31), y: y(2))
        )
        path.closeSubpath()
        return path
    }
}

private struct PurpleGhostEyeView: View {
    let faceBlack: Color
    let highlightWhite: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(faceBlack)
                        .frame(width: width * 0.12, height: height * 0.32)
                        .rotationEffect(.degrees([-38, -20, -2][index]))
                        .position(
                            x: width * ([0.22, 0.35, 0.48][index]),
                            y: height * ([0.19, 0.14, 0.15][index])
                        )
                }

                Circle()
                    .fill(faceBlack)
                    .frame(width: width * 0.82, height: width * 0.82)
                    .position(x: width * 0.52, y: height * 0.52)

                Circle()
                    .fill(highlightWhite)
                    .frame(width: width * 0.25, height: width * 0.25)
                    .position(x: width * 0.44, y: height * 0.42)

                Circle()
                    .fill(highlightWhite)
                    .frame(width: width * 0.15, height: width * 0.15)
                    .position(x: width * 0.32, y: height * 0.61)
            }
        }
    }
}

struct LevelsBlueSwiftUICharacter: View {
    private let bodyFill = Color(red: 0.09, green: 0.68, blue: 0.84)
    private let bodyStroke = Color(red: 0.02, green: 0.42, blue: 0.55)
    private let faceBlack = Color(red: 0.13, green: 0.12, blue: 0.13)
    private let highlightWhite = Color(red: 0.95, green: 0.94, blue: 0.94)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let designSize = CGSize(width: 104, height: 96)
            let scale = min(width / designSize.width, height / designSize.height)
            let drawSize = CGSize(width: designSize.width * scale, height: designSize.height * scale)
            let origin = CGPoint(
                x: (width - drawSize.width) / 2,
                y: (height - drawSize.height) / 2
            )

            ZStack {
                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                    .fill(faceBlack.opacity(0.96))
                    .frame(width: 17 * scale, height: 34 * scale)
                     .rotationEffect(.degrees(12))
                    .position(x: origin.x + 42 * scale, y: origin.y + 81 * scale)

                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                    .fill(faceBlack.opacity(0.96))
                    .frame(width: 17 * scale, height: 34 * scale)
                    .rotationEffect(.degrees(12))
                    .position(x: origin.x + 65 * scale, y: origin.y + 81 * scale)

                Group {
                    BlueCapBodyShape()
                        .stroke(bodyStroke, style: StrokeStyle(lineWidth: 7.5 * scale, lineJoin: .round))

                    BlueCapBodyShape()
                        .fill(bodyFill)

                    PurpleGhostEyeView(faceBlack: faceBlack, highlightWhite: highlightWhite)
                        .frame(width: 29 * scale, height: 33.8 * scale)
                        .position(x: origin.x + 31.245 * scale, y: origin.y + 39 * scale)

                    PurpleGhostEyeView(faceBlack: faceBlack, highlightWhite: highlightWhite)
                        .frame(width: 29 * scale, height: 33.8 * scale)
                        .position(x: origin.x + 73.755 * scale, y: origin.y + 39 * scale)

                    Circle()
                        .fill(faceBlack)
                        .frame(width: 13.5 * scale, height: 13.5 * scale)
                        .position(x: origin.x + 54 * scale, y: origin.y + 64.5 * scale)
                }
                .scaleEffect(0.85)
                .offset(y: -4 * scale)
            }
            .frame(width: drawSize.width, height: drawSize.height)
            .position(x: width / 2, y: height / 2)
        }
    }
}

private struct BlueCapBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = { rect.minX + $0 * rect.width / 104 }
        let y = { rect.minY + $0 * rect.height / 96 }
        let left: CGFloat = 3.26
        let right: CGFloat = 100.74
        let centerX: CGFloat = 52
        let ellipseTop: CGFloat = 4
        let rectTop = ellipseTop + 35.96
        let rectBottom = rectTop + 42.04

        var path = Path()
        path.move(to: CGPoint(x: x(left), y: y(rectBottom)))
        path.addLine(to: CGPoint(x: x(left), y: y(rectTop)))
        path.addCurve(
            to: CGPoint(x: x(centerX), y: y(ellipseTop)),
            control1: CGPoint(x: x(left), y: y(16)),
            control2: CGPoint(x: x(24), y: y(ellipseTop))
        )
        path.addCurve(
            to: CGPoint(x: x(right), y: y(rectTop)),
            control1: CGPoint(x: x(80), y: y(ellipseTop)),
            control2: CGPoint(x: x(right), y: y(16))
        )
        path.addLine(to: CGPoint(x: x(right), y: y(rectBottom)))
        path.addCurve(
            to: CGPoint(x: x(right - 5), y: y(rectBottom + 4)),
            control1: CGPoint(x: x(right), y: y(rectBottom + 2.5)),
            control2: CGPoint(x: x(right - 2), y: y(rectBottom + 4))
        )
        path.addLine(to: CGPoint(x: x(left + 5), y: y(rectBottom + 4)))
        path.addCurve(
            to: CGPoint(x: x(left), y: y(rectBottom)),
            control1: CGPoint(x: x(left + 2), y: y(rectBottom + 4)),
            control2: CGPoint(x: x(left), y: y(rectBottom + 2.5))
        )
        path.closeSubpath()
        return path
    }
}

struct LevelsYellowCoolSwiftUICharacter: View {
    private let bodyFill = Color(red: 1.0, green: 0.85, blue: 0.0)
    private let bodyStroke = Color(red: 0.62, green: 0.53, blue: 0.0)
    private let faceBlack = Color(red: 0.03, green: 0.03, blue: 0.03)
    private let legBlack = Color(red: 0.13, green: 0.12, blue: 0.13)
    private let lensGlare = Color(red: 0.78, green: 0.78, blue: 0.78)
    private let toothWhite = Color(red: 0.96, green: 0.95, blue: 0.93)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let designSize = CGSize(width: 104, height: 96)
            let scale = min(width / designSize.width, height / designSize.height)
            let drawSize = CGSize(width: designSize.width * scale, height: designSize.height * scale)
            let origin = CGPoint(
                x: (width - drawSize.width) / 2,
                y: (height - drawSize.height) / 2
            )

            ZStack {
                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                    .fill(legBlack.opacity(0.98))
                    .frame(width: 17 * scale, height: 34 * scale)
                    .rotationEffect(.degrees(12))
                    .position(x: origin.x + 42 * scale, y: origin.y + 80 * scale)

                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                    .fill(legBlack.opacity(0.98))
                    .frame(width: 17 * scale, height: 34 * scale)
                    .rotationEffect(.degrees(12))
                    .position(x: origin.x + 65 * scale, y: origin.y + 80 * scale)

                Group {
                    YellowCoolBodyShape()
                        .stroke(bodyStroke, style: StrokeStyle(lineWidth: 7.5 * scale, lineJoin: .round))

                    YellowCoolBodyShape()
                        .fill(bodyFill)

                    YellowCoolSunglassesView(faceBlack: faceBlack, lensGlare: lensGlare)
                        .frame(width: 91 * scale, height: 18.2 * scale)
                        .position(x: origin.x + 52 * scale, y: origin.y + 36 * scale)

                    Capsule()
                        .fill(faceBlack)
                        .frame(width: 24 * scale, height: 4.5 * scale)
                        .position(x: origin.x + 61 * scale, y: origin.y + 57 * scale)

                    HStack(spacing: 0) {
                        YellowCoolToothShape()
                            .fill(toothWhite)
                        YellowCoolToothShape()
                            .fill(toothWhite)
                    }
                    .frame(width: 8.8 * scale, height: 7.8 * scale)
                    .overlay(
                        Rectangle()
                            .fill(faceBlack)
                            .frame(width: 1 * scale)
                    )
                    .position(x: origin.x + 61 * scale, y: origin.y + 60.8 * scale)
                }
                .scaleEffect(0.95)
                .offset(y: -7 * scale)
            }
            .frame(width: drawSize.width, height: drawSize.height)
            .position(x: width / 2, y: height / 2)
        }
    }
}

private struct YellowCoolSunglassesView: View {
    let faceBlack: Color
    let lensGlare: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let unitScale = min(width / 91, height / 18.2)
            let leftLensWidth = 41.11 * unitScale
            let rightLensWidth = 41.95 * unitScale
            let lensHeight = 14.26 * unitScale
            let lensY = height * 0.5

            ZStack {
                Capsule()
                    .fill(faceBlack)
                    .frame(width: 9.5 * unitScale, height: 3 * unitScale)
                    .position(x: width * 0.5, y: lensY - 2 * unitScale)

                YellowCoolLensView(faceBlack: faceBlack, lensGlare: lensGlare)
                    .frame(width: leftLensWidth, height: lensHeight)
                    .position(x: width * 0.5 - 24.4 * unitScale, y: lensY)

                YellowCoolLensView(faceBlack: faceBlack, lensGlare: lensGlare)
                    .frame(width: rightLensWidth, height: lensHeight)
                    .position(x: width * 0.5 + 24.4 * unitScale, y: lensY)
            }
        }
    }
}

private struct YellowCoolLensView: View {
    let faceBlack: Color
    let lensGlare: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
                    .fill(faceBlack)

                YellowCoolLensGlareShape()
                    .fill(lensGlare)
                    .frame(width: width * 0.14, height: height * 1.55)
                    .rotationEffect(.degrees(31))
                    .position(x: width * 0.46, y: height * 0.46)

                Rectangle()
                    .fill(lensGlare)
                    .frame(width: width * 0.07, height: height * 1.55)
                    .rotationEffect(.degrees(31))
                    .position(x: width * 0.59, y: height * 0.46)
            }
            .clipShape(RoundedRectangle(cornerRadius: height * 0.32, style: .continuous))
        }
    }
}

private struct YellowCoolLensGlareShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX - rect.width * 0.32, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.32, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.38, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct YellowCoolToothShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.32

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct YellowCoolBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = { rect.minX + $0 * rect.width / 104 }
        let y = { rect.minY + $0 * rect.height / 96 }
        let left: CGFloat = 2.0
        let right: CGFloat = 102.0
        let top: CGFloat = 4.3
        let bottom: CGFloat = top + 84.6

        var path = Path()
        path.move(to: CGPoint(x: x(left), y: y(66)))
        path.addLine(to: CGPoint(x: x(left), y: y(27)))
        path.addCurve(
            to: CGPoint(x: x(52), y: y(top)),
            control1: CGPoint(x: x(left), y: y(10)),
            control2: CGPoint(x: x(27), y: y(top))
        )
        path.addCurve(
            to: CGPoint(x: x(right), y: y(27)),
            control1: CGPoint(x: x(77), y: y(top)),
            control2: CGPoint(x: x(right), y: y(10))
        )
        path.addLine(to: CGPoint(x: x(right), y: y(66)))
        path.addCurve(
            to: CGPoint(x: x(76), y: y(bottom)),
            control1: CGPoint(x: x(right), y: y(81)),
            control2: CGPoint(x: x(91), y: y(bottom))
        )
        path.addCurve(
            to: CGPoint(x: x(52), y: y(bottom - 1.7)),
            control1: CGPoint(x: x(67), y: y(bottom)),
            control2: CGPoint(x: x(60), y: y(bottom - 1.7))
        )
        path.addCurve(
            to: CGPoint(x: x(28), y: y(bottom)),
            control1: CGPoint(x: x(44), y: y(bottom - 1.7)),
            control2: CGPoint(x: x(37), y: y(bottom))
        )
        path.addCurve(
            to: CGPoint(x: x(left), y: y(66)),
            control1: CGPoint(x: x(13), y: y(bottom)),
            control2: CGPoint(x: x(left), y: y(81))
        )
        path.closeSubpath()
        return path
    }
}

struct LevelsGreenQuadSwiftUICharacter: View {
    private let bodyFill = Color(red: 0.02, green: 0.70, blue: 0.43)
    private let bodyStroke = Color(red: 0.00, green: 0.32, blue: 0.23)
    private let faceBlack = Color(red: 0.13, green: 0.12, blue: 0.13)
    private let eyeWhite = Color(red: 0.96, green: 0.94, blue: 0.94)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let designSize = CGSize(width: 104, height: 96)
            let scale = min(width / designSize.width, height / designSize.height)
            let drawSize = CGSize(width: designSize.width * scale, height: designSize.height * scale)
            let origin = CGPoint(
                x: (width - drawSize.width) / 2,
                y: (height - drawSize.height) / 2
            )
            let columnWidth = 21.16 * scale
            let columnHeight = 76.68 * scale
            let columnCorner = 46 * scale
            let columnY = origin.y + 40.5 * scale
            let columnCenters = [
                origin.x + 21.9 * scale,
                origin.x + 42.2 * scale,
                origin.x + 62.5 * scale,
                origin.x + 82.8 * scale
            ]

            ZStack {
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(faceBlack.opacity(0.96))
                    .frame(width: 15 * scale, height: 31 * scale)
                    .rotationEffect(.degrees(10))
                    .position(x: origin.x + 41 * scale, y: origin.y + 78 * scale)

                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(faceBlack.opacity(0.96))
                    .frame(width: 15 * scale, height: 31 * scale)
                    .rotationEffect(.degrees(10))
                    .position(x: origin.x + 65 * scale, y: origin.y + 78 * scale)

                Group {
                    ForEach(Array(columnCenters.enumerated()), id: \.offset) { _, centerX in
                        RoundedRectangle(cornerRadius: columnCorner, style: .continuous)
                            .fill(bodyStroke)
                            .frame(width: columnWidth + 8 * scale, height: columnHeight + 8 * scale)
                            .position(x: centerX, y: columnY)
                    }

                    ForEach(Array(columnCenters.enumerated()), id: \.offset) { _, centerX in
                        RoundedRectangle(cornerRadius: columnCorner, style: .continuous)
                            .fill(bodyFill)
                            .frame(width: columnWidth, height: columnHeight)
                            .position(x: centerX, y: columnY)
                    }

                    Circle()
                        .fill(eyeWhite)
                        .frame(width: 24 * scale, height: 24 * scale)
                        .position(x: origin.x + 39 * scale, y: origin.y + 31.5 * scale)

                    Circle()
                        .fill(eyeWhite)
                        .frame(width: 24 * scale, height: 24 * scale)
                        .position(x: origin.x + 69 * scale, y: origin.y + 31.5 * scale)

                    Circle()
                        .fill(faceBlack)
                        .frame(width: 12.5 * scale, height: 12.5 * scale)
                        .position(x: origin.x + 36.5 * scale, y: origin.y + 34.8 * scale)

                    Circle()
                        .fill(faceBlack)
                        .frame(width: 12.5 * scale, height: 12.5 * scale)
                        .position(x: origin.x + 66.5 * scale, y: origin.y + 34.8 * scale)

                    Capsule()
                        .fill(faceBlack)
                        .frame(width: 25 * scale, height: 8 * scale)
                        .position(x: origin.x + 54 * scale, y: origin.y + 60.5 * scale)
                }
                .offset(y: -3 * scale)
            }
            .frame(width: drawSize.width, height: drawSize.height)
            .position(x: width / 2, y: height / 2)
        }
    }
}

struct LevelsOrangeSwiftUICharacter: View {
    private let bodyFill = Color(red: 1.0, green: 0.29, blue: 0.08)
    private let bodyStroke = Color(red: 0xB3 / 255.0, green: 0x39 / 255.0, blue: 0x0D / 255.0)
    private let faceBlack = Color(red: 0.13, green: 0.12, blue: 0.13)
    private let eyeWhite = Color(red: 0.96, green: 0.95, blue: 0.95)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let designSize = CGSize(width: 92, height: 104)
            let scale = min(width / designSize.width, height / designSize.height)
            let drawSize = CGSize(width: designSize.width * scale, height: designSize.height * scale)
            let origin = CGPoint(
                x: (width - drawSize.width) / 2,
                y: (height - drawSize.height) / 2
            )

            ZStack {
                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                    .fill(faceBlack.opacity(0.92))
                    .frame(width: 16.5 * scale, height: 42 * scale)
                    .rotationEffect(.degrees(16))
                    .position(x: origin.x + 35.5 * scale, y: origin.y + 85.5 * scale)

                RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                    .fill(faceBlack.opacity(0.92))
                    .frame(width: 16.5 * scale, height: 42 * scale)
                    .rotationEffect(.degrees(16))
                    .position(x: origin.x + 58.5 * scale, y: origin.y + 85.5 * scale)

                OrangeCharacterBodyShape()
                    .stroke(bodyStroke, style: StrokeStyle(lineWidth: 8 * scale, lineJoin: .round))

                OrangeCharacterBodyShape()
                    .fill(bodyFill)

                OrangePeekEyeView(
                    pupilLeading: 9.44 * scale,
                    eyeWhite: eyeWhite,
                    faceBlack: faceBlack
                )
                .frame(width: 25.46 * scale, height: 12.95 * scale)
                .position(x: origin.x + 32.37 * scale, y: origin.y + 30.98 * scale)

                OrangePeekEyeView(
                    pupilLeading: 9.44 * scale,
                    eyeWhite: eyeWhite,
                    faceBlack: faceBlack
                )
                .frame(width: 25.46 * scale, height: 12.95 * scale)
                .position(x: origin.x + 64.63 * scale, y: origin.y + 30.98 * scale)

                OrangeSmileView(faceBlack: faceBlack)
                    .frame(width: 26 * scale, height: 20 * scale)
                    .position(x: origin.x + 48.5 * scale, y: origin.y + 58.5 * scale)
            }
            .frame(width: drawSize.width, height: drawSize.height)
            .position(x: width / 2, y: height / 2)
        }
    }
}

private struct OrangeCharacterBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let designSize = CGSize(width: 92, height: 104)
        let scale = min(rect.width / designSize.width, rect.height / designSize.height)
        let origin = CGPoint(
            x: rect.midX - designSize.width * scale / 2,
            y: rect.midY - designSize.height * scale / 2
        )
        let x = { origin.x + $0 * scale }
        let y = { origin.y + $0 * scale }
        let radius = 13 * scale

        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: x(4.0), y: y(0.0), width: 41.86 * scale, height: 41.83 * scale),
            cornerSize: CGSize(width: radius, height: radius)
        )
        path.addRoundedRect(
            in: CGRect(x: x(45.86), y: y(0.0), width: 41.23 * scale, height: 41.83 * scale),
            cornerSize: CGSize(width: radius, height: radius)
        )
        path.addRoundedRect(
            in: CGRect(x: x(25.0), y: y(20.62), width: 41.86 * scale, height: 41.86 * scale),
            cornerSize: CGSize(width: radius, height: radius)
        )
        path.addRoundedRect(
            in: CGRect(x: x(4.0), y: y(41.86), width: 41.86 * scale, height: 41.23 * scale),
            cornerSize: CGSize(width: radius, height: radius)
        )
        path.addRoundedRect(
            in: CGRect(x: x(45.86), y: y(41.86), width: 41.23 * scale, height: 41.23 * scale),
            cornerSize: CGSize(width: radius, height: radius)
        )
        return path
    }
}

private struct OrangePeekEyeView: View {
    let pupilLeading: CGFloat
    let eyeWhite: Color
    let faceBlack: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let pupilWidth = width * (11.41 / 25.46)
            let pupilHeight = height * (5.92 / 12.95)

            ZStack(alignment: .topLeading) {
                Ellipse()
                    .fill(eyeWhite)
                    .frame(width: width, height: height * 2)
                    .frame(width: width, height: height, alignment: .top)
                    .clipped()

                Ellipse()
                    .fill(faceBlack)
                    .frame(width: pupilWidth, height: pupilHeight * 2)
                    .frame(width: pupilWidth, height: pupilHeight, alignment: .top)
                    .clipped()
                    .offset(x: pupilLeading, y: height - pupilHeight)
            }
            .frame(width: width, height: height)
        }
    }
}

private struct OrangeSmileView: View {
    let faceBlack: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .top) {
                Circle()
                    .fill(faceBlack)
                    .frame(width: width, height: width)
                    .offset(y: -width * 0.44)

                HStack(spacing: width * 0.045) {
                    RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                        .fill(.white)
                        .frame(width: width * 0.13, height: height * 0.34)

                    RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                        .fill(.white)
                        .frame(width: width * 0.13, height: height * 0.34)
                }
                .padding(.top, height * 0.02)
                .zIndex(1)
            }
            .frame(width: width, height: height)
            .clipped()
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
                Text(drill.displayTitle)
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
                    Text("\(drill.displayTitle) - Choose difficulty")
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
                Text(drill.displayTitle)
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

                Text(drill.displayTitle)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark ? Color.ballrDarkModeBackground : Color.ballrLightModeBackground)
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
