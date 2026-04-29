import SwiftUI

struct ContentView: View {
    @State private var hasCompletedOnboarding = true

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainBallrView()
            } else {
                OnboardingFlowView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
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
    static let ballrYellow = Color(red: 0.98, green: 0.79, blue: 0.19)
    static let ballrCream = Color(red: 0.99, green: 0.97, blue: 0.91)
    static let ballrBlack = Color(red: 0.08, green: 0.08, blue: 0.08)
}

private struct OnboardingFlowView: View {
    @Binding var hasCompletedOnboarding: Bool

    var body: some View {
        ZStack {
            BallrBackground()
            StartPageView {
                hasCompletedOnboarding = true
            }
        }
        .fontDesign(.rounded)
    }
}

private struct MainBallrView: View {
    @State private var selectedTab: BallrTab = .practice

    var body: some View {
        TabView(selection: $selectedTab) {
            LevelsHomeView()
                .tabItem {
                    Label("Levels", systemImage: "map.fill")
                }
                .tag(BallrTab.levels)

            PracticeHomeView()
                .tabItem {
                    Label("Practice", systemImage: "diamond.fill")
                }
                .tag(BallrTab.practice)

            ProfileHomeView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.shield.fill")
                }
                .tag(BallrTab.profile)
        }
        .tint(Color.ballrOrange)
        .fontDesign(.rounded)
    }
}

private struct StartPageView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.11, green: 0.10, blue: 0.11)
                .ignoresSafeArea()

            LevelsScreenBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 58)

                LevelsMapIcon()
                    .frame(width: 178, height: 128)

                Spacer(minLength: 48)

                Text("Ballr")
                    .font(.system(size: 52, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)

                Text("SOCCER TRAINING")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .tracking(4)
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.top, 14)

                Spacer(minLength: 48)

                Button(action: onStart) {
                    Text("START")
                        .font(.system(size: 27, weight: .black, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.78, green: 0.64, blue: 0.00))
                                .frame(height: 8)
                                .offset(y: 5)
                        }
                }
                .padding(.horizontal, 42)

                Text("Already have an account? Sign in")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.28))
                    .padding(.top, 32)

                Spacer(minLength: 82)
            }
        }
    }
}

private struct LevelsHomeView: View {
    @State private var selectedDrill: Drill?
    @State private var selectedHunterDifficulty: HunterDifficulty?
    @State private var promptedDrill: Drill?
    @State private var isShowingStreakResetMessage = false
    @AppStorage("levelsDailyStreak") private var dailyStreak = 0
    @AppStorage("levelsLastPlayedAt") private var lastPlayedAt = 0.0

    private let currentLevel = 1
    private let lockedLevels = Set(11...18)

    private let levelDrills = (1...20).map { level in
        Drill(
            title: "Level \(level)",
            subtitle: {
                switch level {
                case 1:
                    return "Ball Basics"
                case 2:
                    return "Hand Targets"
                case 3:
                    return "Foot Targets"
                case 4:
                    return "Ball Targets"
                case 5:
                    return "Timed Targets"
                case 6:
                    return "Bomb Targets"
                case 7:
                    return "Timed Hand Targets"
                case 8:
                    return "Timed Foot Targets"
                case 9:
                    return "Combo Targets"
                case 10:
                    return "Timed Targets 45%"
                case 19:
                    return "Ball Blast"
                case 20:
                    return "The Hunter"
                default:
                    return ["Juggling", "Dribbling", "First Touch", "Dribble Tiles"][(level - 1) % 4]
                }
            }(),
            level: level
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.11, green: 0.10, blue: 0.11)
                    .ignoresSafeArea()

                LevelsScreenBackground()
                    .ignoresSafeArea()

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

                        HStack(spacing: 8) {
                            LevelsHeaderStatChip(
                                systemImage: "flame.fill",
                                value: "\(dailyStreak)",
                                label: "Streak"
                            )

                            LevelsHeaderStatChip(
                                systemImage: "bolt.fill",
                                value: "1,240",
                                label: "XP"
                            )
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .frame(height: 78)
                    .background(.ultraThinMaterial)
                    .background(Color(red: 0.11, green: 0.10, blue: 0.11).opacity(0.76))
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(.white.opacity(0.24))
                            .frame(height: 1)
                    }

                    Spacer()
                }
            }
            .navigationDestination(item: $selectedDrill) { drill in
                if drill.level == 1 {
                    LevelOneCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 2 {
                    HandTargetCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 3 {
                    FootTargetCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 4 {
                    LevelFourCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 5 {
                    LevelFiveCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 6 {
                    LevelSixCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 7 {
                    LevelSevenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 8 {
                    LevelEightCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 9 {
                    LevelNineCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 10 {
                    LevelTenCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 19 {
                    TargetDrillCameraView()
                        .ballrCameraPresentationChrome()
                } else if drill.level == 20 {
                    HunterCameraView(difficulty: .hard)
                        .ballrCameraPresentationChrome()
                } else {
                    DrillPlaceholderView(drill: drill)
                }
            }
            .fullScreenCover(item: $selectedHunterDifficulty) { difficulty in
                HunterCameraView(difficulty: difficulty)
                    .ballrCameraPresentationChrome()
            }
            .onAppear(perform: resetMissedStreakIfNeeded)
            .alert("Streak reset", isPresented: $isShowingStreakResetMessage) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You missed a day, so your daily streak reset. Play once today to start it again.")
            }
        }
    }

    private func updateStreakForLevelStart() {
        let now = Date()

        guard lastPlayedAt > 0 else {
            dailyStreak = 1
            lastPlayedAt = now.timeIntervalSince1970
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
    }

    private func resetMissedStreakIfNeeded() {
        guard lastPlayedAt > 0, dailyStreak > 0 else {
            return
        }

        let lastPlayedDate = Date(timeIntervalSince1970: lastPlayedAt)
        let calendar = Calendar.current

        if !calendar.isDateInToday(lastPlayedDate) && !calendar.isDateInYesterday(lastPlayedDate) {
            dailyStreak = 0
            isShowingStreakResetMessage = true
        }
    }
}

private struct PracticeHomeView: View {
    @State private var selectedDrill: Drill?
    @State private var isShowingDribbling = false
    @State private var isShowingJumpingChallenge = false
    @State private var isShowingAgilityChallenge = false
    @State private var isShowingFastTouching = false
    @State private var isShowingFreezeChallenge = false
    @State private var promptedDifficultyDrill: Drill?
    @State private var selectedRockDropDifficulty: BallBlastRockDropDifficulty?
    @State private var selectedPianoTilesDifficulty: PianoTilesDifficulty?
    @State private var isShowingPrecisionTargets = false
    @State private var isShowingMultiplayerPrecisionTargets = false
    @State private var isShowingPassingGates = false

    private let drills = [
        Drill(title: "Jumping Challenge", subtitle: "Jump over the hurdles", level: nil),
        Drill(title: "Agility Challenge", subtitle: "Cross side to side fast", level: nil),
        Drill(title: "Fast Touching", subtitle: "Count every toe touch", level: nil),
        Drill(title: "Freeze Challenge", subtitle: "Move, then freeze fast", level: nil),
        Drill(title: "Juggling", subtitle: "Keep it up, score points", level: nil),
        Drill(title: "Dribbling", subtitle: "Weave through targets", level: nil),
        Drill(title: "Rock Drop", subtitle: "Dodge the falling rocks", level: nil),
        Drill(title: "Precision Targets", subtitle: "Hit the wall target", level: nil),
        Drill(title: "Precision VS", subtitle: "Alternate 5 shots each", level: nil),
        Drill(title: "Passing Gates", subtitle: "Pass through the gate", level: nil),
        Drill(title: "Piano Tiles", subtitle: "Hit every tile", level: nil),
        Drill(title: "Dribble\nTiles", subtitle: "Navigate the grid", level: nil)
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.11, green: 0.10, blue: 0.11)
                    .ignoresSafeArea()

                LevelsScreenBackground()
                    .ignoresSafeArea()

                GeometryReader { geometry in
                    ZStack {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .center) {
                                    LevelsMapIcon()
                                        .frame(width: 64, height: 46)

                                    Spacer()

                                    Text("FREE PRACTICE")
                                        .font(.system(size: 13, weight: .black, design: .rounded))
                                        .tracking(2)
                                        .foregroundStyle(Color.yellow)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.yellow.opacity(0.26), lineWidth: 1)
                                        }
                                }
                                .padding(.bottom, 26)

                                LazyVGrid(columns: columns, spacing: 12) {
                                    ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
                                        Button {
                                            if drill.title == "Jumping Challenge" {
                                                isShowingJumpingChallenge = true
                                            } else if drill.title == "Agility Challenge" {
                                                isShowingAgilityChallenge = true
                                            } else if drill.title == "Fast Touching" {
                                                isShowingFastTouching = true
                                            } else if drill.title == "Freeze Challenge" {
                                                isShowingFreezeChallenge = true
                                            } else if drill.title == "Dribbling" {
                                                isShowingDribbling = true
                                            } else if drill.title == "Rock Drop" {
                                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                                    if promptedDifficultyDrill?.id == drill.id {
                                                        promptedDifficultyDrill = nil
                                                    } else {
                                                        promptedDifficultyDrill = drill
                                                    }
                                                }
                                            } else if drill.title == "Piano Tiles" {
                                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                                    if promptedDifficultyDrill?.id == drill.id {
                                                        promptedDifficultyDrill = nil
                                                    } else {
                                                        promptedDifficultyDrill = drill
                                                    }
                                                }
                                            } else if drill.title == "Precision Targets" {
                                                isShowingPrecisionTargets = true
                                            } else if drill.title == "Precision VS" {
                                                isShowingMultiplayerPrecisionTargets = true
                                            } else if drill.title == "Passing Gates" {
                                                isShowingPassingGates = true
                                            } else {
                                                selectedDrill = drill
                                            }
                                        } label: {
                                            PracticeDrillCardView(drill: drill, style: PracticeDrillStyle(index: index))
                                        }
                                        .buttonStyle(.plain)
                                        .background(
                                            GeometryReader { cardGeometry in
                                                Color.clear.preference(
                                                    key: PracticeDrillFramePreferenceKey.self,
                                                    value: [drill.id: cardGeometry.frame(in: .named("PracticeHomeView"))]
                                                )
                                            }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 22)
                            .padding(.bottom, 34)
                        }
                        .overlayPreferenceValue(PracticeDrillFramePreferenceKey.self) { frames in
                            if
                                let activePromptDrill = promptedDifficultyDrill,
                                let frame = frames[activePromptDrill.id]
                            {
                                let promptWidth = min(248, max(218, geometry.size.width * 0.62))
                                let promptHeight: CGFloat = 176
                                let promptCenterX = min(max(frame.midX, promptWidth * 0.5 + 16), geometry.size.width - promptWidth * 0.5 - 16)
                                let promptCenterY = max(frame.minY - 98, promptHeight * 0.5 + 12)

                                PracticeDifficultyPromptView(
                                    drill: activePromptDrill,
                                    onSelectEasy: {
                                        promptedDifficultyDrill = nil
                                        if activePromptDrill.title == "Rock Drop" {
                                            selectedRockDropDifficulty = .easy
                                        } else if activePromptDrill.title == "Piano Tiles" {
                                            selectedPianoTilesDifficulty = .easy
                                        }
                                    },
                                    onSelectHard: {
                                        promptedDifficultyDrill = nil
                                        if activePromptDrill.title == "Rock Drop" {
                                            selectedRockDropDifficulty = .hard
                                        } else if activePromptDrill.title == "Piano Tiles" {
                                            selectedPianoTilesDifficulty = .hard
                                        }
                                    },
                                    onCancel: {
                                        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                            promptedDifficultyDrill = nil
                                        }
                                    }
                                )
                                .frame(width: promptWidth)
                                .position(x: promptCenterX, y: promptCenterY)
                                .transition(.scale(scale: 0.94).combined(with: .opacity))
                                .zIndex(2)
                            }
                        }
                    }
                }
            }
            .coordinateSpace(name: "PracticeHomeView")
            .fullScreenCover(isPresented: $isShowingJumpingChallenge) {
                JumpingChallengeCameraView()
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(isPresented: $isShowingAgilityChallenge) {
                AgilityChallengeCameraView()
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(isPresented: $isShowingFastTouching) {
                FastTouchingCameraView()
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(isPresented: $isShowingFreezeChallenge) {
                FreezeChallengeCameraView()
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(isPresented: $isShowingDribbling) {
                DribblingCameraView()
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(item: $selectedDrill) { drill in
                if drill.title == "Juggling" {
                    JugglingDrillIntroScreen()
                } else {
                    DrillPlaceholderView(drill: drill)
                }
            }
            .fullScreenCover(item: $selectedRockDropDifficulty) { difficulty in
                BallBlastRockDropCameraView(difficulty: difficulty)
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(item: $selectedPianoTilesDifficulty) { difficulty in
                PianoTilesCameraView(difficulty: difficulty)
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(isPresented: $isShowingPrecisionTargets) {
                PrecisionTargetCameraView()
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(isPresented: $isShowingMultiplayerPrecisionTargets) {
                MultiplayerPrecisionTargetCameraView()
                    .ballrCameraPresentationChrome()
            }
            .fullScreenCover(isPresented: $isShowingPassingGates) {
                PassingGateCameraView()
                    .ballrCameraPresentationChrome()
            }
        }
    }
}

private struct ProfileHomeView: View {
    private let slots = (0..<5).map { _ in AchievementSlot() }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.11, green: 0.10, blue: 0.11)
                    .ignoresSafeArea()

                LevelsScreenBackground()
                    .ignoresSafeArea()

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
                                    .font(.system(size: 22, weight: .black))
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

                        ProfilePlayerCard()

                        HStack(spacing: 12) {
                            ProfileStatCard(value: "47", label: "BEST\nJUGGLES", valueColor: Color.yellow)
                            ProfileStatCard(value: "12", label: "DRILLS DONE", valueColor: Color.orange)
                            ProfileStatCard(value: "5", label: "DAY STREAK", valueColor: .white)
                        }

                        Text("ACHIEVEMENTS")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(Color.yellow.opacity(0.58))
                            .padding(.top, 2)

                        ProfileAchievementRow(slots: slots)

                        NavigationLink {
                            BallrCardDetailView()
                        } label: {
                            HStack {
                                Text("VIEW BALLR CARD")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.yellow)

                                Spacer()

                                Circle()
                                    .fill(Color.yellow)
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 16, weight: .black))
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

    private let backgroundYellow = Color(red: 1.0, green: 0.847, blue: 0.0)
    private let characterPurple = Color(red: 0.631, green: 0.427, blue: 0.757)
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
            let bodyHeight = isLandscape ? height * 1.95 : height * 1.25
            let bodyCenterY = isLandscape ? height * 1.02 : height * 0.74
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
            let topContentSpacer = isLandscape ? height * 0.12 : height * 0.31
            let eyeSpacing = isLandscape ? base * 0.16 : width * 0.09
            let mouthTopPadding = isLandscape ? 14.0 : 20.0
            let cardTopPadding = isLandscape ? 22.0 : 30.0
            let faceScaleFactor = isLandscape ? 0.84 : 1.0
            let logoWidth = isLandscape ? 54.0 : 60.0
            let logoHeight = isLandscape ? 40.0 : 44.0

            ZStack(alignment: .topLeading) {
                backgroundYellow
                    .ignoresSafeArea()

                Group {
                    Capsule()
                        .fill(characterPurple)
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

                VStack(spacing: 0) {
                    HStack {
                        LevelsMapIcon(fillColor: logoBlack)
                            .frame(width: logoWidth, height: logoHeight)
                        Spacer()
                    }
                    .padding(.top, max(safeTop * 0.14, 4))
                    .padding(.leading, 14)
                    .padding(.trailing, 24)

                    Spacer()
                }

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .black))
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
                                VStack(spacing: 22) {
                                    Text("POWER")
                                        .font(.system(size: min(width * 0.12, 48), weight: .light, design: .rounded))
                                        .foregroundStyle(.white)

                                    Text("KEEP THE BALL\nIN THE AIR")
                                        .font(.system(size: min(width * 0.06, 23), weight: .medium, design: .rounded))
                                        .multilineTextAlignment(.center)
                                        .foregroundStyle(.white)
                                }
                                .tracking(0.8)
                                .padding(.top, 8)
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
            resetLaunchState(animated: true)
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
        .font(.system(size: size, weight: .black, design: .rounded))
    }
}

private struct ProfilePlayerCard: View {
    var body: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.yellow)
                Image(systemName: "person.fill")
                    .font(.system(size: 38, weight: .black))
                    .foregroundStyle(Color.ballrBlack)
            }
            .frame(width: 86, height: 86)
            .overlay(
                Circle()
                    .stroke(Color.orange, lineWidth: 4)
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Bishoy")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Level 3 · 1,240 XP")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.12))
                        Capsule()
                            .fill(Color.yellow)
                            .frame(width: geometry.size.width * 0.60)
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
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(valueColor)

            Text(label)
                .font(.system(size: 12, weight: .black, design: .rounded))
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
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
            } else if index == 1 {
                Text("🔥")
                    .font(.system(size: 26))
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
            SoccerFieldBackground(showsStadiumLabels: false)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                BallrEliteCard()

                HStack(spacing: 16) {
                    Button {
                    } label: {
                        Text("SHARE")
                            .font(.system(size: 18, weight: .black, design: .rounded))
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
                            .font(.system(size: 18, weight: .black, design: .rounded))
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
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct BallrEliteCard: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("87")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text("OVR")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.22))
                            .frame(width: 40, height: 48)
                            .overlay {
                                Image(systemName: "soccerball")
                                    .font(.system(size: 22, weight: .black))
                                    .foregroundStyle(.white)
                            }
                            .padding(.top, 10)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 8) {
                        Text("BALLR")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(.white)

                        Text("SEASON 1")
                            .font(.system(size: 13, weight: .black, design: .rounded))
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
                                Text("B")
                                    .font(.system(size: 38, weight: .black, design: .rounded))
                                    .foregroundStyle(Color.ballrBlack)
                            }
                            .offset(y: 20)
                    }

                VStack(spacing: 14) {
                    Text("BISHOY")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(6)
                        .foregroundStyle(Color.yellow)
                        .padding(.top, 38)

                    VStack(spacing: 12) {
                        HStack {
                            BallrCardStat(value: "92", label: "JUG")
                            BallrCardStat(value: "85", label: "DRB")
                            BallrCardStat(value: "88", label: "SPD")
                        }

                        Rectangle()
                            .fill(.white.opacity(0.22))
                            .frame(height: 2)

                        HStack {
                            BallrCardStat(value: "78", label: "SHT")
                            BallrCardStat(value: "81", label: "PAS")
                            BallrCardStat(value: "74", label: "STR")
                        }
                    }
                    .padding(.horizontal, 20)

                    Text("BALLR ELITE")
                        .font(.system(size: 18, weight: .black, design: .rounded))
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
                .font(.system(size: 27, weight: .black, design: .rounded))
                .foregroundStyle(label == "JUG" || label == "DRB" || label == "SPD" ? Color.yellow : .white)

            Text(label)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BallrSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var soundEnabled = true
    @State private var notificationsEnabled = false

    var body: some View {
        ZStack {
            SoccerFieldBackground(showsStadiumLabels: false)
                .ignoresSafeArea()

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
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundStyle(Color.yellow)
                            }
                    }

                    Text("Settings")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(Color.yellow)

                    Spacer()
                }
                .padding(.top, 18)
                .padding(.bottom, 10)

                VStack(spacing: 0) {
                    SettingsNavigationRow(
                        icon: "pencil",
                        title: "Change name",
                        subtitle: "Bishoy",
                        iconBackground: Color.yellow.opacity(0.16),
                        iconColor: Color.yellow
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

                Spacer()

                HStack(spacing: 5) {
                    Text("Ballr v1.0 · Made with")
                    Text("⚽")
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.22))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 18)
            }
            .padding(.horizontal, 24)
        }
        .toolbar(.hidden, for: .navigationBar)
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
                    .font(.system(size: 19, weight: .black, design: .rounded))
                    .foregroundStyle(titleColor)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.38))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .black))
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
                .font(.system(size: 19, weight: .black, design: .rounded))
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
                    .font(.system(size: 22, weight: .black))
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
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color(red: 1.0, green: 0.32, blue: 0.18))

            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)

                Text(label.uppercased())
                    .font(.system(size: 7, weight: .black, design: .rounded))
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
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let fieldInset = width * 0.11
            let fieldTop = height * 0.155
            let fieldBottom = height * 0.90
            let centerY = (fieldTop + fieldBottom) / 2

            ZStack {
                Color(red: 0.11, green: 0.10, blue: 0.11)

                LinearGradient(
                    colors: [
                        Color(red: 0.02, green: 0.10, blue: 0.04),
                        Color(red: 0.03, green: 0.15, blue: 0.06),
                        Color(red: 0.02, green: 0.09, blue: 0.04)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(spacing: 0) {
                    ForEach(0..<14, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.018) : Color.black.opacity(0.055))
                    }
                }

                VStack(spacing: 8) {
                    ForEach(0..<4, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<24, id: \.self) { seat in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill((seat + row).isMultiple(of: 5) ? Color.yellow.opacity(0.16) : Color.white.opacity(0.055))
                                    .frame(width: 6, height: 5)
                            }
                        }
                        .offset(x: row.isMultiple(of: 2) ? -12 : 12)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 94)
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(0.62)

                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 9) {
                            ForEach(0..<22, id: \.self) { seat in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill((seat + row * 2).isMultiple(of: 6) ? Color.yellow.opacity(0.12) : Color.white.opacity(0.04))
                                    .frame(width: 6, height: 5)
                            }
                        }
                        .offset(x: row.isMultiple(of: 2) ? 10 : -10)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 96)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(0.42)

                Path { path in
                    path.addRoundedRect(
                        in: CGRect(
                            x: fieldInset,
                            y: fieldTop,
                            width: width - fieldInset * 2,
                            height: fieldBottom - fieldTop
                        ),
                        cornerSize: CGSize(width: 8, height: 8)
                    )

                    path.move(to: CGPoint(x: fieldInset, y: centerY))
                    path.addLine(to: CGPoint(x: width - fieldInset, y: centerY))
                    path.addEllipse(
                        in: CGRect(
                            x: width / 2 - 72,
                            y: centerY - 72,
                            width: 144,
                            height: 144
                        )
                    )
                    path.addEllipse(
                        in: CGRect(
                            x: width / 2 - 5,
                            y: centerY - 5,
                            width: 10,
                            height: 10
                        )
                    )
                    path.addRoundedRect(
                        in: CGRect(
                            x: width / 2 - 54,
                            y: fieldTop + 2,
                            width: 108,
                            height: 46
                        ),
                        cornerSize: CGSize(width: 6, height: 6)
                    )
                    path.addRoundedRect(
                        in: CGRect(
                            x: width / 2 - 54,
                            y: fieldBottom - 48,
                            width: 108,
                            height: 46
                        ),
                        cornerSize: CGSize(width: 6, height: 6)
                    )
                }
                .stroke(Color.white.opacity(0.055), lineWidth: 2)

                Path { path in
                    path.move(to: CGPoint(x: fieldInset, y: fieldTop))
                    path.addLine(to: CGPoint(x: width - fieldInset, y: fieldTop))
                }
                .stroke(Color.white.opacity(0.075), style: StrokeStyle(lineWidth: 2, lineCap: .round))

                ForEach(0..<10, id: \.self) { index in
                    Path { path in
                        let y = fieldTop + 28 + CGFloat(index) * (fieldBottom - fieldTop) / 10
                        path.move(to: CGPoint(x: fieldInset + 12, y: y))
                        path.addLine(to: CGPoint(x: width - fieldInset - 12, y: y - 18))
                    }
                    .stroke(Color.white.opacity(0.024), lineWidth: 1)
                }

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.50),
                        Color.clear,
                        Color.clear,
                        Color.black.opacity(0.38)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.30),
                        Color.clear,
                        Color.black.opacity(0.30)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
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
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 26)

                    if drill.level == 20 {
                        HStack(spacing: 10) {
                            Button(action: { onSelectEasy?() }) {
                                Text("EASY")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)

                            Button(action: { onSelectHard?() }) {
                                Text("HARD")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(Color(red: 1.0, green: 0.29, blue: 0.18), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 18)
                    } else {
                        Button(action: onStart) {
                            Text("START")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color(red: 1.0, green: 0.29, blue: 0.18), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .id(drill.id)
                .transition(.opacity)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
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
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack {
                Color(red: 0.01, green: 0.14, blue: 0.04)

                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.018) : Color.black.opacity(0.045))
                    }
                }

                Path { path in
                    path.addRect(CGRect(x: 24, y: 0, width: width - 48, height: height - 18))

                    for index in 1..<8 {
                        let y = CGFloat(index) * height / 8
                        path.move(to: CGPoint(x: 24, y: y))
                        path.addLine(to: CGPoint(x: width - 24, y: y))
                    }

                    for index in 0..<4 {
                        let y = CGFloat(index) * height / 3
                        path.addEllipse(in: CGRect(x: width / 2 - 54, y: y + 80, width: 108, height: 108))
                    }

                    for index in 0..<4 {
                        let y = CGFloat(index) * height / 3
                        path.addRect(CGRect(x: width / 2 - 62, y: y, width: 124, height: 70))
                    }
                }
                .stroke(Color.white.opacity(0.045), lineWidth: 3)

                if showsStadiumLabels {
                    ForEach(0..<4, id: \.self) { section in
                        let sectionHeight = height * 0.18
                        let sectionGap = height * 0.06
                        let bottomY = height * 0.94
                        let sectionBottomY = bottomY - CGFloat(section) * (sectionHeight + sectionGap)
                        let labelY = sectionBottomY - sectionHeight + 26

                        Text("STADIUM \(section + 1)")
                            .font(.system(size: 16, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(Color.yellow.opacity(0.22))
                            .frame(width: width)
                            .position(x: width / 2, y: labelY)
                    }

                    ForEach(1..<4, id: \.self) { section in
                        let sectionHeight = height * 0.18
                        let sectionGap = height * 0.06
                        let bottomY = height * 0.94
                        let dividerY = bottomY - CGFloat(section) * sectionHeight - CGFloat(section - 1) * sectionGap - sectionGap / 2

                        VStack(spacing: 8) {
                            Rectangle()
                                .fill(Color.yellow.opacity(0.22))
                                .frame(height: 2)

                            Text("NEXT STADIUM")
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .tracking(2)
                                .foregroundStyle(Color.yellow.opacity(0.35))
                        }
                        .frame(width: width - 52)
                        .position(x: width / 2, y: dividerY)
                    }
                }
            }
        }
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
                        .font(.system(size: level > 9 ? 16 : 20, weight: .black, design: .rounded))
                        .foregroundStyle(isLocked ? .white.opacity(0.40) : Color(red: 0.11, green: 0.10, blue: 0.11))

                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .black))
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
                    .font(.headline.weight(.black))
                    .foregroundStyle(Color.ballrBlack)

                Text(drill.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ballrBlack.opacity(0.7))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.headline.weight(.black))
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
            symbol = "pianokeys"
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
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24)

                    Text(drill.subtitle)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11).opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .padding(.horizontal, 24)

                    HStack(spacing: 10) {
                        Button(action: onSelectEasy) {
                            Text("EASY")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundStyle(Color(red: 0.11, green: 0.10, blue: 0.11))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        Button(action: onSelectHard) {
                            Text("HARD")
                                .font(.system(size: 14, weight: .black, design: .rounded))
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
                        .font(.system(size: 13, weight: .black))
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
                        .font(.system(size: 21, weight: .black))
                        .foregroundStyle(style.iconForeground)
                }

                Spacer()

                Circle()
                    .fill(.white.opacity(style.playOpacity))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.system(size: 14, weight: .black))
                            .foregroundStyle(style.accentColor)
                            .offset(x: 1.5)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(drill.title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.76)
                    .fixedSize(horizontal: false, vertical: true)

                Text(drill.subtitle)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
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
                    .font(.largeTitle.weight(.black))

                Text("Camera drill view coming soon.")
                    .font(.title3.weight(.bold))
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
                            .font(.headline.weight(.black))
                            .foregroundStyle(Color.ballrOrange)

                        ZStack {
                            Circle()
                                .fill(Color.ballrCream)
                                .frame(width: 96, height: 96)

                            Image(systemName: "figure.soccer")
                                .font(.system(size: 48, weight: .black))
                                .foregroundStyle(Color.ballrOrange)
                        }

                        Text("Rookie Striker")
                            .font(.title3.weight(.black))
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
            .font(.system(size: 36, weight: .black, design: .rounded))
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
                .font(.title2.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Color.ballrOrange, in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.black))

                Text(description)
                    .font(.subheadline.weight(.medium))
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
