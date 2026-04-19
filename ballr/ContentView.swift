import SwiftUI

struct ContentView: View {
    @AppStorage("selectedAvatarID") private var selectedAvatarID = AvatarOption.defaultOptions[0].id
    @State private var hasCompletedOnboarding = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                MainBallrView(selectedAvatar: selectedAvatar)
            } else {
                OnboardingFlowView(
                    hasCompletedOnboarding: $hasCompletedOnboarding,
                    selectedAvatar: selectedAvatarBinding
                )
            }
        }
    }

    private var selectedAvatar: AvatarOption {
        AvatarOption.option(for: selectedAvatarID)
    }

    private var selectedAvatarBinding: Binding<AvatarOption> {
        Binding(
            get: { selectedAvatar },
            set: { selectedAvatarID = $0.id }
        )
    }
}

private enum BallrTab: Hashable {
    case levels
    case practice
    case profile
}

private enum OnboardingStep {
    case start
    case avatar
}

private struct AvatarOption: Identifiable, Hashable {
    let id: Int
    let title: String
    let centerX: CGFloat
    let centerY: CGFloat

    static let defaultOptions = [
        AvatarOption(id: 0, title: "Keeper", centerX: 0.1944, centerY: 0.1433),
        AvatarOption(id: 1, title: "Captain", centerX: 0.3981, centerY: 0.1433),
        AvatarOption(id: 2, title: "Playmaker", centerX: 0.6019, centerY: 0.1433),
        AvatarOption(id: 3, title: "Striker", centerX: 0.8056, centerY: 0.1433),
        AvatarOption(id: 4, title: "Dribbler", centerX: 0.1944, centerY: 0.3822),
        AvatarOption(id: 5, title: "Creator", centerX: 0.3981, centerY: 0.3822),
        AvatarOption(id: 6, title: "Sprinter", centerX: 0.6019, centerY: 0.3822),
        AvatarOption(id: 7, title: "Defender", centerX: 0.8056, centerY: 0.3822),
        AvatarOption(id: 8, title: "Speedster", centerX: 0.1944, centerY: 0.6267),
        AvatarOption(id: 9, title: "Blaster", centerX: 0.3981, centerY: 0.6267),
        AvatarOption(id: 10, title: "Builder", centerX: 0.6019, centerY: 0.6267),
        AvatarOption(id: 11, title: "Chef", centerX: 0.8056, centerY: 0.6267),
        AvatarOption(id: 12, title: "Rookie", centerX: 0.1944, centerY: 0.8567),
        AvatarOption(id: 13, title: "Scholar", centerX: 0.3981, centerY: 0.8567),
        AvatarOption(id: 14, title: "Ace", centerX: 0.6019, centerY: 0.8567),
        AvatarOption(id: 15, title: "Artist", centerX: 0.8056, centerY: 0.8567)
    ]

    static func option(for id: Int) -> AvatarOption {
        defaultOptions.first { $0.id == id } ?? defaultOptions[0]
    }
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
    @Binding var selectedAvatar: AvatarOption
    @State private var step: OnboardingStep = .start

    var body: some View {
        ZStack {
            BallrBackground()

            switch step {
            case .start:
                StartPageView {
                    step = .avatar
                }
            case .avatar:
                BuildAvatarView(
                    selectedAvatar: $selectedAvatar,
                    avatarOptions: AvatarOption.defaultOptions
                ) {
                    hasCompletedOnboarding = true
                }
            }
        }
        .fontDesign(.rounded)
    }
}

private struct MainBallrView: View {
    @State private var selectedTab: BallrTab = .levels
    let selectedAvatar: AvatarOption

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

            ProfileHomeView(selectedAvatar: selectedAvatar)
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
            Color(red: 0.04, green: 0.04, blue: 0.04)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 58)

                ZStack {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 140, height: 140)

                    Circle()
                        .stroke(Color(red: 0.04, green: 0.04, blue: 0.04), lineWidth: 7)
                        .frame(width: 64, height: 64)
                }

                Spacer(minLength: 48)

                HStack(spacing: 0) {
                    Text("Ball")
                        .foregroundStyle(Color.yellow)
                    Text("r")
                        .foregroundStyle(Color.orange)
                }
                .font(.system(size: 52, weight: .black, design: .rounded))

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
                        .background(Color.yellow, in: Capsule())
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

private struct BuildAvatarView: View {
    @Binding var selectedAvatar: AvatarOption

    let avatarOptions: [AvatarOption]
    let onContinue: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.04)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Text("Build your avatar")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)
                    .padding(.top, 28)

                AvatarPreview(avatar: selectedAvatar)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)

                Text("CHOOSE YOUR PLAYER")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.38))
                    .frame(maxWidth: .infinity)
                .padding(.top, 18)

                AvatarChoiceGrid(
                    selectedAvatar: $selectedAvatar,
                    avatarOptions: avatarOptions,
                    columns: columns
                )
                .padding(.top, 18)

                Button(action: onContinue) {
                    Text("NEXT")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.04, green: 0.04, blue: 0.04))
                        .frame(maxWidth: .infinity)
                        .frame(height: 76)
                        .background(Color.yellow, in: Capsule())
                }
                .padding(.top, 26)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 22)
        }
    }
}

private struct AvatarChoiceGrid: View {
    @Binding var selectedAvatar: AvatarOption

    let avatarOptions: [AvatarOption]
    let columns: [GridItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(avatarOptions) { avatar in
                AvatarChoiceTile(
                    avatar: avatar,
                    isSelected: selectedAvatar.id == avatar.id
                ) {
                    selectedAvatar = avatar
                }
            }
        }
    }
}

private struct AvatarChoiceTile: View {
    let avatar: AvatarOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.yellow.opacity(0.22) : Color.white.opacity(0.07))

                VStack(spacing: 6) {
                    AvatarSheetCrop(avatar: avatar)
                        .frame(width: 62, height: 62)
                        .clipShape(Circle())

                    Text(avatar.title)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(isSelected ? Color.yellow : .white.opacity(0.68))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.yellow : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

private struct LevelsHomeView: View {
    @State private var selectedDrill: Drill?
    @State private var isShowingSettings = false
    @State private var playerName = "Ballr Kid"
    @State private var soundEnabled = true

    private let levelDrills = (1...20).map { level in
        Drill(
            title: "Level \(level)",
            subtitle: {
                switch level {
                case 2:
                    return "Hand Targets"
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
                Color(red: 0.01, green: 0.12, blue: 0.03)
                    .ignoresSafeArea()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            HStack {
                                HStack(spacing: 0) {
                                    Text("Ball")
                                        .foregroundStyle(Color.yellow)
                                    Text("r")
                                        .foregroundStyle(Color.orange)
                                }
                                .font(.system(size: 38, weight: .black, design: .rounded))

                                Spacer()

                                HStack(spacing: 8) {
                                    HStack(spacing: 5) {
                                        Text("🔥")
                                            .font(.system(size: 15))
                                        Text("5")
                                            .font(.system(size: 14, weight: .black, design: .rounded))
                                            .foregroundStyle(Color.yellow)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.yellow.opacity(0.75), lineWidth: 2)
                                    )

                                    Button {
                                        isShowingSettings.toggle()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(Color.yellow)
                                                .frame(width: 14, height: 14)
                                            Text("1,240 XP")
                                                .font(.system(size: 14, weight: .black, design: .rounded))
                                                .foregroundStyle(Color.yellow)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.yellow, lineWidth: 2)
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 18)
                            .padding(.bottom, 10)

                            LevelsMapView(drills: levelDrills) { drill in
                                selectedDrill = drill
                            }
                            .frame(height: 2600)
                        }
                    }
                    .onAppear {
                        proxy.scrollTo(10, anchor: .center)
                    }
                    .onChange(of: playerName) { _, _ in
                        if !isShowingSettings {
                            proxy.scrollTo(10, anchor: .center)
                        }
                    }
                }

                if isShowingSettings {
                    SettingsOverlay(
                        playerName: $playerName,
                        soundEnabled: $soundEnabled,
                        dismiss: { isShowingSettings = false }
                    )
                }
            }
            .navigationDestination(item: $selectedDrill) { drill in
                if drill.level == 2 {
                    HandTargetCameraView()
                        .navigationBarBackButtonHidden(true)
                } else if drill.level == 19 {
                    TargetDrillCameraView()
                        .navigationBarBackButtonHidden(true)
                } else if drill.level == 20 {
                    HunterCameraView()
                        .navigationBarBackButtonHidden(true)
                } else {
                    DrillPlaceholderView(drill: drill)
                }
            }
        }
    }
}

private struct PracticeHomeView: View {
    @State private var selectedDrill: Drill?
    @State private var isShowingDribbling = false
    @State private var isShowingBallBlast = false
    @State private var isShowingPrecisionTargets = false
    @State private var isShowingPassingGates = false
    @State private var isShowingPianoTiles = false

    private let drills = [
        Drill(title: "Juggling", subtitle: "Keep it up, score points", level: nil),
        Drill(title: "Dribbling", subtitle: "Weave through targets", level: nil),
        Drill(title: "Ball Blast", subtitle: "Hit targets fast", level: nil),
        Drill(title: "Precision Targets", subtitle: "Hit the wall target", level: nil),
        Drill(title: "Passing Gates", subtitle: "Pass through the gate", level: nil),
        Drill(title: "Piano Tiles", subtitle: "Hit every tile", level: nil),
        Drill(title: "Dribble\nTiles", subtitle: "Navigate the grid", level: nil)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                SoccerFieldBackground(showsStadiumLabels: false)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .center) {
                            BallrWordmark(size: 42)

                            Spacer()

                            Text("FREE PRACTICE")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.bottom, 58)

                        ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
                            Button {
                                if drill.title == "Dribbling" {
                                    isShowingDribbling = true
                                } else if drill.title == "Ball Blast" {
                                    isShowingBallBlast = true
                                } else if drill.title == "Precision Targets" {
                                    isShowingPrecisionTargets = true
                                } else if drill.title == "Passing Gates" {
                                    isShowingPassingGates = true
                                } else if drill.title == "Piano Tiles" {
                                    isShowingPianoTiles = true
                                } else {
                                    selectedDrill = drill
                                }
                            } label: {
                                PracticeDrillCardView(drill: drill, style: PracticeDrillStyle(index: index))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 34)
                }
            }
            .navigationDestination(item: $selectedDrill) { drill in
                DrillPlaceholderView(drill: drill)
            }
            .fullScreenCover(isPresented: $isShowingDribbling) {
                DribblingCameraView()
            }
            .fullScreenCover(isPresented: $isShowingBallBlast) {
                BallBlastRockDropCameraView()
            }
            .fullScreenCover(isPresented: $isShowingPrecisionTargets) {
                PrecisionTargetCameraView()
            }
            .fullScreenCover(isPresented: $isShowingPassingGates) {
                PassingGateCameraView()
            }
            .fullScreenCover(isPresented: $isShowingPianoTiles) {
                PianoTilesCameraView()
            }
        }
    }
}

private struct ProfileHomeView: View {
    let selectedAvatar: AvatarOption
    private let slots = (0..<5).map { _ in AchievementSlot() }

    var body: some View {
        NavigationStack {
            ZStack {
                SoccerFieldBackground(showsStadiumLabels: false)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            BallrWordmark(size: 42)

                            Spacer()

                            NavigationLink {
                                BallrSettingsView()
                            } label: {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 22, weight: .black))
                                    .foregroundStyle(Color.yellow)
                                    .frame(width: 48, height: 48)
                            }
                        }
                        .padding(.bottom, 28)

                        ProfilePlayerCard(selectedAvatar: selectedAvatar)

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
                            .background(Color.black.opacity(0.76), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color.yellow.opacity(0.32), lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 34)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
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
    let selectedAvatar: AvatarOption

    var body: some View {
        HStack(spacing: 20) {
            Circle()
                .frame(width: 86, height: 86)
                .overlay {
                    AvatarSheetCrop(avatar: selectedAvatar)
                        .clipShape(Circle())
                }
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
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
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
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
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
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 16))
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

                    SettingsNavigationRow(
                        icon: "person.fill",
                        title: "Change avatar",
                        subtitle: "Edit your player",
                        iconBackground: Color.orange.opacity(0.13),
                        iconColor: Color.orange
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

private struct SettingsOverlay: View {
    @Binding var playerName: String
    @Binding var soundEnabled: Bool
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Settings")
                        .font(.title.weight(.black))
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.ballrOrange)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Change Name")
                        .font(.headline.weight(.bold))
                    TextField("Player name", text: $playerName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Change Avatar")
                        .font(.headline.weight(.bold))
                    HStack(spacing: 12) {
                        ForEach(["face.smiling", "figure.soccer", "star.fill"], id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.title2)
                                .foregroundStyle(Color.ballrOrange)
                                .frame(width: 48, height: 48)
                                .background(Color.ballrCream, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }

                Toggle(isOn: $soundEnabled) {
                    Text("Sound")
                        .font(.headline.weight(.bold))
                }
                .tint(Color.ballrOrange)
            }
            .padding(20)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.ballrBlack, lineWidth: 2)
            )
            .padding(.horizontal, 28)
        }
    }
}

private struct LevelsMapView: View {
    let drills: [Drill]
    let onSelect: (Drill) -> Void

    private var nodePositions: [CGPoint] {
        drills.indices.map { index in
            let section = index / 5
            let item = index % 5
            let sectionHeight: CGFloat = 0.18
            let sectionGap: CGFloat = 0.06
            let bottomY: CGFloat = 0.94
            let xPattern: [CGFloat] = [0.34, 0.66, 0.43, 0.72, 0.52]
            let baseX = xPattern[item]

            return CGPoint(
                x: section.isMultiple(of: 2) ? baseX : 1 - baseX,
                y: bottomY - CGFloat(section) * (sectionHeight + sectionGap) - CGFloat(item) * (sectionHeight / 4)
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SoccerFieldBackground()

                ForEach(0..<4, id: \.self) { section in
                    let startIndex = section * 5
                    let endIndex = min(startIndex + 5, nodePositions.count)
                    let points = Array(nodePositions[startIndex..<endIndex])

                    LevelPathShape(points: points)
                        .stroke(
                            Color.white.opacity(0.24),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round, dash: [13, 13])
                        )
                }

                ForEach(Array(drills.enumerated()), id: \.element.id) { index, drill in
                    let point = nodePositions[index]

                    Button {
                        onSelect(drill)
                    } label: {
                        LevelNodeView(level: index + 1)
                    }
                    .id(index + 1)
                    .position(x: point.x * geometry.size.width, y: point.y * geometry.size.height)
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
    private let unlockedLevelCount = 10

    private var status: String? {
        if level < unlockedLevelCount {
            "DONE"
        } else if level == unlockedLevelCount {
            "CURRENT"
        } else if level == unlockedLevelCount + 1 {
            "LOCKED"
        } else {
            nil
        }
    }

    private var isLocked: Bool {
        level > unlockedLevelCount
    }

    private var fillColor: Color {
        if isLocked {
            Color(red: 0.03, green: 0.12, blue: 0.04)
        } else if level == unlockedLevelCount {
            Color.orange
        } else {
            Color.yellow
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let status {
                Text(status)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(level == unlockedLevelCount ? Color.ballrBlack : (isLocked ? .white.opacity(0.2) : Color.yellow))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(
                        Group {
                            if level == unlockedLevelCount {
                                Capsule().fill(Color.yellow)
                            } else {
                                Capsule().fill(.clear)
                            }
                        }
                    )
                    .offset(y: 8)
                    .zIndex(1)
            }

            ZStack {
                Circle()
                    .stroke(Color.yellow.opacity(isLocked ? 0.08 : 0.24), lineWidth: 14)
                    .frame(width: level == unlockedLevelCount ? 90 : 76, height: level == unlockedLevelCount ? 90 : 76)

                Circle()
                    .fill(fillColor.opacity(isLocked ? 0.16 : 1))
                    .frame(width: level == unlockedLevelCount ? 58 : 50, height: level == unlockedLevelCount ? 58 : 50)
                    .overlay(
                        Circle()
                            .stroke(Color.orange.opacity(isLocked ? 0.08 : 1), lineWidth: 4)
                    )

                Text("\(level)")
                    .font(.system(size: level == unlockedLevelCount ? 22 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(isLocked ? .white.opacity(0.14) : (level == unlockedLevelCount ? .white : Color.ballrBlack))
            }
        }
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
            let previous = resolvedPoints[index - 1]
            let current = resolvedPoints[index]
            let midY = (previous.y + current.y) / 2

            path.addCurve(
                to: current,
                control1: CGPoint(x: previous.x, y: midY),
                control2: CGPoint(x: current.x, y: midY)
            )
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
            symbol = "circle.fill"
            playOpacity = 1
        case 1:
            iconColor = .orange
            iconForeground = .white
            accentColor = .orange
            symbol = "play.fill"
            playOpacity = 0.28
        case 2:
            iconColor = .orange
            iconForeground = .white
            accentColor = .orange
            symbol = "play.fill"
            playOpacity = 0.28
        case 3:
            iconColor = .yellow
            iconForeground = Color.ballrBlack
            accentColor = .yellow
            symbol = "scope"
            playOpacity = 0.28
        case 4:
            iconColor = Color(red: 0.55, green: 0.95, blue: 0.70)
            iconForeground = Color.ballrBlack
            accentColor = Color(red: 0.55, green: 0.95, blue: 0.70)
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

private struct PracticeDrillCardView: View {
    let drill: Drill
    let style: PracticeDrillStyle

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(style.iconColor)
                    .frame(width: 68, height: 68)

                Image(systemName: style.symbol)
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(style.iconForeground)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(drill.title)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(drill.subtitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(2)
            }

            Spacer()

            Circle()
                .fill(.white.opacity(style.playOpacity))
                .frame(width: 48, height: 48)
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 21, weight: .black))
                        .foregroundStyle(style.accentColor)
                        .offset(x: 2)
                }
        }
        .padding(.horizontal, 28)
        .frame(height: 110)
        .background(Color.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20)
                .stroke(style.accentColor.opacity(0.8), lineWidth: 2)
                .mask(
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
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

private struct AvatarPreview: View {
    let avatar: AvatarOption

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.yellow.opacity(0.18))
                .frame(width: 176, height: 176)

            Circle()
                .stroke(Color.yellow, lineWidth: 4)
                .frame(width: 176, height: 176)

            AvatarSheetCrop(avatar: avatar)
                .frame(width: 156, height: 156)
                .clipShape(Circle())

            VStack {
                Spacer()

                Text(avatar.title.uppercased())
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Color.ballrBlack)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Color.yellow, in: Capsule())
                    .offset(y: 10)
            }
        }
        .frame(height: 180)
    }
}

private struct AvatarSheetCrop: View {
    let avatar: AvatarOption

    private let sheetSize: CGFloat = 900
    private let cropSize: CGFloat = 168

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / cropSize
            let imageSize = sheetSize * scale
            Image("AvatarSheet")
                .resizable()
                .interpolation(.high)
                .frame(width: imageSize, height: imageSize)
                .offset(
                    x: side * 0.5 - avatar.centerX * imageSize,
                    y: side * 0.5 - avatar.centerY * imageSize
                )
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
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
