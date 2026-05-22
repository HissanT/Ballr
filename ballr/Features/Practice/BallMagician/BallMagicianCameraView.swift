import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct BallMagicianCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = JugglingCameraController()
    @StateObject private var coordinator: BallMagicianCoordinator
    @State private var showsQuitConfirmation = false
    @State private var showsNextLevel = false
    private let configuration: BallMagicianConfiguration

    init(configuration: BallMagicianConfiguration = .standard) {
        self.configuration = configuration
        _coordinator = StateObject(wrappedValue: BallMagicianCoordinator(configuration: configuration))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                BallMagicianFieldOverlay(
                    ballRect: coordinator.ballDisplayRect,
                    prompt: coordinator.promptText,
                    showsTitlePlate: configuration.showsTitlePlate
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                if coordinator.phase != .completed {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

                if coordinator.phase == .live {
                    BallMagicianCommandCard(
                        command: coordinator.currentCommand,
                        commandID: coordinator.currentCommandID,
                        timerProgress: coordinator.timerProgress,
                        lastResult: coordinator.lastResult,
                        scale: configuration.commandCardScale,
                        style: configuration.commandCardStyle
                    )
                    .position(commandCardPosition(in: geometry.size))
                }

                if cameraController.isStarting {
                    BallMagicianLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    BallMagicianErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.phase == .readiness, cameraController.errorMessage == nil {
                    BallMagicianReadinessOverlay(readyStartedAt: coordinator.readyStartedAt)
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                }

                if coordinator.phase == .completed {
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.completionStartedAt,
                        buttonsVisible: coordinator.showsCompletionButtons,
                        showsNextLevelButton: configuration.showsNextLevelButton,
                        onNextLevel: { showsNextLevel = true },
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .ballrAwardsXPOnSuccess(coordinator.phase == .completed || coordinator.score >= 10)
            .navigationDestination(isPresented: $showsNextLevel) {
                LevelEightCameraView()
                    .ballrCameraPresentationChrome()
            }
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(in: geometry.size)
                cameraController.publishesTrackingFramesToSwiftUI = false
                cameraController.onTrackingFrame = { [weak coordinator, weak cameraController] frame in
                    guard let cameraController else {
                        return
                    }
                    coordinator?.handle(frame: frame, cameraController: cameraController)
                }
                cameraController.start()
            }
            .onDisappear {
                cameraController.onTrackingFrame = nil
                cameraController.publishesTrackingFramesToSwiftUI = true
                cameraController.stop()
                coordinator.tearDown()
                BallrOrientationController.restoreDefaultOrientation()
            }
            .onChange(of: geometry.size) { _, newSize in
                coordinator.prepare(in: newSize)
            }
            .alert("Are you sure you want to quit the game?", isPresented: $showsQuitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive) {
                    dismiss()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top) {
            Button {
                showsQuitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.ballr(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.60), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 10) {
                    BallMagicianHudChip(title: "SCORE", value: "\(coordinator.score)", tint: .yellow)
                    if configuration.roundDuration != nil {
                        BallMagicianHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
                    }
                    BallMagicianHudChip(title: "MISSES", value: "\(coordinator.misses)", tint: .orange)
                }

                Text(coordinator.statusText)
                    .font(.ballr(size: 12, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.74))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.52), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 18)
    }

    private func commandCardPosition(in size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * coordinator.currentCommandPosition.xFraction,
            y: size.height * 0.52
        )
    }
}

private enum BallMagicianPhase {
    case readiness
    case countdown
    case live
    case completed
}

struct BallMagicianConfiguration {
    let upCommandWeight: Int
    let lateralCommandWeight: Int
    let commandTimeLimit: TimeInterval?
    let commandCardScale: CGFloat
    let showsTitlePlate: Bool
    let centersUpCommand: Bool
    let rightLaneFraction: CGFloat
    let depthCommandWeight: Int
    let frontScaleThreshold: CGFloat
    let backScaleThreshold: CGFloat
    let completionScore: Int?
    let roundDuration: TimeInterval?
    let prioritizesLateralCorrections: Bool
    let showsNextLevelButton: Bool
    let commandCardStyle: BallMagicianCommandCardStyle

    static let standard = BallMagicianConfiguration(
        upCommandWeight: 3,
        lateralCommandWeight: 1,
        commandTimeLimit: 3.5,
        commandCardScale: 1.0,
        showsTitlePlate: true,
        centersUpCommand: false,
        rightLaneFraction: 0.68,
        depthCommandWeight: 0,
        frontScaleThreshold: 1.27,
        backScaleThreshold: 0.77,
        completionScore: nil,
        roundDuration: nil,
        prioritizesLateralCorrections: true,
        showsNextLevelButton: false,
        commandCardStyle: .standard
    )

    static let levelSeven = BallMagicianConfiguration(
        upCommandWeight: 0,
        lateralCommandWeight: 1,
        commandTimeLimit: nil,
        commandCardScale: 1.0,
        showsTitlePlate: false,
        centersUpCommand: true,
        rightLaneFraction: 0.80,
        depthCommandWeight: 1,
        frontScaleThreshold: 1.27,
        backScaleThreshold: 0.77,
        completionScore: nil,
        roundDuration: 60.0,
        prioritizesLateralCorrections: false,
        showsNextLevelButton: true,
        commandCardStyle: .plainArrows
    )
}

enum BallMagicianCommandCardStyle {
    case standard
    case plainArrows
}

private enum BallMagicianCommand: CaseIterable { 
    case up
    case left
    case right
    case front
    case back

    var label: String {
        switch self {
        case .up:
            return "JUGGLE"
        case .left:
            return "LEFT"
        case .right:
            return "RIGHT"
        case .front:
            return "FRONT"
        case .back:
            return "BACK"
        }
    }

    var systemImageName: String {
        switch self {
        case .up:
            return "arrow.up"
        case .left:
            return "arrow.left"
        case .right:
            return "arrow.right"
        case .front:
            return "arrow.up"
        case .back:
            return "arrow.down"
        }
    }

    var isLateral: Bool {
        self == .left || self == .right
    }
}

private enum BallMagicianLane {
    case left
    case center
    case right
}

private enum BallMagicianCommandPosition {
    case left
    case center
    case right

    var xFraction: CGFloat {
        switch self {
        case .left:
            return 0.25
        case .center:
            return 0.50
        case .right:
            return 0.75
        }
    }
}

private enum BallMagicianResult {
    case success(Date, UUID)
    case miss(Date, UUID)

    var timestamp: Date {
        switch self {
        case .success(let date, _), .miss(let date, _):
            return date
        }
    }

    var commandID: UUID {
        switch self {
        case .success(_, let commandID), .miss(_, let commandID):
            return commandID
        }
    }
}

private final class BallMagicianCoordinator: ObservableObject {
    @Published private(set) var phase: BallMagicianPhase = .readiness
    @Published private(set) var readyStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var score = 0
    @Published private(set) var misses = 0
    @Published private(set) var timerText = "60"
    @Published private(set) var statusText = "SEARCHING"
    @Published private(set) var currentCommand: BallMagicianCommand?
    @Published private(set) var timerProgress: CGFloat = 1
    @Published private(set) var ballDisplayRect: CGRect?
    @Published private(set) var promptText: String?
    @Published private(set) var lastResult: BallMagicianResult?
    @Published private(set) var currentCommandPosition: BallMagicianCommandPosition = .center
    @Published private(set) var currentCommandID = UUID()
    @Published private(set) var completionStartedAt: Date?
    @Published private(set) var showsCompletionButtons = false

    private let requiredReadyLockSeconds: TimeInterval = 1.2
    private let countdownDuration: TimeInterval = 4.0
    private let completionAnimationDuration: TimeInterval = 2.05
    private let completionButtonRevealDelay: TimeInterval = 0.28
    private let resultFeedbackDuration: TimeInterval = 0.5
    private let lostBallPromptFrameThreshold = 8
    private let lostBodyPromptFrameThreshold = 12
    private let leftLaneFraction: CGFloat = 0.32
    private let configuration: BallMagicianConfiguration

    private var size: CGSize = .zero
    private var detectedBody: BallMagicianDetectedBody?
    private var lostBallFrameCount = 0
    private var lostBodyFrameCount = 0
    private var commandStartedAt: Date?
    private var liveStartedAt: Date?
    private var nextCommandAllowedAt: Date?
    private var pendingBallRectForNextCommand: CGRect?
    private var commandStartBallDiameter: CGFloat?
    private var commandHistory: [BallMagicianCommand] = []
    private var juggleDetector = BallMagicianJuggleDetector()
    private var completionWorkItem: DispatchWorkItem?

    init(configuration: BallMagicianConfiguration = .standard) {
        self.configuration = configuration
    }

    func tearDown() {
        cancelCompletionWorkItem()
    }

    func reset(in size: CGSize) {
        cancelCompletionWorkItem()
        self.size = size
        phase = .readiness
        readyStartedAt = nil
        countdownStartedAt = nil
        score = 0
        misses = 0
        timerText = timeString(configuration.roundDuration ?? 60)
        statusText = "SEARCHING"
        currentCommand = nil
        currentCommandID = UUID()
        currentCommandPosition = .center
        commandStartedAt = nil
        liveStartedAt = nil
        timerProgress = 1
        nextCommandAllowedAt = nil
        pendingBallRectForNextCommand = nil
        commandStartBallDiameter = nil
        ballDisplayRect = nil
        detectedBody = nil
        lostBallFrameCount = 0
        lostBodyFrameCount = 0
        commandHistory.removeAll()
        promptText = nil
        lastResult = nil
        completionStartedAt = nil
        showsCompletionButtons = false
        juggleDetector.reset()
    }

    func prepare(in size: CGSize) {
        self.size = size
    }

    func handle(frame: JugglingFrame, cameraController: JugglingCameraController) {
        let rawBallRect = displayRect(for: frame.ballOverlayState, cameraController: cameraController)
        let isBallTracked = frame.ballOverlayState.isTracking
            && frame.ballOverlayState.confirmedFrames >= 2
            && rawBallRect != nil
        ballDisplayRect = rawBallRect

        let body = detectedBody(from: frame.bodyOverlayState, cameraController: cameraController)
        detectedBody = body

        if isBallTracked {
            lostBallFrameCount = 0
        } else if phase == .live {
            lostBallFrameCount += 1
        }

        if body == nil {
            if phase == .live {
                lostBodyFrameCount += 1
            }
        } else {
            lostBodyFrameCount = 0
        }

        updateStatus(isBallTracked: isBallTracked, hasBody: body != nil)
        updateStartGate(isReady: isBallTracked && body != nil, timestamp: frame.timestamp)

        guard phase != .completed else {
            updatePrompt()
            return
        }

        guard phase == .live else {
            juggleDetector.observe(
                ballDisplayRect: rawBallRect,
                body: body,
                timestamp: frame.timestamp,
                isBallTracked: isBallTracked
            )
            updatePrompt()
            return
        }

        if updateRoundTimer(at: frame.timestamp) {
            updatePrompt()
            return
        }

        if currentCommand == nil {
            startNextCommand(at: frame.timestamp, ballRect: rawBallRect)
        }

        if let nextCommandAllowedAt {
            if frame.timestamp >= nextCommandAllowedAt {
                startNextCommand(at: frame.timestamp, ballRect: pendingBallRectForNextCommand ?? rawBallRect)
            }
            updatePrompt()
            return
        }

        updateTimer(at: frame.timestamp)

        switch currentCommand {
        case .up:
            let event = juggleDetector.step(
                ballDisplayRect: rawBallRect,
                body: body,
                timestamp: frame.timestamp,
                isBallTracked: isBallTracked
            )
            if event == .counted {
                resolveCurrentCommand(as: .success, at: frame.timestamp, ballRect: rawBallRect)
            }
        case .left:
            if ballLane(for: rawBallRect) == .left {
                resolveCurrentCommand(as: .success, at: frame.timestamp, ballRect: rawBallRect)
            }
        case .right:
            if ballLane(for: rawBallRect) == .right {
                resolveCurrentCommand(as: .success, at: frame.timestamp, ballRect: rawBallRect)
            }
        case .front:
            if hasCompletedDepthCommand(.front, ballRect: rawBallRect) {
                resolveCurrentCommand(as: .success, at: frame.timestamp, ballRect: rawBallRect)
            }
        case .back:
            if hasCompletedDepthCommand(.back, ballRect: rawBallRect) {
                resolveCurrentCommand(as: .success, at: frame.timestamp, ballRect: rawBallRect)
            }
        case nil:
            break
        }

        if
            let commandStartedAt,
            let commandTimeLimit = configuration.commandTimeLimit,
            frame.timestamp.timeIntervalSince(commandStartedAt) >= commandTimeLimit
        {
            resolveCurrentCommand(as: .miss, at: frame.timestamp, ballRect: rawBallRect)
        }

        updatePrompt()
    }

    private func updateStartGate(isReady: Bool, timestamp: Date) {
        guard phase != .live, phase != .completed else {
            return
        }

        if phase == .countdown {
            if
                let countdownStartedAt,
                timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration
            {
                phase = .live
                readyStartedAt = nil
                self.countdownStartedAt = nil
                liveStartedAt = timestamp
                score = 0
                misses = 0
                timerText = timeString(configuration.roundDuration ?? 60)
                currentCommand = nil
                currentCommandPosition = .center
                commandStartedAt = nil
                nextCommandAllowedAt = nil
                pendingBallRectForNextCommand = nil
                commandStartBallDiameter = nil
                juggleDetector.start()
            }
            return
        }

        guard isReady else {
            readyStartedAt = nil
            return
        }

        let startedAt = readyStartedAt ?? timestamp
        readyStartedAt = startedAt

        if timestamp.timeIntervalSince(startedAt) >= requiredReadyLockSeconds {
            countdownStartedAt = timestamp
            phase = .countdown
        }
    }

    private enum Resolution {
        case success
        case miss
    }

    private func resolveCurrentCommand(as resolution: Resolution, at timestamp: Date, ballRect: CGRect?) {
        guard currentCommand != nil else {
            return
        }
        let resolvedCommandID = currentCommandID

        commandStartedAt = nil
        timerProgress = 0
        nextCommandAllowedAt = timestamp.addingTimeInterval(resultFeedbackDuration)
        pendingBallRectForNextCommand = ballRect
        commandStartBallDiameter = nil

        switch resolution {
        case .success:
            score += 1
            BallMagicianSoundPlayer.playScore()
            if score.isMultiple(of: 10) {
                BallrDrillSoundPlayer.playCombo()
            }
            lastResult = .success(timestamp, resolvedCommandID)
            if let completionScore = configuration.completionScore, score >= completionScore {
                complete(at: timestamp)
            }
        case .miss:
            misses += 1
            BallrDrillSoundPlayer.playIncorrect()
            lastResult = .miss(timestamp, resolvedCommandID)
        }
    }

    private func complete(at timestamp: Date) {
        guard phase != .completed else {
            return
        }

        phase = .completed
        completionStartedAt = timestamp
        currentCommand = nil
        commandStartedAt = nil
        nextCommandAllowedAt = nil
        BallrDrillSoundPlayer.playWinner()

        let workItem = DispatchWorkItem { [weak self] in
            self?.showsCompletionButtons = true
        }
        completionWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + completionAnimationDuration + completionButtonRevealDelay,
            execute: workItem
        )
    }

    private func cancelCompletionWorkItem() {
        completionWorkItem?.cancel()
        completionWorkItem = nil
    }

    private func startNextCommand(at timestamp: Date, ballRect: CGRect?) {
        nextCommandAllowedAt = nil
        pendingBallRectForNextCommand = nil
        let nextCommand = chooseNextCommand(ballLane: ballLane(for: ballRect))
        currentCommand = nextCommand
        currentCommandID = UUID()
        currentCommandPosition = position(for: nextCommand)
        commandStartedAt = timestamp
        commandStartBallDiameter = ballDiameter(for: ballRect)
        timerProgress = 1
        commandHistory.append(nextCommand)
        if commandHistory.count > 6 {
            commandHistory.removeFirst(commandHistory.count - 6)
        }
    }

    private func chooseNextCommand(ballLane: BallMagicianLane) -> BallMagicianCommand {
        let previousCommand = commandHistory.last
        if configuration.upCommandWeight > 3, previousCommand != .up, Double.random(in: 0...1) < 0.58 {
            return .up
        }

        if configuration.prioritizesLateralCorrections {
            switch ballLane {
            case .left:
                if previousCommand != .right {
                    return .right
                }
            case .right:
                if previousCommand != .left {
                    return .left
                }
            case .center:
                break
            }
        }

        return balancedRandomCommand(excluding: previousCommand)
    }

    private func updateRoundTimer(at timestamp: Date) -> Bool {
        guard let roundDuration = configuration.roundDuration else {
            return false
        }

        guard let liveStartedAt else {
            timerText = timeString(roundDuration)
            return false
        }

        let remaining = max(roundDuration - timestamp.timeIntervalSince(liveStartedAt), 0)
        timerText = timeString(remaining)
        if remaining <= 0 {
            complete(at: timestamp)
            return true
        }

        return false
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        "\(Int(ceil(max(seconds, 0))))"
    }

    private func balancedRandomCommand(excluding excludedCommand: BallMagicianCommand?) -> BallMagicianCommand {
        var candidates = Array(repeating: BallMagicianCommand.up, count: configuration.upCommandWeight)
        candidates += Array(repeating: BallMagicianCommand.left, count: configuration.lateralCommandWeight)
        candidates += Array(repeating: BallMagicianCommand.right, count: configuration.lateralCommandWeight)
        candidates += Array(repeating: BallMagicianCommand.front, count: configuration.depthCommandWeight)
        candidates += Array(repeating: BallMagicianCommand.back, count: configuration.depthCommandWeight)
        if let excludedCommand {
            candidates.removeAll { $0 == excludedCommand }
        }

        return candidates.randomElement()
            ?? BallMagicianCommand.allCases.first { $0 != excludedCommand }
            ?? .left
    }

    private func position(for command: BallMagicianCommand) -> BallMagicianCommandPosition {
        switch command {
        case .left:
            return .left
        case .right:
            return .right
        case .front, .back, .up:
            if configuration.centersUpCommand {
                return .center
            }
            return [.center, .center, .center, .center, .center, .left, .right].randomElement() ?? .center
        }
    }

    private func updateTimer(at timestamp: Date) {
        guard let commandTimeLimit = configuration.commandTimeLimit else {
            timerProgress = 1
            return
        }

        guard let commandStartedAt else {
            timerProgress = 1
            return
        }

        let remaining = max(commandTimeLimit - timestamp.timeIntervalSince(commandStartedAt), 0)
        timerProgress = CGFloat(min(max(remaining / commandTimeLimit, 0), 1))
    }

    private func updateStatus(isBallTracked: Bool, hasBody: Bool) {
        let nextStatus: String
        if !isBallTracked {
            nextStatus = "FIND BALL"
        } else if !hasBody {
            nextStatus = "FIND PLAYER"
        } else {
            nextStatus = phase == .live ? "FOLLOW ARROWS" : "READY"
        }

        if statusText != nextStatus {
            statusText = nextStatus
        }
    }

    private func updatePrompt() {
        if phase == .live, lostBallFrameCount >= lostBallPromptFrameThreshold {
            promptText = "Find the ball"
            return
        }

        if phase == .live, lostBodyFrameCount >= lostBodyPromptFrameThreshold {
            promptText = "Stay in frame"
            return
        }

        promptText = nil
    }

    private func ballLane(for ballRect: CGRect?) -> BallMagicianLane {
        guard let ballRect else {
            return .center
        }

        let width = max(size.width, 1)
        if ballRect.midX <= width * leftLaneFraction {
            return .left
        }
        if ballRect.midX >= width * configuration.rightLaneFraction {
            return .right
        }
        return .center
    }

    private func hasCompletedDepthCommand(_ command: BallMagicianCommand, ballRect: CGRect?) -> Bool {
        guard let currentDiameter = ballDiameter(for: ballRect), currentDiameter > 0 else {
            return false
        }

        if commandStartBallDiameter == nil {
            commandStartBallDiameter = currentDiameter
            return false
        }

        guard let baseline = commandStartBallDiameter, baseline > 0 else {
            return false
        }

        switch command {
        case .front:
            return currentDiameter >= baseline * configuration.frontScaleThreshold
        case .back:
            return currentDiameter <= baseline * configuration.backScaleThreshold
        case .up, .left, .right:
            return false
        }
    }

    private func ballDiameter(for ballRect: CGRect?) -> CGFloat? {
        guard let ballRect else {
            return nil
        }

        return max(ballRect.width, ballRect.height)
    }

    private func displayRect(
        for overlayState: BallTrackerOverlayState,
        cameraController: JugglingCameraController
    ) -> CGRect? {
        guard let normalizedRect = overlayState.normalizedRect else {
            return nil
        }
        return cameraController.displayRect(for: normalizedRect)
    }

    private func detectedBody(
        from overlayState: JugglingBodyOverlayState,
        cameraController: JugglingCameraController
    ) -> BallMagicianDetectedBody? {
        guard overlayState.isTracking else {
            return nil
        }

        var points: [JugglingBodyJoint: CGPoint] = [:]
        var confidences: [JugglingBodyJoint: CGFloat] = [:]
        for point in overlayState.points {
            guard let displayPoint = cameraController.displayPoint(for: point.normalizedPoint) else {
                continue
            }
            points[point.joint] = displayPoint
            confidences[point.joint] = CGFloat(point.confidence)
        }

        return BallMagicianDetectedBody(points: points, confidences: confidences, bounds: size)
    }
}

private struct BallMagicianFieldOverlay: View {
    let ballRect: CGRect?
    let prompt: String?
    let showsTitlePlate: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let ballRect {
                    Circle()
                        .stroke(.yellow, lineWidth: 3)
                        .frame(width: ballRect.width + 8, height: ballRect.height + 8)
                        .position(x: ballRect.midX, y: ballRect.midY)
                        .shadow(color: .yellow.opacity(0.52), radius: 12)
                }

                if let prompt {
                    Text(prompt.uppercased())
                        .font(.ballr(size: 20, weight: .black))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
                        .position(x: geometry.size.width * 0.5, y: geometry.size.height - 84)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsTitlePlate {
                    BallMagicianTitlePlate()
                        .padding(.leading, 74)
                        .padding(.top, 22)
                }
            }
        }
    }
}

private struct BallMagicianTitlePlate: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Ball Magician")
                .font(.ballr(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.8), radius: 4)

            RoundedRectangle(cornerRadius: 999)
                .fill(Color.pink.opacity(0.82))
                .frame(width: 188, height: 5)
                .rotationEffect(.degrees(-1.5))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BallMagicianCommandCard: View {
    let command: BallMagicianCommand?
    let commandID: UUID
    let timerProgress: CGFloat
    let lastResult: BallMagicianResult?
    let scale: CGFloat
    let style: BallMagicianCommandCardStyle

    var body: some View {
        content
        .scaleEffect(scale)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .standard:
            standardContent
        case .plainArrows:
            plainArrowContent
        }
    }

    private var standardContent: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.black.opacity(0.46))
                    .frame(width: 180, height: 126)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(borderColor, lineWidth: 5)
                    }
                    .shadow(color: borderColor.opacity(0.78), radius: 24)
                    .shadow(color: .black.opacity(0.82), radius: 12)

                Circle()
                    .stroke(.white.opacity(0.34), lineWidth: 8)
                    .frame(width: 100, height: 100)

                Circle()
                    .trim(from: 0, to: max(0.02, timerProgress))
                    .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .opacity(timerProgress > 0 ? 1 : 0.2)

                standardCommandIcon
                    .symbolEffect(.bounce, value: command?.label)
            }

            Text(command?.label ?? "READY")
                .font(.ballr(size: 22, weight: .black))
                .tracking(1.5)
                .foregroundStyle(.white)
                .frame(minWidth: 112)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var plainArrowContent: some View {
        ZStack {
            plainCommandIcon
                .symbolEffect(.bounce, value: command?.label)
        }
        .frame(width: 140, height: 120)
    }

    @ViewBuilder
    private var standardCommandIcon: some View {
        switch command {
        case .front:
            BallMagicianDepthArrowIcon(direction: .back, motion: .front)
                .id(commandID)
        case .back:
            BallMagicianDepthArrowIcon(direction: .front, motion: .back)
                .id(commandID)
        default:
            BallMagicianMotionArrowIcon(command: command, color: borderColor)
                .id(commandID)
        }
    }

    @ViewBuilder
    private var plainCommandIcon: some View {
        switch command {
        case .front:
            BallMagicianPlainDepthArrowIcon(systemImageName: "arrow.up", color: borderColor, motion: .front)
                .id(commandID)
        case .back:
            BallMagicianPlainDepthArrowIcon(systemImageName: "arrow.down", color: borderColor, motion: .back)
                .id(commandID)
        default:
            BallMagicianMotionArrowIcon(command: command, color: borderColor)
                .id(commandID)
        }
    }

    private var borderColor: Color {
        guard
            let lastResult,
            lastResult.commandID == commandID,
            Date().timeIntervalSince(lastResult.timestamp) <= 0.50
        else {
            return .yellow
        }

        switch lastResult {
        case .success:
            return .green
        case .miss:
            return .red
        }
    }
}

private struct BallMagicianMotionArrowIcon: View {
    let command: BallMagicianCommand?
    let color: Color
    @State private var animationStartedAt = Date()

    private let animationDuration: TimeInterval = 2.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = animationProgress(at: timeline.date)
            let offset = arrowOffset(progress: progress)

            ZStack {
                Image(systemName: command?.systemImageName ?? "sparkles")
                    .font(.ballr(size: 68, weight: .black))
                    .foregroundStyle(.black.opacity(0.78))
                    .offset(x: offset.width, y: offset.height + 3)

                Image(systemName: command?.systemImageName ?? "sparkles")
                    .font(.ballr(size: 66, weight: .black))
                    .foregroundStyle(color)
                    .shadow(color: .white.opacity(0.95), radius: 2)
                    .shadow(color: .black.opacity(0.82), radius: 7)
                    .offset(offset)
            }
        }
        .onAppear {
            animationStartedAt = Date()
        }
    }

    private func animationProgress(at date: Date) -> CGFloat {
        CGFloat(min(max(date.timeIntervalSince(animationStartedAt) / animationDuration, 0), 1))
    }

    private func arrowOffset(progress: CGFloat) -> CGSize {
        guard let command else {
            return .zero
        }

        let twoPulse = pow(sin(.pi * 2 * progress), 2)
        let juggleWave = -sin(.pi * 4 * progress)

        switch command {
        case .left:
            return CGSize(width: -22 * twoPulse, height: 0)
        case .right:
            return CGSize(width: 22 * twoPulse, height: 0)
        case .up:
            return CGSize(width: 0, height: 18 * juggleWave)
        case .front, .back:
            return .zero
        }
    }
}

private struct BallMagicianDepthArrowIcon: View {
    let direction: BallMagicianDepthDirection
    let motion: BallMagicianDepthMotion
    @State private var animationStartedAt = Date()

    private let animationDuration: TimeInterval = 2.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = animationProgress(at: timeline.date)

            ZStack {
                depthTunnel(progress: progress)

                BallMagicianGroundLaneShape()
                    .stroke(.white.opacity(0.26), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 92, height: 70)
                    .offset(y: 6)

                Ellipse()
                    .fill(.black.opacity(0.28))
                    .frame(width: 96, height: 18)
                    .offset(y: 37)

                BallMagicianGroundArrowShape(direction: direction)
                    .fill(direction.fillColor)
                    .overlay {
                        BallMagicianGroundArrowShape(direction: direction)
                            .stroke(.white.opacity(0.98), lineWidth: 5)
                    }
                    .frame(width: 88, height: 76)
                    .shadow(color: .black.opacity(0.86), radius: 8, x: 0, y: 4)
            }
            .scaleEffect(motion.iconScale(progress: progress))
            .frame(width: 108, height: 94)
        }
        .onAppear {
            animationStartedAt = Date()
        }
    }

    private func animationProgress(at date: Date) -> CGFloat {
        let rawProgress = min(max(date.timeIntervalSince(animationStartedAt) / animationDuration, 0), 1)
        let easedProgress = rawProgress * rawProgress * (3 - (2 * rawProgress))
        return CGFloat(easedProgress)
    }

    @ViewBuilder
    private func depthTunnel(progress: CGFloat) -> some View {
        ForEach(0..<3, id: \.self) { index in
            let ringScale = motion.ringScale(index: index, progress: progress)
            let ringOpacity = motion.ringOpacity(index: index, progress: progress)

            Ellipse()
                .stroke(direction.fillColor.opacity(ringOpacity), lineWidth: 3)
                .frame(
                    width: 36 + CGFloat(index * 24),
                    height: 10 + CGFloat(index * 7)
                )
                .scaleEffect(ringScale)
                .offset(y: 30 - CGFloat(index * 18))
                .shadow(color: direction.fillColor.opacity(ringOpacity * 0.72), radius: 7)
        }
    }
}

private struct BallMagicianPlainDepthArrowIcon: View {
    let systemImageName: String
    let color: Color
    let motion: BallMagicianDepthMotion
    @State private var animationStartedAt = Date()

    private let animationDuration: TimeInterval = 2.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = animationProgress(at: timeline.date)
            let scale = motion.iconScale(progress: progress)
            let yOffset = motion.plainYOffset(progress: progress)

            ZStack {
                Image(systemName: systemImageName)
                    .font(.ballr(size: 78, weight: .black))
                    .foregroundStyle(.black.opacity(0.76))
                    .offset(x: 0, y: yOffset + 4)

                Image(systemName: systemImageName)
                    .font(.ballr(size: 76, weight: .black))
                    .foregroundStyle(color)
                    .shadow(color: .white.opacity(0.95), radius: 2)
                    .shadow(color: color.opacity(0.80), radius: 18)
                    .shadow(color: .black.opacity(0.82), radius: 7)
                    .offset(y: yOffset)
            }
            .scaleEffect(scale)
        }
        .onAppear {
            animationStartedAt = Date()
        }
    }

    private func animationProgress(at date: Date) -> CGFloat {
        let rawProgress = min(max(date.timeIntervalSince(animationStartedAt) / animationDuration, 0), 1)
        let easedProgress = rawProgress * rawProgress * (3 - (2 * rawProgress))
        return CGFloat(easedProgress)
    }
}

private enum BallMagicianDepthMotion {
    case front
    case back

    func iconScale(progress: CGFloat) -> CGFloat {
        switch self {
        case .front:
            return 0.62 + (0.70 * progress)
        case .back:
            return 1.32 - (0.70 * progress)
        }
    }

    func ringScale(index: Int, progress: CGFloat) -> CGFloat {
        let stagger = CGFloat(index) * 0.12
        let adjustedProgress = min(max((progress - stagger) / 0.76, 0), 1)

        switch self {
        case .front:
            return 0.38 + adjustedProgress * 1.62
        case .back:
            return 2.00 - adjustedProgress * 1.62
        }
    }

    func ringOpacity(index: Int, progress: CGFloat) -> CGFloat {
        let stagger = CGFloat(index) * 0.12
        let adjustedProgress = min(max((progress - stagger) / 0.76, 0), 1)
        return 0.72 * (1 - abs(0.5 - adjustedProgress))
    }

    func plainYOffset(progress: CGFloat) -> CGFloat {
        switch self {
        case .front:
            return 18 - (36 * progress)
        case .back:
            return -18 + (36 * progress)
        }
    }
}

private enum BallMagicianDepthDirection {
    case front
    case back

    var fillColor: Color {
        switch self {
        case .front:
            return Color(red: 1.0, green: 0.68, blue: 0.82)
        case .back:
            return Color(red: 0.54, green: 0.88, blue: 1.0)
        }
    }
}

private struct BallMagicianGroundLaneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.82, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.32, y: rect.minY + rect.height * 0.30))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.68, y: rect.minY + rect.height * 0.30))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.24, y: rect.minY + rect.height * 0.62))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.76, y: rect.minY + rect.height * 0.62))
        return path
    }
}

private struct BallMagicianGroundArrowShape: Shape {
    let direction: BallMagicianDepthDirection

    func path(in rect: CGRect) -> Path {
        switch direction {
        case .front:
            return frontPath(in: rect)
        case .back:
            return backPath(in: rect)
        }
    }

    private func frontPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.66, y: rect.minY + rect.height * 0.56))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.56, y: rect.minY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.06))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.minY + rect.height * 0.56))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.58))
        path.closeSubpath()
        return path
    }

    private func backPath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.42))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.63, y: rect.minY + rect.height * 0.44))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.74, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.37, y: rect.minY + rect.height * 0.44))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.42))
        path.closeSubpath()
        return path
    }
}

private struct BallMagicianHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.ballr(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.68))

            Text(value)
                .font(.ballr(size: 28, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct BallMagicianLoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.84)
                .ignoresSafeArea()

            ProgressView()
                .tint(.yellow)
                .scaleEffect(1.4)
        }
    }
}

private struct BallMagicianErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(permissionDenied ? "Camera Needed" : "Unable to Start")
                    .font(.ballr(size: 30, weight: .black))
                    .foregroundStyle(.yellow)

                Text(message)
                    .font(.ballr(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button("DONE", action: onDismiss)
                    .font(.ballr(size: 20, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 160, height: 54)
                    .background(.yellow, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(30)
        }
    }
}

private struct BallMagicianReadinessOverlay: View {
    let readyStartedAt: Date?

    private let requiredLockSeconds: TimeInterval = 1.2

    var body: some View {
        TimelineView(.animation) { timeline in
            let progress = readinessProgress(at: timeline.date)

            ZStack {
                Color.black.opacity(0.82)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    Text(readyStartedAt == nil ? "Find the ball" : "Hold still")
                        .font(.ballr(size: 34, weight: .black))
                        .foregroundStyle(.yellow)

                    Text("Keep the ball and your lower body in frame.")
                        .font(.ballr(size: 18, weight: .bold))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    if readyStartedAt != nil {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 999)
                                .fill(.white.opacity(0.12))
                                .frame(width: 240, height: 16)

                            RoundedRectangle(cornerRadius: 999)
                                .fill(Color.yellow)
                                .frame(width: 240 * progress, height: 16)
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    private func readinessProgress(at date: Date) -> CGFloat {
        guard let readyStartedAt else {
            return 0
        }
        return min(max(date.timeIntervalSince(readyStartedAt) / requiredLockSeconds, 0), 1)
    }
}

private struct BallMagicianDetectedBody {
    let zones: [BallMagicianContactZone]

    init?(points: [JugglingBodyJoint: CGPoint], confidences: [JugglingBodyJoint: CGFloat], bounds: CGSize) {
        self.zones = Self.makeZones(points: points, confidences: confidences, bounds: bounds)

        guard !zones.isEmpty else {
            return nil
        }
    }

    private static func makeZones(
        points: [JugglingBodyJoint: CGPoint],
        confidences: [JugglingBodyJoint: CGFloat],
        bounds: CGSize
    ) -> [BallMagicianContactZone] {
        var zones: [BallMagicianContactZone] = []
        appendZones(
            side: .left,
            ankleJoint: .leftAnkle,
            kneeJoint: .leftKnee,
            hipJoint: .leftHip,
            points: points,
            confidences: confidences,
            bounds: bounds,
            zones: &zones
        )
        appendZones(
            side: .right,
            ankleJoint: .rightAnkle,
            kneeJoint: .rightKnee,
            hipJoint: .rightHip,
            points: points,
            confidences: confidences,
            bounds: bounds,
            zones: &zones
        )
        return zones
    }

    private static func appendZones(
        side: BallMagicianBodySide,
        ankleJoint: JugglingBodyJoint,
        kneeJoint: JugglingBodyJoint,
        hipJoint: JugglingBodyJoint,
        points: [JugglingBodyJoint: CGPoint],
        confidences: [JugglingBodyJoint: CGFloat],
        bounds: CGSize,
        zones: inout [BallMagicianContactZone]
    ) {
        let ankle = points[ankleJoint]
        let knee = points[kneeJoint]
        let hip = points[hipJoint]

        if let ankle, let knee {
            let shinLength = max(distance(ankle, knee), 1)
            let footWidth = clamp(shinLength * 0.78, minValue: 42, maxValue: 150)
            let footHeight = clamp(shinLength * 0.48, minValue: 30, maxValue: 92)
            let rect = CGRect(
                x: ankle.x - footWidth * 0.5,
                y: ankle.y - footHeight * 0.72,
                width: footWidth,
                height: footHeight * 1.12
            ).intersection(boundsRect(for: bounds))
            if !rect.isNull, !rect.isEmpty {
                zones.append(
                    BallMagicianContactZone(
                        kind: side == .left ? .leftFoot : .rightFoot,
                        rect: rect,
                        confidence: min(confidences[ankleJoint] ?? 0.25, confidences[kneeJoint] ?? 0.25)
                    )
                )
            }

            let kneeSize = clamp(shinLength * 0.54, minValue: 36, maxValue: 102)
            let kneeRect = CGRect(
                x: knee.x - kneeSize * 0.5,
                y: knee.y - kneeSize * 0.5,
                width: kneeSize,
                height: kneeSize
            ).intersection(boundsRect(for: bounds))
            if !kneeRect.isNull, !kneeRect.isEmpty {
                zones.append(
                    BallMagicianContactZone(
                        kind: side == .left ? .leftKnee : .rightKnee,
                        rect: kneeRect,
                        confidence: confidences[kneeJoint] ?? 0.25
                    )
                )
            }
        }

        if let hip, let knee {
            let thighLength = max(distance(hip, knee), 1)
            let center = CGPoint(x: (hip.x + knee.x) * 0.5, y: (hip.y + knee.y) * 0.5)
            let width = clamp(thighLength * 0.62, minValue: 44, maxValue: 138)
            let height = clamp(thighLength * 0.82, minValue: 48, maxValue: 160)
            let rect = CGRect(
                x: center.x - width * 0.5,
                y: center.y - height * 0.5,
                width: width,
                height: height
            ).intersection(boundsRect(for: bounds))
            if !rect.isNull, !rect.isEmpty {
                zones.append(
                    BallMagicianContactZone(
                        kind: side == .left ? .leftHip : .rightHip,
                        rect: rect,
                        confidence: min(confidences[hipJoint] ?? 0.25, confidences[kneeJoint] ?? 0.25)
                    )
                )
            }
        }
    }

    private static func boundsRect(for bounds: CGSize) -> CGRect {
        CGRect(origin: .zero, size: bounds)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func clamp(_ value: CGFloat, minValue: CGFloat, maxValue: CGFloat) -> CGFloat {
        min(max(value, minValue), maxValue)
    }
}

private enum BallMagicianBodySide {
    case left
    case right
}

private struct BallMagicianContactZone {
    let kind: BallMagicianContactKind
    let rect: CGRect
    let confidence: CGFloat
}

private enum BallMagicianContactKind: Hashable {
    case leftFoot
    case rightFoot
    case leftKnee
    case rightKnee
    case leftHip
    case rightHip

    var isFoot: Bool {
        switch self {
        case .leftFoot, .rightFoot:
            return true
        case .leftKnee, .rightKnee, .leftHip, .rightHip:
            return false
        }
    }

    var priorityMultiplier: CGFloat {
        switch self {
        case .leftFoot, .rightFoot:
            return 1.08
        case .leftKnee, .rightKnee:
            return 1.0
        case .leftHip, .rightHip:
            return 0.92
        }
    }
}

private enum BallMagicianJuggleEvent {
    case counted
    case ignoredGroundBounce
}

private struct BallMagicianJuggleDetector {
    private struct Sample {
        let rect: CGRect
        let center: CGPoint
        let diameter: CGFloat
        let timestamp: Date
        let velocity: CGVector?
    }

    private struct ContactEvidence {
        let kind: BallMagicianContactKind
        let score: CGFloat
        let actualOverlapRatio: CGFloat
        let centerNormalizedY: CGFloat
        let distanceFromZone: CGFloat
        let zoneRect: CGRect
    }

    private struct PendingContact {
        let evidence: ContactEvidence
        let timestamp: Date
    }

    private let maxSampleAge: TimeInterval = 0.72
    private let pendingContactLifetime: TimeInterval = 0.26
    private let countCooldown: TimeInterval = 0.22
    private let contactScoreThreshold: CGFloat = 0.24
    private let minimumFootOverlapRatio: CGFloat = 0.025
    private let strongFootProximityThreshold: CGFloat = 0.50

    private var samples: [Sample] = []
    private var pendingContact: PendingContact?
    private var lastCountedAt: Date?

    mutating func start() {
        samples.removeAll()
        pendingContact = nil
    }

    mutating func reset() {
        samples.removeAll()
        pendingContact = nil
        lastCountedAt = nil
    }

    mutating func observe(
        ballDisplayRect: CGRect?,
        body: BallMagicianDetectedBody?,
        timestamp: Date,
        isBallTracked: Bool
    ) {
        _ = step(
            ballDisplayRect: ballDisplayRect,
            body: body,
            timestamp: timestamp,
            isBallTracked: isBallTracked,
            allowsCounting: false
        )
    }

    mutating func step(
        ballDisplayRect: CGRect?,
        body: BallMagicianDetectedBody?,
        timestamp: Date,
        isBallTracked: Bool
    ) -> BallMagicianJuggleEvent? {
        step(
            ballDisplayRect: ballDisplayRect,
            body: body,
            timestamp: timestamp,
            isBallTracked: isBallTracked,
            allowsCounting: true
        )
    }

    private mutating func step(
        ballDisplayRect: CGRect?,
        body: BallMagicianDetectedBody?,
        timestamp: Date,
        isBallTracked: Bool,
        allowsCounting: Bool
    ) -> BallMagicianJuggleEvent? {
        guard isBallTracked, let ballDisplayRect else {
            pendingContact = nil
            return nil
        }

        let sample = makeSample(rect: ballDisplayRect, timestamp: timestamp)
        samples.append(sample)
        let maxAge = maxSampleAge
        samples.removeAll { timestamp.timeIntervalSince($0.timestamp) > maxAge }
        if samples.count > 18 {
            samples.removeFirst(samples.count - 18)
        }

        if let pendingContact, timestamp.timeIntervalSince(pendingContact.timestamp) > pendingContactLifetime {
            self.pendingContact = nil
        }

        guard let body, samples.count >= 3 else {
            return nil
        }

        let contact = bestContact(for: sample.rect, body: body)
        if let contact, sample.velocity?.dy ?? 0 > minDownSpeed(for: sample.diameter) * 0.55 {
            pendingContact = PendingContact(
                evidence: contact,
                timestamp: timestamp
            )
        }

        guard allowsCounting, didReboundUpward(at: sample) else {
            return nil
        }

        let previous = samples[samples.count - 2]
        let previousContact = bestContact(for: previous.rect, body: body)
        let resolvedContact = strongestContact(
            current: contact,
            previous: previousContact,
            pending: pendingContact,
            timestamp: timestamp
        )

        guard let resolvedContact else {
            pendingContact = nil
            return .ignoredGroundBounce
        }

        guard isValidPlayerContact(resolvedContact, sample: sample) else {
            pendingContact = nil
            return .ignoredGroundBounce
        }

        guard timestamp.timeIntervalSince(lastCountedAt ?? .distantPast) >= countCooldown else {
            return nil
        }

        lastCountedAt = timestamp
        pendingContact = nil
        return .counted
    }

    private func makeSample(rect: CGRect, timestamp: Date) -> Sample {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let diameter = max(rect.width, rect.height, 1)

        guard let previous = samples.last else {
            return Sample(rect: rect, center: center, diameter: diameter, timestamp: timestamp, velocity: nil)
        }

        let deltaTime = max(timestamp.timeIntervalSince(previous.timestamp), 1.0 / 90.0)
        let velocity = CGVector(
            dx: (center.x - previous.center.x) / deltaTime,
            dy: (center.y - previous.center.y) / deltaTime
        )
        return Sample(rect: rect, center: center, diameter: diameter, timestamp: timestamp, velocity: velocity)
    }

    private func didReboundUpward(at sample: Sample) -> Bool {
        guard
            samples.count >= 3,
            let currentVelocity = sample.velocity,
            let previousVelocity = samples[samples.count - 2].velocity
        else {
            return false
        }

        let downSpeed = minDownSpeed(for: sample.diameter)
        let upSpeed = minUpSpeed(for: sample.diameter)
        if previousVelocity.dy >= downSpeed, currentVelocity.dy <= -upSpeed {
            return true
        }

        let twoBack = samples[samples.count - 3]
        let previous = samples[samples.count - 2]
        let verticalSlack = max(sample.diameter * 0.06, 3)
        let wasDescending = previous.center.y > twoBack.center.y + verticalSlack
        let isRising = sample.center.y < previous.center.y - verticalSlack
        return wasDescending && isRising && currentVelocity.dy <= -upSpeed * 0.55
    }

    private func strongestContact(
        current: ContactEvidence?,
        previous: ContactEvidence?,
        pending: PendingContact?,
        timestamp: Date
    ) -> ContactEvidence? {
        var candidates: [ContactEvidence] = []
        if let current {
            candidates.append(current)
        }
        if let previous {
            candidates.append(previous)
        }
        if let pending, timestamp.timeIntervalSince(pending.timestamp) <= pendingContactLifetime {
            candidates.append(pending.evidence)
        }

        return candidates.max(by: { $0.score < $1.score })
    }

    private func bestContact(
        for ballRect: CGRect,
        body: BallMagicianDetectedBody
    ) -> ContactEvidence? {
        body.zones
            .map { zone in
                contactEvidence(ballRect: ballRect, zone: zone)
            }
            .filter { $0.score >= contactScoreThreshold }
            .max(by: { $0.score < $1.score })
    }

    private func contactEvidence(ballRect: CGRect, zone: BallMagicianContactZone) -> ContactEvidence {
        let diameter = max(ballRect.width, ballRect.height, 1)
        let tolerance = max(diameter * 0.68, 22)
        let expandedZone = zone.rect.insetBy(dx: -tolerance, dy: -tolerance)
        let center = CGPoint(x: ballRect.midX, y: ballRect.midY)

        let distance = distance(from: center, to: zone.rect)
        let proximityScore = max(0, 1 - distance / tolerance) * 0.58

        let overlapRect = ballRect.intersection(expandedZone)
        let overlapScore: CGFloat
        if overlapRect.isNull || overlapRect.isEmpty {
            overlapScore = 0
        } else {
            let ballArea = max(ballRect.width * ballRect.height, 1)
            let zoneArea = max(zone.rect.width * zone.rect.height, 1)
            let overlapArea = overlapRect.width * overlapRect.height
            overlapScore = min(overlapArea / min(ballArea, zoneArea), 1) * 0.54
        }

        let actualOverlapRect = ballRect.intersection(zone.rect)
        let actualOverlapRatio: CGFloat
        if actualOverlapRect.isNull || actualOverlapRect.isEmpty {
            actualOverlapRatio = 0
        } else {
            let ballArea = max(ballRect.width * ballRect.height, 1)
            let zoneArea = max(zone.rect.width * zone.rect.height, 1)
            actualOverlapRatio = min((actualOverlapRect.width * actualOverlapRect.height) / min(ballArea, zoneArea), 1)
        }

        let normalizedCenterY = (center.y - zone.rect.minY) / max(zone.rect.height, 1)
        let centerBonus: CGFloat = expandedZone.contains(center) ? 0.18 : 0
        let score = min((max(proximityScore, overlapScore) + centerBonus) * zone.confidence * zone.kind.priorityMultiplier, 1)

        return ContactEvidence(
            kind: zone.kind,
            score: score,
            actualOverlapRatio: actualOverlapRatio,
            centerNormalizedY: normalizedCenterY,
            distanceFromZone: distance,
            zoneRect: zone.rect
        )
    }

    private func isValidPlayerContact(_ contact: ContactEvidence, sample: Sample) -> Bool {
        guard contact.kind.isFoot else {
            return contact.score >= contactScoreThreshold
        }

        let lowerFootAllowance = max(sample.diameter * 0.16, 7)
        let isNotBelowFoot = sample.center.y <= contact.zoneRect.maxY + lowerFootAllowance
        let overlapsFoot = contact.actualOverlapRatio >= minimumFootOverlapRatio
        let tightlyAboveFoot = contact.score >= strongFootProximityThreshold
            && contact.distanceFromZone <= max(sample.diameter * 0.34, 12)
            && contact.centerNormalizedY <= 0.96

        return isNotBelowFoot && (overlapsFoot || tightlyAboveFoot)
    }

    private func minDownSpeed(for diameter: CGFloat) -> CGFloat {
        max(diameter * 1.85, 86)
    }

    private func minUpSpeed(for diameter: CGFloat) -> CGFloat {
        max(diameter * 1.45, 74)
    }

    private func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }
}

private enum BallMagicianSoundPlayer {
    private static var scorePlayer: AVAudioPlayer?

    static func playScore() {
        guard let url = Bundle.main.url(forResource: "target_scored_sound_effect", withExtension: "wav") else {
            return
        }

        do {
            scorePlayer = try AVAudioPlayer(contentsOf: url)
            scorePlayer?.prepareToPlay()
            scorePlayer?.play()
        } catch {
            #if DEBUG
            print("Ball Magician score sound failed: \(error.localizedDescription)")
            #endif
        }
    }
}
