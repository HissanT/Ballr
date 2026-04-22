import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct PrecisionTargetCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBallSpec: PrecisionTargetBallSpec?

    var body: some View {
        Group {
            if let selectedBallSpec {
                PrecisionTargetLiveCameraView(ballSpec: selectedBallSpec)
            } else {
                PrecisionTargetSetupView(
                    onSelect: { selectedBallSpec = $0 },
                    onCancel: { dismiss() }
                )
            }
        }
        .ballrCameraPresentationChrome()
    }
}

struct MultiplayerPrecisionTargetCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var setupStep: MultiplayerPrecisionSetupStep = .playerOne
    @State private var playerOneName = ""
    @State private var playerTwoName = ""
    @State private var selectedBallSpec: PrecisionTargetBallSpec?

    var body: some View {
        Group {
            switch setupStep {
            case .playerOne:
                MultiplayerPrecisionNameEntryView(
                    title: "Player One",
                    subtitle: "Enter the first player's name before the round starts.",
                    placeholder: "Player 1",
                    buttonTitle: "NEXT",
                    name: $playerOneName,
                    onBack: nil,
                    onCancel: { dismiss() },
                    onContinue: { setupStep = .playerTwo }
                )
            case .playerTwo:
                MultiplayerPrecisionNameEntryView(
                    title: "Player Two",
                    subtitle: "Enter the second player's name for the alternating target challenge.",
                    placeholder: "Player 2",
                    buttonTitle: "BALL SIZE",
                    name: $playerTwoName,
                    onBack: { setupStep = .playerOne },
                    onCancel: { dismiss() },
                    onContinue: { setupStep = .ballSize }
                )
            case .ballSize:
                MultiplayerPrecisionTargetSetupView(
                    onSelect: {
                        selectedBallSpec = $0
                        setupStep = .live
                    },
                    onBack: { setupStep = .playerTwo },
                    onCancel: { dismiss() }
                )
            case .live:
                if let activeBallSpec = selectedBallSpec {
                    MultiplayerPrecisionTargetLiveCameraView(
                        ballSpec: activeBallSpec,
                        playerOneName: sanitizedName(playerOneName, fallback: "Player 1"),
                        playerTwoName: sanitizedName(playerTwoName, fallback: "Player 2"),
                        onReplay: {
                            selectedBallSpec = nil
                            setupStep = .playerOne
                        },
                        onExit: { dismiss() }
                    )
                }
            }
        }
        .ballrCameraPresentationChrome()
    }

    private func sanitizedName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private enum MultiplayerPrecisionSetupStep {
    case playerOne
    case playerTwo
    case ballSize
    case live
}

private struct PrecisionTargetSetupView: View {
    let onSelect: (PrecisionTargetBallSpec) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            PrecisionTargetSetupBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    PrecisionTargetSetupCloseButton(action: onCancel)

                    Spacer()
                }

                Spacer(minLength: 10)

                Text("Precision Targets")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Choose the ball size before calibration.")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                PrecisionTargetBallSelectionList(onSelect: onSelect)
                .padding(.top, 10)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }
}

private struct MultiplayerPrecisionTargetSetupView: View {
    let onSelect: (PrecisionTargetBallSpec) -> Void
    let onBack: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            PrecisionTargetSetupBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    PrecisionTargetSetupIconButton(systemName: "chevron.left", action: onBack)
                    PrecisionTargetSetupCloseButton(action: onCancel)
                    Spacer()
                }

                Spacer(minLength: 10)

                Text("Multiplayer Targets")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Text("Choose the ball size, then both players share the same target and calibration.")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))

                PrecisionTargetBallSelectionList(onSelect: onSelect)
                    .padding(.top, 10)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }
}

private struct MultiplayerPrecisionNameEntryView: View {
    let title: String
    let subtitle: String
    let placeholder: String
    let buttonTitle: String
    @Binding var name: String
    let onBack: (() -> Void)?
    let onCancel: () -> Void
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            PrecisionTargetSetupBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    if let onBack {
                        PrecisionTargetSetupIconButton(systemName: "chevron.left", action: onBack)
                    }
                    PrecisionTargetSetupCloseButton(action: onCancel)
                    Spacer()
                }

                Spacer(minLength: 18)

                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("PLAYER NAME")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color.yellow.opacity(0.92))

                    TextField(placeholder, text: $name)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 72)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.8), lineWidth: 2)
                        )

                    Text("Leave it blank to use \(placeholder).")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                }

                Button(action: onContinue) {
                    Text(buttonTitle)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.05))
                        .frame(maxWidth: .infinity)
                        .frame(height: 74)
                        .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(red: 0.78, green: 0.64, blue: 0.00))
                                .frame(height: 8)
                                .offset(y: 5)
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 10)

                Spacer(minLength: 30)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
    }
}

private struct PrecisionTargetBallSelectionList: View {
    let onSelect: (PrecisionTargetBallSpec) -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(PrecisionTargetBallSpec.presets) { spec in
                Button {
                    onSelect(spec)
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.yellow)
                            Circle()
                                .stroke(Color.orange, lineWidth: 4)
                            Text(spec.sizeName)
                                .font(.system(size: 20, weight: .black, design: .rounded))
                                .foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.08))
                        }
                        .frame(width: 58, height: 58)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(spec.label)
                                .font(.system(size: 22, weight: .black, design: .rounded))
                                .foregroundStyle(.white)

                            Text("\(String(format: "%.1f", spec.diameterCM)) cm diameter")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                        }

                        Spacer()

                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 18)
                    .frame(height: 86)
                    .background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.8), lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PrecisionTargetSetupCloseButton: View {
    let action: () -> Void

    var body: some View {
        PrecisionTargetSetupIconButton(systemName: "xmark", action: action)
    }
}

private struct PrecisionTargetSetupIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.65), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct PrecisionTargetSetupBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.01, green: 0.14, blue: 0.04)

            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { index in
                    Rectangle()
                        .fill(index.isMultiple(of: 2) ? Color.white.opacity(0.018) : Color.black.opacity(0.045))
                }
            }

            GeometryReader { geometry in
                Path { path in
                    let width = geometry.size.width
                    let height = geometry.size.height
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
                }
                .stroke(Color.white.opacity(0.045), lineWidth: 3)
            }
        }
    }
}

private struct PrecisionTargetLiveCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = PrecisionTargetCoordinator()
    @State private var showsQuitConfirmation = false

    let ballSpec: PrecisionTargetBallSpec

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                PrecisionTargetRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomStatus
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if cameraController.isStarting {
                    PrecisionTargetLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    PrecisionTargetErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        coordinator.handleTap(at: value.location, cameraController: cameraController)
                    }
            )
            .ballrCameraPresentationChrome()
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(ballSpec: ballSpec, viewSize: geometry.size)
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
                coordinator.prepare(viewSize: newSize)
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
                PrecisionTargetHudChip(title: "SCORE", value: "\(coordinator.score)", tint: .yellow)
                PrecisionTargetHudChip(title: "BALL", value: coordinator.ballLabel, tint: .orange)
                PrecisionTargetHudChip(title: "DEPTH", value: coordinator.depthText, tint: .white)
            }
        }
    }

    private var bottomStatus: some View {
        VStack(spacing: 8) {
            Text(coordinator.phaseTitle)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color.yellow)

            Text(coordinator.statusText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 78)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MultiplayerPrecisionTargetLiveCameraView: View {
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = PrecisionTargetCoordinator()
    @State private var showsQuitConfirmation = false
    @State private var playerScores = [0, 0]
    @State private var playerShots = [0, 0]
    @State private var currentPlayerIndex = 0
    @State private var pendingShotResolution: MultiplayerPendingShotResolution?
    @State private var finalResult: MultiplayerPrecisionResult?

    let ballSpec: PrecisionTargetBallSpec
    let playerOneName: String
    let playerTwoName: String
    let onReplay: () -> Void
    let onExit: () -> Void

    private let shotsPerPlayer = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.10)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                PrecisionTargetRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    bottomStatus
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if cameraController.isStarting {
                    PrecisionTargetLoadingOverlay()
                }

                if let pendingShotResolution {
                    MultiplayerPrecisionTurnOverlay(
                        state: pendingShotResolution.overlayState,
                        onContinue: confirmPendingShot,
                        onReplayShot: replayPendingShot
                    )
                }

                if let finalResult {
                    MultiplayerPrecisionResultsOverlay(
                        result: finalResult,
                        onReplay: onReplay,
                        onExit: onExit
                    )
                }

                if let errorMessage = cameraController.errorMessage {
                    PrecisionTargetErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: onExit
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        coordinator.handleTap(at: value.location, cameraController: cameraController)
                    }
            )
            .ballrCameraPresentationChrome()
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(ballSpec: ballSpec, viewSize: geometry.size)
                coordinator.onShotLocked = { impact in
                    DispatchQueue.main.async {
                        handleLockedShot(impact)
                    }
                }
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
                coordinator.onShotLocked = nil
                cameraController.onTrackingFrame = nil
                cameraController.publishesTrackingFramesToSwiftUI = true
                cameraController.stop()
                BallrOrientationController.restoreDefaultOrientation()
            }
            .onChange(of: geometry.size) { _, newSize in
                coordinator.prepare(viewSize: newSize)
            }
            .alert("Are you sure you want to quit the drill?", isPresented: $showsQuitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive) {
                    onExit()
                }
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            MultiplayerPrecisionScoreCard(
                name: playerOneName,
                score: playerScores[0],
                shotsTaken: playerShots[0],
                shotsPerPlayer: shotsPerPlayer,
                isActive: currentPlayerIndex == 0,
                isLeading: true
            )

            Spacer(minLength: 10)

            VStack(spacing: 8) {
                Button {
                    showsQuitConfirmation = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.62), in: Circle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 8) {
                    PrecisionTargetHudChip(title: "TURN", value: activePlayerName, tint: .yellow, width: 126)
                    PrecisionTargetHudChip(title: "BALL", value: coordinator.ballLabel, tint: .orange)
                    PrecisionTargetHudChip(title: "DEPTH", value: coordinator.depthText, tint: .white)
                }
            }

            Spacer(minLength: 10)

            MultiplayerPrecisionScoreCard(
                name: playerTwoName,
                score: playerScores[1],
                shotsTaken: playerShots[1],
                shotsPerPlayer: shotsPerPlayer,
                isActive: currentPlayerIndex == 1,
                isLeading: false
            )
        }
    }

    private var bottomStatus: some View {
        VStack(spacing: 8) {
            Text(coordinator.phaseTitle)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Color.yellow)

            Text(coordinator.statusText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 86)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }

    private var activePlayerName: String {
        currentPlayerIndex == 0 ? playerOneName : playerTwoName
    }

    private func handleLockedShot(_ impact: PrecisionImpact) {
        guard pendingShotResolution == nil, finalResult == nil else {
            return
        }

        let completedPlayerIndex = currentPlayerIndex
        playerScores[completedPlayerIndex] += impact.score
        playerShots[completedPlayerIndex] += 1

        let finishedShots = playerShots[0] + playerShots[1]
        let completedPlayerName = completedPlayerIndex == 0 ? playerOneName : playerTwoName

        let nextPlayerIndex = 1 - completedPlayerIndex
        let isRoundEnding = finishedShots >= shotsPerPlayer * 2
        coordinator.pauseLive(
            phaseTitle: isRoundEnding ? "ROUND COMPLETE" : "TURN COMPLETE",
            statusText: impact.score > 0
                ? "\(completedPlayerName) scored +\(impact.score)."
                : "\(completedPlayerName) missed."
        )
        pendingShotResolution = MultiplayerPendingShotResolution(
            playerIndex: completedPlayerIndex,
            scoredPoints: impact.score,
            nextPlayerIndex: nextPlayerIndex,
            isRoundEnding: isRoundEnding,
            overlayState: MultiplayerTurnOverlayState(
                completedPlayerName: completedPlayerName,
                scoredPoints: impact.score,
                nextPlayerName: nextPlayerIndex == 0 ? playerOneName : playerTwoName,
                isRoundEnding: isRoundEnding
            )
        )
    }

    private func confirmPendingShot() {
        guard let pendingShotResolution else {
            return
        }

        self.pendingShotResolution = nil
        if pendingShotResolution.isRoundEnding {
            BallrDrillSoundPlayer.playWinner()
            finalResult = MultiplayerPrecisionResult(
                playerOneName: playerOneName,
                playerTwoName: playerTwoName,
                playerOneScore: playerScores[0],
                playerTwoScore: playerScores[1]
            )
            return
        }

        currentPlayerIndex = pendingShotResolution.nextPlayerIndex
        coordinator.resumeLiveAfterTurn(
            instruction: "\(activePlayerName), reset the ball and throw toward the wall"
        )
    }

    private func replayPendingShot() {
        guard let pendingShotResolution else {
            return
        }

        let playerIndex = pendingShotResolution.playerIndex
        playerScores[playerIndex] -= pendingShotResolution.scoredPoints
        playerShots[playerIndex] = max(playerShots[playerIndex] - 1, 0)
        self.pendingShotResolution = nil
        coordinator.resumeLiveAfterTurn(
            instruction: "\(activePlayerName), replay the shot toward the wall"
        )
    }
}

private struct MultiplayerPendingShotResolution {
    let playerIndex: Int
    let scoredPoints: Int
    let nextPlayerIndex: Int
    let isRoundEnding: Bool
    let overlayState: MultiplayerTurnOverlayState
}

private struct MultiplayerTurnOverlayState {
    let completedPlayerName: String
    let scoredPoints: Int
    let nextPlayerName: String
    let isRoundEnding: Bool
}

private struct MultiplayerPrecisionResult {
    let playerOneName: String
    let playerTwoName: String
    let playerOneScore: Int
    let playerTwoScore: Int

    var headline: String {
        if playerOneScore == playerTwoScore {
            return "It's a Tie"
        }
        return winnerName + " Wins"
    }

    var summary: String {
        if playerOneScore == playerTwoScore {
            return "Both players finished with \(playerOneScore) points."
        }
        return "\(winnerName) finishes ahead \(winningScore)-\(losingScore)."
    }

    private var winnerName: String {
        playerOneScore > playerTwoScore ? playerOneName : playerTwoName
    }

    private var winningScore: Int {
        max(playerOneScore, playerTwoScore)
    }

    private var losingScore: Int {
        min(playerOneScore, playerTwoScore)
    }
}

private struct PrecisionTargetBallSpec: Identifiable, Equatable {
    let id: String
    let label: String
    let sizeName: String
    let diameterCM: CGFloat

    var diameterM: CGFloat {
        diameterCM / 100.0
    }

    static let presets = [
        PrecisionTargetBallSpec(id: "3", label: "Size 3", sizeName: "3", diameterCM: 19.1),
        PrecisionTargetBallSpec(id: "4", label: "Size 4", sizeName: "4", diameterCM: 20.3),
        PrecisionTargetBallSpec(id: "5", label: "Size 5", sizeName: "5", diameterCM: 22.0)
    ]
}

private enum PrecisionTargetPhase {
    case selectCenter
    case reference
    case calibration
    case live
}

private enum PrecisionThrowPhase {
    case idle
    case outboundCandidate
    case outboundConfirmed
    case cooldown
}

private struct PrecisionDepthEstimate {
    let distanceM: CGFloat
    let pixelDiameter: CGFloat
}

private struct PrecisionDepthSample {
    let timestamp: Date
    let centerPixels: CGPoint
    let pixelDiameter: CGFloat
    let smoothedDiameter: CGFloat
    let rawDistanceM: CGFloat
    let estimatedDistanceM: CGFloat
}

private struct PrecisionWallCalibration {
    let wallDistanceM: CGFloat
    let impactPixelDiameter: CGFloat
    let confidence: CGFloat
}

private struct PrecisionImpact {
    let centerPixels: CGPoint
    let displayPoint: CGPoint?
    let radialDistanceCM: CGFloat
    let dxCM: CGFloat
    let dyCM: CGFloat
    let score: Int
    let timestamp: Date
}

private struct PrecisionTrackerOverlay {
    let displayRect: CGRect?
    let rawDisplayRect: CGRect?
    let center: CGPoint?
    let confidence: Double?
    let isTracking: Bool
    let misses: Int
}

private struct PrecisionThrowState {
    var phase: PrecisionThrowPhase = .idle
    var nearStartDepthM: CGFloat?
    var outboundFrames = 0
    var missingFrames = 0
    var furthestSample: PrecisionDepthSample?
    var eligibleSamples: [PrecisionDepthSample] = []
}

private final class PrecisionTargetCoordinator: ObservableObject {
    @Published private(set) var score = 0
    @Published private(set) var ballLabel = "--"
    @Published private(set) var depthText = "--"
    @Published private(set) var phaseTitle = "SELECT TARGET"
    @Published private(set) var statusText = "Tap the center of the target on the wall"

    var onShotLocked: ((PrecisionImpact) -> Void)?

    private let defaultFocalLengthPX: CGFloat = 2400.0
    private let focalReferenceWidthPX: CGFloat = 1920.0
    private let referenceHoldSeconds: TimeInterval = 5.0
    private let wallHoldSeconds: TimeInterval = 10.0
    private let holdMaxMissingFrames = 15
    private let holdMaxFrameDelta: TimeInterval = 0.1
    private let smoothingAlpha: CGFloat = 0.35
    private let minValidCalibrationSamples = 12
    private let minCalibrationDiameterPX: CGFloat = 16.0
    private let minWallDistanceM: CGFloat = 1.5
    private let maxWallDistanceM: CGFloat = 12.0
    private let outboundMinimumFrames = 4
    private let impactReversalM: CGFloat = 0.04
    private let resetReturnDepthM: CGFloat = 0.75
    private let cooldownMissingFrames = 6
    private let impactDisappearFrames = 4
    private let impactMarkerHoldSeconds: TimeInterval = 5.0
    private let maxLiveCenterJumpPX: CGFloat = 220
    private let maxLiveCenterJumpDiameters: CGFloat = 4.0
    private let maxLiveDiameterRatio: CGFloat = 2.35

    private var phase: PrecisionTargetPhase = .selectCenter
    private var ballSpec: PrecisionTargetBallSpec = PrecisionTargetBallSpec.presets[2]
    private var viewSize: CGSize = .zero
    private var bullseyeTrackerPoint: CGPoint?
    private var bullseyeDisplayPoint: CGPoint?
    private var wallCalibration: PrecisionWallCalibration?
    private var currentDepth: PrecisionDepthEstimate?
    private var zeroReferenceDepthM: CGFloat?
    private var referenceStartedAt: Date?
    private var referenceElapsed: TimeInterval = 0
    private var referenceMissingFrames = 0
    private var referenceSamples: [CGFloat] = []
    private var calibrationStartedAt: Date?
    private var calibrationElapsed: TimeInterval = 0
    private var calibrationMissingFrames = 0
    private var calibrationDepthSamples: [CGFloat] = []
    private var calibrationDiameterSamples: [CGFloat] = []
    private var diameterWindow: [CGFloat] = []
    private var smoothedDiameter: CGFloat?
    private var isLivePaused = false
    private var throwState = PrecisionThrowState()
    private var lastImpact: PrecisionImpact?
    private var lastScore = 0
    private var perfectHitChainActive = false
    private var trackerOverlay = PrecisionTrackerOverlay(
        displayRect: nil,
        rawDisplayRect: nil,
        center: nil,
        confidence: nil,
        isTracking: false,
        misses: 0
    )
    private weak var renderView: PrecisionTargetRenderView?

    func attach(renderView: PrecisionTargetRenderView) {
        self.renderView = renderView
        publishRender()
    }

    func reset(ballSpec: PrecisionTargetBallSpec, viewSize: CGSize) {
        self.ballSpec = ballSpec
        self.viewSize = viewSize
        phase = .selectCenter
        score = 0
        ballLabel = ballSpec.label
        depthText = "--"
        phaseTitle = "SELECT TARGET"
        statusText = "Tap the center of the target on the wall"
        bullseyeTrackerPoint = nil
        bullseyeDisplayPoint = nil
        wallCalibration = nil
        currentDepth = nil
        zeroReferenceDepthM = nil
        referenceStartedAt = nil
        referenceElapsed = 0
        referenceMissingFrames = 0
        referenceSamples.removeAll()
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
        diameterWindow.removeAll()
        smoothedDiameter = nil
        isLivePaused = false
        throwState = PrecisionThrowState()
        lastImpact = nil
        lastScore = 0
        perfectHitChainActive = false
        trackerOverlay = PrecisionTrackerOverlay(
            displayRect: nil,
            rawDisplayRect: nil,
            center: nil,
            confidence: nil,
            isTracking: false,
            misses: 0
        )
        publishRender()
    }

    func prepare(viewSize: CGSize) {
        self.viewSize = viewSize
        publishRender()
    }

    func pauseLive(phaseTitle: String, statusText: String) {
        guard phase == .live else {
            return
        }
        isLivePaused = true
        self.phaseTitle = phaseTitle
        self.statusText = statusText
        publishRender()
    }

    func resumeLiveAfterTurn(instruction: String) {
        guard phase == .live else {
            return
        }
        isLivePaused = false
        phaseTitle = "LIVE"
        statusText = instruction
        throwState.phase = .cooldown
        throwState.missingFrames = 0
        lastImpact = nil
        lastScore = 0
        publishRender()
    }

    func handleTap(at displayPoint: CGPoint, cameraController: BallTrackerCameraController) {
        guard phase == .selectCenter else {
            return
        }
        guard let trackerPoint = cameraController.trackerPoint(forDisplayPoint: displayPoint) else {
            statusText = "Tap inside the camera view"
            return
        }

        bullseyeTrackerPoint = trackerPoint
        bullseyeDisplayPoint = displayPoint
        phase = .reference
        phaseTitle = "PASSING SPOT"
        statusText = "Hold the ball at your passing spot for 5 seconds"
        referenceStartedAt = nil
        referenceElapsed = 0
        referenceMissingFrames = 0
        referenceSamples.removeAll()
        publishRender()
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        updateTrackerOverlay(from: frame.overlayState, cameraController: cameraController)
        updateBullseyeDisplayPoint(cameraController: cameraController)
        let focalLength = effectiveFocalLength(frameWidth: frame.framePixelSize.width)
        let sample = buildDepthSample(frame: frame, focalLength: focalLength)
        currentDepth = sample.map {
            PrecisionDepthEstimate(distanceM: $0.estimatedDistanceM, pixelDiameter: $0.smoothedDiameter)
        }
        updateHUDDepth()

        switch phase {
        case .selectCenter:
            phaseTitle = "SELECT TARGET"
            statusText = "Tap the center of the target on the wall"
        case .reference:
            stepReference(sample: sample, timestamp: frame.timestamp)
        case .calibration:
            stepCalibration(sample: sample, timestamp: frame.timestamp)
        case .live:
            stepLive(sample: sample, frame: frame, cameraController: cameraController)
        }

        publishRender()
    }

    private func buildDepthSample(frame: BallTrackerFrame, focalLength: CGFloat) -> PrecisionDepthSample? {
        let overlay = frame.overlayState
        guard
            overlay.confirmedFrames >= 1,
            overlay.misses == 0,
            let centerPixels = overlay.centerPixels,
            let pixelDiameter = overlay.pixelDiameter,
            pixelDiameter >= 1
        else {
            return nil
        }

        appendDiameter(pixelDiameter)
        let medianDiameter = median(diameterWindow) ?? pixelDiameter
        let nextSmoothed = smoothedDiameter.map {
            $0 + (medianDiameter - $0) * smoothingAlpha
        } ?? medianDiameter
        smoothedDiameter = nextSmoothed

        let rawDistance = estimateDistance(pixelDiameter: pixelDiameter, focalLength: focalLength)
        let estimatedDistance = estimateDistance(pixelDiameter: nextSmoothed, focalLength: focalLength)
        return PrecisionDepthSample(
            timestamp: frame.timestamp,
            centerPixels: centerPixels,
            pixelDiameter: pixelDiameter,
            smoothedDiameter: nextSmoothed,
            rawDistanceM: rawDistance,
            estimatedDistanceM: estimatedDistance
        )
    }

    private func appendDiameter(_ diameter: CGFloat) {
        diameterWindow.append(diameter)
        if diameterWindow.count > 5 {
            diameterWindow.removeFirst(diameterWindow.count - 5)
        }
    }

    private func stepReference(sample: PrecisionDepthSample?, timestamp: Date) {
        guard let sample else {
            if referenceElapsed <= 0 {
                statusText = "Keep the ball visible at your passing spot"
                return
            }
            referenceMissingFrames += 1
            if referenceMissingFrames > holdMaxMissingFrames {
                referenceStartedAt = nil
                referenceElapsed = 0
                referenceMissingFrames = 0
                referenceSamples.removeAll()
                statusText = "Passing spot hold lost. Hold the ball still and start again."
                return
            }
            referenceStartedAt = nil
            statusText = "Passing spot paused. Reacquire the ball: \(remainingText(referenceHoldSeconds - referenceElapsed))"
            return
        }

        if let referenceStartedAt {
            referenceElapsed += min(max(timestamp.timeIntervalSince(referenceStartedAt), 0), holdMaxFrameDelta)
        }
        referenceStartedAt = timestamp
        referenceMissingFrames = 0
        referenceSamples.append(sample.rawDistanceM)

        if referenceElapsed < referenceHoldSeconds {
            statusText = "Hold the ball at your passing spot: \(remainingText(referenceHoldSeconds - referenceElapsed))"
            return
        }

        guard let zeroDepth = median(referenceSamples) else {
            statusText = "Reference failed. Hold the ball still and try again."
            referenceStartedAt = nil
            return
        }

        zeroReferenceDepthM = zeroDepth
        phase = .calibration
        phaseTitle = "WALL DEPTH"
        statusText = "Reference locked. Hold the ball at the wall for 10 seconds"
        referenceStartedAt = nil
        referenceElapsed = 0
        referenceMissingFrames = 0
        referenceSamples.removeAll()
        diameterWindow.removeAll()
        smoothedDiameter = nil
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
    }

    private func stepCalibration(sample: PrecisionDepthSample?, timestamp: Date) {
        guard let sample else {
            if calibrationElapsed <= 0 {
                statusText = "Keep the ball visible at the wall"
                return
            }
            calibrationMissingFrames += 1
            if calibrationMissingFrames > holdMaxMissingFrames {
                resetCalibration(message: "Wall hold lost. Hold the ball at the wall again.")
                return
            }
            calibrationStartedAt = nil
            statusText = "Wall hold paused. Reacquire the ball: \(remainingText(wallHoldSeconds - calibrationElapsed))"
            return
        }

        if let calibrationStartedAt {
            calibrationElapsed += min(max(timestamp.timeIntervalSince(calibrationStartedAt), 0), holdMaxFrameDelta)
        }
        calibrationStartedAt = timestamp
        calibrationMissingFrames = 0
        calibrationDepthSamples.append(sample.rawDistanceM)
        calibrationDiameterSamples.append(sample.pixelDiameter)

        if calibrationElapsed < wallHoldSeconds {
            statusText = "Hold the ball at the wall: \(remainingText(wallHoldSeconds - calibrationElapsed))"
            return
        }

        guard
            calibrationDepthSamples.count >= minValidCalibrationSamples,
            let wallDistance = median(calibrationDepthSamples),
            let impactDiameter = median(calibrationDiameterSamples),
            impactDiameter >= minCalibrationDiameterPX,
            wallDistance >= minWallDistanceM,
            wallDistance <= maxWallDistanceM
        else {
            resetCalibration(message: "Wall calibration failed. Hold the ball at the wall again.")
            return
        }

        wallCalibration = PrecisionWallCalibration(
            wallDistanceM: wallDistance,
            impactPixelDiameter: impactDiameter,
            confidence: 0.95
        )
        phase = .live
        phaseTitle = "LIVE"
        statusText = "Calibration locked. Hit the target."
        throwState = PrecisionThrowState()
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
    }

    private func resetCalibration(message: String) {
        calibrationStartedAt = nil
        calibrationElapsed = 0
        calibrationMissingFrames = 0
        calibrationDepthSamples.removeAll()
        calibrationDiameterSamples.removeAll()
        diameterWindow.removeAll()
        smoothedDiameter = nil
        statusText = message
    }

    private func stepLive(
        sample: PrecisionDepthSample?,
        frame: BallTrackerFrame,
        cameraController: BallTrackerCameraController
    ) {
        guard let wallCalibration, bullseyeTrackerPoint != nil else {
            phase = .calibration
            phaseTitle = "WALL DEPTH"
            statusText = "Precision target needs calibration"
            return
        }

        if isLivePaused {
            return
        }

        let wallDistance = wallCalibration.wallDistanceM
        let zeroDepth = zeroReferenceDepthM ?? 0
        let wallTravel = max(wallDistance - zeroDepth, 0.5)
        let impactTolerance = max(CGFloat(0.20), wallDistance * 0.06)

        let liveSample = sample.flatMap { isLiveSampleConsistent($0) ? $0 : nil }

        guard let sample = liveSample else {
            if
                throwState.phase == .outboundConfirmed,
                let furthestSample = throwState.furthestSample,
                throwState.eligibleSamples.count >= outboundMinimumFrames
            {
                throwState.missingFrames += 1
                if
                    throwState.missingFrames <= impactDisappearFrames,
                    furthestSample.rawDistanceM >= wallDistance - impactTolerance
                {
                    lockImpact(furthestSample, frame: frame, cameraController: cameraController)
                }
            } else if throwState.phase == .cooldown {
                throwState.missingFrames += 1
                if throwState.missingFrames > cooldownMissingFrames {
                    let holdRemaining = impactMarkerHoldRemaining(at: frame.timestamp)
                    if holdRemaining > 0 {
                        throwState.missingFrames = cooldownMissingFrames
                        statusText = "Last shot locked: \(remainingText(holdRemaining))"
                    } else {
                        throwState = PrecisionThrowState()
                    }
                }
            }
            return
        }

        throwState.missingFrames = 0
        if let nearStart = throwState.nearStartDepthM {
            throwState.nearStartDepthM = min(nearStart, sample.rawDistanceM)
        } else {
            throwState.nearStartDepthM = sample.rawDistanceM
        }

        switch throwState.phase {
        case .idle:
            throwState.eligibleSamples.removeAll()
            throwState.outboundFrames = 0
            throwState.furthestSample = nil
            if
                let nearStart = throwState.nearStartDepthM,
                sample.rawDistanceM - nearStart >= 0.12
            {
                throwState.phase = .outboundCandidate
                appendEligibleSample(sample)
                throwState.outboundFrames = 1
                statusText = "Throw detected. Tracking wall approach."
            } else {
                statusText = "Throw toward the wall"
            }
        case .outboundCandidate:
            appendEligibleSample(sample)
            guard let nearStart = throwState.nearStartDepthM else {
                return
            }
            if sample.rawDistanceM < nearStart + 0.05 {
                throwState = PrecisionThrowState(nearStartDepthM: sample.rawDistanceM)
                statusText = "Throw toward the wall"
                return
            }

            let previous = throwState.eligibleSamples.dropLast().last
            if previous == nil || sample.rawDistanceM >= (previous?.rawDistanceM ?? sample.rawDistanceM) - 0.02 {
                throwState.outboundFrames += 1
            } else {
                throwState.outboundFrames = max(throwState.outboundFrames - 1, 0)
            }

            if
                throwState.outboundFrames >= outboundMinimumFrames,
                sample.rawDistanceM - nearStart >= wallTravel * 0.40
            {
                throwState.phase = .outboundConfirmed
                throwState.furthestSample = sample
                statusText = "Outbound throw confirmed."
            }
        case .outboundConfirmed:
            appendEligibleSample(sample)
            let previous = throwState.eligibleSamples.dropLast().last
            if throwState.furthestSample == nil || sample.rawDistanceM > (throwState.furthestSample?.rawDistanceM ?? 0) {
                throwState.furthestSample = sample
            }

            guard let furthestSample = throwState.furthestSample else {
                return
            }

            let reversedEnough = sample.rawDistanceM <= furthestSample.rawDistanceM - impactReversalM
                || (previous != nil && sample.rawDistanceM <= (previous?.rawDistanceM ?? sample.rawDistanceM) - 0.03)
            if furthestSample.rawDistanceM >= wallDistance - impactTolerance, reversedEnough {
                lockImpact(furthestSample, frame: frame, cameraController: cameraController)
                return
            }

            if
                let nearStart = throwState.nearStartDepthM,
                sample.rawDistanceM < nearStart + 0.10
            {
                throwState = PrecisionThrowState(nearStartDepthM: sample.rawDistanceM)
                statusText = "Throw toward the wall"
            }
        case .cooldown:
            let holdRemaining = impactMarkerHoldRemaining(at: sample.timestamp)
            if holdRemaining > 0 {
                statusText = "Last shot locked: \(remainingText(holdRemaining))"
                return
            }

            if sample.rawDistanceM <= max(wallDistance - resetReturnDepthM, 0) {
                throwState = PrecisionThrowState(nearStartDepthM: sample.rawDistanceM)
                statusText = "Ready for the next throw"
            } else {
                statusText = "Waiting for ball reset"
            }
        }
    }

    private func appendEligibleSample(_ sample: PrecisionDepthSample) {
        throwState.eligibleSamples.append(sample)
        if throwState.eligibleSamples.count > 12 {
            throwState.eligibleSamples.removeFirst(throwState.eligibleSamples.count - 12)
        }
    }

    private func isLiveSampleConsistent(_ sample: PrecisionDepthSample) -> Bool {
        guard
            let previous = throwState.eligibleSamples.last ?? throwState.furthestSample,
            sample.timestamp.timeIntervalSince(previous.timestamp) <= 0.22
        else {
            return true
        }

        let centerJump = hypot(
            sample.centerPixels.x - previous.centerPixels.x,
            sample.centerPixels.y - previous.centerPixels.y
        )
        let maxJump = max(
            maxLiveCenterJumpPX,
            max(sample.pixelDiameter, previous.pixelDiameter) * maxLiveCenterJumpDiameters
        )
        guard centerJump <= maxJump else {
            return false
        }

        let smallerDiameter = max(min(sample.pixelDiameter, previous.pixelDiameter), 1)
        let diameterRatio = max(sample.pixelDiameter, previous.pixelDiameter) / smallerDiameter
        return diameterRatio <= maxLiveDiameterRatio
    }

    private func lockImpact(
        _ impactSample: PrecisionDepthSample,
        frame: BallTrackerFrame,
        cameraController: BallTrackerCameraController
    ) {
        guard throwState.phase != .cooldown else {
            return
        }
        let holdRemaining = impactMarkerHoldRemaining(at: impactSample.timestamp)
        if holdRemaining > 0 {
            throwState.phase = .cooldown
            throwState.missingFrames = 0
            statusText = "Last shot locked: \(remainingText(holdRemaining))"
            return
        }
        guard
            let bullseyeTrackerPoint,
            let wallCalibration = wallCalibration
        else {
            return
        }

        let centerPixels = robustImpactCenter(impactTimestamp: impactSample.timestamp) ?? impactSample.centerPixels
        let bullseyePixels = CGPoint(
            x: bullseyeTrackerPoint.x * frame.framePixelSize.width,
            y: bullseyeTrackerPoint.y * frame.framePixelSize.height
        )
        let focalLength = effectiveFocalLength(frameWidth: frame.framePixelSize.width)
        let dxCM = pixelOffsetToCM(centerPixels.x - bullseyePixels.x, wallDistanceM: wallCalibration.wallDistanceM, focalLength: focalLength)
        let dyCM = pixelOffsetToCM(centerPixels.y - bullseyePixels.y, wallDistanceM: wallCalibration.wallDistanceM, focalLength: focalLength)
        let radialCM = hypot(dxCM, dyCM)
        let awardedScore = scoreFromRadialDistance(radialCM)
        let displayPoint = displayPoint(forPixelPoint: centerPixels, frameSize: frame.framePixelSize, cameraController: cameraController)

        lastImpact = PrecisionImpact(
            centerPixels: centerPixels,
            displayPoint: displayPoint,
            radialDistanceCM: radialCM,
            dxCM: dxCM,
            dyCM: dyCM,
            score: awardedScore,
            timestamp: impactSample.timestamp
        )
        lastScore = awardedScore
        score += awardedScore
        let didStartPerfectHitChain = awardedScore == 5 && !perfectHitChainActive
        perfectHitChainActive = awardedScore == 5
        if didStartPerfectHitChain {
            BallrDrillSoundPlayer.playCombo()
        }
        throwState.phase = .cooldown
        throwState.missingFrames = 0
        statusText = awardedScore > 0 ? "Hit scored: +\(awardedScore)" : "Missed: \(String(format: "%.1f", radialCM)) cm off center"
        if let lastImpact {
            onShotLocked?(lastImpact)
        }
    }

    private func impactMarkerHoldRemaining(at timestamp: Date) -> TimeInterval {
        guard let lastImpact else {
            return 0
        }
        return max(impactMarkerHoldSeconds - timestamp.timeIntervalSince(lastImpact.timestamp), 0)
    }

    private func robustImpactCenter(impactTimestamp: Date) -> CGPoint? {
        var samples: [PrecisionDepthSample] = []
        for sample in throwState.eligibleSamples.reversed() where sample.timestamp <= impactTimestamp {
            samples.append(sample)
            if samples.count == 5 {
                break
            }
        }
        guard !samples.isEmpty else {
            return nil
        }

        let centerX = median(samples.map { $0.centerPixels.x })
        let centerY = median(samples.map { $0.centerPixels.y })
        guard let centerX, let centerY else {
            return nil
        }

        return CGPoint(x: centerX, y: centerY)
    }

    private func updateBullseyeDisplayPoint(cameraController: BallTrackerCameraController) {
        guard let bullseyeTrackerPoint else {
            return
        }
        bullseyeDisplayPoint = cameraController.displayPoint(forTrackerPoint: bullseyeTrackerPoint) ?? bullseyeDisplayPoint
    }

    private func updateHUDDepth() {
        guard let currentDepth else {
            depthText = "--"
            return
        }

        if let zeroReferenceDepthM {
            depthText = String(format: "%.1fm", max(currentDepth.distanceM - zeroReferenceDepthM, 0))
        } else {
            depthText = String(format: "%.1fm", currentDepth.distanceM)
        }
    }

    private func publishRender() {
        let targetRadii = targetDisplayRadii()
        renderView?.update(
            bullseye: bullseyeDisplayPoint,
            targetRadii: targetRadii,
            lastImpact: lastImpact,
            trackerOverlay: trackerOverlay,
            lastScore: lastScore,
            phase: phase,
            score: score
        )
    }

    private func targetDisplayRadii() -> [CGFloat] {
        guard
            let wallCalibration,
            let bullseyeDisplayPoint,
            viewSize.width > 0
        else {
            return []
        }

        let focalLength = effectiveFocalLength(frameWidth: 1920)
        let normalizedRadii = PrecisionTargetScoring.radiiCM.map {
            ($0 / 100.0) * focalLength / wallCalibration.wallDistanceM / 1920.0
        }
        return normalizedRadii.map { normalizedRadius in
            let approximateDisplayX = bullseyeDisplayPoint.x + normalizedRadius * viewSize.width
            return abs(approximateDisplayX - bullseyeDisplayPoint.x)
        }
    }

    private func updateTrackerOverlay(
        from overlayState: BallTrackerOverlayState,
        cameraController: BallTrackerCameraController
    ) {
        let displayRect = overlayState.normalizedRect.flatMap {
            cameraController.displayRect(for: $0)
        }
        let rawDisplayRect = overlayState.rawNormalizedRect.flatMap {
            cameraController.displayRect(for: $0)
        }
        let center = displayRect.map {
            CGPoint(x: $0.midX, y: $0.midY)
        }
        trackerOverlay = PrecisionTrackerOverlay(
            displayRect: displayRect,
            rawDisplayRect: rawDisplayRect,
            center: center,
            confidence: overlayState.confidence,
            isTracking: overlayState.isTracking,
            misses: overlayState.misses
        )
    }

    private func displayPoint(
        forPixelPoint pixelPoint: CGPoint,
        frameSize: CGSize,
        cameraController: BallTrackerCameraController
    ) -> CGPoint? {
        guard frameSize.width > 0, frameSize.height > 0 else {
            return nil
        }
        let trackerPoint = CGPoint(x: pixelPoint.x / frameSize.width, y: pixelPoint.y / frameSize.height)
        return cameraController.displayPoint(forTrackerPoint: trackerPoint)
    }

    private func estimateDistance(pixelDiameter: CGFloat, focalLength: CGFloat) -> CGFloat {
        (ballSpec.diameterM * focalLength) / max(pixelDiameter, 0.000001)
    }

    private func effectiveFocalLength(frameWidth: CGFloat) -> CGFloat {
        defaultFocalLengthPX * max(frameWidth, 1) / focalReferenceWidthPX
    }

    private func pixelOffsetToCM(_ offset: CGFloat, wallDistanceM: CGFloat, focalLength: CGFloat) -> CGFloat {
        offset * wallDistanceM / focalLength * 100.0
    }

    private func scoreFromRadialDistance(_ radialCM: CGFloat) -> Int {
        PrecisionTargetScoring.score(for: radialCM)
    }

    private func remainingText(_ seconds: TimeInterval) -> String {
        "\(String(format: "%.1f", max(seconds, 0)))s remaining"
    }

    private func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else {
            return nil
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) * 0.5
        }
        return sorted[middle]
    }
}

private enum PrecisionTargetScoring {
    static let radiiCM: [CGFloat] = [17.6, 35.2, 44.0]
    static let scores = [5, 3, 1]

    static func score(for radialCM: CGFloat) -> Int {
        for (index, radius) in radiiCM.enumerated() where radialCM < radius {
            return scores[index]
        }
        return 0
    }
}

private struct PrecisionTargetRenderSurface: UIViewRepresentable {
    let coordinator: PrecisionTargetCoordinator

    func makeUIView(context: Context) -> PrecisionTargetRenderView {
        let view = PrecisionTargetRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: PrecisionTargetRenderView, context: Context) {
    }
}

private final class PrecisionTargetRenderView: UIView {
    private let targetLayer = CALayer()
    private let trackerRawLayer = CAShapeLayer()
    private let trackerLayer = CAShapeLayer()
    private let trackerCenterLayer = CAShapeLayer()
    private let trackerTextLayer = CATextLayer()
    private let impactLayer = CAShapeLayer()
    private let scoreLayer = CATextLayer()
    private let centerLayer = CAShapeLayer()
    private var bullseye: CGPoint?
    private var targetRadii: [CGFloat] = []
    private var lastImpact: PrecisionImpact?
    private var trackerOverlay = PrecisionTrackerOverlay(
        displayRect: nil,
        rawDisplayRect: nil,
        center: nil,
        confidence: nil,
        isTracking: false,
        misses: 0
    )
    private var lastScore = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.addSublayer(targetLayer)
        layer.addSublayer(trackerRawLayer)
        layer.addSublayer(trackerLayer)
        layer.addSublayer(trackerCenterLayer)
        layer.addSublayer(trackerTextLayer)
        layer.addSublayer(centerLayer)
        layer.addSublayer(impactLayer)
        layer.addSublayer(scoreLayer)
        configureLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        bullseye: CGPoint?,
        targetRadii: [CGFloat],
        lastImpact: PrecisionImpact?,
        trackerOverlay: PrecisionTrackerOverlay,
        lastScore: Int,
        phase: PrecisionTargetPhase,
        score: Int
    ) {
        self.bullseye = bullseye
        self.targetRadii = targetRadii
        self.lastImpact = lastImpact
        self.trackerOverlay = trackerOverlay
        self.lastScore = lastScore
        render()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        targetLayer.frame = bounds
        trackerRawLayer.frame = bounds
        trackerLayer.frame = bounds
        trackerCenterLayer.frame = bounds
        trackerTextLayer.frame = bounds
        render()
    }

    private func configureLayers() {
        trackerRawLayer.fillColor = UIColor.clear.cgColor
        trackerRawLayer.strokeColor = UIColor.white.withAlphaComponent(0.38).cgColor
        trackerRawLayer.lineWidth = 1.5
        trackerRawLayer.lineDashPattern = [5, 4]

        trackerLayer.fillColor = UIColor.clear.cgColor
        trackerLayer.lineWidth = 2.2
        trackerLayer.shadowColor = UIColor.black.cgColor
        trackerLayer.shadowOpacity = 0.42
        trackerLayer.shadowRadius = 5
        trackerLayer.shadowOffset = .zero

        trackerCenterLayer.fillColor = UIColor.clear.cgColor
        trackerCenterLayer.lineWidth = 2.0
        trackerCenterLayer.shadowColor = UIColor.black.cgColor
        trackerCenterLayer.shadowOpacity = 0.45
        trackerCenterLayer.shadowRadius = 4
        trackerCenterLayer.shadowOffset = .zero

        trackerTextLayer.contentsScale = UIScreen.main.scale
        trackerTextLayer.alignmentMode = .center
        trackerTextLayer.font = UIFont.systemFont(ofSize: 11, weight: .black)
        trackerTextLayer.fontSize = 11
        trackerTextLayer.foregroundColor = UIColor.white.cgColor
        trackerTextLayer.shadowColor = UIColor.black.cgColor
        trackerTextLayer.shadowOpacity = 0.7
        trackerTextLayer.shadowRadius = 3
        trackerTextLayer.shadowOffset = .zero

        impactLayer.fillColor = UIColor.clear.cgColor
        impactLayer.strokeColor = UIColor.white.cgColor
        impactLayer.lineWidth = 3
        impactLayer.shadowColor = UIColor.black.cgColor
        impactLayer.shadowOpacity = 0.45
        impactLayer.shadowRadius = 8
        impactLayer.shadowOffset = .zero

        centerLayer.fillColor = UIColor.white.cgColor
        centerLayer.strokeColor = UIColor.orange.cgColor
        centerLayer.lineWidth = 3

        scoreLayer.contentsScale = UIScreen.main.scale
        scoreLayer.alignmentMode = .center
        scoreLayer.font = UIFont.systemFont(ofSize: 30, weight: .black)
        scoreLayer.fontSize = 30
        scoreLayer.foregroundColor = UIColor.yellow.cgColor
        scoreLayer.shadowColor = UIColor.black.cgColor
        scoreLayer.shadowOpacity = 0.55
        scoreLayer.shadowRadius = 6
        scoreLayer.shadowOffset = .zero
    }

    private func render() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderTarget()
        renderTracker()
        renderImpact()
        CATransaction.commit()
    }

    private func renderTarget() {
        targetLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard let bullseye else {
            centerLayer.path = nil
            return
        }

        let resolvedRadii = targetRadii.isEmpty ? [48, 97, 132] : targetRadii
        let colors = [
            UIColor(red: 0.62, green: 0.88, blue: 1.00, alpha: 0.46),
            UIColor(red: 0.63, green: 1.00, blue: 0.74, alpha: 0.42),
            UIColor(red: 1.00, green: 0.94, blue: 0.56, alpha: 0.44)
        ]
        let fillColors = [
            UIColor(red: 0.62, green: 0.88, blue: 1.00, alpha: 0.10),
            UIColor(red: 0.63, green: 1.00, blue: 0.74, alpha: 0.12),
            UIColor(red: 1.00, green: 0.94, blue: 0.56, alpha: 0.14)
        ]

        for (index, radius) in resolvedRadii.reversed().enumerated() {
            let ring = CAShapeLayer()
            ring.fillColor = fillColors[min(index, fillColors.count - 1)].cgColor
            ring.strokeColor = colors[min(index, colors.count - 1)].cgColor
            ring.lineWidth = index == 0 ? 3.2 : 2.6
            ring.shadowColor = UIColor.black.cgColor
            ring.shadowOpacity = 0.22
            ring.shadowRadius = 4
            ring.shadowOffset = .zero
            ring.path = UIBezierPath(
                ovalIn: CGRect(
                    x: bullseye.x - radius,
                    y: bullseye.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            ).cgPath
            targetLayer.addSublayer(ring)
        }

        let centerRect = CGRect(x: bullseye.x - 6, y: bullseye.y - 6, width: 12, height: 12)
        centerLayer.path = UIBezierPath(ovalIn: centerRect).cgPath

        let labels = ["+5", "+3", "+1"]
        for (index, text) in labels.enumerated() {
            guard index < resolvedRadii.count else {
                continue
            }
            let label = CATextLayer()
            label.contentsScale = UIScreen.main.scale
            label.alignmentMode = .center
            label.font = UIFont.systemFont(ofSize: 16, weight: .black)
            label.fontSize = 16
            label.foregroundColor = UIColor.white.cgColor
            label.string = text
            label.frame = CGRect(
                x: bullseye.x - 28,
                y: bullseye.y - resolvedRadii[index] - 24,
                width: 56,
                height: 22
            )
            label.shadowColor = UIColor.black.cgColor
            label.shadowOpacity = 0.7
            label.shadowRadius = 4
            targetLayer.addSublayer(label)
        }
    }

    private func renderTracker() {
        guard let displayRect = trackerOverlay.displayRect else {
            trackerLayer.path = nil
            trackerRawLayer.path = nil
            trackerCenterLayer.path = nil
            trackerTextLayer.string = nil
            return
        }

        let trackingColor = trackerOverlay.isTracking
            ? UIColor.systemGreen.withAlphaComponent(0.92)
            : UIColor.systemOrange.withAlphaComponent(0.82)
        trackerLayer.strokeColor = trackingColor.cgColor
        trackerCenterLayer.strokeColor = trackingColor.cgColor
        trackerLayer.path = UIBezierPath(roundedRect: displayRect, cornerRadius: 8).cgPath

        if
            let rawDisplayRect = trackerOverlay.rawDisplayRect,
            trackerOverlay.isTracking
        {
            trackerRawLayer.path = UIBezierPath(roundedRect: rawDisplayRect, cornerRadius: 8).cgPath
        } else {
            trackerRawLayer.path = nil
        }

        let center = trackerOverlay.center ?? CGPoint(x: displayRect.midX, y: displayRect.midY)
        let crosshair = UIBezierPath()
        crosshair.move(to: CGPoint(x: center.x - 8, y: center.y))
        crosshair.addLine(to: CGPoint(x: center.x + 8, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 8))
        crosshair.addLine(to: CGPoint(x: center.x, y: center.y + 8))
        trackerCenterLayer.path = crosshair.cgPath

        let confidence = trackerOverlay.confidence.map { String(format: "%.2f", $0) } ?? "--"
        trackerTextLayer.string = trackerOverlay.isTracking
            ? "BALL \(confidence)"
            : "BALL HOLD \(trackerOverlay.misses)"
        trackerTextLayer.frame = CGRect(
            x: displayRect.midX - 48,
            y: max(displayRect.minY - 20, 0),
            width: 96,
            height: 16
        )
    }

    private func renderImpact() {
        guard let impact = lastImpact, let displayPoint = impact.displayPoint else {
            impactLayer.path = nil
            scoreLayer.string = nil
            return
        }

        impactLayer.path = UIBezierPath(
            ovalIn: CGRect(x: displayPoint.x - 13, y: displayPoint.y - 13, width: 26, height: 26)
        ).cgPath
        scoreLayer.string = impact.score > 0 ? "+\(impact.score)" : "0"
        scoreLayer.frame = CGRect(x: displayPoint.x - 42, y: displayPoint.y - 58, width: 84, height: 38)
    }
}

private struct MultiplayerPrecisionScoreCard: View {
    let name: String
    let score: Int
    let shotsTaken: Int
    let shotsPerPlayer: Int
    let isActive: Bool
    let isLeading: Bool

    var body: some View {
        VStack(alignment: isLeading ? .leading : .trailing, spacing: 5) {
            Text(name.uppercased())
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(isActive ? Color.yellow : .white.opacity(0.86))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(score)")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("SHOTS \(shotsTaken)/\(shotsPerPlayer)")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
        }
        .frame(width: 150, alignment: isLeading ? .leading : .trailing)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.black.opacity(isActive ? 0.74 : 0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((isActive ? Color.yellow : Color.orange).opacity(0.8), lineWidth: isActive ? 2.2 : 1.3)
        )
    }
}

private struct MultiplayerPrecisionTurnOverlay: View {
    let state: MultiplayerTurnOverlayState
    let onContinue: () -> Void
    let onReplayShot: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text(state.scoredPoints > 0 ? "\(state.completedPlayerName) scored +\(state.scoredPoints)" : "\(state.completedPlayerName) missed")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(state.isRoundEnding ? "Accept this shot to finish the round." : "\(state.nextPlayerName), you're up next.")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.yellow)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button(action: onReplayShot) {
                        Text("REPLAY THIS SHOT")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(.white)
                            .frame(width: 190, height: 66)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: onContinue) {
                        Text("CONTINUE")
                            .font(.system(size: 20, weight: .black, design: .rounded))
                            .tracking(2)
                            .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.05))
                            .frame(width: 170, height: 66)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.78), lineWidth: 2)
            )
            .padding(.horizontal, 36)
        }
    }
}

private struct MultiplayerPrecisionResultsOverlay: View {
    let result: MultiplayerPrecisionResult
    let onReplay: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.68)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text(result.headline)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Color.yellow)

                Text(result.summary)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                HStack(spacing: 14) {
                    MultiplayerPrecisionResultScore(name: result.playerOneName, score: result.playerOneScore)
                    MultiplayerPrecisionResultScore(name: result.playerTwoName, score: result.playerTwoScore)
                }

                HStack(spacing: 12) {
                    Button(action: onExit) {
                        Text("EXIT")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 150, height: 60)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: onReplay) {
                        Text("REPLAY")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(Color(red: 0.05, green: 0.05, blue: 0.05))
                            .frame(width: 150, height: 60)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                        }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 28)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.8), lineWidth: 2)
            )
            .padding(.horizontal, 34)
        }
    }
}

private struct MultiplayerPrecisionResultScore: View {
    let name: String
    let score: Int

    var body: some View {
        VStack(spacing: 6) {
            Text(name.uppercased())
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(score)")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(Color.yellow)
        }
        .frame(width: 150, height: 94)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.72), lineWidth: 1.5)
        )
    }
}

private struct PrecisionTargetHudChip: View {
    let title: String
    let value: String
    let tint: Color
    var width: CGFloat = 78

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
        .frame(width: width, height: 54)
        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.68), lineWidth: 1.4)
        )
    }
}

private struct PrecisionTargetLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting Precision Targets...")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PrecisionTargetErrorOverlay: View {
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
