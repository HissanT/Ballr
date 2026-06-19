import AVFoundation
import SwiftUI

enum BallrDrillStartPhase {
    case readiness
    case countdown
    case live
}

enum BallrCountdownMascot {
    case pink
    case orange
    case purple
    case blue
    case yellow
    case green
}

private struct BallrCountdownMascotEnvironmentKey: EnvironmentKey {
    static let defaultValue: BallrCountdownMascot? = nil
}

extension EnvironmentValues {
    var ballrCountdownMascot: BallrCountdownMascot? {
        get { self[BallrCountdownMascotEnvironmentKey.self] }
        set { self[BallrCountdownMascotEnvironmentKey.self] = newValue }
    }
}

struct BallrDrillCountdownOverlay: View {
    let startedAt: Date
    var mascot: BallrCountdownMascot? = nil
    var showsYellowCharacterFlight = false

    private let duration: TimeInterval = 4.0
    @State private var currentLabel = "3"

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let label = label(for: elapsed)

            ZStack {
                Color.black.opacity(0.94)
                    .ignoresSafeArea()

                Text(label)
                    .font(.ballr(size: label == "START" ? 54 : 96, weight: .black))
                    .foregroundStyle(Color.white)
                    .opacity(textOpacity(for: elapsed))
                    .scaleEffect(textScale(for: elapsed))
            }
            .opacity(elapsed < duration ? 1 : 0)
            .allowsHitTesting(false)
            .onAppear {
                currentLabel = label
                BallrBackgroundAudioController.shared.startGameplayCountdownMusic()
                if label == "START" {
                    BallrDrillSoundPlayer.playWhistle()
                }
            }
            .onDisappear {
                BallrBackgroundAudioController.shared.intensifyGameplayMusic()
            }
            .onChange(of: label) { _, newLabel in
                guard newLabel != currentLabel else {
                    return
                }
                currentLabel = newLabel
                if newLabel == "START" {
                    BallrDrillSoundPlayer.playWhistle()
                }
            }
        }
    }

    private func label(for elapsed: TimeInterval) -> String {
        switch elapsed {
        case ..<1:
            return "3"
        case ..<2:
            return "2"
        case ..<3:
            return "1"
        case ..<4:
            return "START"
        default:
            return ""
        }
    }

    private func textOpacity(for elapsed: TimeInterval) -> Double {
        let phaseProgress = elapsed - floor(elapsed)
        return max(0.15, 1.0 - phaseProgress * 0.55)
    }

    private func textScale(for elapsed: TimeInterval) -> CGFloat {
        let phaseProgress = elapsed - floor(elapsed)
        return 1.0 + CGFloat(phaseProgress) * 0.16
    }
}

private struct FlyingCountdownMascotCharacter: View {
    let mascot: BallrCountdownMascot
    let elapsed: TimeInterval

    @State private var didPlayFlightSound = false

    private let flightDuration: TimeInterval = 3.0

    private var clampedProgress: CGFloat {
        min(max(CGFloat(elapsed / flightDuration), 0), 1)
    }

    private var characterSize: CGSize {
        switch mascot {
        case .pink:
            return CGSize(width: 96, height: 108)
        case .orange:
            return CGSize(width: 96, height: 108)
        case .purple:
            return CGSize(width: 100, height: 105)
        case .blue:
            return CGSize(width: 102, height: 104)
        case .yellow:
            return CGSize(width: 104, height: 100)
        case .green:
            return CGSize(width: 104, height: 96)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let characterWidth = characterSize.width
            let characterHeight = characterSize.height
            let start = CGPoint(
                x: characterWidth * 0.34,
                y: size.height - characterHeight * 0.38
            )
            let topRight = CGPoint(
                x: size.width - characterWidth * 0.42,
                y: characterHeight * 0.42
            )
            let exit = CGPoint(
                x: size.width + characterWidth * 0.72,
                y: -characterHeight * 0.54
            )
            let center = position(
                progress: clampedProgress,
                start: start,
                topRight: topRight,
                exit: exit,
                size: size
            )
            let opacity = elapsed < flightDuration ? 1.0 : 0.0

            CountdownMascotCharacterView(mascot: mascot)
                .frame(width: characterWidth, height: characterHeight)
                .position(center)
                .opacity(opacity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            guard !didPlayFlightSound else { return }
            didPlayFlightSound = true
            BallrDrillSoundPlayer.playMascotFlight()
        }
    }

    private func position(progress: CGFloat, start: CGPoint, topRight: CGPoint, exit: CGPoint, size: CGSize) -> CGPoint {
        let flightProgress = smoothstep(progress)
        let x = start.x + (exit.x - start.x) * flightProgress
        let y = start.y + (exit.y - start.y) * flightProgress

        return CGPoint(
            x: x,
            y: y
        )
    }

    private func smoothstep(_ progress: CGFloat) -> CGFloat {
        let clampedProgress = min(max(progress, 0), 1)
        return clampedProgress * clampedProgress * (3 - 2 * clampedProgress)
    }

}

private struct CountdownRecedingWaveBackground: View {
    let progress: CGFloat
    let phase: TimeInterval

    var body: some View {
        ZStack {
            PracticeLevelBottomWaveShape(
                progress: reverseWaveProgress(start: 0.00, end: 0.70),
                phase: phase,
                amplitude: 20,
                cycles: 1.35
            )
            .fill(Color(red: 1.00, green: 0.96, blue: 0.42))
            .ignoresSafeArea()

            PracticeLevelBottomWaveShape(
                progress: reverseWaveProgress(start: 0.16, end: 0.84),
                phase: phase + 0.22,
                amplitude: 26,
                cycles: 1.65
            )
            .fill(Color(red: 1.00, green: 0.82, blue: 0.10))
            .ignoresSafeArea()

            PracticeLevelBottomWaveShape(
                progress: reverseWaveProgress(start: 0.32, end: 1.00),
                phase: phase + 0.44,
                amplitude: 32,
                cycles: 1.95
            )
            .fill(Color(red: 0.95, green: 0.62, blue: 0.00))
            .ignoresSafeArea()

            PracticeLevelWaveFoamShape(
                progress: reverseWaveProgress(start: 0.10, end: 0.88),
                phase: phase + 0.08
            )
            .stroke(Color.white.opacity(0.18), lineWidth: 3)
            .ignoresSafeArea()
        }
    }

    private func reverseWaveProgress(start: CGFloat, end: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        guard end > start else {
            return clamped < end ? 1 : 0
        }
        let forward = min(max((clamped - start) / (end - start), 0), 1)
        return 1 - forward
    }
}

private struct CountdownMascotCharacterView: View {
    let mascot: BallrCountdownMascot

    var body: some View {
        switch mascot {
        case .pink:
            LevelsPinkSwiftUICharacter()
        case .orange:
            LevelsOrangeSwiftUICharacter()
        case .purple:
            LevelsPurpleSwiftUICharacter()
        case .blue:
            LevelsBlueSwiftUICharacter()
        case .yellow:
            LevelsYellowCoolSwiftUICharacter()
        case .green:
            LevelsGreenQuadSwiftUICharacter()
        }
    }
}

private struct YellowCountdownCharacter: View {
    private let fillColor = Color(red: 1.0, green: 0.84, blue: 0.0)
    private let strokeColor = Color(red: 0xA5 / 255.0, green: 0x8B / 255.0, blue: 0x0A / 255.0)
    private let black = Color(red: 0.137, green: 0.122, blue: 0.125)
    private let glare = Color(red: 0.72, green: 0.72, blue: 0.70)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let headHeight = height * 0.78
            let strokeWidth = max(width * 0.035, 5)

            ZStack {
                YellowCountdownHeadShape()
                    .fill(fillColor)
                    .overlay {
                        YellowCountdownHeadShape()
                            .stroke(strokeColor, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                    }
                    .frame(width: width * 0.88, height: headHeight)
                    .position(x: width * 0.50, y: height * 0.39)

                YellowCountdownLegShape()
                    .fill(black)
                    .frame(width: width * 0.15, height: height * 0.25)
                    .rotationEffect(.degrees(9))
                    .position(x: width * 0.32, y: height * 0.86)

                YellowCountdownLegShape()
                    .fill(black)
                    .frame(width: width * 0.15, height: height * 0.25)
                    .rotationEffect(.degrees(8))
                    .position(x: width * 0.62, y: height * 0.86)

                YellowCountdownGlassesView()
                    .frame(width: width * 0.78, height: height * 0.15)
                    .position(x: width * 0.50, y: height * 0.36)

                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: width * 0.017, style: .continuous)
                        .fill(black)
                        .frame(width: width * 0.20, height: height * 0.035)

                    HStack(spacing: width * 0.008) {
                        YellowCountdownToothShape()
                            .fill(.white)
                            .frame(width: width * 0.040, height: height * 0.075)
                        YellowCountdownToothShape()
                            .fill(.white)
                            .frame(width: width * 0.040, height: height * 0.075)
                    }
                    .offset(y: height * 0.025)
                }
                .position(x: width * 0.60, y: height * 0.57)
            }
        }
    }
}

private struct YellowCountdownHeadShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        let topY = h * 0.04
        let bottomY = h * 0.94
        let sideInset = w * 0.035

        path.move(to: CGPoint(x: w * 0.50, y: topY))
        path.addCurve(
            to: CGPoint(x: w - sideInset, y: h * 0.30),
            control1: CGPoint(x: w * 0.75, y: topY),
            control2: CGPoint(x: w - sideInset, y: h * 0.12)
        )
        path.addLine(to: CGPoint(x: w - sideInset, y: h * 0.62))
        path.addCurve(
            to: CGPoint(x: w * 0.74, y: bottomY),
            control1: CGPoint(x: w - sideInset, y: h * 0.81),
            control2: CGPoint(x: w * 0.91, y: bottomY)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: bottomY * 0.985),
            control1: CGPoint(x: w * 0.62, y: bottomY),
            control2: CGPoint(x: w * 0.59, y: bottomY * 0.975)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.26, y: bottomY),
            control1: CGPoint(x: w * 0.41, y: bottomY * 0.975),
            control2: CGPoint(x: w * 0.38, y: bottomY)
        )
        path.addCurve(
            to: CGPoint(x: sideInset, y: h * 0.62),
            control1: CGPoint(x: w * 0.09, y: bottomY),
            control2: CGPoint(x: sideInset, y: h * 0.81)
        )
        path.addLine(to: CGPoint(x: sideInset, y: h * 0.30))
        path.addCurve(
            to: CGPoint(x: w * 0.50, y: topY),
            control1: CGPoint(x: sideInset, y: h * 0.12),
            control2: CGPoint(x: w * 0.25, y: topY)
        )
        path.closeSubpath()
        return path
    }
}

private struct YellowCountdownLegShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: w * 0.25, y: 0))
        path.addLine(to: CGPoint(x: w, y: 0))
        path.addCurve(
            to: CGPoint(x: w * 0.58, y: h),
            control1: CGPoint(x: w * 0.96, y: h * 0.38),
            control2: CGPoint(x: w * 0.82, y: h)
        )
        path.addCurve(
            to: CGPoint(x: 0, y: h * 0.72),
            control1: CGPoint(x: w * 0.18, y: h),
            control2: CGPoint(x: -w * 0.07, y: h * 0.89)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.25, y: 0),
            control1: CGPoint(x: w * 0.05, y: h * 0.50),
            control2: CGPoint(x: w * 0.20, y: h * 0.32)
        )
        path.closeSubpath()
        return path
    }
}

private struct YellowCountdownGlassesView: View {
    private let black = Color.black
    private let glare = Color(red: 0.72, green: 0.72, blue: 0.70)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let lensWidth = width * 0.44
            let lensHeight = height * 0.82

            ZStack {
                HStack(spacing: width * 0.10) {
                    lens(width: lensWidth, height: lensHeight)
                    lens(width: lensWidth, height: lensHeight)
                }

                Capsule()
                    .fill(black)
                    .frame(width: width * 0.13, height: height * 0.08)
                    .offset(y: -height * 0.04)
            }
        }
    }

    private func lens(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
            .fill(black)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                HStack(spacing: width * 0.05) {
                    ParallelogramShape(slant: width * 0.16)
                        .fill(glare)
                        .frame(width: width * 0.17, height: height * 1.25)
                    ParallelogramShape(slant: width * 0.14)
                        .fill(glare)
                        .frame(width: width * 0.08, height: height * 1.25)
                }
                .rotationEffect(.degrees(0))
                .offset(x: width * 0.26, y: -height * 0.02)
                .clipped()
            }
            .clipped()
    }
}

private struct ParallelogramShape: Shape {
    let slant: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + slant, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct YellowCountdownToothShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width * 0.45
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

enum BallrDrillSoundPlayer {
    private static let rockDropTargetVolume: Float = 0.7
    private static let rockHitBallTargetVolume: Float = 1.0
    private static var whistlePlayer: AVAudioPlayer?
    private static var winnerPlayer: AVAudioPlayer?
    private static var comboPlayer: AVAudioPlayer?
    private static var incorrectPlayer: AVAudioPlayer?
    private static var jeffBouncePlayers: [AVAudioPlayer] = []
    private static var jeffWobbleStepPlayer: AVAudioPlayer?
    private static var jeffCartoonFallPlayer: AVAudioPlayer?
    private static var rockDropLoopPlayer: AVAudioPlayer?
    private static var rockHitBallPlayer: AVAudioPlayer?
    private static var hunterExplosionPlayer: AVAudioPlayer?
    private static var mascotFlightPlayer: AVAudioPlayer?
    private static var rockDropLoopStopWorkItem: DispatchWorkItem?
    private static var rockHitBallFadeOutWorkItem: DispatchWorkItem?

    static func playWhistle() {
        play(resource: "Whistle", fileExtension: "mp3", player: &whistlePlayer, errorLabel: "Countdown whistle")
    }

    static func playWinner() {
        play(resource: "Winner", fileExtension: "mp3", player: &winnerPlayer, errorLabel: "Winner sound")
    }

    static func playCombo() {
        play(resource: "Combos", fileExtension: "mp3", player: &comboPlayer, errorLabel: "Combo sound")
    }

    static func playIncorrect() {
        play(
            resource: "lesiakower-error-mistake-sound-effect-incorrect-answer-437420",
            fileExtension: "mp3",
            player: &incorrectPlayer,
            errorLabel: "Incorrect sound"
        )
    }

    static func scheduleJeffBounceSounds(startedAt: Date, bounceTimes: [TimeInterval]) {
        prepareJeffBouncePlayers(count: bounceTimes.count)

        guard !jeffBouncePlayers.isEmpty else {
            return
        }

        let now = Date()
        for (index, bounceTime) in bounceTimes.enumerated() where index < jeffBouncePlayers.count {
            let delay = startedAt.addingTimeInterval(bounceTime).timeIntervalSince(now)
            guard delay > 0 else {
                continue
            }

            let player = jeffBouncePlayers[index]
            player.stop()
            player.currentTime = 0
            player.volume = 0.82
            player.prepareToPlay()
            player.play(atTime: player.deviceCurrentTime + delay)
        }
    }

    static func stopScheduledJeffBounceSounds() {
        jeffBouncePlayers.forEach { player in
            player.stop()
            player.currentTime = 0
            player.volume = 0.82
        }
    }

    static func playJeffWobbleStep() {
        play(
            resource: "jeff_wobble_step",
            fileExtension: "wav",
            player: &jeffWobbleStepPlayer,
            errorLabel: "Jeff wobble step sound",
            initialVolume: 0.72
        )
    }

    static func prepareJeffCartoonFall() {
        prepare(
            resource: "jeff_cartoon_fall",
            fileExtension: "wav",
            player: &jeffCartoonFallPlayer,
            errorLabel: "Jeff cartoon fall sound"
        )
        jeffCartoonFallPlayer?.volume = 0.78
    }

    static func playJeffCartoonFall() {
        play(
            resource: "jeff_cartoon_fall",
            fileExtension: "wav",
            player: &jeffCartoonFallPlayer,
            errorLabel: "Jeff cartoon fall sound",
            initialVolume: 0.78
        )
    }

    static func startRockDropLoop() {
        rockDropLoopStopWorkItem?.cancel()
        rockHitBallFadeOutWorkItem?.cancel()
        play(
            resource: "rockDrop1",
            fileExtension: "mp3",
            player: &rockDropLoopPlayer,
            errorLabel: "Rock Drop loop sound",
            loops: true,
            initialVolume: 0
        )
        rockDropLoopPlayer?.setVolume(rockDropTargetVolume, fadeDuration: 3.0)
    }

    static func stopRockDropLoop(fadeOut: Bool = true) {
        rockDropLoopStopWorkItem?.cancel()

        guard let rockDropLoopPlayer else {
            return
        }

        guard fadeOut, rockDropLoopPlayer.isPlaying else {
            rockDropLoopPlayer.stop()
            rockDropLoopPlayer.currentTime = 0
            rockDropLoopPlayer.volume = rockDropTargetVolume
            return
        }

        rockDropLoopPlayer.setVolume(0, fadeDuration: 3.0)
        let stopWorkItem = DispatchWorkItem {
            rockDropLoopPlayer.stop()
            rockDropLoopPlayer.currentTime = 0
            rockDropLoopPlayer.volume = rockDropTargetVolume
        }
        rockDropLoopStopWorkItem = stopWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: stopWorkItem)
    }

    static func playRockHitBall() {
        rockHitBallFadeOutWorkItem?.cancel()
        stopRockDropLoop(fadeOut: false)
        play(
            resource: "rockHitBall",
            fileExtension: "mp3",
            player: &rockHitBallPlayer,
            errorLabel: "Rock hit ball sound",
            initialVolume: 0
        )
        guard let rockHitBallPlayer else {
            return
        }

        let fadeDuration = min(3.0, max(rockHitBallPlayer.duration * 0.5, 0.12))
        let fadeOutDelay = max(rockHitBallPlayer.duration - fadeDuration, 0)
        rockHitBallPlayer.setVolume(rockHitBallTargetVolume, fadeDuration: fadeDuration)

        let fadeOutWorkItem = DispatchWorkItem {
            rockHitBallPlayer.setVolume(0, fadeDuration: fadeDuration)
        }
        rockHitBallFadeOutWorkItem = fadeOutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeOutDelay, execute: fadeOutWorkItem)
    }

    static func playHunterExplosion() {
        play(
            resource: "hunter_kid_explosion",
            fileExtension: "wav",
            player: &hunterExplosionPlayer,
            errorLabel: "Hunter explosion sound",
            initialVolume: 0.76
        )
    }

    static func playMascotFlight() {
        if mascotFlightPlayer == nil {
            prepareMascotFlightPlayer()
        }

        mascotFlightPlayer?.stop()
        mascotFlightPlayer?.currentTime = 0
        mascotFlightPlayer?.volume = 0.36
        mascotFlightPlayer?.play()
    }

    static func stopRockDropSounds() {
        rockDropLoopStopWorkItem?.cancel()
        rockHitBallFadeOutWorkItem?.cancel()
        stopRockDropLoop(fadeOut: false)
        rockHitBallPlayer?.stop()
        rockHitBallPlayer?.currentTime = 0
        rockHitBallPlayer?.volume = rockHitBallTargetVolume
    }

    private static func play(
        resource: String,
        fileExtension: String,
        player: inout AVAudioPlayer?,
        errorLabel: String,
        loops: Bool = false,
        initialVolume: Float? = nil
    ) {
        if player == nil {
            prepare(resource: resource, fileExtension: fileExtension, player: &player, errorLabel: errorLabel, loops: loops)
        }

        player?.stop()
        player?.currentTime = 0
        if let initialVolume {
            player?.volume = initialVolume
        }
        player?.play()
    }

    private static func prepare(
        resource: String,
        fileExtension: String,
        player: inout AVAudioPlayer?,
        errorLabel: String,
        loops: Bool = false
    ) {
        guard player == nil else {
            return
        }

        guard let url = Bundle.main.url(forResource: resource, withExtension: fileExtension) else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.numberOfLoops = loops ? -1 : 0
            audioPlayer.prepareToPlay()
            player = audioPlayer
        } catch {
            print("\(errorLabel) failed to load: \(error.localizedDescription)")
            return
        }
    }

    private static func prepareMascotFlightPlayer() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            let audioPlayer = try AVAudioPlayer(data: mascotFlightSoundData())
            audioPlayer.volume = 0.36
            audioPlayer.prepareToPlay()
            mascotFlightPlayer = audioPlayer
        } catch {
            print("Mascot flight sound failed to load: \(error.localizedDescription)")
        }
    }

    private static func mascotFlightSoundData() -> Data {
        let sampleRate = 44_100
        let duration = 1.18
        let sampleCount = Int(Double(sampleRate) * duration)
        let channelCount: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(channelCount) * Int(bitsPerSample) / 8)
        let blockAlign = UInt16(Int(channelCount) * Int(bitsPerSample) / 8)
        let dataByteCount = UInt32(sampleCount * Int(blockAlign))

        var data = Data()

        func appendString(_ string: String) {
            data.append(contentsOf: string.utf8)
        }

        func appendUInt16(_ value: UInt16) {
            var littleEndianValue = value.littleEndian
            withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
        }

        func appendUInt32(_ value: UInt32) {
            var littleEndianValue = value.littleEndian
            withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
        }

        func appendInt16(_ value: Int16) {
            var littleEndianValue = value.littleEndian
            withUnsafeBytes(of: &littleEndianValue) { data.append(contentsOf: $0) }
        }

        appendString("RIFF")
        appendUInt32(36 + dataByteCount)
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(channelCount)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(byteRate)
        appendUInt16(blockAlign)
        appendUInt16(bitsPerSample)
        appendString("data")
        appendUInt32(dataByteCount)

        var chirpPhase = 0.0
        var filteredNoise = 0.0
        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let progress = time / duration
            let clampedProgress = min(max(progress, 0), 1)
            let attack = min(clampedProgress / 0.14, 1.0)
            let release = min((1.0 - clampedProgress) / 0.24, 1.0)
            let envelope = attack * release
            let rawNoise = pseudoNoise(for: index)
            filteredNoise = filteredNoise * 0.93 + rawNoise * 0.07

            let lift = 0.58 + 0.42 * clampedProgress
            let wind = filteredNoise * envelope * lift * 0.36
            let lowAir = sin(2.0 * .pi * (130.0 + 90.0 * clampedProgress) * time) * envelope * 0.055
            let chirpEnvelope = gaussian(center: 0.27, width: 0.07, progress: clampedProgress)
                + gaussian(center: 0.56, width: 0.09, progress: clampedProgress) * 0.72
            let chirpFrequency = 560.0 + 230.0 * clampedProgress + 55.0 * sin(2.0 * .pi * 5.0 * time)
            chirpPhase += 2.0 * .pi * chirpFrequency / Double(sampleRate)
            let chirp = sin(chirpPhase) * chirpEnvelope * 0.12
            let sample = (wind + lowAir + chirp) * 0.72
            appendInt16(Int16(max(-1.0, min(1.0, sample)) * Double(Int16.max)))
        }

        return data
    }

    private static func pseudoNoise(for index: Int) -> Double {
        let value = sin(Double(index) * 12.9898 + 78.233) * 43_758.5453
        let fraction = value - floor(value)
        return fraction * 2.0 - 1.0
    }

    private static func gaussian(center: Double, width: Double, progress: Double) -> Double {
        exp(-pow((progress - center) / width, 2.0))
    }

    private static func prepareJeffBouncePlayers(count: Int) {
        guard jeffBouncePlayers.count < count else {
            return
        }

        guard let url = Bundle.main.url(forResource: "jeff_ball_bounce", withExtension: "wav") else {
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            while jeffBouncePlayers.count < count {
                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.volume = 0.82
                audioPlayer.prepareToPlay()
                jeffBouncePlayers.append(audioPlayer)
            }
        } catch {
            print("Jeff bounce sound failed to load: \(error.localizedDescription)")
        }
    }
}

struct BallrDrillReadinessOverlay: View {
    let ballFoundStartedAt: Date?

    private let requiredLockSeconds: TimeInterval

    init(ballFoundStartedAt: Date?, requiredLockSeconds: TimeInterval = 3.0) {
        self.ballFoundStartedAt = ballFoundStartedAt
        self.requiredLockSeconds = requiredLockSeconds
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = readinessProgress(at: timeline.date)

            ZStack {
                Color.black.opacity(0.86)
                    .ignoresSafeArea()

                if ballFoundStartedAt == nil {
                    VStack(spacing: 14) {
                        Text("Find the ball")
                            .font(.ballr(size: 36, weight: .black))
                            .foregroundStyle(Color.yellow)

                        Text("Put the phone sideways and keep the ball in frame.")
                            .font(.ballr(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.78))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                } else {
                    VStack(spacing: 18) {
                        Text("Put the phone sideways")
                            .font(.ballr(size: 28, weight: .black))
                            .foregroundStyle(.white)

                        Text("Keep the ball in frame.")
                            .font(.ballr(size: 18, weight: .bold))
                            .foregroundStyle(.white.opacity(0.74))

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.white.opacity(0.16))

                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.yellow)
                                .frame(width: 220 * progress)
                        }
                        .frame(width: 220, height: 12)

                        Text("Hold still")
                            .font(.ballr(size: 13, weight: .black))
                            .tracking(1.6)
                            .foregroundStyle(Color.yellow)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func readinessProgress(at date: Date) -> CGFloat {
        guard let ballFoundStartedAt else {
            return 0
        }
        return CGFloat(min(max(date.timeIntervalSince(ballFoundStartedAt) / requiredLockSeconds, 0), 1))
    }
}
