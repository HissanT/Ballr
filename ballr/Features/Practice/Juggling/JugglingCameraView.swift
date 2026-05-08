import AVFoundation
import Combine
import Foundation
import SwiftUI
import UIKit

struct JugglingCameraView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var cameraController = JugglingCameraController()
    @StateObject private var coordinator = JugglingCoordinator()
    @State private var showsQuitConfirmation = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .ignoresSafeArea()

                BallTrackerPreviewLayerView(previewLayer: cameraController.previewLayer)
                    .ignoresSafeArea()

                Color.black.opacity(0.16)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                JugglingRenderSurface(coordinator: coordinator)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                    Spacer()
                }
                .padding(.vertical, 14)
                .zIndex(100)

                if cameraController.isStarting {
                    JugglingLoadingOverlay()
                }

                if let errorMessage = cameraController.errorMessage {
                    JugglingErrorOverlay(
                        message: errorMessage,
                        permissionDenied: cameraController.permissionDenied,
                        onDismiss: { dismiss() }
                    )
                }

                if coordinator.phase == .readiness, cameraController.errorMessage == nil {
                    JugglingReadinessOverlay(readyStartedAt: coordinator.readyStartedAt)
                }

                if coordinator.phase == .countdown, let countdownStartedAt = coordinator.countdownStartedAt {
                    BallrDrillCountdownOverlay(startedAt: countdownStartedAt)
                }
        }
        .ballrCameraPresentationChrome()
        .ballrAwardsXPOnSuccess(coordinator.juggleCount >= 10)
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
                JugglingHudChip(title: "JUGGLES", value: "\(coordinator.juggleCount)", tint: .yellow)

                Text(coordinator.statusText)
                    .font(.ballr(size: 12, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 18)
    }
}

enum JugglingPhase {
    case readiness
    case countdown
    case live
}

private final class JugglingCoordinator: ObservableObject {
    @Published private(set) var phase: JugglingPhase = .readiness
    @Published private(set) var readyStartedAt: Date?
    @Published private(set) var countdownStartedAt: Date?
    @Published private(set) var juggleCount = 0
    @Published private(set) var statusText = "SEARCHING"

    private let requiredReadyLockSeconds: TimeInterval = 1.2
    private let countdownDuration: TimeInterval = 4.0
    private let lostBallPromptFrameThreshold = 8
    private let lostBodyPromptFrameThreshold = 12

    private var size: CGSize = .zero
    private var lostBallFrameCount = 0
    private var lostBodyFrameCount = 0
    private var ballDisplayRect: CGRect?
    private var detectedBody: JugglingDetectedBody?
    private var gameState = JugglingCounterState()
    private weak var renderView: JugglingRenderView?

    func attach(renderView: JugglingRenderView) {
        self.renderView = renderView
        renderView.update(
            ballDisplayRect: ballDisplayRect,
            isBallTracked: false,
            body: detectedBody,
            highlightedKind: highlightedKind,
            debugEventText: gameState.debugEventText,
            prompt: promptText
        )
    }

    func tearDown() {}

    func reset(in size: CGSize) {
        self.size = resolvedGameplaySize(fallback: size)
        phase = .readiness
        readyStartedAt = nil
        countdownStartedAt = nil
        juggleCount = 0
        statusText = "SEARCHING"
        lostBallFrameCount = 0
        lostBodyFrameCount = 0
        ballDisplayRect = nil
        detectedBody = nil
        gameState.reset()
        renderView?.update(
            ballDisplayRect: nil,
            isBallTracked: false,
            body: nil,
            highlightedKind: nil,
            debugEventText: gameState.debugEventText,
            prompt: promptText
        )
    }

    func prepare(in size: CGSize) {
        self.size = resolvedGameplaySize(fallback: size)
        renderView?.update(
            ballDisplayRect: ballDisplayRect,
            isBallTracked: false,
            body: detectedBody,
            highlightedKind: highlightedKind,
            debugEventText: gameState.debugEventText,
            prompt: promptText
        )
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

        if phase == .live {
            switch gameState.step(
                ballDisplayRect: rawBallRect,
                body: body,
                timestamp: frame.timestamp,
                isBallTracked: isBallTracked
            ) {
            case .counted(let kind):
                juggleCount += 1
                JugglingSoundPlayer.playScore()
                if juggleCount.isMultiple(of: 10) {
                    BallrDrillSoundPlayer.playCombo()
                }
                renderView?.flash(kind: kind)
            case .ignoredGroundBounce:
                break
            case nil:
                break
            }
        } else {
            gameState.observe(
                ballDisplayRect: rawBallRect,
                body: body,
                timestamp: frame.timestamp,
                isBallTracked: isBallTracked
            )
        }

        renderView?.update(
            ballDisplayRect: ballDisplayRect,
            isBallTracked: isBallTracked,
            body: body,
            highlightedKind: highlightedKind,
            debugEventText: gameState.debugEventText,
            prompt: promptText
        )
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
    ) -> JugglingDetectedBody? {
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

        let envelopeRect = overlayState.normalizedEnvelopeRect.flatMap {
            cameraController.displayRect(for: $0)
        }
        return JugglingDetectedBody(
            points: points,
            confidences: confidences,
            envelopeRect: envelopeRect,
            bounds: size
        )
    }

    private func updateStatus(isBallTracked: Bool, hasBody: Bool) {
        let nextStatus: String
        if !isBallTracked {
            nextStatus = "FIND BALL"
        } else if !hasBody {
            nextStatus = "FIND PLAYER"
        } else {
            nextStatus = phase == .live ? "COUNTING" : "READY"
        }

        if statusText != nextStatus {
            statusText = nextStatus
        }
    }

    private func updateStartGate(isReady: Bool, timestamp: Date) {
        guard phase != .live else {
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
                gameState.start()
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

    private var highlightedKind: JugglingContactKind? {
        guard phase == .live else {
            return nil
        }
        return gameState.highlightedKind(at: Date())
    }

    private var promptText: String? {
        switch phase {
        case .readiness:
            return nil
        case .countdown:
            return nil
        case .live:
            if lostBallFrameCount >= lostBallPromptFrameThreshold {
                return "Find the ball"
            }
            if lostBodyFrameCount >= lostBodyPromptFrameThreshold {
                return "Stay in frame"
            }
            return nil
        }
    }
}

private struct JugglingRenderSurface: UIViewRepresentable {
    let coordinator: JugglingCoordinator

    func makeUIView(context: Context) -> JugglingRenderView {
        let view = JugglingRenderView()
        coordinator.attach(renderView: view)
        return view
    }

    func updateUIView(_ uiView: JugglingRenderView, context: Context) {
        coordinator.attach(renderView: uiView)
    }
}

private final class JugglingRenderView: UIView {
    private var ballDisplayRect: CGRect?
    private var isBallTracked = false
    private var body: JugglingDetectedBody?
    private var highlightedKind: JugglingContactKind?
    private var highlightUntil: Date?
    private var debugEventText: String?

    private let promptLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear

        promptLabel.font = .systemFont(ofSize: 20, weight: .black)
        promptLabel.textColor = .white
        promptLabel.textAlignment = .center
        promptLabel.backgroundColor = UIColor.black.withAlphaComponent(0.56)
        promptLabel.layer.cornerRadius = 8
        promptLabel.clipsToBounds = true
        promptLabel.alpha = 0
        addSubview(promptLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let labelWidth = min(bounds.width * 0.58, 260)
        promptLabel.frame = CGRect(
            x: (bounds.width - labelWidth) * 0.5,
            y: bounds.height - 82,
            width: labelWidth,
            height: 44
        )
    }

    func update(
        ballDisplayRect: CGRect?,
        isBallTracked: Bool,
        body: JugglingDetectedBody?,
        highlightedKind: JugglingContactKind?,
        debugEventText: String?,
        prompt: String?
    ) {
        self.ballDisplayRect = ballDisplayRect
        self.isBallTracked = isBallTracked
        self.body = body
        self.highlightedKind = highlightedKind ?? activeHighlightedKind()
        self.debugEventText = debugEventText

        if promptLabel.text != prompt {
            promptLabel.text = prompt
        }
        UIView.animate(withDuration: 0.15) {
            self.promptLabel.alpha = prompt == nil ? 0 : 1
        }

        setNeedsDisplay()
    }

    func flash(kind: JugglingContactKind) {
        highlightedKind = kind
        highlightUntil = Date().addingTimeInterval(0.18)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else {
            return
        }

        if let ballDisplayRect, isBallTracked {
            context.setStrokeColor(UIColor.systemYellow.cgColor)
            context.setLineWidth(3)
            context.strokeEllipse(in: ballDisplayRect.insetBy(dx: -3, dy: -3))
        }

        #if DEBUG
        if let body {
            if let envelopeRect = body.envelopeRect {
                context.setFillColor(UIColor.systemTeal.withAlphaComponent(0.08).cgColor)
                context.setStrokeColor(UIColor.systemTeal.withAlphaComponent(0.78).cgColor)
                context.setLineWidth(2.5)
                context.fill(envelopeRect)
                context.stroke(envelopeRect)
            }

            for zone in body.zones {
                let isHighlighted = zone.kind == activeHighlightedKind()
                context.setFillColor((isHighlighted ? UIColor.systemYellow : UIColor.systemGreen).withAlphaComponent(isHighlighted ? 0.22 : 0.10).cgColor)
                context.setStrokeColor((isHighlighted ? UIColor.systemYellow : UIColor.systemGreen).withAlphaComponent(0.70).cgColor)
                context.setLineWidth(isHighlighted ? 3 : 1.5)
                context.fill(zone.rect)
                context.stroke(zone.rect)
            }
        }

        if let debugEventText {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: BallrFont.uiFont(size: 14, weight: .bold),
                .foregroundColor: UIColor.white,
                .backgroundColor: UIColor.black.withAlphaComponent(0.55)
            ]
            debugEventText.draw(
                at: CGPoint(x: 18, y: bounds.height - 138),
                withAttributes: attributes
            )
        }
        #endif
    }

    private func activeHighlightedKind() -> JugglingContactKind? {
        guard let highlightUntil, Date() <= highlightUntil else {
            return nil
        }
        return highlightedKind
    }
}

private struct JugglingDetectedBody {
    let points: [JugglingBodyJoint: CGPoint]
    let confidences: [JugglingBodyJoint: CGFloat]
    let envelopeRect: CGRect?
    let zones: [JugglingContactZone]

    init?(
        points: [JugglingBodyJoint: CGPoint],
        confidences: [JugglingBodyJoint: CGFloat],
        envelopeRect: CGRect?,
        bounds: CGSize
    ) {
        self.points = points
        self.confidences = confidences
        self.envelopeRect = envelopeRect?.intersection(Self.boundsRect(for: bounds))
        self.zones = Self.makeZones(points: points, confidences: confidences, bounds: bounds)

        guard !zones.isEmpty || self.envelopeRect != nil else {
            return nil
        }
    }

    private static func makeZones(
        points: [JugglingBodyJoint: CGPoint],
        confidences: [JugglingBodyJoint: CGFloat],
        bounds: CGSize
    ) -> [JugglingContactZone] {
        var zones: [JugglingContactZone] = []
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
        side: JugglingBodySide,
        ankleJoint: JugglingBodyJoint,
        kneeJoint: JugglingBodyJoint,
        hipJoint: JugglingBodyJoint,
        points: [JugglingBodyJoint: CGPoint],
        confidences: [JugglingBodyJoint: CGFloat],
        bounds: CGSize,
        zones: inout [JugglingContactZone]
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
                    JugglingContactZone(
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
                    JugglingContactZone(
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
                    JugglingContactZone(
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

private enum JugglingBodySide {
    case left
    case right
}

private struct JugglingContactZone {
    let kind: JugglingContactKind
    let rect: CGRect
    let confidence: CGFloat
}

private enum JugglingContactKind: Hashable {
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

private enum JugglingCounterEvent {
    case counted(JugglingContactKind)
    case ignoredGroundBounce
}

private enum JugglingCounterDebugReason {
    case counted
    case likelyGroundBounce
    case noRebound
    case noContact
    case weakPlayerContact
    case cooldown

    var text: String {
        switch self {
        case .counted:
            return "counted"
        case .likelyGroundBounce:
            return "likelyGroundBounce"
        case .noRebound:
            return "noRebound"
        case .noContact:
            return "noContact"
        case .weakPlayerContact:
            return "weakPlayerContact"
        case .cooldown:
            return "cooldown"
        }
    }
}

private struct JugglingCounterState {
    private struct Sample {
        let rect: CGRect
        let center: CGPoint
        let diameter: CGFloat
        let timestamp: Date
        let velocity: CGVector?
    }

    private struct ContactEvidence {
        let kind: JugglingContactKind
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
    private let highlightDuration: TimeInterval = 0.18
    private let contactScoreThreshold: CGFloat = 0.24
    private let minimumFootOverlapRatio: CGFloat = 0.025
    private let strongFootProximityThreshold: CGFloat = 0.50

    private var samples: [Sample] = []
    private var pendingContact: PendingContact?
    private var lastCountedAt: Date?
    private var lastCountedKind: JugglingContactKind?
    private var lastDebugReason: JugglingCounterDebugReason?
    private var lastDebugReasonAt: Date?

    var debugEventText: String? {
        guard
            let lastDebugReason,
            let lastDebugReasonAt,
            Date().timeIntervalSince(lastDebugReasonAt) <= 0.9
        else {
            return nil
        }
        return lastDebugReason.text
    }

    mutating func start() {
        samples.removeAll()
        pendingContact = nil
    }

    mutating func reset() {
        samples.removeAll()
        pendingContact = nil
        lastCountedAt = nil
        lastCountedKind = nil
        lastDebugReason = nil
        lastDebugReasonAt = nil
    }

    mutating func observe(
        ballDisplayRect: CGRect?,
        body: JugglingDetectedBody?,
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
        body: JugglingDetectedBody?,
        timestamp: Date,
        isBallTracked: Bool
    ) -> JugglingCounterEvent? {
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
        body: JugglingDetectedBody?,
        timestamp: Date,
        isBallTracked: Bool,
        allowsCounting: Bool
    ) -> JugglingCounterEvent? {
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
            if allowsCounting {
                recordDebug(.noRebound, at: timestamp)
            }
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
            recordDebug(.likelyGroundBounce, at: timestamp)
            return .ignoredGroundBounce
        }

        guard isValidPlayerContact(resolvedContact, sample: sample) else {
            pendingContact = nil
            recordDebug(resolvedContact.kind.isFoot ? .weakPlayerContact : .noContact, at: timestamp)
            return .ignoredGroundBounce
        }

        guard timestamp.timeIntervalSince(lastCountedAt ?? .distantPast) >= countCooldown else {
            recordDebug(.cooldown, at: timestamp)
            return nil
        }

        lastCountedAt = timestamp
        lastCountedKind = resolvedContact.kind
        pendingContact = nil
        recordDebug(.counted, at: timestamp)
        return .counted(resolvedContact.kind)
    }

    func highlightedKind(at date: Date) -> JugglingContactKind? {
        guard
            let lastCountedAt,
            let lastCountedKind,
            date.timeIntervalSince(lastCountedAt) <= highlightDuration
        else {
            return nil
        }
        return lastCountedKind
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
        body: JugglingDetectedBody
    ) -> ContactEvidence? {
        body.zones
            .map { zone in
                contactEvidence(ballRect: ballRect, zone: zone)
            }
            .filter { $0.score >= contactScoreThreshold }
            .max(by: { $0.score < $1.score })
    }

    private func contactEvidence(ballRect: CGRect, zone: JugglingContactZone) -> ContactEvidence {
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

    private mutating func recordDebug(_ reason: JugglingCounterDebugReason, at timestamp: Date) {
        lastDebugReason = reason
        lastDebugReasonAt = timestamp
    }
}

private struct JugglingHudChip: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(title)
                .font(.ballr(size: 11, weight: .black))
                .foregroundStyle(.white.opacity(0.68))

            Text(value)
                .font(.ballr(size: 38, weight: .black))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct JugglingLoadingOverlay: View {
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

private struct JugglingErrorOverlay: View {
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

private struct JugglingReadinessOverlay: View {
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

                    Text("Keep your lower body and the ball in frame.")
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

private enum JugglingSoundPlayer {
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
            print("Juggling score sound failed: \(error.localizedDescription)")
            #endif
        }
    }
}
