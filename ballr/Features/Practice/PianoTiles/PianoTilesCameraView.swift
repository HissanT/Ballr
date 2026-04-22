import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct PianoTilesCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = PianoTilesCoordinator()
    @State private var showsQuitConfirmation = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.20)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                PianoTilesRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if cameraController.isStarting {
                    PianoTilesLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    PianoTilesErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                } else if coordinator.phase == .readiness && cameraController.errorMessage == nil {
                    BallrDrillReadinessOverlay(ballFoundStartedAt: coordinator.ballFoundStartedAt)
                }

                if coordinator.phase == .gameOver {
                    PianoTilesFinishedOverlay(
                        title: "GAME OVER",
                        subtitle: "A tile slipped past.",
                        scoreText: coordinator.scoreText,
                        primaryTitle: "PLAY AGAIN",
                        onPrimary: { coordinator.reset(in: geometry.size) },
                        onDone: { dismiss() }
                    )
                }

                if coordinator.phase == .won {
                    PianoTilesFinishedOverlay(
                        title: "COMPLETE",
                        subtitle: "Clean run.",
                        scoreText: "40/40",
                        primaryTitle: "PLAY AGAIN",
                        onPrimary: { coordinator.reset(in: geometry.size) },
                        onDone: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
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
                BallrOrientationController.restoreDefaultOrientation()
            }
            .onChange(of: geometry.size) { _, newSize in
                coordinator.prepare(in: newSize)
            }
            .alert("Are you sure you want to quit the drill?", isPresented: $showsQuitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive) {
                    dismiss()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                showsQuitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.58), in: Circle())
            }

            Spacer()

            HStack(spacing: 8) {
                PianoTilesHudChip(title: "SCORE", value: coordinator.scoreText, tint: .yellow)
                PianoTilesHudChip(title: "LEFT", value: coordinator.remainingText, tint: .green)
                PianoTilesHudChip(title: "MODE", value: coordinator.modeText, tint: .cyan)
            }
        }
    }
}

private enum PianoTilesPhase {
    case readiness
    case countdown
    case live
    case gameOver
    case won
}

private enum PianoTileKind {
    case tap
    case hold
}

private enum PianoTilesEvent {
    case completed(PianoTileSoundTrigger)
    case holdStarted(PianoTileSoundTrigger)
    case missed
    case won(PianoTileSoundTrigger?)
}

private struct PianoTileSoundTrigger {
    let lane: Int
    let kind: PianoTileKind
    let sequenceIndex: Int
}

private struct PianoTileSpawnWarning {
    let lane: Int
    let progress: CGFloat
}

private final class PianoTilesCoordinator: ObservableObject {
    @Published private(set) var phase: PianoTilesPhase = .readiness
    @Published private(set) var ballFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var scoreText = "0/40"
    @Published private(set) var remainingText = "40"
    @Published private(set) var modeText = "READY"

    private let requiredBallLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let lostBallPromptFrameThreshold = 18
    private let maxPausedFramesBeforeTilesMove = 10

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var pausedFrameCount = 0
    private var lostBallFrameCount = 0
    private var heldBallDisplayRect: CGRect?
    private var gameState = PianoTilesGameState()
    private weak var renderView: PianoTilesRenderView?

    func attach(renderView: PianoTilesRenderView) {
        self.renderView = renderView
        renderView.onBoundsChange = { [weak self] size in
            self?.prepare(in: size)
        }
        let renderSize = renderView.bounds.size
        if renderSize.width > 0, renderSize.height > 0 {
            size = renderSize
        }
        renderView.update(
            tiles: gameState.tiles,
            activeSequenceIndex: gameState.activeSequenceIndex,
            ballDisplayRect: nil,
            isTracking: false,
            prompt: promptText,
            spawnWarning: nil
        )
    }

    func reset(in size: CGSize) {
        self.size = resolvedGameplaySize(fallback: size)
        phase = .readiness
        ballFoundStartedAt = nil
        countdownStartedAt = nil
        scoreText = "0/40"
        remainingText = "40"
        modeText = "READY"
        liveElapsed = 0
        lastStepAt = nil
        pausedFrameCount = 0
        lostBallFrameCount = 0
        heldBallDisplayRect = nil
        PianoTilesSoundPlayer.stop()
        gameState.reset()
        renderView?.update(
            tiles: gameState.tiles,
            activeSequenceIndex: gameState.activeSequenceIndex,
            ballDisplayRect: nil,
            isTracking: false,
            prompt: promptText,
            spawnWarning: nil
        )
    }

    func prepare(in size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            return
        }
        self.size = resolvedGameplaySize(fallback: size)
        renderView?.update(
            tiles: gameState.tiles,
            activeSequenceIndex: gameState.activeSequenceIndex,
            ballDisplayRect: nil,
            isTracking: phase == .live,
            prompt: promptText,
            spawnWarning: phase == .live ? gameState.spawnWarning(elapsed: liveElapsed) : nil
        )
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        let overlayState = frame.overlayState
        let detectedBallDisplayRect = collisionDisplayRect(for: overlayState, cameraController: cameraController)
        let detectedIsTracking = overlayState.isTracking && detectedBallDisplayRect != nil
        let effectiveBallDisplayRect = resolvedBallDisplayRect(
            detectedBallDisplayRect,
            rawIsTracking: overlayState.isTracking
        )

        guard phase != .gameOver, phase != .won else {
            renderView?.update(
                tiles: gameState.tiles,
                activeSequenceIndex: gameState.activeSequenceIndex,
                ballDisplayRect: effectiveBallDisplayRect,
                isTracking: detectedIsTracking,
                prompt: promptText,
                spawnWarning: nil
            )
            return
        }

        updateStartGate(isTracking: detectedIsTracking, timestamp: frame.timestamp)

        if phase == .live {
            stepLiveGame(
                ballDisplayRect: detectedBallDisplayRect,
                isTracking: detectedIsTracking,
                timestamp: frame.timestamp
            )
        }

        publishScore()
        renderView?.update(
            tiles: gameState.tiles,
            activeSequenceIndex: gameState.activeSequenceIndex,
            ballDisplayRect: effectiveBallDisplayRect,
            isTracking: detectedIsTracking,
            prompt: promptText,
            spawnWarning: phase == .live ? gameState.spawnWarning(elapsed: liveElapsed) : nil
        )
    }

    private func resolvedBallDisplayRect(
        _ detectedBallDisplayRect: CGRect?,
        rawIsTracking: Bool
    ) -> CGRect? {
        if rawIsTracking, let detectedBallDisplayRect {
            heldBallDisplayRect = detectedBallDisplayRect
            lostBallFrameCount = 0
            return detectedBallDisplayRect
        }

        guard phase == .live, let heldBallDisplayRect else {
            lostBallFrameCount = 0
            return nil
        }

        lostBallFrameCount += 1
        if lostBallFrameCount < lostBallPromptFrameThreshold {
            return heldBallDisplayRect
        }

        return nil
    }

    private func collisionDisplayRect(
        for overlayState: BallTrackerOverlayState,
        cameraController: BallTrackerCameraController
    ) -> CGRect? {
        guard let normalizedRect = overlayState.rawNormalizedRect else {
            return nil
        }
        guard let displayRect = cameraController.displayRect(for: normalizedRect) else {
            return nil
        }
        return Self.collisionCircleRect(from: displayRect)
    }

    private func resolvedGameplaySize(fallback size: CGSize) -> CGSize {
        guard let renderView else {
            return size
        }

        let renderSize = renderView.bounds.size
        guard renderSize.width > 0, renderSize.height > 0 else {
            return size
        }
        return renderSize
    }

    private static func collisionCircleRect(from rect: CGRect) -> CGRect? {
        guard rect.width > 0, rect.height > 0 else {
            return nil
        }

        let diameter = min(rect.width, rect.height)
        guard diameter > 0 else {
            return nil
        }

        return CGRect(
            x: rect.midX - diameter * 0.5,
            y: rect.midY - diameter * 0.5,
            width: diameter,
            height: diameter
        )
    }

    private func updateStartGate(isTracking: Bool, timestamp: Date) {
        if phase == .live {
            return
        }

        if phase == .countdown {
            if
                let countdownStartedAt,
                timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration
            {
                phase = .live
                modeText = "PLAY"
                lastStepAt = nil
            }
            return
        }

        guard phase == .readiness else {
            return
        }

        guard isTracking else {
            ballFoundStartedAt = nil
            return
        }

        let startedAt = ballFoundStartedAt ?? timestamp
        ballFoundStartedAt = startedAt
        if timestamp.timeIntervalSince(startedAt) >= requiredBallLockSeconds {
            countdownStartedAt = timestamp
            phase = .countdown
            modeText = "SET"
        }
    }

    private func stepLiveGame(
        ballDisplayRect: CGRect?,
        isTracking: Bool,
        timestamp: Date
    ) {
        guard isTracking, let ballDisplayRect else {
            pausedFrameCount += 1
            if pausedFrameCount <= maxPausedFramesBeforeTilesMove {
                lastStepAt = nil
                modeText = "PAUSED"
                return
            }

            let previousStepAt = lastStepAt ?? timestamp
            lastStepAt = timestamp
            let delta = min(max(timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
            liveElapsed += delta
            switch gameState.stepWithoutBall(in: size, elapsed: liveElapsed, delta: delta) {
            case .missed:
                phase = .gameOver
                modeText = "MISS"
                return
            case .won(_):
                BallrDrillSoundPlayer.playWinner()
                phase = .won
                modeText = "CLEAR"
                return
            case .completed(_), .holdStarted(_), .none:
                break
            }
            modeText = "PAUSED"
            return
        }
        pausedFrameCount = 0

        let previousStepAt = lastStepAt ?? timestamp
        lastStepAt = timestamp
        let delta = min(max(timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
        liveElapsed += delta

        let event = gameState.step(
            ballDisplayRect: ballDisplayRect,
            in: size,
            elapsed: liveElapsed,
            delta: delta
        )

        switch event {
        case .completed(let trigger):
            PianoTilesSoundPlayer.playCompletion(for: trigger)
            modeText = "HIT"
        case .holdStarted(let trigger):
            PianoTilesSoundPlayer.playHoldStart(for: trigger)
            modeText = "HOLD"
        case .missed:
            PianoTilesSoundPlayer.stop()
            phase = .gameOver
            modeText = "MISS"
        case .won(let trigger):
            if let trigger {
                PianoTilesSoundPlayer.playCompletion(for: trigger)
            }
            BallrDrillSoundPlayer.playWinner()
            phase = .won
            modeText = "CLEAR"
        case .none:
            modeText = "PLAY"
        }
    }

    private var promptText: String? {
        switch phase {
        case .readiness, .countdown:
            return nil
        case .live:
            return heldBallDisplayRect == nil || lostBallFrameCount >= lostBallPromptFrameThreshold ? "Find the ball" : nil
        case .gameOver:
            return "Game over"
        case .won:
            return "Complete"
        }
    }

    private func publishScore() {
        scoreText = "\(gameState.score)/\(PianoTilesGameState.totalTileCount)"
        remainingText = "\(max(PianoTilesGameState.totalTileCount - gameState.score, 0))"
    }
}

private enum PianoTilesSoundPlayer {
    private static let queue = DispatchQueue(label: "com.ballr.piano-tiles-sound")
    private static var playersByNote: [String: AVAudioPlayer] = [:]
    private static var didAttemptPrepare = false
    private static var availableNotes: [String] = []
    private static let preferredNotes = [
        "40", "42", "44", "45", "47", "49", "51", "52",
        "54", "56", "57", "59", "61", "63", "64", "63",
        "61", "59", "57", "56", "54", "52", "51", "49",
        "47", "45", "44", "42"
    ]

    static func playCompletion(for trigger: PianoTileSoundTrigger) {
        playNote(for: trigger, volume: 0.9)
    }

    static func playHoldStart(for trigger: PianoTileSoundTrigger) {
        playNote(for: trigger, volume: 0.72)
    }

    static func stop() {
        queue.async {
            playersByNote.values.forEach { player in
                player.stop()
                player.currentTime = 0
            }
        }
    }

    private static func playNote(for trigger: PianoTileSoundTrigger, volume: Float) {
        queue.async {
            do {
                try prepareIfNeeded()
                guard let note = noteName(for: trigger), let player = playersByNote[note] else {
                    return
                }
                player.stop()
                player.currentTime = 0
                player.volume = volume
                player.play()
            } catch {
                print("Piano Tiles sound failed: \(error.localizedDescription)")
            }
        }
    }

    private static func noteName(for trigger: PianoTileSoundTrigger) -> String? {
        let playablePreferredNotes = preferredNotes.filter { playersByNote[$0] != nil }
        if !playablePreferredNotes.isEmpty {
            let noteOffset = trigger.lane + trigger.sequenceIndex
            return playablePreferredNotes[noteOffset % playablePreferredNotes.count]
        }

        guard !availableNotes.isEmpty else {
            return nil
        }
        return availableNotes[trigger.sequenceIndex % availableNotes.count]
    }

    private static func prepareIfNeeded() throws {
        if didAttemptPrepare {
            return
        }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setPreferredIOBufferDuration(0.006)
        try session.setActive(true)

        var loadedNoteNames: [String] = []
        for noteIndex in 1...88 {
            let noteName = String(format: "%02d", noteIndex)
            guard let url = Bundle.main.url(forResource: noteName, withExtension: "wav", subdirectory: "sounds") else {
                continue
            }

            let loadedPlayer = try AVAudioPlayer(contentsOf: url)
            loadedPlayer.prepareToPlay()
            playersByNote[noteName] = loadedPlayer
            loadedNoteNames.append(noteName)
        }

        availableNotes = loadedNoteNames
        didAttemptPrepare = true
    }
}

private struct PianoTilesRenderSurface: UIViewRepresentable {
    let coordinator: PianoTilesCoordinator

    func makeUIView(context: Context) -> PianoTilesRenderView {
        let view = PianoTilesRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: PianoTilesRenderView, context: Context) {
    }
}

private final class PianoTilesRenderView: UIView {
    private let laneLayer = CAShapeLayer()
    private let missLineLayer = CAShapeLayer()
    private let spawnWarningOuterLayer = CAShapeLayer()
    private let spawnWarningInnerLayer = CAShapeLayer()
    private let spawnWarningCoreLayer = CAShapeLayer()
    private let ballRingLayer = CAShapeLayer()
    private let ballCenterLayer = CAShapeLayer()
    private let promptLabel = UILabel()

    private var tileLayers: [UUID: PianoTileLayerSet] = [:]
    private var tiles: [PianoTile] = []
    private var activeSequenceIndex = 0
    private var ballDisplayRect: CGRect?
    private var isTracking = false
    private var prompt: String?
    private var spawnWarning: PianoTileSpawnWarning?
    var onBoundsChange: ((CGSize) -> Void)?
    private var lastReportedBoundsSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        configureLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        tiles: [PianoTile],
        activeSequenceIndex: Int,
        ballDisplayRect: CGRect?,
        isTracking: Bool,
        prompt: String?,
        spawnWarning: PianoTileSpawnWarning?
    ) {
        self.tiles = tiles
        self.activeSequenceIndex = activeSequenceIndex
        self.ballDisplayRect = ballDisplayRect
        self.isTracking = isTracking
        self.prompt = prompt
        self.spawnWarning = spawnWarning
        render()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reportBoundsIfNeeded()
        render()
    }

    private func configureLayers() {
        laneLayer.fillColor = UIColor.clear.cgColor
        laneLayer.strokeColor = UIColor.white.withAlphaComponent(0.16).cgColor
        laneLayer.lineWidth = 2
        layer.addSublayer(laneLayer)

        missLineLayer.fillColor = UIColor.clear.cgColor
        missLineLayer.strokeColor = UIColor.systemRed.withAlphaComponent(0.58).cgColor
        missLineLayer.lineWidth = 3
        missLineLayer.lineDashPattern = [10, 7]
        layer.addSublayer(missLineLayer)

        spawnWarningOuterLayer.fillColor = UIColor.systemRed.cgColor
        spawnWarningOuterLayer.shadowColor = UIColor.systemRed.cgColor
        spawnWarningOuterLayer.shadowOffset = .zero
        spawnWarningOuterLayer.shadowRadius = 28
        spawnWarningOuterLayer.shadowOpacity = 0
        spawnWarningOuterLayer.isHidden = true
        layer.addSublayer(spawnWarningOuterLayer)

        spawnWarningInnerLayer.fillColor = UIColor.systemRed.cgColor
        spawnWarningInnerLayer.shadowColor = UIColor.systemRed.cgColor
        spawnWarningInnerLayer.shadowOffset = .zero
        spawnWarningInnerLayer.shadowRadius = 16
        spawnWarningInnerLayer.shadowOpacity = 0
        spawnWarningInnerLayer.isHidden = true
        layer.addSublayer(spawnWarningInnerLayer)

        spawnWarningCoreLayer.fillColor = UIColor.white.cgColor
        spawnWarningCoreLayer.shadowColor = UIColor.systemRed.cgColor
        spawnWarningCoreLayer.shadowOffset = .zero
        spawnWarningCoreLayer.shadowRadius = 10
        spawnWarningCoreLayer.shadowOpacity = 0
        spawnWarningCoreLayer.isHidden = true
        layer.addSublayer(spawnWarningCoreLayer)

        ballRingLayer.fillColor = UIColor.clear.cgColor
        ballRingLayer.strokeColor = UIColor.white.cgColor
        ballRingLayer.lineWidth = 3
        ballRingLayer.shadowColor = UIColor.black.cgColor
        ballRingLayer.shadowOpacity = 0.45
        ballRingLayer.shadowRadius = 6
        ballRingLayer.shadowOffset = .zero
        layer.addSublayer(ballRingLayer)

        ballCenterLayer.fillColor = UIColor.yellow.cgColor
        layer.addSublayer(ballCenterLayer)

        promptLabel.font = .systemFont(ofSize: 17, weight: .black)
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        promptLabel.layer.cornerRadius = 8
        promptLabel.layer.masksToBounds = true
        addSubview(promptLabel)
    }

    private func reportBoundsIfNeeded() {
        guard bounds.size != lastReportedBoundsSize else {
            return
        }

        lastReportedBoundsSize = bounds.size
        guard bounds.width > 0, bounds.height > 0 else {
            return
        }
        onBoundsChange?(bounds.size)
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderLanes()
        renderSpawnWarning()
        renderTiles()
        renderBall()
        renderPrompt()
        CATransaction.commit()
    }

    private func renderLanes() {
        let path = UIBezierPath()
        let metrics = PianoTilesMetrics(size: bounds.size)
        for index in 1..<PianoTilesGameState.laneCount {
            let x = metrics.horizontalInset
                + CGFloat(index) * metrics.laneWidth
                + CGFloat(index - 1) * metrics.laneGap
                + metrics.laneGap * 0.5
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: bounds.height))
        }
        laneLayer.path = path.cgPath

        let missY = PianoTilesGameState.missLineY(in: bounds.size)
        let missPath = UIBezierPath()
        missPath.move(to: CGPoint(x: metrics.horizontalInset, y: missY))
        missPath.addLine(to: CGPoint(x: bounds.width - metrics.horizontalInset, y: missY))
        missLineLayer.path = missPath.cgPath
    }

    private func renderTiles() {
        let activeIDs = Set(tiles.map(\.id))
        let inactiveIDs = tileLayers.keys.filter { !activeIDs.contains($0) }
        for id in inactiveIDs {
            tileLayers[id]?.container.removeFromSuperlayer()
            tileLayers[id] = nil
        }

        for tile in tiles {
            let layerSet = tileLayers[tile.id] ?? makeTileLayerSet(for: tile)
            update(layerSet: layerSet, with: tile)
        }
    }

    private func renderSpawnWarning() {
        guard let spawnWarning, spawnWarning.lane >= 0, spawnWarning.lane < PianoTilesGameState.laneCount else {
            spawnWarningOuterLayer.isHidden = true
            spawnWarningOuterLayer.path = nil
            spawnWarningInnerLayer.isHidden = true
            spawnWarningInnerLayer.path = nil
            spawnWarningCoreLayer.isHidden = true
            spawnWarningCoreLayer.path = nil
            return
        }

        let metrics = PianoTilesMetrics(size: bounds.size)
        let laneX = metrics.horizontalInset
            + CGFloat(spawnWarning.lane) * (metrics.laneWidth + metrics.laneGap)
            + metrics.laneWidth * 0.5

        let pulse = 0.5 + 0.5 * sin(spawnWarning.progress * .pi * 4)
        let flareWidth = metrics.laneWidth * (1.10 + pulse * 0.34)
        let flareY = max(14, bounds.height * 0.028)

        let outerRect = CGRect(
            x: laneX - flareWidth * 0.5,
            y: flareY - 18,
            width: flareWidth,
            height: 36
        )
        let innerRect = CGRect(
            x: laneX - flareWidth * 0.36,
            y: flareY - 9,
            width: flareWidth * 0.72,
            height: 18
        )
        let coreRect = CGRect(
            x: laneX - flareWidth * 0.22,
            y: flareY - 2.5,
            width: flareWidth * 0.44,
            height: 5
        )

        let outerPath = UIBezierPath(ovalIn: outerRect).cgPath
        let innerPath = UIBezierPath(ovalIn: innerRect).cgPath
        let corePath = UIBezierPath(
            roundedRect: coreRect,
            cornerRadius: coreRect.height * 0.5
        ).cgPath

        spawnWarningOuterLayer.isHidden = false
        spawnWarningOuterLayer.path = outerPath
        spawnWarningOuterLayer.fillColor = UIColor.systemRed.withAlphaComponent(0.18 + pulse * 0.14).cgColor
        spawnWarningOuterLayer.shadowPath = outerPath
        spawnWarningOuterLayer.shadowOpacity = 0.26 + Float(pulse) * 0.22

        spawnWarningInnerLayer.isHidden = false
        spawnWarningInnerLayer.path = innerPath
        spawnWarningInnerLayer.fillColor = UIColor.systemRed.withAlphaComponent(0.30 + pulse * 0.20).cgColor
        spawnWarningInnerLayer.shadowPath = innerPath
        spawnWarningInnerLayer.shadowOpacity = 0.34 + Float(pulse) * 0.26

        spawnWarningCoreLayer.isHidden = false
        spawnWarningCoreLayer.path = corePath
        spawnWarningCoreLayer.fillColor = UIColor(red: 1.0, green: 0.72, blue: 0.72, alpha: 0.88 + pulse * 0.10).cgColor
        spawnWarningCoreLayer.shadowPath = corePath
        spawnWarningCoreLayer.shadowOpacity = 0.36 + Float(pulse) * 0.22
    }

    private func makeTileLayerSet(for tile: PianoTile) -> PianoTileLayerSet {
        let container = CALayer()
        container.shadowColor = UIColor.black.cgColor
        container.shadowOpacity = 0.38
        container.shadowRadius = 11
        container.shadowOffset = CGSize(width: 0, height: 4)

        let glow = CAShapeLayer()
        glow.fillColor = UIColor.clear.cgColor
        glow.lineJoin = .round

        let body = CAShapeLayer()
        body.lineJoin = .round

        let blackKey = CAShapeLayer()
        blackKey.lineJoin = .round

        let highlight = CAShapeLayer()
        highlight.lineJoin = .round

        let stripe = CAShapeLayer()
        let progress = CAShapeLayer()
        let label = CATextLayer()
        label.contentsScale = max(traitCollection.displayScale, 1)
        label.alignmentMode = .center
        label.font = UIFont.systemFont(ofSize: 15, weight: .black)
        label.fontSize = 15
        label.foregroundColor = UIColor.white.cgColor

        container.addSublayer(glow)
        container.addSublayer(body)
        container.addSublayer(progress)
        container.addSublayer(blackKey)
        container.addSublayer(highlight)
        container.addSublayer(stripe)
        container.addSublayer(label)
        layer.insertSublayer(container, above: laneLayer)

        let layerSet = PianoTileLayerSet(
            container: container,
            glow: glow,
            body: body,
            blackKey: blackKey,
            highlight: highlight,
            stripe: stripe,
            progress: progress,
            label: label
        )
        tileLayers[tile.id] = layerSet
        return layerSet
    }

    private func update(layerSet: PianoTileLayerSet, with tile: PianoTile) {
        guard let rect = tile.rect(in: bounds.size) else {
            layerSet.container.isHidden = true
            return
        }

        layerSet.container.isHidden = false
        layerSet.container.frame = rect
        let localBounds = CGRect(origin: .zero, size: rect.size)
        let isActive = tile.sequenceIndex == activeSequenceIndex
        let cornerRadius = PianoTile.bodyCornerRadius
        let bodyPath = tile.bodyPath(in: localBounds).cgPath
        let accentColor: UIColor
        let labelText: String
        let baseAlpha: CGFloat = isActive ? 0.94 : 0.64

        switch tile.kind {
        case .tap:
            accentColor = UIColor(red: 0.52, green: 1.0, blue: 0.73, alpha: 1)
            labelText = "+1"
        case .hold:
            accentColor = UIColor(red: 1.0, green: 0.90, blue: 0.36, alpha: 1)
            let percent = Int(round(min(tile.holdProgress / PianoTilesGameState.holdDuration, 1.0) * 100))
            labelText = percent > 0 ? "\(percent)%" : "HOLD"
        }

        layerSet.glow.frame = localBounds
        layerSet.glow.path = bodyPath
        layerSet.glow.strokeColor = accentColor.withAlphaComponent(isActive ? 0.34 : 0.12).cgColor
        layerSet.glow.lineWidth = isActive ? 8 : 5

        layerSet.body.frame = localBounds
        layerSet.body.path = bodyPath
        layerSet.body.fillColor = UIColor(red: 0.93, green: 0.97, blue: 0.96, alpha: baseAlpha).cgColor
        layerSet.body.strokeColor = accentColor.withAlphaComponent(isActive ? 0.95 : 0.46).cgColor
        layerSet.body.lineWidth = isActive ? 3 : 2

        let blackKeyHeight = tile.kind == .hold ? localBounds.height * 0.26 : localBounds.height * 0.42
        let blackKeyWidth = localBounds.width * 0.48
        let blackKeyRect = CGRect(
            x: localBounds.midX - blackKeyWidth * 0.5,
            y: 0,
            width: blackKeyWidth,
            height: blackKeyHeight
        )
        layerSet.blackKey.frame = localBounds
        layerSet.blackKey.path = UIBezierPath(
            roundedRect: blackKeyRect,
            byRoundingCorners: [.bottomLeft, .bottomRight],
            cornerRadii: CGSize(width: 6, height: 6)
        ).cgPath
        layerSet.blackKey.fillColor = UIColor(red: 0.015, green: 0.018, blue: 0.02, alpha: isActive ? 0.92 : 0.66).cgColor

        let highlightRect = CGRect(
            x: 8,
            y: 7,
            width: localBounds.width - 16,
            height: max(4, localBounds.height * 0.05)
        )
        layerSet.highlight.frame = localBounds
        layerSet.highlight.path = UIBezierPath(roundedRect: highlightRect, cornerRadius: 3).cgPath
        layerSet.highlight.fillColor = UIColor.white.withAlphaComponent(isActive ? 0.56 : 0.28).cgColor

        let stripeRect = CGRect(x: 0, y: 0, width: 8, height: localBounds.height)
        layerSet.stripe.frame = localBounds
        layerSet.stripe.path = UIBezierPath(
            roundedRect: stripeRect,
            byRoundingCorners: [.topLeft, .bottomLeft],
            cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
        ).cgPath
        layerSet.stripe.fillColor = accentColor.withAlphaComponent(isActive ? 0.92 : 0.42).cgColor

        layerSet.progress.frame = localBounds
        if tile.kind == .hold {
            let progressHeight = localBounds.height * CGFloat(min(tile.holdProgress / PianoTilesGameState.holdDuration, 1.0))
            let progressRect = CGRect(
                x: 8,
                y: localBounds.height - progressHeight,
                width: localBounds.width - 8,
                height: progressHeight
            )
            layerSet.progress.fillColor = accentColor.withAlphaComponent(isActive ? 0.26 : 0.14).cgColor
            layerSet.progress.path = UIBezierPath(roundedRect: progressRect, cornerRadius: 6).cgPath
        } else {
            layerSet.progress.path = nil
        }

        layerSet.label.string = labelText
        layerSet.label.foregroundColor = UIColor(red: 0.02, green: 0.025, blue: 0.03, alpha: isActive ? 0.96 : 0.68).cgColor
        layerSet.label.frame = CGRect(
            x: 12,
            y: localBounds.midY - 10,
            width: localBounds.width - 24,
            height: 22
        )
    }

    private func renderBall() {
        guard let ballDisplayRect else {
            ballRingLayer.isHidden = true
            ballCenterLayer.isHidden = true
            ballRingLayer.path = nil
            ballCenterLayer.path = nil
            return
        }

        ballRingLayer.isHidden = false
        ballCenterLayer.isHidden = false
        ballRingLayer.strokeColor = (isTracking ? UIColor.white : UIColor.systemOrange).cgColor
        ballRingLayer.path = UIBezierPath(ovalIn: ballDisplayRect).cgPath
        ballCenterLayer.path = UIBezierPath(
            ovalIn: CGRect(
                x: ballDisplayRect.midX - 5,
                y: ballDisplayRect.midY - 5,
                width: 10,
                height: 10
            )
        ).cgPath
    }

    private func renderPrompt() {
        promptLabel.text = prompt
        promptLabel.isHidden = prompt == nil
        let size = CGSize(width: 190, height: 44)
        promptLabel.frame = CGRect(
            x: bounds.midX - size.width * 0.5,
            y: bounds.midY - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }
}

private struct PianoTileLayerSet {
    let container: CALayer
    let glow: CAShapeLayer
    let body: CAShapeLayer
    let blackKey: CAShapeLayer
    let highlight: CAShapeLayer
    let stripe: CAShapeLayer
    let progress: CAShapeLayer
    let label: CATextLayer
}

private struct PianoTilesMusicNote {
    let prefersFastTile: Bool
    let speedMultiplier: CGFloat
}

private struct PianoTilesMusicChart {
    private let notes: [PianoTilesMusicNote]

    func note(at index: Int) -> PianoTilesMusicNote {
        guard !notes.isEmpty else {
            return PianoTilesMusicNote(
                prefersFastTile: false,
                speedMultiplier: 1.0
            )
        }
        return notes[min(max(index, 0), notes.count - 1)]
    }

    static func make(totalCount: Int) -> PianoTilesMusicChart {
        let speedBeats = [
            [2, 5],
            [1, 4],
            [3, 6]
        ].randomElement() ?? [2, 5]

        var notes: [PianoTilesMusicNote] = []
        notes.reserveCapacity(totalCount)

        for index in 0..<totalCount {
            let beat = index % 8
            let prefersFastTile = speedBeats.contains(beat) && beat != 7
            let speedOptions: [CGFloat] = [1.18, 1.22, 1.26]
            let speedMultiplier = speedOptions.randomElement() ?? 1.22
            notes.append(
                PianoTilesMusicNote(
                    prefersFastTile: prefersFastTile,
                    speedMultiplier: speedMultiplier
                )
            )
        }

        return PianoTilesMusicChart(notes: notes)
    }
}

private struct PianoTilesGameState {
    static let laneCount = 4
    static let totalTileCount = 40
    static let holdDuration: TimeInterval = 2.0
    static let holdGrace: TimeInterval = 0.25
    private static let requiredBallOverlapRatio: CGFloat = 0.20
    private static let overlapSamplingDensity: CGFloat = 6
    private static let minimumOverlapGrid = 18
    private static let maximumOverlapGrid = 36
    private static let maxQueuedTapTiles = 3
    private static let warningLeadDuration: TimeInterval = 0.75
    private static let spawnGapScale: Double = 1.5
    private static let tileSpeedScale: CGFloat = 1.1

    var tiles: [PianoTile] = []
    private(set) var activeSequenceIndex = 0
    private(set) var score = 0

    private var sequence: [PianoTileSpec] = []
    private var nextSequenceIndex = 0
    private var nextSpawnElapsed: TimeInterval = 0
    private var blockedSpawnNeedsReschedule = false

    mutating func reset() {
        tiles = []
        activeSequenceIndex = 0
        score = 0
        sequence = Self.makeSequence()
        nextSequenceIndex = 0
        nextSpawnElapsed = Self.warningLeadDuration
        blockedSpawnNeedsReschedule = false
    }

    mutating func step(
        ballDisplayRect: CGRect,
        in size: CGSize,
        elapsed: TimeInterval,
        delta: TimeInterval
    ) -> PianoTilesEvent? {
        guard size.width > 0, size.height > 0, !sequence.isEmpty else {
            return nil
        }

        for index in tiles.indices {
            tiles[index].advance(delta: delta)
        }

        spawnTilesIfNeeded(in: size, elapsed: elapsed)

        guard activeSequenceIndex < Self.totalTileCount else {
            return .won(nil)
        }

        guard let activeTileIndex = tiles.firstIndex(where: { $0.sequenceIndex == activeSequenceIndex }) else {
            removeStaleTiles(in: size)
            if nextSequenceIndex > activeSequenceIndex {
                return .missed
            }
            return nil
        }

        let overlaps = overlaps(tile: tiles[activeTileIndex], ballDisplayRect: ballDisplayRect, size: size)
        switch tiles[activeTileIndex].kind {
        case .tap:
            if overlaps {
                let trigger = soundTrigger(for: tiles[activeTileIndex])
                completeActiveTile()
                return activeSequenceIndex >= Self.totalTileCount ? .won(trigger) : .completed(trigger)
            }
        case .hold:
            if overlaps {
                let shouldPlayStartSound = !tiles[activeTileIndex].holdStartSoundPlayed
                if shouldPlayStartSound {
                    tiles[activeTileIndex].holdStartSoundPlayed = true
                }
                tiles[activeTileIndex].holdProgress += delta
                tiles[activeTileIndex].holdGap = 0
                if tiles[activeTileIndex].holdProgress >= Self.holdDuration {
                    let trigger = soundTrigger(for: tiles[activeTileIndex])
                    completeActiveTile()
                    return activeSequenceIndex >= Self.totalTileCount ? .won(trigger) : .completed(trigger)
                }
                if shouldPlayStartSound {
                    return .holdStarted(soundTrigger(for: tiles[activeTileIndex]))
                }
            } else if tiles[activeTileIndex].holdProgress > 0 {
                tiles[activeTileIndex].holdGap += delta
                if tiles[activeTileIndex].holdGap > Self.holdGrace {
                    tiles[activeTileIndex].holdProgress = 0
                    tiles[activeTileIndex].holdGap = 0
                }
            }
        }

        if isMissed(tiles[activeTileIndex], in: size) {
            return .missed
        }

        removeStaleTiles(in: size)
        return nil
    }

    mutating func stepWithoutBall(
        in size: CGSize,
        elapsed: TimeInterval,
        delta: TimeInterval
    ) -> PianoTilesEvent? {
        guard size.width > 0, size.height > 0, !sequence.isEmpty else {
            return nil
        }

        for index in tiles.indices {
            tiles[index].advance(delta: delta)
        }
        spawnTilesIfNeeded(in: size, elapsed: elapsed)

        guard activeSequenceIndex < Self.totalTileCount else {
            return .won(nil)
        }

        guard let activeTile = tiles.first(where: { $0.sequenceIndex == activeSequenceIndex }) else {
            removeStaleTiles(in: size)
            return nextSequenceIndex > activeSequenceIndex ? .missed : nil
        }

        if isMissed(activeTile, in: size) {
            return .missed
        }

        removeStaleTiles(in: size)
        return nil
    }

    static func missLineY(in size: CGSize) -> CGFloat {
        max(size.height - 44, size.height * 0.82)
    }

    private mutating func spawnTilesIfNeeded(in size: CGSize, elapsed: TimeInterval) {
        guard nextSequenceIndex < Self.totalTileCount else {
            return
        }

        let unresolvedTapCount = tiles.filter { $0.sequenceIndex >= activeSequenceIndex && $0.kind == .tap }.count
        let canSpawn = !hasUnresolvedHoldTile && unresolvedTapCount < Self.maxQueuedTapTiles

        guard canSpawn else {
            if elapsed >= nextSpawnElapsed {
                blockedSpawnNeedsReschedule = true
            }
            return
        }

        if blockedSpawnNeedsReschedule {
            nextSpawnElapsed = elapsed + Self.warningLeadDuration
            blockedSpawnNeedsReschedule = false
            return
        }

        guard elapsed >= nextSpawnElapsed else {
            return
        }

        spawnTile(in: size)
        let progress = Double(nextSequenceIndex) / Double(Self.totalTileCount)
        let baseGap = Double.random(in: 1.08...1.82)
        let lateGameTrim = min(progress * 0.18, 0.18)
        let spawnGap = max(1.0, baseGap - lateGameTrim) * Self.spawnGapScale
        nextSpawnElapsed = elapsed + spawnGap
    }

    private mutating func spawnTile(in size: CGSize) {
        let spec = sequence[nextSequenceIndex]
        let metrics = PianoTilesMetrics(size: size)
        let progress = CGFloat(nextSequenceIndex) / CGFloat(max(Self.totalTileCount - 1, 1))
        let tapHeight = min(max(size.height * 0.18, 82), 124)
        let baseSpeed = CGFloat(82 + progress * 48)
        let tileHeight = tapHeight
        let speed = baseSpeed * spec.speedMultiplier * Self.tileSpeedScale
        tiles.append(
            PianoTile(
                sequenceIndex: nextSequenceIndex,
                lane: spec.lane,
                kind: spec.kind,
                centerY: -tileHeight * 0.65,
                width: metrics.laneWidth * 0.86,
                height: tileHeight,
                speed: speed
            )
        )
        nextSequenceIndex += 1
    }

    func spawnWarning(elapsed: TimeInterval) -> PianoTileSpawnWarning? {
        guard nextSequenceIndex < Self.totalTileCount else {
            return nil
        }

        guard !blockedSpawnNeedsReschedule, !hasUnresolvedHoldTile else {
            return nil
        }

        let unresolvedTapCount = tiles.filter { $0.sequenceIndex >= activeSequenceIndex && $0.kind == .tap }.count
        guard unresolvedTapCount < Self.maxQueuedTapTiles else {
            return nil
        }

        let warningStart = nextSpawnElapsed - Self.warningLeadDuration
        guard elapsed >= warningStart, elapsed < nextSpawnElapsed else {
            return nil
        }

        let progress = CGFloat((elapsed - warningStart) / Self.warningLeadDuration)
        return PianoTileSpawnWarning(
            lane: sequence[nextSequenceIndex].lane,
            progress: min(max(progress, 0), 1)
        )
    }

    private mutating func completeActiveTile() {
        score += 1
        activeSequenceIndex += 1
        tiles.removeAll { $0.sequenceIndex < activeSequenceIndex }
    }

    private func soundTrigger(for tile: PianoTile) -> PianoTileSoundTrigger {
        PianoTileSoundTrigger(
            lane: tile.lane,
            kind: tile.kind,
            sequenceIndex: tile.sequenceIndex
        )
    }

    private mutating func removeStaleTiles(in size: CGSize) {
        tiles.removeAll { tile in
            guard let rect = tile.rect(in: size) else {
                return true
            }
            return rect.minY > size.height + 80 || tile.sequenceIndex < activeSequenceIndex
        }
    }

    private func isMissed(_ tile: PianoTile, in size: CGSize) -> Bool {
        guard let rect = tile.rect(in: size) else {
            return false
        }
        return rect.minY >= Self.missLineY(in: size)
    }

    private func overlaps(tile: PianoTile, ballDisplayRect: CGRect, size: CGSize) -> Bool {
        guard let tileRect = tile.rect(in: size) else {
            return false
        }

        let currentContact = ballContact(from: ballDisplayRect)
        let tilePath = tile.bodyPath(in: tileRect)
        let overlapRatio = overlapRatio(
            circleCenter: currentContact.center,
            radius: currentContact.radius,
            tilePath: tilePath
        )
        return overlapRatio >= Self.requiredBallOverlapRatio
    }

    private func ballContact(from rect: CGRect) -> (center: CGPoint, radius: CGFloat) {
        let diameter = min(rect.width, rect.height)
        return (
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: diameter * 0.5
        )
    }

    private func overlapRatio(
        circleCenter: CGPoint,
        radius: CGFloat,
        tilePath: UIBezierPath
    ) -> CGFloat {
        guard radius > 0 else {
            return 0
        }

        let circleBounds = CGRect(
            x: circleCenter.x - radius,
            y: circleCenter.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        guard tilePath.bounds.intersects(circleBounds) else {
            return 0
        }

        let samplesPerAxis = max(
            Self.minimumOverlapGrid,
            min(Self.maximumOverlapGrid, Int(ceil(radius / Self.overlapSamplingDensity)))
        )
        guard samplesPerAxis > 0 else {
            return 0
        }

        let stepX = circleBounds.width / CGFloat(samplesPerAxis)
        let stepY = circleBounds.height / CGFloat(samplesPerAxis)
        var circleSamples = 0
        var overlapSamples = 0

        for row in 0..<samplesPerAxis {
            let y = circleBounds.minY + (CGFloat(row) + 0.5) * stepY
            for column in 0..<samplesPerAxis {
                let x = circleBounds.minX + (CGFloat(column) + 0.5) * stepX
                let point = CGPoint(x: x, y: y)
                guard hypot(point.x - circleCenter.x, point.y - circleCenter.y) <= radius else {
                    continue
                }

                circleSamples += 1
                if tilePath.contains(point) {
                    overlapSamples += 1
                }
            }
        }

        guard circleSamples > 0 else {
            return 0
        }
        return CGFloat(overlapSamples) / CGFloat(circleSamples)
    }

    private var hasUnresolvedHoldTile: Bool {
        false
    }

    private static func makeSequence() -> [PianoTileSpec] {
        var specs: [PianoTileSpec] = []
        var lastLane: Int?
        let musicChart = PianoTilesMusicChart.make(totalCount: Self.totalTileCount)
        var previousFastTile = false

        for index in 0..<Self.totalTileCount {
            var lane = Int.random(in: 0..<Self.laneCount)
            if let lastLane, lane == lastLane {
                lane = (lane + Int.random(in: 1..<Self.laneCount)) % Self.laneCount
            }

            lastLane = lane

            let note = musicChart.note(at: index)
            let speedMultiplier: CGFloat
            if note.prefersFastTile, !previousFastTile {
                speedMultiplier = note.speedMultiplier
                previousFastTile = true
            } else {
                speedMultiplier = 1.0
                previousFastTile = false
            }
            specs.append(
                PianoTileSpec(
                    lane: lane,
                    kind: .tap,
                    speedMultiplier: speedMultiplier
                )
            )
        }

        return specs
    }
}

private struct PianoTileSpec {
    let lane: Int
    let kind: PianoTileKind
    let speedMultiplier: CGFloat
}

private struct PianoTile: Identifiable {
    static let bodyCornerRadius: CGFloat = 8

    let id = UUID()
    let sequenceIndex: Int
    let lane: Int
    let kind: PianoTileKind
    var centerY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let speed: CGFloat
    var holdProgress: TimeInterval = 0
    var holdGap: TimeInterval = 0
    var holdStartSoundPlayed = false

    mutating func advance(delta: TimeInterval) {
        centerY += speed * CGFloat(delta)
    }

    func bodyPath(in rect: CGRect) -> UIBezierPath {
        UIBezierPath(roundedRect: rect, cornerRadius: Self.bodyCornerRadius)
    }

    func rect(in size: CGSize) -> CGRect? {
        guard lane >= 0, lane < PianoTilesGameState.laneCount else {
            return nil
        }

        let metrics = PianoTilesMetrics(size: size)
        let laneX = metrics.horizontalInset
            + CGFloat(lane) * (metrics.laneWidth + metrics.laneGap)
            + metrics.laneWidth * 0.5
        return CGRect(
            x: laneX - width * 0.5,
            y: centerY - height * 0.5,
            width: width,
            height: height
        )
    }
}

private struct PianoTilesMetrics {
    let horizontalInset: CGFloat
    let laneGap: CGFloat
    let laneWidth: CGFloat

    init(size: CGSize) {
        horizontalInset = max(18, size.width * 0.055)
        laneGap = max(7, size.width * 0.012)
        laneWidth = max(
            34,
            (size.width - horizontalInset * 2 - laneGap * CGFloat(PianoTilesGameState.laneCount - 1))
                / CGFloat(PianoTilesGameState.laneCount)
        )
    }
}

private struct PianoTilesHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))

            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        }
        .frame(width: 78, height: 54)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.68), lineWidth: 1.4)
        )
    }
}

private struct PianoTilesLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting Piano Tiles...")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PianoTilesErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Camera Unavailable")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button(action: onDismiss) {
                        Text("CLOSE")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if permissionDenied {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                                return
                            }
                            UIApplication.shared.open(url)
                        } label: {
                            Text("OPEN SETTINGS")
                                .font(.system(size: 15, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 18)
                                .frame(height: 42)
                                .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)
        }
    }
}

private struct PianoTilesFinishedOverlay: View {
    let title: String
    let subtitle: String
    let scoreText: String
    let primaryTitle: String
    let onPrimary: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))

                Text(scoreText)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)
                    .padding(.top, 4)

                HStack(spacing: 10) {
                    Button(action: onDone) {
                        Text("DONE")
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button(action: onPrimary) {
                        Text(primaryTitle)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 18)
                            .frame(height: 42)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 24)
        }
    }
}
