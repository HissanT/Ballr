import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct TicTacToeShootingVSCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var setupStep: TicTacToeShootingVSSetupStep = .playerOne
    @State private var playerOneName = ""
    @State private var playerTwoName = ""

    var body: some View {
        switch setupStep {
        case .playerOne:
            TicTacToeShootingVSNameEntryView(
                title: "Player One",
                subtitle: "Player 1 will claim X tiles.",
                placeholder: "Player 1",
                buttonTitle: "NEXT",
                name: $playerOneName,
                onBack: nil,
                onCancel: { dismiss() },
                onContinue: { setupStep = .playerTwo }
            )
        case .playerTwo:
            TicTacToeShootingVSNameEntryView(
                title: "Player Two",
                subtitle: "Player 2 will claim O tiles.",
                placeholder: "Player 2",
                buttonTitle: "START SETUP",
                name: $playerTwoName,
                onBack: { setupStep = .playerOne },
                onCancel: { dismiss() },
                onContinue: { setupStep = .live }
            )
        case .live:
            TicTacToeShootingVSLiveCameraView(
                playerOneName: sanitizedName(playerOneName, fallback: "Player 1"),
                playerTwoName: sanitizedName(playerTwoName, fallback: "Player 2"),
                onReplayGame: {
                    playerOneName = ""
                    playerTwoName = ""
                    setupStep = .playerOne
                },
                onExit: { dismiss() }
            )
        }
    }

    private func sanitizedName(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private enum TicTacToeShootingVSSetupStep {
    case playerOne
    case playerTwo
    case live
}

private struct TicTacToeShootingVSNameEntryView: View {
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
            TicTacToeShootingVSSetupBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    if let onBack {
                        TicTacToeShootingVSIconButton(systemName: "chevron.left", action: onBack)
                    }
                    TicTacToeShootingVSIconButton(systemName: "xmark", action: onCancel)
                    Spacer()
                }

                Spacer(minLength: 18)

                VStack(alignment: .leading, spacing: 12) {
                    Text(title)
                        .font(.ballr(size: 36, weight: .black))
                        .foregroundStyle(.white)

                    Text(subtitle)
                        .font(.ballr(size: 17, weight: .bold))
                        .foregroundStyle(.white.opacity(0.62))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("PLAYER NAME")
                        .font(.ballr(size: 14, weight: .black))
                        .tracking(2)
                        .foregroundStyle(Color.yellow.opacity(0.92))

                    TextField(placeholder, text: $name)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .font(.ballr(size: 24, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 72)
                        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.orange.opacity(0.8), lineWidth: 2)
                        )

                    Text("Leave it blank to use \(placeholder).")
                        .font(.ballr(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.52))
                }

                Button(action: onContinue) {
                    Text(buttonTitle)
                        .font(.ballr(size: 22, weight: .black))
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
        .ballrCameraPresentationChrome()
    }
}

private struct TicTacToeShootingVSIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.ballr(size: 18, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(.black.opacity(0.65), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct TicTacToeShootingVSSetupBackground: View {
    var body: some View {
        BallrAppBackground()
    }
}

private struct TicTacToeShootingVSLiveCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = BallTrackerCameraController()
    @StateObject private var coordinator = TicTacToeShootingVSCoordinator()
    @State private var showsQuitConfirmation = false
    @State private var dragStartBox: CGRect?
    @State private var dragMode: TicTacToeShootingVSPlacementDragMode = .none
    @State private var dragPassedMoveThreshold = false
    @State private var pinchStartBox: CGRect?
    @State private var isPinchingTarget = false
    @State private var suppressDragUntil = Date.distantPast
    let playerOneName: String
    let playerTwoName: String
    let onReplayGame: () -> Void
    let onExit: () -> Void

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

                TicTacToeShootingVSRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if coordinator.phase == .setup {
                        setupControls
                    } else if coordinator.phase != .live {
                        bottomStatus
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .zIndex(100)

                if cameraController.isStarting {
                    TicTacToeShootingVSLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    TicTacToeShootingVSErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: onExit
                    )
                }

                if let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt, showsYellowCharacterFlight: true)
                }

                if coordinator.requiresPassingSpotReturn, coordinator.result == nil {
                    TicTacToeShootingVSFullscreenPromptOverlay(message: "MOVE BACK TO THE\nSHOOTING SPOT")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(250)
                }

                if let result = coordinator.result, coordinator.showsCompletionOverlay {
                    TicTacToeShootingVSCompletionOverlay(
                        result: result,
                        canReplayShot: coordinator.canReplayShot,
                        onReplayShot: { coordinator.replayPreviousShot() },
                        onPlayAgain: onReplayGame,
                        onExit: onExit
                    )
                        .zIndex(300)
                }
            }
            .animation(.easeInOut(duration: 0.24), value: coordinator.requiresPassingSpotReturn)
            .contentShape(Rectangle())
            .gesture(setupDragGesture(in: geometry.size))
            .simultaneousGesture(setupPinchGesture(in: geometry.size))
            .ballrCameraPresentationChrome()
            .ballrAwardsXPOnSuccess(coordinator.isComplete)
            .onAppear {
                BallrOrientationController.lockDribblingLandscape()
                coordinator.reset(viewSize: geometry.size, playerOneName: playerOneName, playerTwoName: playerTwoName)
                cameraController.trackingProfile = .shooting
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
                cameraController.trackingProfile = .standard
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
        .ignoresSafeArea()
    }

    private var topBar: some View {
        ZStack(alignment: .top) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Button {
                        showsQuitConfirmation = true
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.ballr(size: 19, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(.black.opacity(0.58), in: Circle())
                    }
                    .buttonStyle(.plain)

                    TicTacToeShootingVSPlayerHudChip(
                        name: coordinator.playerOneName,
                        mark: .x,
                        isActive: coordinator.currentMark == .x,
                        tint: .yellow
                    )
                }

                Spacer(minLength: 12)

                TicTacToeShootingVSPlayerHudChip(
                    name: coordinator.playerTwoName,
                    mark: .o,
                    isActive: coordinator.currentMark == .o,
                    tint: .cyan
                )
            }

            VStack(spacing: 8) {
                TicTacToeShootingVSTurnHudChip(
                    name: activeTurnName,
                    mark: coordinator.currentMark
                )

                if coordinator.canReplayShot, coordinator.result == nil {
                    Button(action: { coordinator.replayPreviousShot() }) {
                        Text("REPLAY SHOT")
                            .font(.ballr(size: 13, weight: .black))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .frame(height: 34)
                            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.yellow.opacity(0.78), lineWidth: 1.2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var activeTurnName: String {
        coordinator.currentMark == .x ? coordinator.playerOneName : coordinator.playerTwoName
    }

    private var bottomStatus: some View {
        VStack(spacing: 8) {
            Text(coordinator.phaseTitle)
                .font(.ballr(size: 18, weight: .black))
                .foregroundStyle(Color.yellow)

            Text(coordinator.statusText)
                .font(.ballr(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 86)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }

    private var setupControls: some View {
        Button {
            coordinator.startCalibration()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text("START")
            }
            .font(.ballr(size: 22, weight: .black))
            .tracking(1.8)
            .foregroundStyle(.black)
            .frame(width: 190, height: 62)
            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(red: 0.78, green: 0.64, blue: 0.00))
                    .frame(height: 7)
                    .offset(y: 4)
            }
        }
        .buttonStyle(.plain)
    }

    private func setupDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard coordinator.phase == .setup, !isPinchingTarget, Date() >= suppressDragUntil else {
                    return
                }
                if dragStartBox == nil {
                    dragStartBox = coordinator.targetBox
                    dragMode = coordinator.placementDragMode(at: value.startLocation)
                    dragPassedMoveThreshold = false
                }
                guard let startBox = dragStartBox else {
                    return
                }
                switch dragMode {
                case .moveFromCenter:
                    let distance = hypot(value.translation.width, value.translation.height)
                    guard dragPassedMoveThreshold || distance >= 8 else {
                        return
                    }
                    dragPassedMoveThreshold = true
                    coordinator.updateTargetBox(
                        startBox.offsetBy(dx: value.translation.width, dy: value.translation.height),
                        in: size
                    )
                case .moveFromOutside:
                    coordinator.moveTargetBox(startBox, center: value.location, in: size)
                case .resize(let edge):
                    coordinator.resizeTargetBox(startBox, edge: edge, translation: value.translation, in: size)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                dragStartBox = nil
                dragMode = .none
                dragPassedMoveThreshold = false
            }
    }

    private func setupPinchGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                guard coordinator.phase == .setup else {
                    return
                }
                guard isPinchingTarget || abs(scale - 1.0) >= 0.035 else {
                    return
                }
                isPinchingTarget = true
                suppressDragUntil = .distantFuture
                dragStartBox = nil
                dragMode = .none
                dragPassedMoveThreshold = false
                if pinchStartBox == nil {
                    pinchStartBox = coordinator.targetBox
                }
                guard let startBox = pinchStartBox else {
                    return
                }
                coordinator.scaleTargetBox(startBox, scale: scale, in: size)
            }
            .onEnded { _ in
                pinchStartBox = nil
                isPinchingTarget = false
                suppressDragUntil = Date().addingTimeInterval(0.2)
                dragStartBox = nil
                dragMode = .none
                dragPassedMoveThreshold = false
            }
    }
}

private enum TicTacToeShootingVSPlacementDragMode: Equatable {
    case none
    case moveFromOutside
    case moveFromCenter
    case resize(TicTacToeShootingVSResizeEdge)
}

private enum TicTacToeShootingVSResizeEdge {
    case top
    case bottom
    case left
    case right
}

private enum TicTacToeShootingVSPhase {
    case setup
    case reference
    case calibration
    case countdown
    case live
}

private enum TicTacToeShootingVSCell: CaseIterable, Hashable {
    case topLeft
    case topMiddle
    case topRight
    case middleLeft
    case center
    case middleRight
    case bottomLeft
    case bottomMiddle
    case bottomRight

    var row: Int {
        switch self {
        case .topLeft, .topMiddle, .topRight:
            return 0
        case .middleLeft, .center, .middleRight:
            return 1
        case .bottomLeft, .bottomMiddle, .bottomRight:
            return 2
        }
    }

    var column: Int {
        switch self {
        case .topLeft, .middleLeft, .bottomLeft:
            return 0
        case .topMiddle, .center, .bottomMiddle:
            return 1
        case .topRight, .middleRight, .bottomRight:
            return 2
        }
    }

    var index: Int {
        row * 3 + column
    }

    static func cell(row: Int, column: Int) -> TicTacToeShootingVSCell? {
        allCases.first { $0.row == row && $0.column == column }
    }
}

private enum TicTacToeShootingVSTileState {
    case intact
    case breaking(mark: TicTacToeShootingVSMark, startedAt: Date)
    case claimed(mark: TicTacToeShootingVSMark)

    var isAvailableForHit: Bool {
        if case .intact = self {
            return true
        }
        return false
    }

    var mark: TicTacToeShootingVSMark? {
        if case .breaking(let mark, _) = self {
            return mark
        }
        if case .claimed(let mark) = self {
            return mark
        }
        return nil
    }
}

private enum TicTacToeShootingVSMark: String, Equatable {
    case x = "X"
    case o = "O"

    var next: TicTacToeShootingVSMark {
        self == .x ? .o : .x
    }

    var playerIndex: Int {
        self == .x ? 0 : 1
    }

    var color: UIColor {
        switch self {
        case .x:
            return UIColor(red: 1.0, green: 0.84, blue: 0.05, alpha: 1.0)
        case .o:
            return UIColor(red: 0.18, green: 0.88, blue: 1.0, alpha: 1.0)
        }
    }
}

private struct TicTacToeShootingVSResult {
    let headline: String
    let summary: String
    let winningMark: TicTacToeShootingVSMark?
}

private struct TicTacToeShootingVSReplaySnapshot {
    let tileStates: [TicTacToeShootingVSCell: TicTacToeShootingVSTileState]
    let currentMark: TicTacToeShootingVSMark
    let phaseTitle: String
    let statusText: String
    let result: TicTacToeShootingVSResult?
    let showsCompletionOverlay: Bool
    let winningLine: [TicTacToeShootingVSCell]?
    let winningLineStartedAt: Date?
    let impact: TicTacToeShootingVSImpact?
}

private struct TicTacToeShootingVSTrackerOverlay {
    let displayRect: CGRect?
    let rawDisplayRect: CGRect?
    let center: CGPoint?
    let confidence: Double?
    let isTracking: Bool
    let misses: Int

    static let idle = TicTacToeShootingVSTrackerOverlay(
        displayRect: nil,
        rawDisplayRect: nil,
        center: nil,
        confidence: nil,
        isTracking: false,
        misses: 0
    )
}

private struct TicTacToeShootingVSDepthSample {
    let timestamp: Date
    let centerPixels: CGPoint
    let frameWidth: CGFloat
    let pixelDiameter: CGFloat
    let smoothedDiameter: CGFloat
    let rawDistanceM: CGFloat
    let estimatedDistanceM: CGFloat
}

private struct TicTacToeShootingVSWallCalibration {
    let wallDistanceM: CGFloat
    let impactPixelDiameter: CGFloat
}

private enum TicTacToeShootingVSThrowPhase {
    case idle
    case outboundCandidate
    case outboundConfirmed
    case cooldown
}

private struct TicTacToeShootingVSThrowState {
    var phase: TicTacToeShootingVSThrowPhase = .idle
    var nearStartDepthM: CGFloat?
    var outboundFrames = 0
    var missingFrames = 0
    var cooldownStartedAt: Date?
    var furthestSample: TicTacToeShootingVSDepthSample?
    var eligibleSamples: [TicTacToeShootingVSDepthSample] = []
}

private struct TicTacToeShootingVSImpact {
    let displayPoint: CGPoint?
    let cell: TicTacToeShootingVSCell?
    let didBreakTile: Bool
    let timestamp: Date
}

private final class TicTacToeShootingVSCoordinator: ObservableObject {
    @Published private(set) var phase: TicTacToeShootingVSPhase = .setup
    @Published private(set) var phaseTitle = "PLACE TARGET"
    @Published private(set) var statusText = "Drag the box into place. Pinch to resize."
    @Published private(set) var tilesRemaining = TicTacToeShootingVSCell.allCases.count
    @Published private(set) var isComplete = false
    @Published private(set) var playerOneName = "Player 1"
    @Published private(set) var playerTwoName = "Player 2"
    @Published private(set) var currentMark: TicTacToeShootingVSMark = .x
    @Published private(set) var result: TicTacToeShootingVSResult?
    @Published private(set) var showsCompletionOverlay = false
    @Published private(set) var canReplayShot = false
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var requiresPassingSpotReturn = false
    @Published private(set) var targetBox: CGRect = .zero

    private let targetAspectRatio: CGFloat = 1.0
    private let ballDiameterM: CGFloat = 0.22
    private let defaultFocalLengthPX: CGFloat = 2400.0
    private let focalReferenceWidthPX: CGFloat = 1920.0
    private let referenceHoldSeconds: TimeInterval = 5.0
    private let wallHoldSeconds: TimeInterval = 10.0
    private let holdMaxMissingFrames = 15
    private let holdMaxFrameDelta: TimeInterval = 0.1
    private let countdownDuration: TimeInterval = 4.0
    private let smoothingAlpha: CGFloat = 0.35
    private let minValidCalibrationSamples = 12
    private let minCalibrationDiameterPX: CGFloat = 16.0
    private let minWallDistanceM: CGFloat = 1.5
    private let maxWallDistanceM: CGFloat = 14.0
    private let outboundMinimumFrames = 4
    private let impactReversalM: CGFloat = 0.04
    private let passingSpotReturnDistanceMargin: CGFloat = 0.20
    private let returnPromptDelay: TimeInterval = 7.0
    private let cooldownMissingFrames = 6
    private let impactDisappearFrames = 8
    private let maxLiveCenterJumpPX: CGFloat = 220
    private let maxLiveCenterJumpDiameters: CGFloat = 4.0
    private let maxLiveDiameterRatio: CGFloat = 2.35
    private let edgeLiveCenterJumpMultiplier: CGFloat = 1.55
    private let edgeLiveDiameterRatioMultiplier: CGFloat = 1.30
    private let tileBreakDuration: TimeInterval = 0.62
    private let completionOverlayDelay: TimeInterval = 3.95

    private var viewSize: CGSize = .zero
    private var wallCalibration: TicTacToeShootingVSWallCalibration?
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
    private var throwState = TicTacToeShootingVSThrowState()
    private var lastImpact: TicTacToeShootingVSImpact?
    private var tileStates: [TicTacToeShootingVSCell: TicTacToeShootingVSTileState] = [:]
    private var winningLine: [TicTacToeShootingVSCell]?
    private var winningLineStartedAt: Date?
    private var replaySnapshot: TicTacToeShootingVSReplaySnapshot?
    private var completionOverlayWorkItem: DispatchWorkItem?
    private var trackerOverlay = TicTacToeShootingVSTrackerOverlay.idle
    private weak var renderView: TicTacToeShootingVSRenderView?

    func attach(renderView: TicTacToeShootingVSRenderView) {
        self.renderView = renderView
        publishRender()
    }

    func reset(viewSize: CGSize, playerOneName: String, playerTwoName: String) {
        self.viewSize = viewSize
        self.playerOneName = playerOneName
        self.playerTwoName = playerTwoName
        phase = .setup
        phaseTitle = "PLACE TARGET"
        statusText = "Drag the center or open space to move. Drag edges to resize."
        tilesRemaining = TicTacToeShootingVSCell.allCases.count
        isComplete = false
        currentMark = .x
        result = nil
        showsCompletionOverlay = false
        canReplayShot = false
        countdownStartedAt = nil
        requiresPassingSpotReturn = false
        targetBox = defaultTargetBox(in: viewSize)
        wallCalibration = nil
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
        throwState = TicTacToeShootingVSThrowState()
        lastImpact = nil
        tileStates = Dictionary(uniqueKeysWithValues: TicTacToeShootingVSCell.allCases.map { ($0, .intact) })
        winningLine = nil
        winningLineStartedAt = nil
        replaySnapshot = nil
        completionOverlayWorkItem?.cancel()
        completionOverlayWorkItem = nil
        trackerOverlay = .idle
        publishRender()
    }

    func prepare(viewSize: CGSize) {
        self.viewSize = viewSize
        if targetBox == .zero {
            targetBox = defaultTargetBox(in: viewSize)
        } else {
            targetBox = clampedBox(targetBox, in: viewSize)
        }
        publishRender()
    }

    func updateTargetBox(_ box: CGRect, in size: CGSize) {
        guard phase == .setup else {
            return
        }
        targetBox = clampedBox(box, in: size)
        publishRender()
    }

    func moveTargetBox(_ box: CGRect, center: CGPoint, in size: CGSize) {
        guard phase == .setup else {
            return
        }
        let moved = CGRect(
            x: center.x - box.width * 0.5,
            y: center.y - box.height * 0.5,
            width: box.width,
            height: box.height
        )
        targetBox = clampedBox(moved, in: size)
        publishRender()
    }

    func placementDragMode(at point: CGPoint) -> TicTacToeShootingVSPlacementDragMode {
        guard phase == .setup, targetBox.width > 0, targetBox.height > 0 else {
            return .none
        }
        guard targetBox.contains(point) else {
            return .moveFromOutside
        }

        let edgeBand = max(24, min(targetBox.width, targetBox.height) * 0.12)
        let distanceToLeft = abs(point.x - targetBox.minX)
        let distanceToRight = abs(point.x - targetBox.maxX)
        let distanceToTop = abs(point.y - targetBox.minY)
        let distanceToBottom = abs(point.y - targetBox.maxY)
        let nearestHorizontalEdge = min(distanceToLeft, distanceToRight)
        let nearestVerticalEdge = min(distanceToTop, distanceToBottom)

        if nearestHorizontalEdge <= edgeBand, nearestHorizontalEdge <= nearestVerticalEdge {
            return distanceToLeft <= distanceToRight ? .resize(.left) : .resize(.right)
        }
        if nearestVerticalEdge <= edgeBand {
            return distanceToTop <= distanceToBottom ? .resize(.top) : .resize(.bottom)
        }

        let centerRect = targetBox.insetBy(dx: targetBox.width * 0.33, dy: targetBox.height * 0.33)
        return centerRect.contains(point) ? .moveFromCenter : .none
    }

    func resizeTargetBox(
        _ box: CGRect,
        edge: TicTacToeShootingVSResizeEdge,
        translation: CGSize,
        in size: CGSize
    ) {
        guard phase == .setup else {
            return
        }

        var resized = box
        switch edge {
        case .left:
            let width = clampedTargetWidth(box.width - translation.width, in: size)
            resized = CGRect(x: box.maxX - width, y: box.minY, width: width, height: box.height)
        case .right:
            let width = clampedTargetWidth(box.width + translation.width, in: size)
            resized = CGRect(x: box.minX, y: box.minY, width: width, height: box.height)
        case .top:
            let height = clampedTargetHeight(box.height - translation.height, in: size)
            resized = CGRect(x: box.minX, y: box.maxY - height, width: box.width, height: height)
        case .bottom:
            let height = clampedTargetHeight(box.height + translation.height, in: size)
            resized = CGRect(x: box.minX, y: box.minY, width: box.width, height: height)
        }

        targetBox = clampedBox(resized, in: size)
        publishRender()
    }

    func scaleTargetBox(_ box: CGRect, scale: CGFloat, in size: CGSize) {
        guard phase == .setup else {
            return
        }
        let resolvedScale = clampedScale(for: box, scale: scale, in: size)
        let newSize = CGSize(
            width: box.width * resolvedScale,
            height: box.height * resolvedScale
        )
        let scaled = CGRect(
            x: box.midX - newSize.width * 0.5,
            y: box.midY - newSize.height * 0.5,
            width: newSize.width,
            height: newSize.height
        )
        targetBox = clampedBox(scaled, in: size)
        publishRender()
    }

    func startCalibration() {
        guard phase == .setup else {
            return
        }
        phase = .reference
        phaseTitle = "PASSING SPOT"
        statusText = "Hold the ball at your passing spot for 5 seconds"
        referenceStartedAt = nil
        referenceElapsed = 0
        referenceMissingFrames = 0
        referenceSamples.removeAll()
        setRequiresPassingSpotReturn(false)
        publishRender()
    }

    func handle(frame: BallTrackerFrame, cameraController: BallTrackerCameraController) {
        updateTrackerOverlay(from: frame.overlayState, cameraController: cameraController)
        let focalLength = effectiveFocalLength(frameWidth: frame.framePixelSize.width)
        let sample = buildDepthSample(frame: frame, focalLength: focalLength)
        advanceTileAnimations(timestamp: frame.timestamp)

        switch phase {
        case .setup:
            phaseTitle = "PLACE TARGET"
            statusText = "Drag the center or open space to move. Drag edges to resize."
            setRequiresPassingSpotReturn(false)
        case .reference:
            stepReference(sample: sample, timestamp: frame.timestamp)
        case .calibration:
            stepCalibration(sample: sample, timestamp: frame.timestamp)
        case .countdown:
            stepCountdown(timestamp: frame.timestamp)
        case .live:
            if !isComplete {
                stepLive(sample: sample, frame: frame, cameraController: cameraController)
            }
        }

        publishRender()
    }

    private func buildDepthSample(frame: BallTrackerFrame, focalLength: CGFloat) -> TicTacToeShootingVSDepthSample? {
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
        return TicTacToeShootingVSDepthSample(
            timestamp: frame.timestamp,
            centerPixels: centerPixels,
            frameWidth: frame.framePixelSize.width,
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

    private func stepReference(sample: TicTacToeShootingVSDepthSample?, timestamp: Date) {
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

    private func stepCalibration(sample: TicTacToeShootingVSDepthSample?, timestamp: Date) {
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
            wallDistance >= minWallDistanceM,
            wallDistance <= maxWallDistanceM,
            impactDiameter >= minCalibrationDiameterPX
        else {
            resetCalibration(message: "Wall calibration failed. Hold the ball at the wall again.")
            return
        }

        wallCalibration = TicTacToeShootingVSWallCalibration(
            wallDistanceM: wallDistance,
            impactPixelDiameter: impactDiameter
        )
        phase = .countdown
        phaseTitle = "GET READY"
        statusText = "Tic Tac Toe ShootingVS starts in 3"
        countdownStartedAt = timestamp
        throwState = TicTacToeShootingVSThrowState()
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
        countdownStartedAt = nil
        diameterWindow.removeAll()
        smoothedDiameter = nil
        statusText = message
    }

    private func stepCountdown(timestamp: Date) {
        guard let countdownStartedAt else {
            self.countdownStartedAt = timestamp
            return
        }

        let elapsed = timestamp.timeIntervalSince(countdownStartedAt)
        if elapsed >= countdownDuration {
            phase = .live
            phaseTitle = "LIVE"
            statusText = "\(activePlayerName), shoot to claim an \(currentMark.rawValue)"
            self.countdownStartedAt = nil
        }
    }

    private func stepLive(
        sample: TicTacToeShootingVSDepthSample?,
        frame: BallTrackerFrame,
        cameraController: BallTrackerCameraController
    ) {
        guard let wallCalibration else {
            phase = .calibration
            phaseTitle = "WALL DEPTH"
            statusText = "Tic Tac Toe ShootingVS needs calibration"
            setRequiresPassingSpotReturn(false)
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
                setRequiresPassingSpotReturn(shouldShowReturnPrompt(at: frame.timestamp))
                if throwState.missingFrames > cooldownMissingFrames {
                    throwState.missingFrames = cooldownMissingFrames
                    statusText = requiresPassingSpotReturn ? "Bring the ball back to the passing spot" : "Shot locked. Get ready to return."
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
        if throwState.phase != .cooldown {
            setRequiresPassingSpotReturn(false)
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
                statusText = "Shot detected. Tracking wall approach."
            } else {
                statusText = "\(activePlayerName), shoot to claim an \(currentMark.rawValue)"
            }
        case .outboundCandidate:
            appendEligibleSample(sample)
            guard let nearStart = throwState.nearStartDepthM else {
                return
            }
            if sample.rawDistanceM < nearStart + 0.05 {
                throwState = TicTacToeShootingVSThrowState(nearStartDepthM: sample.rawDistanceM)
                statusText = "\(activePlayerName), shoot to claim an \(currentMark.rawValue)"
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
                statusText = "Outbound shot confirmed."
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
                throwState = TicTacToeShootingVSThrowState(nearStartDepthM: sample.rawDistanceM)
                statusText = "\(activePlayerName), shoot to claim an \(currentMark.rawValue)"
            }
        case .cooldown:
            if isBackAtPassingSpot(sample.rawDistanceM, zeroDepth: zeroDepth) {
                throwState = TicTacToeShootingVSThrowState(nearStartDepthM: sample.rawDistanceM)
                setRequiresPassingSpotReturn(false)
                statusText = "\(activePlayerName), shoot to claim an \(currentMark.rawValue)"
            } else {
                setRequiresPassingSpotReturn(shouldShowReturnPrompt(at: sample.timestamp))
                statusText = requiresPassingSpotReturn ? "Bring the ball back to the passing spot" : "Shot locked. Hold for a moment."
            }
        }
    }

    private func lockImpact(
        _ impactSample: TicTacToeShootingVSDepthSample,
        frame: BallTrackerFrame,
        cameraController: BallTrackerCameraController
    ) {
        guard throwState.phase != .cooldown else {
            return
        }
        let centerPixels = robustImpactCenter(impactTimestamp: impactSample.timestamp) ?? impactSample.centerPixels
        let displayPoint = displayPoint(forPixelPoint: centerPixels, frameSize: frame.framePixelSize, cameraController: cameraController)
        let cell = displayPoint.flatMap(zoneCell)
        let didBreakTile: Bool
        let snapshot = makeReplaySnapshot()
        let completedMark = currentMark
        let completedPlayerName = activePlayerName

        if let cell, (tileStates[cell] ?? .intact).isAvailableForHit {
            tileStates[cell] = .breaking(mark: completedMark, startedAt: impactSample.timestamp)
            updateTileProgress()
            didBreakTile = true
            TicTacToeShootingVSSoundPlayer.playGlassBreak()
            advanceTurn(after: "\(completedPlayerName) claimed \(completedMark.rawValue)")
        } else if cell != nil {
            didBreakTile = false
            advanceTurn(after: "\(completedPlayerName) hit a claimed tile")
        } else {
            didBreakTile = false
            BallrDrillSoundPlayer.playIncorrect()
            advanceTurn(after: "\(completedPlayerName) missed the grid")
        }

        replaySnapshot = snapshot
        canReplayShot = true
        lastImpact = TicTacToeShootingVSImpact(
            displayPoint: displayPoint,
            cell: cell,
            didBreakTile: didBreakTile,
            timestamp: impactSample.timestamp
        )

        throwState.phase = .cooldown
        throwState.cooldownStartedAt = impactSample.timestamp
        throwState.missingFrames = 0
        setRequiresPassingSpotReturn(false)
    }

    private func advanceTileAnimations(timestamp: Date) {
        var didChange = false
        for (cell, state) in tileStates {
            if case .breaking(let mark, let startedAt) = state, timestamp.timeIntervalSince(startedAt) >= tileBreakDuration {
                tileStates[cell] = .claimed(mark: mark)
                didChange = true
            }
        }
        if didChange {
            evaluateBoardIfNeeded()
            publishRender()
        }
    }

    private func updateTileProgress() {
        tilesRemaining = tileStates.values.filter { $0.mark == nil }.count
    }

    func replayPreviousShot() {
        guard let snapshot = replaySnapshot else {
            return
        }
        tileStates = snapshot.tileStates
        currentMark = snapshot.currentMark
        phaseTitle = snapshot.phaseTitle
        statusText = "\(activePlayerName), replay the shot"
        result = snapshot.result
        isComplete = snapshot.result != nil
        showsCompletionOverlay = snapshot.showsCompletionOverlay
        winningLine = snapshot.winningLine
        winningLineStartedAt = snapshot.winningLineStartedAt
        lastImpact = nil
        updateTileProgress()
        throwState = TicTacToeShootingVSThrowState()
        setRequiresPassingSpotReturn(false)
        replaySnapshot = nil
        canReplayShot = false
        publishRender()
    }

    private var activePlayerName: String {
        currentMark == .x ? playerOneName : playerTwoName
    }

    private func advanceTurn(after message: String) {
        currentMark = currentMark.next
        statusText = "\(message). \(activePlayerName) is next."
    }

    private func makeReplaySnapshot() -> TicTacToeShootingVSReplaySnapshot {
        TicTacToeShootingVSReplaySnapshot(
            tileStates: tileStates,
            currentMark: currentMark,
            phaseTitle: phaseTitle,
            statusText: statusText,
            result: result,
            showsCompletionOverlay: showsCompletionOverlay,
            winningLine: winningLine,
            winningLineStartedAt: winningLineStartedAt,
            impact: lastImpact
        )
    }

    private func evaluateBoardIfNeeded() {
        guard !isComplete else {
            return
        }
        updateTileProgress()

        if let winningLine = winningBoardLine() {
            guard let mark = tileStates[winningLine[0]]?.mark else {
                return
            }
            let winnerName = mark == .x ? playerOneName : playerTwoName
            completeChallenge(
                result: TicTacToeShootingVSResult(
                    headline: "\(winnerName) Wins",
                    summary: "\(winnerName) connected three \(mark.rawValue)s.",
                    winningMark: mark
                ),
                winningLine: winningLine
            )
            return
        }

        if tilesRemaining == 0 {
            completeChallenge(
                result: TicTacToeShootingVSResult(
                    headline: "It's a Draw",
                    summary: "All tiles were claimed with no three-in-a-row.",
                    winningMark: nil
                ),
                winningLine: nil
            )
        }
    }

    private func winningBoardLine() -> [TicTacToeShootingVSCell]? {
        let lines: [[TicTacToeShootingVSCell]] = [
            [.topLeft, .topMiddle, .topRight],
            [.middleLeft, .center, .middleRight],
            [.bottomLeft, .bottomMiddle, .bottomRight],
            [.topLeft, .middleLeft, .bottomLeft],
            [.topMiddle, .center, .bottomMiddle],
            [.topRight, .middleRight, .bottomRight],
            [.topLeft, .center, .bottomRight],
            [.topRight, .center, .bottomLeft]
        ]

        return lines.first { line in
            guard let firstMark = tileStates[line[0]]?.mark else {
                return false
            }
            return line.allSatisfy { tileStates[$0]?.mark == firstMark }
        }
    }

    private func completeChallenge(result: TicTacToeShootingVSResult, winningLine: [TicTacToeShootingVSCell]?) {
        guard !isComplete else {
            return
        }
        isComplete = true
        self.result = result
        self.winningLine = winningLine
        winningLineStartedAt = winningLine == nil ? nil : Date()
        showsCompletionOverlay = false
        phaseTitle = result.winningMark == nil ? "DRAW" : "WINNER"
        statusText = result.summary
        BallrDrillSoundPlayer.playWinner()
        publishRender()

        completionOverlayWorkItem?.cancel()
        let delay = winningLine == nil ? 0.75 : completionOverlayDelay
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isComplete, self.result != nil else {
                return
            }
            self.showsCompletionOverlay = true
        }
        completionOverlayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func zoneCell(for point: CGPoint) -> TicTacToeShootingVSCell? {
        guard targetBox.contains(point), targetBox.width > 0, targetBox.height > 0 else {
            return nil
        }
        let column = min(max(Int(((point.x - targetBox.minX) / targetBox.width) * 3), 0), 2)
        let row = min(max(Int(((point.y - targetBox.minY) / targetBox.height) * 3), 0), 2)
        return TicTacToeShootingVSCell.cell(row: row, column: column)
    }

    private func appendEligibleSample(_ sample: TicTacToeShootingVSDepthSample) {
        throwState.eligibleSamples.append(sample)
        if throwState.eligibleSamples.count > 12 {
            throwState.eligibleSamples.removeFirst(throwState.eligibleSamples.count - 12)
        }
    }

    private func isLiveSampleConsistent(_ sample: TicTacToeShootingVSDepthSample) -> Bool {
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
        let edgeTolerance = liveEdgeTolerance(for: sample)
        let maxJump = max(
            maxLiveCenterJumpPX,
            max(sample.pixelDiameter, previous.pixelDiameter) * maxLiveCenterJumpDiameters
        ) * (1 + edgeTolerance * (edgeLiveCenterJumpMultiplier - 1))
        guard centerJump <= maxJump else {
            return false
        }

        let smallerDiameter = max(min(sample.pixelDiameter, previous.pixelDiameter), 1)
        let diameterRatio = max(sample.pixelDiameter, previous.pixelDiameter) / smallerDiameter
        return diameterRatio <= maxLiveDiameterRatio * (1 + edgeTolerance * (edgeLiveDiameterRatioMultiplier - 1))
    }

    private func liveEdgeTolerance(for sample: TicTacToeShootingVSDepthSample) -> CGFloat {
        let frameWidth = max(sample.frameWidth, 1)
        let normalizedX = min(max(sample.centerPixels.x / frameWidth, 0), 1)
        let distanceToEdge = min(normalizedX, 1 - normalizedX)
        return min(max((0.24 - distanceToEdge) / 0.24, 0), 1)
    }

    private func robustImpactCenter(impactTimestamp: Date) -> CGPoint? {
        var samples: [TicTacToeShootingVSDepthSample] = []
        for sample in throwState.eligibleSamples.reversed() where sample.timestamp <= impactTimestamp {
            samples.append(sample)
            if samples.count == 5 {
                break
            }
        }
        guard !samples.isEmpty else {
            return nil
        }

        guard
            let centerX = median(samples.map { $0.centerPixels.x }),
            let centerY = median(samples.map { $0.centerPixels.y })
        else {
            return nil
        }
        return CGPoint(x: centerX, y: centerY)
    }

    private func isBackAtPassingSpot(_ distance: CGFloat, zeroDepth: CGFloat) -> Bool {
        let margin = max(zeroDepth * passingSpotReturnDistanceMargin, 0.12)
        return distance >= zeroDepth - margin && distance <= zeroDepth + margin
    }

    private func shouldShowReturnPrompt(at timestamp: Date) -> Bool {
        guard let cooldownStartedAt = throwState.cooldownStartedAt else {
            return false
        }
        return timestamp.timeIntervalSince(cooldownStartedAt) >= returnPromptDelay
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
        trackerOverlay = TicTacToeShootingVSTrackerOverlay(
            displayRect: displayRect,
            rawDisplayRect: rawDisplayRect,
            center: center,
            confidence: overlayState.confidence,
            isTracking: overlayState.isTracking,
            misses: overlayState.misses
        )
    }

    private func publishRender() {
        renderView?.update(
            targetBox: targetBox,
            tileStates: tileStates,
            trackerOverlay: trackerOverlay,
            impact: lastImpact,
            phase: phase,
            winningLine: winningLine,
            winningLineStartedAt: winningLineStartedAt
        )
    }

    private func defaultTargetBox(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return .zero
        }
        let width = min(size.width * 0.46, 360)
        let height = width / targetAspectRatio
        return CGRect(
            x: size.width * 0.5 - width * 0.5,
            y: size.height * 0.46 - height * 0.5,
            width: width,
            height: height
        )
    }

    private func clampedBox(_ box: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else {
            return box
        }
        let width = box.width
        let height = box.height
        let safeTop: CGFloat = 18
        let safeBottom: CGFloat = 28
        let minX: CGFloat = 24
        let maxX = max(minX, size.width - width - 24)
        let minY = safeTop
        let maxY = max(minY, size.height - height - safeBottom)
        let originX = min(max(box.midX - width * 0.5, minX), maxX)
        let originY = min(max(box.midY - height * 0.5, minY), maxY)
        return CGRect(x: originX, y: originY, width: width, height: height)
    }

    private func clampedScale(for box: CGRect, scale: CGFloat, in size: CGSize) -> CGFloat {
        guard box.width > 0, box.height > 0, size.width > 0, size.height > 0 else {
            return scale
        }
        let minWidth = minimumTargetWidth(in: size)
        let maxWidth = maximumTargetWidth(in: size)
        let minHeight = minimumTargetHeight(in: size)
        let maxHeight = maximumTargetHeight(in: size)
        let minScale = max(minWidth / box.width, minHeight / box.height)
        let maxScale = min(maxWidth / box.width, maxHeight / box.height)
        return min(max(scale, minScale), maxScale)
    }

    private func clampedTargetWidth(_ width: CGFloat, in size: CGSize) -> CGFloat {
        min(max(width, minimumTargetWidth(in: size)), maximumTargetWidth(in: size))
    }

    private func clampedTargetHeight(_ height: CGFloat, in size: CGSize) -> CGFloat {
        min(max(height, minimumTargetHeight(in: size)), maximumTargetHeight(in: size))
    }

    private func minimumTargetWidth(in size: CGSize) -> CGFloat {
        min(max(size.width * 0.20, 140), 220)
    }

    private func maximumTargetWidth(in size: CGSize) -> CGFloat {
        max(size.width - 72, minimumTargetWidth(in: size))
    }

    private func minimumTargetHeight(in size: CGSize) -> CGFloat {
        min(max(size.height * 0.18, 92), 180)
    }

    private func maximumTargetHeight(in size: CGSize) -> CGFloat {
        max(size.height - 64, minimumTargetHeight(in: size))
    }

    private func setRequiresPassingSpotReturn(_ isRequired: Bool) {
        guard requiresPassingSpotReturn != isRequired else {
            return
        }
        requiresPassingSpotReturn = isRequired
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
        (ballDiameterM * focalLength) / max(pixelDiameter, 0.000001)
    }

    private func effectiveFocalLength(frameWidth: CGFloat) -> CGFloat {
        defaultFocalLengthPX * max(frameWidth, 1) / focalReferenceWidthPX
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

private struct TicTacToeShootingVSRenderSurface: UIViewRepresentable {
    let coordinator: TicTacToeShootingVSCoordinator

    func makeUIView(context: Context) -> TicTacToeShootingVSRenderView {
        let view = TicTacToeShootingVSRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: TicTacToeShootingVSRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class TicTacToeShootingVSRenderView: UIView {
    private let gridLayer = CALayer()
    private let trackerRawLayer = CAShapeLayer()
    private let trackerLayer = CAShapeLayer()
    private let trackerCenterLayer = CAShapeLayer()
    private let trackerTextLayer = CATextLayer()
    private let impactLayer = CAShapeLayer()
    private var displayLink: CADisplayLink?
    private var targetBox: CGRect = .zero
    private var tileStates: [TicTacToeShootingVSCell: TicTacToeShootingVSTileState] = [:]
    private var trackerOverlay = TicTacToeShootingVSTrackerOverlay.idle
    private var impact: TicTacToeShootingVSImpact?
    private var phase: TicTacToeShootingVSPhase = .setup
    private var winningLine: [TicTacToeShootingVSCell]?
    private var winningLineStartedAt: Date?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        layer.addSublayer(gridLayer)
        layer.addSublayer(trackerRawLayer)
        layer.addSublayer(trackerLayer)
        layer.addSublayer(trackerCenterLayer)
        layer.addSublayer(trackerTextLayer)
        layer.addSublayer(impactLayer)
        configureLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            displayLink?.invalidate()
            displayLink = nil
        } else if displayLink == nil {
            let displayLink = CADisplayLink(target: self, selector: #selector(renderFrame))
            displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 30)
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    func update(
        targetBox: CGRect,
        tileStates: [TicTacToeShootingVSCell: TicTacToeShootingVSTileState],
        trackerOverlay: TicTacToeShootingVSTrackerOverlay,
        impact: TicTacToeShootingVSImpact?,
        phase: TicTacToeShootingVSPhase,
        winningLine: [TicTacToeShootingVSCell]?,
        winningLineStartedAt: Date?
    ) {
        self.targetBox = targetBox
        self.tileStates = tileStates
        self.trackerOverlay = trackerOverlay
        self.impact = impact
        self.phase = phase
        self.winningLine = winningLine
        self.winningLineStartedAt = winningLineStartedAt
        render(date: Date())
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gridLayer.frame = bounds
        trackerRawLayer.frame = bounds
        trackerLayer.frame = bounds
        trackerCenterLayer.frame = bounds
        trackerTextLayer.frame = bounds
        impactLayer.frame = bounds
        render(date: Date())
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
        trackerCenterLayer.lineWidth = 2
        trackerCenterLayer.shadowColor = UIColor.black.cgColor
        trackerCenterLayer.shadowOpacity = 0.45
        trackerCenterLayer.shadowRadius = 4
        trackerCenterLayer.shadowOffset = .zero

        trackerTextLayer.contentsScale = UIScreen.main.scale
        trackerTextLayer.alignmentMode = .center
        trackerTextLayer.font = BallrFont.uiFont(size: 11, weight: .black)
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

    }

    @objc private func renderFrame() {
        render(date: Date())
    }

    private func render(date: Date) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderGrid()
        renderWinningLine(date: date)
        renderTracker()
        renderImpact()
        CATransaction.commit()
    }

    private func renderGrid() {
        gridLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        guard targetBox.width > 0, targetBox.height > 0 else {
            return
        }

        addBoardSurface()

        let cellWidth = targetBox.width / 3
        let cellHeight = targetBox.height / 3
        let gap = min(max(min(targetBox.width, targetBox.height) * 0.018, 4), 8)
        for cell in TicTacToeShootingVSCell.allCases {
            let rect = CGRect(
                x: targetBox.minX + CGFloat(cell.column) * cellWidth,
                y: targetBox.minY + CGFloat(cell.row) * cellHeight,
                width: cellWidth,
                height: cellHeight
            ).insetBy(dx: gap * 0.5, dy: gap * 0.5)

            switch tileStates[cell] ?? .intact {
            case .intact:
                addCellSurface(in: rect)
            case .breaking(let mark, let startedAt):
                renderBreakingTile(cell: cell, rect: rect, startedAt: startedAt)
                renderMark(mark, in: rect, alpha: 0.35)
            case .claimed(let mark):
                renderMark(mark, in: rect, alpha: 1.0)
            }
        }

        addCornerBrackets()
        addBoardGridLines()
    }

    private func addBoardSurface() {
        let board = CAShapeLayer()
        board.path = UIBezierPath(roundedRect: targetBox, cornerRadius: 4).cgPath
        board.fillColor = UIColor.black.withAlphaComponent(0.10).cgColor
        board.strokeColor = UIColor.clear.cgColor
        board.lineWidth = 0
        gridLayer.addSublayer(board)
    }

    private func addBoardGridLines() {
        let gridPath = UIBezierPath()
        for index in 1...2 {
            let x = targetBox.minX + targetBox.width * CGFloat(index) / 3
            gridPath.move(to: CGPoint(x: x, y: targetBox.minY + targetBox.height * 0.06))
            gridPath.addLine(to: CGPoint(x: x, y: targetBox.maxY - targetBox.height * 0.06))

            let y = targetBox.minY + targetBox.height * CGFloat(index) / 3
            gridPath.move(to: CGPoint(x: targetBox.minX + targetBox.width * 0.06, y: y))
            gridPath.addLine(to: CGPoint(x: targetBox.maxX - targetBox.width * 0.06, y: y))
        }

        let lines = CAShapeLayer()
        lines.path = gridPath.cgPath
        lines.strokeColor = UIColor.black.withAlphaComponent(0.96).cgColor
        lines.fillColor = UIColor.clear.cgColor
        lines.lineWidth = max(5, min(targetBox.width, targetBox.height) * 0.026)
        lines.lineCap = .round
        lines.lineJoin = .round
        lines.shadowColor = UIColor.black.cgColor
        lines.shadowOpacity = 0.26
        lines.shadowRadius = 3
        lines.shadowOffset = .zero
        gridLayer.addSublayer(lines)
    }

    private func addCellSurface(in rect: CGRect) {
        let cellLayer = CAShapeLayer()
        cellLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 4).cgPath
        cellLayer.fillColor = UIColor(red: 1.00, green: 0.82, blue: 0.04, alpha: 0.88).cgColor
        cellLayer.strokeColor = UIColor.black.withAlphaComponent(phase == .setup ? 0.22 : 0.12).cgColor
        cellLayer.lineWidth = 1
        gridLayer.addSublayer(cellLayer)
    }

    private func addCornerBrackets() {
        let length = min(targetBox.width, targetBox.height) * 0.16
        let inset: CGFloat = 8
        let corners = [
            (CGPoint(x: targetBox.minX + inset, y: targetBox.minY + inset), CGFloat(0)),
            (CGPoint(x: targetBox.maxX - inset, y: targetBox.minY + inset), CGFloat.pi / 2),
            (CGPoint(x: targetBox.maxX - inset, y: targetBox.maxY - inset), CGFloat.pi),
            (CGPoint(x: targetBox.minX + inset, y: targetBox.maxY - inset), -CGFloat.pi / 2)
        ]

        for (origin, rotation) in corners {
            let path = UIBezierPath()
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: length, y: 0))
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: length))

            let bracket = CAShapeLayer()
            bracket.path = path.cgPath
            bracket.strokeColor = UIColor(red: 1.00, green: 0.84, blue: 0.05, alpha: phase == .setup ? 0.96 : 0.72).cgColor
            bracket.lineWidth = phase == .setup ? 4 : 2.8
            bracket.lineCap = .round
            bracket.shadowColor = UIColor.black.cgColor
            bracket.shadowOpacity = 0.48
            bracket.shadowRadius = 8
            bracket.shadowOffset = .zero
            bracket.position = origin
            bracket.transform = CATransform3DMakeRotation(rotation, 0, 0, 1)
            gridLayer.addSublayer(bracket)
        }
    }

    private func renderBreakingTile(cell: TicTacToeShootingVSCell, rect: CGRect, startedAt: Date) {
        let elapsed = Date().timeIntervalSince(startedAt)
        let progress = CGFloat(min(max(elapsed / 0.62, 0), 1))
        let eased = progress * progress * (3 - 2 * progress)
        let shardColor = UIColor.white.withAlphaComponent(max(0, 0.94 - 0.94 * progress)).cgColor
        let strokeColor = UIColor.black.withAlphaComponent(max(0, 0.48 - 0.48 * progress)).cgColor
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let shardPaths = shardPolygons(in: rect)

        for (index, path) in shardPaths.enumerated() {
            let direction = shardDirection(cell: cell, index: index)
            let layer = CAShapeLayer()
            layer.path = path.cgPath
            layer.fillColor = shardColor
            layer.strokeColor = strokeColor
            layer.lineWidth = 0.8
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            let distance = min(rect.width, rect.height) * (0.18 + CGFloat(index % 3) * 0.035)
            let translation = CGSize(width: direction.x * distance * eased, height: direction.y * distance * eased)
            let angle = direction.rotation * eased
            var transform = CATransform3DIdentity
            transform = CATransform3DTranslate(transform, translation.width, translation.height, 0)
            transform = CATransform3DRotate(transform, angle, 0, 0, 1)
            transform = CATransform3DScale(transform, 1 - 0.22 * eased, 1 - 0.22 * eased, 1)
            layer.transform = transform
            layer.opacity = Float(max(0, 1 - progress))
            gridLayer.addSublayer(layer)
        }

        let flash = CAShapeLayer()
        flash.path = UIBezierPath(roundedRect: rect.insetBy(dx: -2, dy: -2), cornerRadius: 5).cgPath
        flash.fillColor = UIColor.yellow.withAlphaComponent(max(0, 0.24 - 0.24 * progress)).cgColor
        flash.strokeColor = UIColor.white.withAlphaComponent(max(0, 0.84 - 0.84 * progress)).cgColor
        flash.lineWidth = 2
        flash.position = CGPoint(x: center.x - rect.midX, y: center.y - rect.midY)
        gridLayer.addSublayer(flash)
    }

    private func shardPolygons(in rect: CGRect) -> [UIBezierPath] {
        let points = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.midX, y: rect.midY),
            CGPoint(x: rect.maxX, y: rect.midY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.midX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        let triangles: [[CGPoint]] = [
            [points[0], points[1], points[4]],
            [points[0], points[4], points[3]],
            [points[1], points[2], points[5], points[4]],
            [points[3], points[4], points[7], points[6]],
            [points[4], points[5], points[8], points[7]],
            [points[6], points[7], points[8]]
        ]
        return triangles.map { polygon in
            let path = UIBezierPath()
            guard let first = polygon.first else {
                return path
            }
            path.move(to: first)
            for point in polygon.dropFirst() {
                path.addLine(to: point)
            }
            path.close()
            return path
        }
    }

    private func shardDirection(cell: TicTacToeShootingVSCell, index: Int) -> (x: CGFloat, y: CGFloat, rotation: CGFloat) {
        let seed = CGFloat((cell.index + 1) * (index + 2))
        let angle = seed * 1.37
        let x = cos(angle)
        let y = sin(angle)
        let rotation = (index.isMultiple(of: 2) ? 1 : -1) * (0.45 + CGFloat(index) * 0.08)
        return (x, y, rotation)
    }

    private func renderMark(_ mark: TicTacToeShootingVSMark, in rect: CGRect, alpha: CGFloat) {
        switch mark {
        case .x:
            renderXMark(in: rect, color: mark.color, alpha: alpha)
        case .o:
            renderOMark(in: rect, color: mark.color, alpha: alpha)
        }
    }

    private func renderXMark(in rect: CGRect, color: UIColor, alpha: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let markSize = min(rect.width, rect.height)
        let markRect = CGRect(
            x: center.x - markSize * 0.5,
            y: center.y - markSize * 0.5,
            width: markSize,
            height: markSize
        )
        let lineWidth = max(8, markSize * 0.16)
        let strokeInset = lineWidth * 0.5
        let pathRect = markRect.insetBy(dx: strokeInset, dy: strokeInset)
        let path = UIBezierPath()
        path.move(to: CGPoint(x: pathRect.minX, y: pathRect.minY))
        path.addLine(to: CGPoint(x: pathRect.maxX, y: pathRect.maxY))
        path.move(to: CGPoint(x: pathRect.maxX, y: pathRect.minY))
        path.addLine(to: CGPoint(x: pathRect.minX, y: pathRect.maxY))

        let layer = CAShapeLayer()
        layer.path = path.cgPath
        layer.strokeColor = color.withAlphaComponent(alpha).cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = lineWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.66
        layer.shadowRadius = 7
        layer.shadowOffset = .zero
        gridLayer.addSublayer(layer)
    }

    private func renderOMark(in rect: CGRect, color: UIColor, alpha: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let markSize = min(rect.width, rect.height)
        let markRect = CGRect(
            x: center.x - markSize * 0.5,
            y: center.y - markSize * 0.5,
            width: markSize,
            height: markSize
        )
        let lineWidth = max(8, markSize * 0.15)

        let layer = CAShapeLayer()
        layer.path = UIBezierPath(ovalIn: markRect.insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5)).cgPath
        layer.strokeColor = color.withAlphaComponent(alpha).cgColor
        layer.fillColor = UIColor.clear.cgColor
        layer.lineWidth = lineWidth
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.66
        layer.shadowRadius = 7
        layer.shadowOffset = .zero
        gridLayer.addSublayer(layer)
    }

    private func renderWinningLine(date: Date) {
        guard
            let winningLine,
            winningLine.count == 3,
            targetBox.width > 0,
            targetBox.height > 0
        else {
            return
        }

        let start = cellCenter(winningLine[0])
        let end = cellCenter(winningLine[2])
        let elapsed = winningLineStartedAt.map { date.timeIntervalSince($0) } ?? 1
        let progress = CGFloat(min(max(elapsed / 0.95, 0), 1))
        let eased = progress * progress * (3 - 2 * progress)
        let animatedEnd = CGPoint(
            x: start.x + (end.x - start.x) * eased,
            y: start.y + (end.y - start.y) * eased
        )
        let path = UIBezierPath()
        path.move(to: start)
        path.addLine(to: animatedEnd)

        let line = CAShapeLayer()
        line.path = path.cgPath
        line.strokeColor = UIColor(red: 1.00, green: 0.84, blue: 0.05, alpha: 1).cgColor
        line.lineWidth = max(8, min(targetBox.width, targetBox.height) * 0.045)
        line.lineCap = .round
        line.shadowColor = UIColor.black.cgColor
        line.shadowOpacity = 0.95
        line.shadowRadius = 7
        line.shadowOffset = .zero
        gridLayer.addSublayer(line)

        let inner = CAShapeLayer()
        inner.path = path.cgPath
        inner.strokeColor = UIColor.white.withAlphaComponent(0.92).cgColor
        inner.fillColor = UIColor.clear.cgColor
        inner.lineWidth = max(3, min(targetBox.width, targetBox.height) * 0.014)
        inner.lineCap = .round
        gridLayer.addSublayer(inner)
    }

    private func cellCenter(_ cell: TicTacToeShootingVSCell) -> CGPoint {
        CGPoint(
            x: targetBox.minX + (CGFloat(cell.column) + 0.5) * targetBox.width / 3,
            y: targetBox.minY + (CGFloat(cell.row) + 0.5) * targetBox.height / 3
        )
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
        guard let impact, let displayPoint = impact.displayPoint else {
            impactLayer.path = nil
            return
        }

        impactLayer.strokeColor = (impact.didBreakTile ? UIColor.yellow : UIColor.white).cgColor
        impactLayer.path = UIBezierPath(
            ovalIn: CGRect(x: displayPoint.x - 13, y: displayPoint.y - 13, width: 26, height: 26)
        ).cgPath
    }
}

private struct TicTacToeShootingVSHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.ballr(size: 14, weight: .black))
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.ballr(size: 34, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .frame(minWidth: 104, minHeight: 70, alignment: .trailing)
        .background(.black.opacity(0.66), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.82), lineWidth: 2)
        )
    }
}

private struct TicTacToeShootingVSTurnHudChip: View {
    let name: String
    let mark: TicTacToeShootingVSMark

    var body: some View {
        VStack(spacing: 3) {
            Text("TURN")
                .font(.ballr(size: 11, weight: .black))
                .foregroundStyle(.white.opacity(0.68))
            Text(name)
                .font(.ballr(size: 15, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
        .padding(.horizontal, 12)
        .frame(width: 142, height: 52)
        .background(.black.opacity(0.70), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke((mark == .x ? Color.yellow : Color.cyan).opacity(0.88), lineWidth: 2)
        )
    }
}

private struct TicTacToeShootingVSPlayerHudChip: View {
    let name: String
    let mark: TicTacToeShootingVSMark
    let isActive: Bool
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(mark.rawValue)
                .font(.ballr(size: 26, weight: .black))
                .foregroundStyle(tint)
            Text(name)
                .font(.ballr(size: 15, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 14)
        .frame(width: 142, height: 70, alignment: .leading)
        .background(.black.opacity(isActive ? 0.82 : 0.56), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(isActive ? 0.95 : 0.34), lineWidth: isActive ? 2.5 : 1.4)
        )
    }
}

private struct TicTacToeShootingVSCompletionOverlay: View {
    let result: TicTacToeShootingVSResult
    let canReplayShot: Bool
    let onReplayShot: () -> Void
    let onPlayAgain: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(result.winningMark?.rawValue ?? "=")
                    .font(.ballr(size: 48, weight: .black))
                    .foregroundStyle(result.winningMark == .o ? Color.cyan : Color.yellow)

                Text(result.headline.uppercased())
                    .font(.ballr(size: 26, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(result.summary)
                    .font(.ballr(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    if canReplayShot {
                        Button(action: onReplayShot) {
                            Text("REPLAY SHOT")
                                .font(.ballr(size: 14, weight: .black))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .frame(height: 42)
                                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    Button(action: onPlayAgain) {
                        Text("PLAY AGAIN")
                            .font(.ballr(size: 14, weight: .black))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 15)
                            .frame(height: 42)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button(action: onExit) {
                        Text("EXIT")
                            .font(.ballr(size: 14, weight: .black))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .frame(height: 42)
                            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.yellow.opacity(0.62), lineWidth: 2)
            )
            .padding(.horizontal, 24)
        }
    }
}

private enum TicTacToeShootingVSSoundPlayer {
    private static var glassBreakPlayer: AVAudioPlayer?

    static func playGlassBreak() {
        if glassBreakPlayer == nil {
            guard let url = Bundle.main.url(forResource: "shooting_zone_glass_break", withExtension: "wav") else {
                return
            }

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)

                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                glassBreakPlayer = player
            } catch {
                print("Tic Tac Toe ShootingVS glass break sound failed to load: \(error.localizedDescription)")
                return
            }
        }

        glassBreakPlayer?.stop()
        glassBreakPlayer?.currentTime = 0
        glassBreakPlayer?.play()
    }
}

private struct TicTacToeShootingVSLoadingOverlay: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
            Text("Starting Tic Tac Toe ShootingVS...")
                .font(.ballr(size: 16, weight: .black))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 20)
        .frame(height: 94)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TicTacToeShootingVSErrorOverlay: View {
    let message: String
    let permissionDenied: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Camera Unavailable")
                    .font(.ballr(size: 24, weight: .black))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.ballr(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.78))
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Button(action: onDismiss) {
                        Text("CLOSE")
                            .font(.ballr(size: 15, weight: .black))
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
                                .font(.ballr(size: 15, weight: .black))
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

private struct TicTacToeShootingVSFullscreenPromptOverlay: View {
    let message: String
    @State private var isPresented = false

    var body: some View {
        GeometryReader { geometry in
            let safeInsets = geometry.safeAreaInsets
            let safeTextWidth = max(geometry.size.width - safeInsets.leading - safeInsets.trailing - 96, 260)

            ZStack {
                Color.black.opacity(0.76)
                    .ignoresSafeArea()
                    .offset(y: isPresented ? 0 : geometry.size.height)

                Text(message)
                    .font(.ballr(size: min(max(geometry.size.width * 0.115, 50), 104), weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.58)
                    .frame(width: safeTextWidth)
                    .position(
                        x: safeInsets.leading + (geometry.size.width - safeInsets.leading - safeInsets.trailing) / 2,
                        y: geometry.size.height / 2
                    )
                    .offset(y: isPresented ? 0 : geometry.size.height * 0.38)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .onAppear {
                isPresented = false
                withAnimation(.easeOut(duration: 0.42)) {
                    isPresented = true
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
