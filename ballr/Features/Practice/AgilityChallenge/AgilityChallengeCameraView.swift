import Combine
import Foundation
import SwiftUI
import UIKit

struct AgilityChallengeCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = AgilityPoseCameraController()
    @StateObject private var coordinator = AgilityChallengeCoordinator()
    @State private var showsQuitConfirmation = false
    @State private var showsNextLevel = false

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
                    PracticeLevelCompletionOverlay(
                        startedAt: coordinator.finishStartedAt,
                        buttonsVisible: coordinator.showsFinishButtons,
                        showsNextLevelButton: true,
                        onNextLevel: { showsNextLevel = true },
                        onTryAgain: { coordinator.reset(in: geometry.size) },
                        onBackToLevels: { dismiss() }
                    )
                }
            }
            .ballrCameraPresentationChrome()
            .ballrAwardsXPOnSuccess(coordinator.phase == .finished)
            .navigationDestination(isPresented: $showsNextLevel) {
                LevelSevenCameraView()
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
    @Published private(set) var finishStartedAt: Date?
    @Published private(set) var showsFinishButtons = false

    private let requiredBodyLockSeconds: TimeInterval = 3.0
    private let countdownDuration: TimeInterval = 4.0
    private let roundDuration: TimeInterval = 30.0
    private let finishAnimationDuration: TimeInterval = 2.05
    private let finishButtonRevealDelay: TimeInterval = 0.28
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
    private var hitFlashSide: AgilitySide?
    private var hitFlashStartedAt: Date?
    private weak var renderView: AgilityChallengeRenderView?
    private var finishWorkItem: DispatchWorkItem?

    func attach(renderView: AgilityChallengeRenderView) {
        self.renderView = renderView
        renderView.update(
            body: displayedBody,
            prompt: promptText,
            activeSide: activeSide,
            hitFlashSide: hitFlashSide,
            hitFlashStartedAt: hitFlashStartedAt,
            leftLineX: leftLineX,
            rightLineX: rightLineX
        )
    }

    func tearDown() {
        cancelFinishWorkItem()
    }

    func reset(in size: CGSize) {
        cancelFinishWorkItem()
        self.size = size
        phase = .readiness
        bodyFoundStartedAt = nil
        countdownStartedAt = nil
        timerText = "30"
        score = 0
        finishStartedAt = nil
        showsFinishButtons = false
        liveElapsed = 0
        lastStepAt = nil
        lostTrackingFrameCount = 0
        armedSide = nil
        lastZone = .center
        displayedBody = nil
        hitFlashSide = nil
        hitFlashStartedAt = nil
        renderView?.update(
            body: displayedBody,
            prompt: promptText,
            activeSide: activeSide,
            hitFlashSide: hitFlashSide,
            hitFlashStartedAt: hitFlashStartedAt,
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
            hitFlashSide: hitFlashSide,
            hitFlashStartedAt: hitFlashStartedAt,
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
                hitFlashSide: hitFlashSide,
                hitFlashStartedAt: hitFlashStartedAt,
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
                finish(at: frame.timestamp)
            }
        }

        renderView?.update(
            body: displayedBody,
            prompt: promptText,
            activeSide: activeSide,
            hitFlashSide: hitFlashSide,
            hitFlashStartedAt: hitFlashStartedAt,
            leftLineX: leftLineX,
            rightLineX: rightLineX
        )
    }

    private func finish(at timestamp: Date) {
        guard phase != .finished else {
            return
        }

        phase = .finished
        finishStartedAt = timestamp
        BallrDrillSoundPlayer.playWinner()

        let workItem = DispatchWorkItem { [weak self] in
            self?.showsFinishButtons = true
        }
        finishWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + finishAnimationDuration + finishButtonRevealDelay,
            execute: workItem
        )
    }

    private func cancelFinishWorkItem() {
        finishWorkItem?.cancel()
        finishWorkItem = nil
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
                registerHitFlash(side: .left)
            }
            armedSide = .right
        case .right:
            if armedSide == .right {
                score += 1
                registerHitFlash(side: .right)
            }
            armedSide = .left
        case .center:
            break
        }
    }

    private func registerHitFlash(side: AgilitySide) {
        hitFlashSide = side
        hitFlashStartedAt = Date()
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
    private var hitFlashSide: AgilitySide?
    private var hitFlashStartedAt: Date?
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
        hitFlashSide: AgilitySide?,
        hitFlashStartedAt: Date?,
        leftLineX: CGFloat,
        rightLineX: CGFloat
    ) {
        self.body = body
        self.prompt = prompt
        self.activeSide = activeSide
        self.hitFlashSide = hitFlashSide
        self.hitFlashStartedAt = hitFlashStartedAt
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

        drawZones(in: context, date: Date())
    }

    private func drawZones(in context: CGContext, date: Date) {
        let leftZoneMaxX = min(bounds.width * 0.48, leftLineX + 18)
        let rightZoneMinX = max(bounds.width * 0.52, rightLineX - 18)

        drawEdgeZone(
            rect: CGRect(x: 0, y: 0, width: max(leftZoneMaxX, 0), height: bounds.height),
            side: .left,
            isActive: activeSide == .left,
            date: date,
            in: context
        )
        drawEdgeZone(
            rect: CGRect(x: rightZoneMinX, y: 0, width: max(bounds.width - rightZoneMinX, 0), height: bounds.height),
            side: .right,
            isActive: activeSide == .right,
            date: date,
            in: context
        )
    }

    private func drawEdgeZone(
        rect: CGRect,
        side: AgilitySide,
        isActive: Bool,
        date: Date,
        in context: CGContext
    ) {
        guard rect.width > 1, rect.height > 1 else {
            return
        }

        let green = UIColor.systemGreen
        let pulse = isActive ? CGFloat((sin(date.timeIntervalSinceReferenceDate * 8.0) + 1) * 0.5) : 0
        let hitFlash = hitFlashProgress(for: side, at: date)
        let intensity = max(isActive ? 0.48 + pulse * 0.34 : 0, hitFlash)
        let baseAlpha: CGFloat = isActive ? 0.28 + pulse * 0.08 : 0.14
        let edgeAlpha: CGFloat = min(0.86, (isActive ? 0.56 + pulse * 0.18 : 0.28) + hitFlash * 0.28)
        let mistAlpha: CGFloat = min(0.62, (isActive ? 0.28 + pulse * 0.12 : 0.12) + hitFlash * 0.22)

        context.saveGState()

        let colors: [CGColor]
        let startPoint: CGPoint
        let endPoint: CGPoint
        switch side {
        case .left:
            colors = [
                green.withAlphaComponent(edgeAlpha).cgColor,
                green.withAlphaComponent(baseAlpha).cgColor,
                green.withAlphaComponent(0.02).cgColor
            ]
            startPoint = CGPoint(x: rect.minX, y: rect.midY)
            endPoint = CGPoint(x: rect.maxX, y: rect.midY)
        case .right:
            colors = [
                green.withAlphaComponent(0.02).cgColor,
                green.withAlphaComponent(baseAlpha).cgColor,
                green.withAlphaComponent(edgeAlpha).cgColor
            ]
            startPoint = CGPoint(x: rect.minX, y: rect.midY)
            endPoint = CGPoint(x: rect.maxX, y: rect.midY)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 0.52, 1.0]) {
            context.clip(to: rect)
            context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        }
        context.restoreGState()

        drawZoneMist(in: rect, side: side, isActive: isActive, alpha: mistAlpha, date: date, context: context)
        drawRoughZoneEdge(in: rect, side: side, intensity: intensity, date: date, context: context)

        context.saveGState()
        context.setShadow(offset: .zero, blur: 24 + intensity * 34, color: green.withAlphaComponent(0.18 + intensity * 0.44).cgColor)
        context.setFillColor(green.withAlphaComponent((isActive ? 0.12 : 0.06) + hitFlash * 0.16).cgColor)
        context.fill(rect)
        context.restoreGState()
    }

    private func drawZoneMist(
        in rect: CGRect,
        side: AgilitySide,
        isActive: Bool,
        alpha: CGFloat,
        date: Date,
        context: CGContext
    ) {
        let green = UIColor.systemGreen
        let drift = CGFloat(sin(date.timeIntervalSinceReferenceDate * 1.7))
        let mistCenters: [(CGFloat, CGFloat, CGFloat)] = [
            (0.10, 0.18, 34),
            (0.34, 0.30, 48),
            (0.20, 0.48, 42),
            (0.46, 0.63, 56),
            (0.16, 0.78, 38),
            (0.38, 0.88, 46)
        ]

        context.saveGState()
        context.clip(to: rect.insetBy(dx: -18, dy: 0))
        for (xFraction, yFraction, radius) in mistCenters {
            let mirroredXFraction = side == .left ? xFraction : 1 - xFraction
            let center = CGPoint(
                x: rect.minX + rect.width * mirroredXFraction + drift * 5,
                y: rect.minY + rect.height * yFraction
            )
            let adjustedRadius = radius * (isActive ? 1.18 : 1.0)
            let circleRect = CGRect(
                x: center.x - adjustedRadius,
                y: center.y - adjustedRadius,
                width: adjustedRadius * 2,
                height: adjustedRadius * 2
            )
            context.setShadow(offset: .zero, blur: adjustedRadius * 0.45, color: green.withAlphaComponent(alpha).cgColor)
            context.setFillColor(green.withAlphaComponent(alpha * 0.42).cgColor)
            context.fillEllipse(in: circleRect)
        }
        context.restoreGState()
    }

    private func drawRoughZoneEdge(
        in rect: CGRect,
        side: AgilitySide,
        intensity: CGFloat,
        date: Date,
        context: CGContext
    ) {
        let green = UIColor.systemGreen
        let edgeX = side == .left ? rect.maxX : rect.minX
        let direction: CGFloat = side == .left ? 1 : -1
        let roughWidth = max(42, bounds.width * 0.055)
        let rowHeight = max(42, bounds.height / 11)

        context.saveGState()
        context.clip(to: bounds.insetBy(dx: -roughWidth, dy: 0))

        for index in 0..<13 {
            let fraction = CGFloat(index) / 12
            let wave = CGFloat(sin(date.timeIntervalSinceReferenceDate * 2.4 + Double(index) * 1.17))
            let notch = CGFloat(sin(Double(index) * 2.31)) * roughWidth * 0.20
            let center = CGPoint(
                x: edgeX + direction * (roughWidth * (0.22 + 0.42 * abs(wave)) + notch),
                y: rect.minY + rect.height * fraction
            )
            let radiusX = roughWidth * (0.72 + 0.26 * abs(wave))
            let radiusY = rowHeight * (0.76 + 0.22 * CGFloat(cos(Double(index) * 1.9)))
            let alpha = (0.10 + intensity * 0.22) * (0.82 + 0.18 * abs(wave))
            let mistRect = CGRect(
                x: center.x - radiusX,
                y: center.y - radiusY,
                width: radiusX * 2,
                height: radiusY * 2
            )
            context.setShadow(offset: .zero, blur: 18 + intensity * 28, color: green.withAlphaComponent(alpha).cgColor)
            context.setFillColor(green.withAlphaComponent(alpha * 0.34).cgColor)
            context.fillEllipse(in: mistRect)
        }

        let edgeGlowRect = CGRect(
            x: side == .left ? edgeX - roughWidth * 0.35 : edgeX - roughWidth * 0.65,
            y: rect.minY,
            width: roughWidth,
            height: rect.height
        )
        let colors: [CGColor]
        if side == .left {
            colors = [
                green.withAlphaComponent(0.00).cgColor,
                green.withAlphaComponent(0.12 + intensity * 0.30).cgColor,
                green.withAlphaComponent(0.00).cgColor
            ]
        } else {
            colors = [
                green.withAlphaComponent(0.00).cgColor,
                green.withAlphaComponent(0.12 + intensity * 0.30).cgColor,
                green.withAlphaComponent(0.00).cgColor
            ]
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: [0.0, 0.45, 1.0]) {
            context.clip(to: edgeGlowRect)
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: edgeGlowRect.minX, y: edgeGlowRect.midY),
                end: CGPoint(x: edgeGlowRect.maxX, y: edgeGlowRect.midY),
                options: []
            )
        }
        context.restoreGState()
    }

    private func hitFlashProgress(for side: AgilitySide, at date: Date) -> CGFloat {
        guard hitFlashSide == side, let hitFlashStartedAt else {
            return 0
        }
        let elapsed = date.timeIntervalSince(hitFlashStartedAt)
        guard elapsed >= 0, elapsed < 0.62 else {
            return 0
        }
        let progress = CGFloat(elapsed / 0.62)
        return pow(1 - progress, 0.45)
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
        Color.clear
            .ignoresSafeArea()
            .allowsHitTesting(false)
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
