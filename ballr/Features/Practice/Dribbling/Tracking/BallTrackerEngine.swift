import CoreGraphics
import Vision

struct BallTrackerOverlayState {
    let normalizedRect: CGRect?
    let rawNormalizedRect: CGRect?
    let confidence: Double?
    let candidateCount: Int
    let statusText: String
    let isTracking: Bool
    let centerPixels: CGPoint?
    let pixelSize: CGSize?
    let pixelDiameter: CGFloat?
    let confirmedFrames: Int
    let misses: Int

    static let idle = BallTrackerOverlayState(
        normalizedRect: nil,
        rawNormalizedRect: nil,
        confidence: nil,
        candidateCount: 0,
        statusText: "Searching",
        isTracking: false,
        centerPixels: nil,
        pixelSize: nil,
        pixelDiameter: nil,
        confirmedFrames: 0,
        misses: 0
    )
}

final class BallTrackerEngine {
    private struct Candidate {
        let normalizedRect: CGRect
        let center: CGPoint
        let size: CGSize
        let radius: CGFloat
        let confidence: CGFloat

        func pixelCenter(in frameSize: CGSize) -> CGPoint {
            CGPoint(x: center.x * frameSize.width, y: center.y * frameSize.height)
        }

        func pixelSize(in frameSize: CGSize) -> CGSize {
            CGSize(width: size.width * frameSize.width, height: size.height * frameSize.height)
        }

        func pixelDiameter(in frameSize: CGSize) -> CGFloat {
            let resolvedSize = pixelSize(in: frameSize)
            return max(resolvedSize.width, resolvedSize.height)
        }
    }

    private struct Track {
        var normalizedRect: CGRect
        var rawNormalizedRect: CGRect?
        var center: CGPoint
        var size: CGSize
        var velocity: CGVector
        var radius: CGFloat
        var confidence: CGFloat
        var misses: Int
        var confirmedFrames: Int
        var nis: CGFloat
        var vyRaw: CGFloat?

        func pixelCenter(in frameSize: CGSize) -> CGPoint {
            CGPoint(x: center.x * frameSize.width, y: center.y * frameSize.height)
        }

        func pixelSize(in frameSize: CGSize) -> CGSize {
            CGSize(width: size.width * frameSize.width, height: size.height * frameSize.height)
        }

        func pixelDiameter(in frameSize: CGSize) -> CGFloat {
            let resolvedSize = pixelSize(in: frameSize)
            return max(resolvedSize.width, resolvedSize.height)
        }
    }

    private struct MotionState {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat
        var vy: CGFloat
        var covariance: Matrix4
        var lastTime: TimeInterval
        var lastMeasurement: CGPoint?
        var lastMeasurementTime: TimeInterval?
        var contactCountdown: Int
        var nis: CGFloat
        var vyRaw: CGFloat?
    }

    private struct Matrix4 {
        var v: [CGFloat]

        static func initial(positionVariance: CGFloat, velocityVariance: CGFloat) -> Matrix4 {
            Matrix4(v: [
                positionVariance, 0, 0, 0,
                0, positionVariance, 0, 0,
                0, 0, velocityVariance, 0,
                0, 0, 0, velocityVariance
            ])
        }

        subscript(_ row: Int, _ col: Int) -> CGFloat {
            get { v[row * 4 + col] }
            set { v[row * 4 + col] = newValue }
        }

        func predicted(deltaFrames dt: CGFloat, sigmaA: CGFloat) -> Matrix4 {
            let f: [[CGFloat]] = [
                [1, 0, dt, 0],
                [0, 1, 0, dt],
                [0, 0, 1, 0],
                [0, 0, 0, 1]
            ]
            var result = Matrix4(v: Array(repeating: 0, count: 16))
            for row in 0..<4 {
                for col in 0..<4 {
                    var value: CGFloat = 0
                    for i in 0..<4 {
                        for j in 0..<4 {
                            value += f[row][i] * self[i, j] * f[col][j]
                        }
                    }
                    result[row, col] = value
                }
            }

            let sigma2 = sigmaA * sigmaA
            let dt2 = dt * dt
            let dt3 = dt2 * dt
            let dt4 = dt2 * dt2
            result[0, 0] += 0.25 * dt4 * sigma2
            result[0, 2] += 0.5 * dt3 * sigma2
            result[2, 0] += 0.5 * dt3 * sigma2
            result[2, 2] += dt2 * sigma2
            result[1, 1] += 0.25 * dt4 * sigma2
            result[1, 3] += 0.5 * dt3 * sigma2
            result[3, 1] += 0.5 * dt3 * sigma2
            result[3, 3] += dt2 * sigma2
            return result.symmetrized()
        }

        func kalmanGain(inv00: CGFloat, inv01: CGFloat, inv10: CGFloat, inv11: CGFloat) -> KalmanGain {
            KalmanGain(
                k00: self[0, 0] * inv00 + self[0, 1] * inv10,
                k01: self[0, 0] * inv01 + self[0, 1] * inv11,
                k10: self[1, 0] * inv00 + self[1, 1] * inv10,
                k11: self[1, 0] * inv01 + self[1, 1] * inv11,
                k20: self[2, 0] * inv00 + self[2, 1] * inv10,
                k21: self[2, 0] * inv01 + self[2, 1] * inv11,
                k30: self[3, 0] * inv00 + self[3, 1] * inv10,
                k31: self[3, 0] * inv01 + self[3, 1] * inv11
            )
        }

        func updated(gain: KalmanGain) -> Matrix4 {
            let gains: [[CGFloat]] = [
                [gain.k00, gain.k01],
                [gain.k10, gain.k11],
                [gain.k20, gain.k21],
                [gain.k30, gain.k31]
            ]
            var result = self
            for row in 0..<4 {
                for col in 0..<4 {
                    result[row, col] = self[row, col] - gains[row][0] * self[0, col] - gains[row][1] * self[1, col]
                }
            }
            return result.symmetrized()
        }

        func symmetrized() -> Matrix4 {
            var result = self
            for row in 0..<4 {
                for col in (row + 1)..<4 {
                    let value = (self[row, col] + self[col, row]) * 0.5
                    result[row, col] = value
                    result[col, row] = value
                }
            }
            return result
        }
    }

    private struct KalmanGain {
        let k00: CGFloat
        let k01: CGFloat
        let k10: CGFloat
        let k11: CGFloat
        let k20: CGFloat
        let k21: CGFloat
        let k30: CGFloat
        let k31: CGFloat
    }

    private let initConfidenceThreshold: CGFloat = 0.50
    private let reacquireConfidenceThreshold: CGFloat = 0.70
    private let maxMisses = 4
    private let referenceFPS: CGFloat = 30.0
    private let soccerBallDiameterMeters: CGFloat = 0.22
    private let measurementNoisePixels: CGFloat = 4.0
    private let processAccelNoiseNominal: CGFloat = 22.0
    private let processAccelNoiseContact: CGFloat = 200.0
    private let contactNISThreshold: CGFloat = 6.0
    private let contactHoldFrames = 3
    private let rawVelocityMinDelta: TimeInterval = 1.0 / 120.0
    private let initialPositionVariancePixels: CGFloat = 100.0
    private let initialVelocityVariancePixels: CGFloat = 50.0
    private let gravityMinPixelsPerFrameSquared: CGFloat = 0.75
    private let gravityMaxPixelsPerFrameSquared: CGFloat = 6.0
    private let sizeSmoothing: CGFloat = 0.60
    private let trackGateRadiusMultiplier: CGFloat = 5.0
    private let trackGateMinRadiusPixels: CGFloat = 55.0
    private let trackGateSpeedFactor: CGFloat = 1.5
    private let trackGateMissPenaltyPixels: CGFloat = 25.0
    private let trackScoreAcceptThreshold: CGFloat = 0.35
    private let scoreWeightConfidence: CGFloat = 0.55
    private let scoreWeightMotion: CGFloat = 0.35
    private let scoreWeightSize: CGFloat = 0.10
    private let proximityBonusGateFraction: CGFloat = 0.4
    private let proximityBonus: CGFloat = 0.05
    private let reacquireMinimumMisses = 2

    private var track: Track?
    private var motion: MotionState?

    func reset() {
        track = nil
        motion = nil
    }

    func process(
        observations: [VNRecognizedObjectObservation],
        frameSize: CGSize,
        timestamp: Date,
        config: BallTrackerConfig
    ) -> BallTrackerOverlayState {
        let resolvedFrameSize = CGSize(width: max(frameSize.width, 1), height: max(frameSize.height, 1))
        let minimumConfidence = CGFloat(config.ballrRuntimeDefaults.confidenceThreshold)
        let candidates = candidates(
            from: observations,
            minimumConfidence: minimumConfidence,
            acceptedLabels: config.acceptedBallLabels
        )

        guard !candidates.isEmpty || track != nil else {
            motion = nil
            return .idle
        }

        let frameTime = timestamp.timeIntervalSinceReferenceDate
        predictTrack(frameTime: frameTime, frameSize: resolvedFrameSize)

        if let candidate = choosePrimaryCandidate(from: candidates, frameSize: resolvedFrameSize) {
            updateTrack(with: candidate, frameTime: frameTime, frameSize: resolvedFrameSize)
        } else {
            track = advanceTrack()
        }

        guard let track else {
            return BallTrackerOverlayState(
                normalizedRect: nil,
                rawNormalizedRect: nil,
                confidence: nil,
                candidateCount: candidates.count,
                statusText: "Searching",
                isTracking: false,
                centerPixels: nil,
                pixelSize: nil,
                pixelDiameter: nil,
                confirmedFrames: 0,
                misses: 0
            )
        }

        let pixelSize = track.pixelSize(in: resolvedFrameSize)
        return BallTrackerOverlayState(
            normalizedRect: track.normalizedRect,
            rawNormalizedRect: track.rawNormalizedRect,
            confidence: Double(track.confidence),
            candidateCount: candidates.count,
            statusText: track.misses == 0 ? "Tracking" : "Searching",
            isTracking: track.misses == 0,
            centerPixels: track.pixelCenter(in: resolvedFrameSize),
            pixelSize: pixelSize,
            pixelDiameter: max(pixelSize.width, pixelSize.height),
            confirmedFrames: track.confirmedFrames,
            misses: track.misses
        )
    }

    private func candidates(
        from observations: [VNRecognizedObjectObservation],
        minimumConfidence: CGFloat,
        acceptedLabels: Set<String>
    ) -> [Candidate] {
        observations.compactMap { observation in
            let topLabel = observation.labels.first
            let identifier = topLabel?.identifier.lowercased()
            let confidence = CGFloat(topLabel?.confidence ?? 0.0)

            if let identifier, !identifier.isEmpty, !acceptedLabels.contains(identifier) {
                return nil
            }

            guard confidence >= minimumConfidence else {
                return nil
            }

            let normalizedRect = trackerRect(fromVisionBoundingBox: observation.boundingBox)
            guard !normalizedRect.isNull, !normalizedRect.isEmpty else {
                return nil
            }

            return Candidate(
                normalizedRect: normalizedRect,
                center: CGPoint(x: normalizedRect.midX, y: normalizedRect.midY),
                size: normalizedRect.size,
                radius: max(normalizedRect.width, normalizedRect.height) * 0.5,
                confidence: confidence
            )
        }
    }

    private func choosePrimaryCandidate(from candidates: [Candidate], frameSize: CGSize) -> Candidate? {
        guard !candidates.isEmpty else {
            return nil
        }

        let strongest = candidates.max(by: { $0.confidence < $1.confidence })
        guard let track else {
            guard let strongest, strongest.confidence >= initConfidenceThreshold else {
                return nil
            }
            return strongest
        }

        let scoredCandidate = candidates
            .map { ($0, score(candidate: $0, track: track, frameSize: frameSize)) }
            .max(by: { $0.1 < $1.1 })

        if let scoredCandidate, scoredCandidate.1 >= trackScoreAcceptThreshold {
            return scoredCandidate.0
        }

        if
            track.misses >= reacquireMinimumMisses,
            let strongest,
            strongest.confidence >= reacquireConfidenceThreshold
        {
            return strongest
        }

        return nil
    }

    private func trackerRect(fromVisionBoundingBox boundingBox: CGRect) -> CGRect {
        // This model exports boxes in the same top-left normalized canvas the app
        // uses for preview mapping. Do not invert y here.
        CGRect(
            x: boundingBox.origin.x,
            y: boundingBox.origin.y,
            width: boundingBox.width,
            height: boundingBox.height
        )
        .standardized
        .intersection(unitRect)
    }

    private func score(candidate: Candidate, track: Track, frameSize: CGSize) -> CGFloat {
        let projectedCenter = track.center
        let distance = hypot(
            candidate.center.x - projectedCenter.x,
            candidate.center.y - projectedCenter.y
        )
        let gate = trackGateRadius(for: track, frameSize: frameSize)

        if distance > gate && candidate.confidence < reacquireConfidenceThreshold {
            return -1.0
        }

        let motionScore = max(0.0, 1.0 - distance / max(gate, 0.0001))
        let sizeDelta = abs(candidate.radius - track.radius) / max(track.radius, 0.0001)
        let sizeScore = max(0.0, 1.0 - sizeDelta)
        var score = (
            candidate.confidence * scoreWeightConfidence
            + motionScore * scoreWeightMotion
            + sizeScore * scoreWeightSize
        )

        if distance <= gate * proximityBonusGateFraction {
            score += proximityBonus
        }

        return score
    }

    private func trackGateRadius(for track: Track, frameSize: CGSize) -> CGFloat {
        let speed = hypot(track.velocity.dx, track.velocity.dy)
        let base = max(track.radius * trackGateRadiusMultiplier, trackGateMinRadiusPixels / frameSize.width)
        return base
            + speed * trackGateSpeedFactor
            + CGFloat(track.misses) * trackGateMissPenaltyPixels / frameSize.width
    }

    private func predictTrack(frameTime: TimeInterval, frameSize: CGSize) {
        guard let currentTrack = track else {
            motion = nil
            return
        }

        if motion == nil {
            motion = bootstrapMotionState(from: currentTrack, frameTime: frameTime, frameSize: frameSize)
        }
        guard var motion else {
            return
        }

        let deltaFrames = max(CGFloat(frameTime - motion.lastTime) * referenceFPS, 0.0)
        let gravityPixels = gravityFromRadius(currentTrack.radius, frameSize: frameSize)
        let gravityNormalized = gravityPixels / frameSize.height
        let sigmaA = (motion.contactCountdown > 0 ? processAccelNoiseContact : processAccelNoiseNominal) / frameSize.width

        if deltaFrames > 0 {
            motion.x += motion.vx * deltaFrames
            motion.y += motion.vy * deltaFrames + 0.5 * deltaFrames * deltaFrames * gravityNormalized
            motion.vy += deltaFrames * gravityNormalized
            motion.covariance = motion.covariance.predicted(deltaFrames: deltaFrames, sigmaA: sigmaA)
        }

        motion.lastTime = frameTime
        motion.contactCountdown = max(motion.contactCountdown - 1, 0)
        self.motion = motion

        let predictedRect = clampedRect(center: CGPoint(x: motion.x, y: motion.y), size: currentTrack.size)
        track = Track(
            normalizedRect: predictedRect,
            rawNormalizedRect: currentTrack.rawNormalizedRect,
            center: CGPoint(x: predictedRect.midX, y: predictedRect.midY),
            size: predictedRect.size,
            velocity: CGVector(dx: motion.vx, dy: motion.vy),
            radius: max(predictedRect.width, predictedRect.height) * 0.5,
            confidence: currentTrack.confidence,
            misses: currentTrack.misses,
            confirmedFrames: currentTrack.confirmedFrames,
            nis: motion.nis,
            vyRaw: motion.vyRaw
        )
    }

    private func updateTrack(with candidate: Candidate, frameTime: TimeInterval, frameSize: CGSize) {
        guard let existingTrack = track else {
            let newTrack = Track(
                normalizedRect: candidate.normalizedRect,
                rawNormalizedRect: candidate.normalizedRect,
                center: candidate.center,
                size: candidate.size,
                velocity: .zero,
                radius: candidate.radius,
                confidence: candidate.confidence,
                misses: 0,
                confirmedFrames: 1,
                nis: 0,
                vyRaw: nil
            )
            track = newTrack
            motion = MotionState(
                x: candidate.center.x,
                y: candidate.center.y,
                vx: 0,
                vy: 0,
                covariance: Matrix4.initial(
                    positionVariance: initialPositionVariancePixels / frameSize.width,
                    velocityVariance: initialVelocityVariancePixels / frameSize.width
                ),
                lastTime: frameTime,
                lastMeasurement: candidate.pixelCenter(in: frameSize),
                lastMeasurementTime: frameTime,
                contactCountdown: 0,
                nis: 0,
                vyRaw: nil
            )
            return
        }

        if motion == nil {
            motion = bootstrapMotionState(from: existingTrack, frameTime: frameTime, frameSize: frameSize)
        }
        guard var motion else {
            return
        }

        let measurement = candidate.center
        let innovationX = measurement.x - motion.x
        let innovationY = measurement.y - motion.y
        let measurementVarianceX = pow(measurementNoisePixels / frameSize.width, 2)
        let measurementVarianceY = pow(measurementNoisePixels / frameSize.height, 2)
        let s00 = motion.covariance[0, 0] + measurementVarianceX
        let s01 = motion.covariance[0, 1]
        let s10 = motion.covariance[1, 0]
        let s11 = motion.covariance[1, 1] + measurementVarianceY
        let determinant = s00 * s11 - s01 * s10
        let inv00: CGFloat
        let inv01: CGFloat
        let inv10: CGFloat
        let inv11: CGFloat

        if abs(determinant) > 0.0000001 {
            inv00 = s11 / determinant
            inv01 = -s01 / determinant
            inv10 = -s10 / determinant
            inv11 = s00 / determinant
        } else {
            inv00 = 1 / max(s00, 0.0000001)
            inv01 = 0
            inv10 = 0
            inv11 = 1 / max(s11, 0.0000001)
        }

        let nis = max(
            0,
            innovationX * (inv00 * innovationX + inv01 * innovationY)
            + innovationY * (inv10 * innovationX + inv11 * innovationY)
        )
        let gain = motion.covariance.kalmanGain(inv00: inv00, inv01: inv01, inv10: inv10, inv11: inv11)
        motion.x += gain.k00 * innovationX + gain.k01 * innovationY
        motion.y += gain.k10 * innovationX + gain.k11 * innovationY
        motion.vx += gain.k20 * innovationX + gain.k21 * innovationY
        motion.vy += gain.k30 * innovationX + gain.k31 * innovationY
        motion.covariance = motion.covariance.updated(gain: gain)

        let blendedSize = CGSize(
            width: mix(existingTrack.size.width, candidate.size.width, amount: sizeSmoothing),
            height: mix(existingTrack.size.height, candidate.size.height, amount: sizeSmoothing)
        )
        let smoothedRect = clampedRect(center: CGPoint(x: motion.x, y: motion.y), size: blendedSize)

        let candidatePixelCenter = candidate.pixelCenter(in: frameSize)
        var vyRaw = motion.vyRaw
        if let lastMeasurement = motion.lastMeasurement, let lastMeasurementTime = motion.lastMeasurementTime {
            let delta = max(frameTime - lastMeasurementTime, rawVelocityMinDelta)
            vyRaw = (candidatePixelCenter.y - lastMeasurement.y) / CGFloat(delta)
        }

        motion.lastMeasurement = candidatePixelCenter
        motion.lastMeasurementTime = frameTime
        motion.contactCountdown = nis >= contactNISThreshold ? contactHoldFrames : motion.contactCountdown
        motion.nis = nis
        motion.vyRaw = vyRaw
        self.motion = motion

        track = Track(
            normalizedRect: smoothedRect,
            rawNormalizedRect: candidate.normalizedRect,
            center: CGPoint(x: smoothedRect.midX, y: smoothedRect.midY),
            size: smoothedRect.size,
            velocity: CGVector(dx: motion.vx, dy: motion.vy),
            radius: max(smoothedRect.width, smoothedRect.height) * 0.5,
            confidence: candidate.confidence,
            misses: 0,
            confirmedFrames: existingTrack.confirmedFrames + 1,
            nis: nis,
            vyRaw: vyRaw
        )
    }

    private func advanceTrack() -> Track? {
        guard var track else {
            motion = nil
            return nil
        }

        track.misses += 1
        guard track.misses <= maxMisses else {
            motion = nil
            return nil
        }

        track.confidence *= 0.92
        return track
    }

    private func bootstrapMotionState(
        from track: Track,
        frameTime: TimeInterval,
        frameSize: CGSize
    ) -> MotionState {
        MotionState(
            x: track.center.x,
            y: track.center.y,
            vx: track.velocity.dx,
            vy: track.velocity.dy,
            covariance: Matrix4.initial(
                positionVariance: initialPositionVariancePixels / frameSize.width,
                velocityVariance: initialVelocityVariancePixels / frameSize.width
            ),
            lastTime: frameTime,
            lastMeasurement: nil,
            lastMeasurementTime: nil,
            contactCountdown: 0,
            nis: track.nis,
            vyRaw: track.vyRaw
        )
    }

    private func gravityFromRadius(_ radius: CGFloat, frameSize: CGSize) -> CGFloat {
        let pixelRadius = radius * max(frameSize.width, frameSize.height)
        let diameterPixels = max(pixelRadius * 2.0, 1.0)
        let pixelsPerMeter = diameterPixels / soccerBallDiameterMeters
        let gravity = 9.81 * pixelsPerMeter / (referenceFPS * referenceFPS)
        return min(max(gravity, gravityMinPixelsPerFrameSquared), gravityMaxPixelsPerFrameSquared)
    }

    private func clampedRect(center: CGPoint, size: CGSize) -> CGRect {
        let width = min(max(size.width, 0.01), 1.0)
        let height = min(max(size.height, 0.01), 1.0)
        let clampedCenter = CGPoint(
            x: min(max(center.x, width * 0.5), 1.0 - width * 0.5),
            y: min(max(center.y, height * 0.5), 1.0 - height * 0.5)
        )

        return CGRect(
            x: clampedCenter.x - width * 0.5,
            y: clampedCenter.y - height * 0.5,
            width: width,
            height: height
        )
        .intersection(unitRect)
    }

    private func mix(_ current: CGFloat, _ target: CGFloat, amount: CGFloat) -> CGFloat {
        current + (target - current) * amount
    }

    private var unitRect: CGRect {
        CGRect(x: 0, y: 0, width: 1, height: 1)
    }
}
