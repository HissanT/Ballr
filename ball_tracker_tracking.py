from dataclasses import dataclass
from typing import Optional

import numpy as np

SPORTS_BALL_CLASS_ID = 0
CANDIDATE_CONF_THRESHOLD = 0.25
INIT_CONF_THRESHOLD = 0.40
REACQUIRE_CONF_THRESHOLD = 0.60
IOU_THRESHOLD = 0.35
MAX_DETECTIONS = 8
MAX_MISSES = 4
MOTION_DECAY = 0.82
CENTER_SMOOTHING = 0.65
VELOCITY_SMOOTHING = 0.55
RADIUS_SMOOTHING = 0.60
MODEL_PATH = "runs/train/ballr_v4/weights/best.pt"


@dataclass
class DetectionCandidate:
    x1: int
    y1: int
    x2: int
    y2: int
    center: np.ndarray
    radius: float
    confidence: float


@dataclass
class BallTrack:
    center: np.ndarray
    velocity: np.ndarray
    radius: float
    confidence: float
    track_id: int
    misses: int = 0
    confirmed_frames: int = 0


def predicted_center(track: BallTrack) -> np.ndarray:
    return track.center + track.velocity


def track_gate_radius(track: BallTrack) -> float:
    speed = float(np.linalg.norm(track.velocity))
    base = max(track.radius * 5.0, 55.0)
    return base + speed * 1.5 + track.misses * 25.0


def extract_candidates(results) -> list[DetectionCandidate]:
    if not results or results[0].boxes is None or not len(results[0].boxes):
        return []

    candidates: list[DetectionCandidate] = []
    for box in results[0].boxes:
        x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
        center = np.array(((x1 + x2) / 2.0, (y1 + y2) / 2.0), dtype=np.float32)
        radius = max((x2 - x1), (y2 - y1)) / 2.0
        candidates.append(
            DetectionCandidate(
                x1=x1,
                y1=y1,
                x2=x2,
                y2=y2,
                center=center,
                radius=radius,
                confidence=float(box.conf[0]),
            )
        )

    return candidates


def score_candidate(candidate: DetectionCandidate, track: BallTrack) -> float:
    projected_center = predicted_center(track)
    distance = float(np.linalg.norm(candidate.center - projected_center))
    gate = track_gate_radius(track)
    if distance > gate and candidate.confidence < REACQUIRE_CONF_THRESHOLD:
        return -1.0

    motion_score = max(0.0, 1.0 - distance / max(gate, 1.0))
    size_delta = abs(candidate.radius - track.radius) / max(track.radius, 1.0)
    size_score = max(0.0, 1.0 - size_delta)
    score = candidate.confidence * 0.55 + motion_score * 0.35 + size_score * 0.10

    if distance <= gate * 0.4:
        score += 0.05

    return score


def choose_primary_candidate(
    candidates: list[DetectionCandidate], track: Optional[BallTrack]
) -> Optional[DetectionCandidate]:
    if not candidates:
        return None

    strongest = max(candidates, key=lambda candidate: candidate.confidence)
    if track is None:
        return strongest if strongest.confidence >= INIT_CONF_THRESHOLD else None

    best_candidate = max(candidates, key=lambda candidate: score_candidate(candidate, track))
    best_score = score_candidate(best_candidate, track)
    if best_score >= 0.35:
        return best_candidate

    if track.misses >= 2 and strongest.confidence >= REACQUIRE_CONF_THRESHOLD:
        return strongest

    return None


def update_track(
    track: Optional[BallTrack],
    candidate: DetectionCandidate,
    next_track_id: int,
) -> tuple[BallTrack, int]:
    if track is None:
        return (
            BallTrack(
                center=candidate.center.copy(),
                velocity=np.zeros(2, dtype=np.float32),
                radius=candidate.radius,
                confidence=candidate.confidence,
                track_id=next_track_id,
                confirmed_frames=1,
            ),
            next_track_id + 1,
        )

    projected = predicted_center(track)
    blended_center = projected * (1.0 - CENTER_SMOOTHING) + candidate.center * CENTER_SMOOTHING
    instantaneous_velocity = blended_center - track.center
    blended_velocity = (
        track.velocity * (1.0 - VELOCITY_SMOOTHING)
        + instantaneous_velocity * VELOCITY_SMOOTHING
    )
    blended_radius = track.radius * (1.0 - RADIUS_SMOOTHING) + candidate.radius * RADIUS_SMOOTHING

    return (
        BallTrack(
            center=blended_center,
            velocity=blended_velocity,
            radius=blended_radius,
            confidence=candidate.confidence,
            track_id=track.track_id,
            confirmed_frames=track.confirmed_frames + 1,
        ),
        next_track_id,
    )


def advance_track(track: Optional[BallTrack]) -> Optional[BallTrack]:
    if track is None:
        return None

    misses = track.misses + 1
    if misses > MAX_MISSES:
        return None

    return BallTrack(
        center=track.center + track.velocity,
        velocity=track.velocity * MOTION_DECAY,
        radius=track.radius,
        confidence=max(track.confidence * 0.92, 0.0),
        track_id=track.track_id,
        misses=misses,
        confirmed_frames=track.confirmed_frames,
    )
