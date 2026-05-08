import Combine
import Foundation
import SwiftUI
import UIKit

struct AgilityChallengeCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = AgilityPoseCameraController()
    @StateObject private var coordinator = AgilityChallengeCoordinator()
    @State private var showsQuitConfirmation = false

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

                AgilityChallengeRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                if coordinator.phase == .readiness || coordinator.phase == .countdown || coordinator.phase == .live {
                    VStack(spacing: 0) {
                        topBar
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .zIndex(100)
                }

                if cameraController.isStarting {
                    AgilityChallengeLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    AgilityChallengeErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.phase == .readiness, cameraController.errorMessage == nil {
                    AgilityChallengeReadinessOverlay(bodyFoundStartedAt: coordinator.bodyFoundStartedAt)
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                }

                if coordinator.phase == .finished {
                    AgilityChallengeFinishedOverlay(
                        scoreText: "\(coordinator.score)",
                        onPrimary: { coordinator.reset(in: geometry.size) },
                        onDone: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .ballrAwardsXPOnSuccess(coordinator.phase == .finished)
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
            .alert("Are you sure you want to quit the drill?", isPresented: $showsQuitConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Quit", role: .destructive) {
                    dismiss()
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                showsQuitConfirmation = true
            } label: {
                Image(systemName: "xmark")
                    .font(.ballr(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.58), in: Circle())
            }

            Spacer()

            HStack(spacing: 10) {
                AgilityChallengeHudChip(title: "CROSSES", value: "\(coordinator.score)", tint: .yellow)
                AgilityChallengeHudChip(title: "TIME", value: coordinator.timerText, tint: .orange)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 18)
    }
}

private enum AgilityChallengePhase {
    case readiness
    case countdown
    case live
    case finished
}

private enum AgilitySide {
    case left
    case right
}

private enum AgilityZone {
    case left
    case center
    case right
}

private final class AgilityChallengeCoordinator: ObservableObject {
    @Published private(set) var phase: AgilityChallengePhase = .readiness
    @Published private(set) var bodyFoundStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var timerText = "30"
    @Published private(set) var score = 0

    private let requiredBodyLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 30.0
    private let lostTrackingPromptFrameThreshold = 12
    private let leftLineFraction: CGFloat = 0.14
    private let rightLineFraction: CGFloat = 0.86

    private var size: CGSize = .zero
    private var liveElapsed: TimeInterval = 0
    private var lastStepAt: Date?
    private var lostTrackingFrameCount = 0
    private var armedSide: AgilitySide?
    private var lastZone: AgilityZone = .center
    private var displayedBody: AgilityDisplayedBody?
    private weak var renderView: AgilityChallengeRenderView?

    func attach(renderView: AgilityChallengeRenderView) {
        self.renderView = renderView
        renderView.update(
            body: displayedBody,
            prompt: promptText,
            activeSide: activeSide,
            leftLineX: leftLineX,
            rightLineX: rightLineX
        )
    }

    func tearDown() {}

    func reset(in size: CGSize) {
        self.size = size
        phase = .readiness
        bodyFoundStartedAt = nil
        countdownStartedAt = nil
        timerText = "30"
        score = 0
        liveElapsed = 0
        lastStepAt = nil
        lostTrackingFrameCount = 0
        armedSide = nil
        lastZone = .center
        displayedBody = nil
        renderView?.update(
            body: displayedBody,
            prompt: promptText,
            activeSide: activeSide,
            leftLineX: leftLineX,
            rightLineX: rightLineX
        )
    }

    func prepare(in size: CGSize) {
        self.size = resolvedGameplaySize(fallback: size)
        renderView?.update(
            body: displayedBody,
            prompt: promptText,
            activeSide: activeSide,
            leftLineX: leftLineX,
            rightLineX: rightLineX
        )
    }

    func handle(frame: AgilityChallengeFrame, cameraController: AgilityPoseCameraController) {
        let effectiveSize = resolvedGameplaySize(fallback: size)

        let trackedBody = frame.overlayState.trackedBody.flatMap { trackedBody -> AgilityDisplayedBody? in
            guard let center = cameraController.displayPoint(for: trackedBody.normalizedCenter) else {
                return nil
            }
            let radius = min(max(trackedBody.normalizedSpan * effectiveSize.width * 0.42, 26), 44)
            return AgilityDisplayedBody(center: center, radius: radius)
        }
        displayedBody = trackedBody

        let isTracking = trackedBody != nil
        if isTracking {
            lostTrackingFrameCount = 0
        } else if phase == .live {
            lostTrackingFrameCount += 1
        }

        guard phase != .finished else {
            renderView?.update(
                body: displayedBody,
                prompt: promptText,
                activeSide: activeSide,
                leftLineX: leftLineX,
                rightLineX: rightLineX
            )
            return
        }

        updateStartGate(isTracking: isTracking, timestamp: frame.timestamp)

        if phase == .live {
            let previousStepAt = lastStepAt ?? frame.timestamp
            let deltaTime = min(max(frame.timestamp.timeIntervalSince(previousStepAt), 0), 0.12)
            lastStepAt = frame.timestamp
            liveElapsed = min(liveElapsed + deltaTime, roundDuration)
            timerText = String(Int(ceil(max(roundDuration - liveElapsed, 0))))

            if let trackedBody {
                updateScore(using: trackedBody.center.x)
            } else {
                lastZone = .center
            }

            if liveElapsed >= roundDuration {
                phase = .finished
                BallrDrillSoundPlayer.playWinner()
            }
        }

        renderView?.update(
            body: displayedBody,
            prompt: promptText,
            activeSide: activeSide,
            leftLineX: leftLineX,
            rightLineX: rightLineX
        )
    }

    private func updateStartGate(isTracking: Bool, timestamp: Date) {
        if phase == .live || phase == .finished {
            return
        }

        if phase == .countdown {
            if
                let countdownStartedAt,
                timestamp.timeIntervalSince(countdownStartedAt) >= countdownDuration
            {
                phase = .live
                liveElapsed = 0
                lastStepAt = timestamp
                timerText = "30"
                score = 0
                armedSide = nil
                lastZone = .center
            }
            return
        }

        guard isTracking else {
            bodyFoundStartedAt = nil
            return
        }

        let startedAt = bodyFoundStartedAt ?? timestamp
        bodyFoundStartedAt = startedAt

        if timestamp.timeIntervalSince(startedAt) >= requiredBodyLockSeconds {
            countdownStartedAt = timestamp
            phase = .countdown
        }
    }

    private func updateScore(using centerX: CGFloat) {
        let zone = zone(for: centerX)
        guard zone != lastZone else {
            return
        }

        defer { lastZone = zone }

        switch zone {
        case .left:
            if armedSide == .left {
                score += 1
            }
            armedSide = .right
        case .right:
            if armedSide == .right {
                score += 1
            }
            armedSide = .left
        case .center:
            break
        }
    }

    private func zone(for x: CGFloat) -> AgilityZone {
        if x <= leftLineX + 18 {
            return .left
        }
        if x >= rightLineX - 18 {
            return .right
        }
        return .center
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

    private var leftLineX: CGFloat {
        resolvedGameplaySize(fallback: size).width * leftLineFraction
    }

    private var rightLineX: CGFloat {
        resolvedGameplaySize(fallback: size).width * rightLineFraction
    }

    private var activeSide: AgilitySide? {
        guard phase == .live else {
            return nil
        }
        return armedSide
    }

    private var promptText: String? {
        if phase == .live, lostTrackingFrameCount >= lostTrackingPromptFrameThreshold {
            return "Find your body"
        }

        guard phase == .live else {
            return nil
        }

        switch armedSide {
        case .left:
            return "Reach LEFT"
        case .right:
            return "Reach RIGHT"
        case .none:
            return "Touch either side to start"
        }
    }
}

private struct AgilityChallengeRenderSurface: UIViewRepresentable {
    let coordinator: AgilityChallengeCoordinator

    func makeUIView(context: Context) -> AgilityChallengeRenderView {
        let view = AgilityChallengeRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: AgilityChallengeRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class AgilityChallengeRenderView: UIView {
    private var body: AgilityDisplayedBody?
    private var prompt: String?
    private var activeSide: AgilitySide?
    private var leftLineX: CGFloat = 0
    private var rightLineX: CGFloat = 0

    private let promptLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        promptLabel.font = .systemFont(ofSize: 16, weight: .black)
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.backgroundColor = UIColor.black.withAlphaComponent(0.68)
        promptLabel.layer.cornerRadius = 10
        promptLabel.layer.masksToBounds = true
        promptLabel.isHidden = true
        addSubview(promptLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        body: AgilityDisplayedBody?,
        prompt: String?,
        activeSide: AgilitySide?,
        leftLineX: CGFloat,
        rightLineX: CGFloat
    ) {
        self.body = body
        self.prompt = prompt
        self.activeSide = activeSide
        self.leftLineX = leftLineX
        self.rightLineX = rightLineX
        promptLabel.text = prompt
        promptLabel.isHidden = prompt == nil
        setNeedsLayout()
        setNeedsDisplay()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        promptLabel.frame = CGRect(
            x: max((bounds.width - 220) * 0.5, 16),
            y: 84,
            width: min(220, bounds.width - 32),
            height: 38
        )
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        drawLanes(in: context)
        drawBodyMarker(in: context)
    }

    private func drawLanes(in context: CGContext) {
        let topY = bounds.height * 0.16
        let bottomY = bounds.height * 0.90

        drawLane(at: leftLineX, isActive: activeSide == .left, in: context, topY: topY, bottomY: bottomY)
        drawLane(at: rightLineX, isActive: activeSide == .right, in: context, topY: topY, bottomY: bottomY)
    }

    private func drawLane(
        at x: CGFloat,
        isActive: Bool,
        in context: CGContext,
        topY: CGFloat,
        bottomY: CGFloat
    ) {
        guard x > 0 else {
            return
        }

        let glowColor = isActive ? UIColor.systemYellow.withAlphaComponent(0.42) : UIColor.white.withAlphaComponent(0.14)
        context.saveGState()
        context.setShadow(offset: .zero, blur: isActive ? 20 : 12, color: glowColor.cgColor)
        context.setStrokeColor(glowColor.cgColor)
        context.setLineWidth(isActive ? 10 : 8)
        context.move(to: CGPoint(x: x, y: topY))
        context.addLine(to: CGPoint(x: x, y: bottomY))
        context.strokePath()
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor((isActive ? UIColor.systemOrange : UIColor.white.withAlphaComponent(0.48)).cgColor)
        context.setLineWidth(3)
        context.setLineDash(phase: 0, lengths: [14, 10])
        context.move(to: CGPoint(x: x, y: topY))
        context.addLine(to: CGPoint(x: x, y: bottomY))
        context.strokePath()
        context.restoreGState()
    }

    private func drawBodyMarker(in context: CGContext) {
        guard let body else {
            return
        }

        let center = body.center
        let radius = body.radius
        let outerRect = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let innerRect = outerRect.insetBy(dx: radius * 0.28, dy: radius * 0.28)

        context.saveGState()
        context.setShadow(offset: .zero, blur: 28, color: UIColor.systemYellow.withAlphaComponent(0.55).cgColor)
        UIColor.systemYellow.withAlphaComponent(0.22).setFill()
        UIBezierPath(ovalIn: outerRect).fill()
        context.restoreGState()

        UIColor.systemOrange.withAlphaComponent(0.88).setFill()
        UIBezierPath(ovalIn: innerRect).fill()

        UIColor.white.withAlphaComponent(0.70).setFill()
        UIBezierPath(
            ovalIn: CGRect(
                x: center.x - radius * 0.18,
                y: center.y - radius * 0.42,
                width: radius * 0.36,
                height: radius * 0.22
            )
        )
        .fill()
    }
}

private struct AgilityDisplayedBody {
    let center: CGPoint
    let radius: CGFloat
}

private struct AgilityChallengeHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.ballr(size: 10, weight: .black))
                .foregroundStyle(.white.opacity(0.72))
            Text(value)
                .font(.ballr(size: 24, weight: .black))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct AgilityChallengeLoadingOverlay: View {
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

private struct AgilityChallengeErrorOverlay: View {
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

private struct AgilityChallengeReadinessOverlay: View {
    let bodyFoundStartedAt: Date?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Text("KEEP THE BALL IN THE\nFRAME")
                    .font(.ballr(size: min(geometry.size.width * 0.058, 46), weight: .black))
                    .tracking(1.4)
                    .lineSpacing(13)
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .shadow(color: .white.opacity(0.18), radius: 1, x: 0, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                BallrJeffCameraOverlay()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }
}

private struct AgilityChallengeFinishedOverlay: View {
    let scoreText: String
    let onPrimary: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.90)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("TIME")
                    .font(.ballr(size: 36, weight: .black))
                    .foregroundStyle(.yellow)

                Text("You crossed the full distance \(scoreText) times.")
                    .font(.ballr(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.86))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                HStack(spacing: 14) {
                    Button("DONE", action: onDone)
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 130, height: 56)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    Button("PLAY AGAIN", action: onPrimary)
                        .font(.ballr(size: 18, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 170, height: 56)
                        .background(.yellow, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(30)
        }
    }
}
