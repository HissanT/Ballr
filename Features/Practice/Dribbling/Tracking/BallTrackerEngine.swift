import CoreGraphics
import Vision

struct BallTrackerOverlayState {
    let normalizedRect: CGRect?
    let confidence: Double?
    let candidateCount: Int
    let statusText: String
    let isTracking: Bool

    static let idle = BallTrackerOverlayState(
        normalizedRect: nil,
        confidence: nil,
        candidateCount: 0,
        statusText: "Searching",
        isTracking: false
    )
}

final class BallTrackerEngine {
    private struct Candidate {
        let normalizedRect: CGRect
        let center: CGPoint
        let size: CGSize
        let radius: CGFloat
        let confidence: CGFloat
    }

    private struct Track {
        var normalizedRect: CGRect
        var center: CGPoint
        var size: CGSize
        var velocity: CGVector
        var radius: CGFloat
        var confidence: CGFloat
        var misses: Int
    }

    private let initConfidenceThreshold: CGFloat = 0.50
    private let reacquireConfidenceThreshold: CGFloat = 0.70
    private let maxMisses = 4
    private let centerSmoothing: CGFloat = 0.65
    private let velocitySmoothing: CGFloat = 0.55
    private let sizeSmoothing: CGFloat = 0.60
    private let trackGateRadiusMultiplier: CGFloat = 5.0
    private let trackGateMinRadius: CGFloat = 0.05
    private let trackGateSpeedFactor: CGFloat = 1.5
    private let trackGateMissPenalty: CGFloat = 0.02
    private let trackScoreAcceptThreshold: CGFloat = 0.35
    private let scoreWeightConfidence: CGFloat = 0.55
    private let scoreWeightMotion: CGFloat = 0.35
    private let scoreWeightSize: CGFloat = 0.10
    private let proximityBonusGateFraction: CGFloat = 0.4
    private let proximityBonus: CGFloat = 0.05
    private let reacquireMinimumMisses = 2

    private var track: Track?

    func reset() {
        track = nil
    }

    func process(
        observations: [VNRecognizedObjectObservation],
        config: BallTrackerConfig
    ) -> BallTrackerOverlayState {
        let minimumConfidence = CGFloat(config.ballrRuntimeDefaults.confidenceThreshold)
        let candidates = candidates(
            from: observations,
            minimumConfidence: minimumConfidence,
            acceptedLabels: config.acceptedBallLabels
        )

        guard !candidates.isEmpty || track != nil else {
            return .idle
        }

        if let candidate = choosePrimaryCandidate(from: candidates) {
            track = updateTrack(with: candidate)
        } else {
            track = advanceTrack()
        }

        guard let track else {
            return BallTrackerOverlayState(
                normalizedRect: nil,
                confidence: nil,
                candidateCount: candidates.count,
                statusText: "Searching",
                isTracking: false
            )
        }

        return BallTrackerOverlayState(
            normalizedRect: track.normalizedRect,
            confidence: Double(track.confidence),
            candidateCount: candidates.count,
            statusText: track.misses == 0 ? "Tracking" : "Searching",
            isTracking: track.misses == 0
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

    private func choosePrimaryCandidate(from candidates: [Candidate]) -> Candidate? {
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
            .map { ($0, score(candidate: $0, track: track)) }
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
        // This Core ML package exports boxes in the same top-left normalized model
        // canvas that the SwiftUI/AV preview conversion expects. Do not invert y
        // here, or vertical motion appears reversed on the camera overlay.
        CGRect(
            x: boundingBox.origin.x,
            y: boundingBox.origin.y,
            width: boundingBox.width,
            height: boundingBox.height
        )
        .standardized
        .intersection(unitRect)
    }

    private func score(candidate: Candidate, track: Track) -> CGFloat {
        let projectedCenter = CGPoint(
            x: track.center.x + track.velocity.dx,
            y: track.center.y + track.velocity.dy
        )
        let distance = hypot(
            candidate.center.x - projectedCenter.x,
            candidate.center.y - projectedCenter.y
        )
        let gate = trackGateRadius(for: track)

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

    private func trackGateRadius(for track: Track) -> CGFloat {
        let speed = hypot(track.velocity.dx, track.velocity.dy)
        let base = max(track.radius * trackGateRadiusMultiplier, trackGateMinRadius)
        return base + speed * trackGateSpeedFactor + CGFloat(track.misses) * trackGateMissPenalty
    }

    private func updateTrack(with candidate: Candidate) -> Track {
        guard let existingTrack = track else {
            return Track(
                normalizedRect: candidate.normalizedRect,
                center: candidate.center,
                size: candidate.size,
                velocity: .zero,
                radius: candidate.radius,
                confidence: candidate.confidence,
                misses: 0
            )
        }

        let predictedCenter = CGPoint(
            x: existingTrack.center.x + existingTrack.velocity.dx,
            y: existingTrack.center.y + existingTrack.velocity.dy
        )
        let rawVelocity = CGVector(
            dx: candidate.center.x - existingTrack.center.x,
            dy: candidate.center.y - existingTrack.center.y
        )
        let smoothedVelocity = CGVector(
            dx: mix(existingTrack.velocity.dx, rawVelocity.dx, amount: velocitySmoothing),
            dy: mix(existingTrack.velocity.dy, rawVelocity.dy, amount: velocitySmoothing)
        )
        let smoothedCenter = CGPoint(
            x: mix(predictedCenter.x, candidate.center.x, amount: centerSmoothing),
            y: mix(predictedCenter.y, candidate.center.y, amount: centerSmoothing)
        )
        let smoothedSize = CGSize(
            width: mix(existingTrack.size.width, candidate.size.width, amount: sizeSmoothing),
            height: mix(existingTrack.size.height, candidate.size.height, amount: sizeSmoothing)
        )
        let smoothedRect = clampedRect(center: smoothedCenter, size: smoothedSize)

        return Track(
            normalizedRect: smoothedRect,
            center: CGPoint(x: smoothedRect.midX, y: smoothedRect.midY),
            size: smoothedRect.size,
            velocity: smoothedVelocity,
            radius: max(smoothedRect.width, smoothedRect.height) * 0.5,
            confidence: candidate.confidence,
            misses: 0
        )
    }

    private func advanceTrack() -> Track? {
        guard var track else {
            return nil
        }

        track.misses += 1
        guard track.misses <= maxMisses else {
            return nil
        }

        let predictedCenter = CGPoint(
            x: track.center.x + track.velocity.dx,
            y: track.center.y + track.velocity.dy
        )
        let predictedRect = clampedRect(center: predictedCenter, size: track.size)

        track.normalizedRect = predictedRect
        track.center = CGPoint(x: predictedRect.midX, y: predictedRect.midY)
        track.radius = max(predictedRect.width, predictedRect.height) * 0.5
        track.confidence *= 0.92
        return track
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
