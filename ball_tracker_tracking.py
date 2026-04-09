from dataclasses import dataclass
from typing import Optional

import numpy as np

SPORTS_BALL_CLASS_ID = 0
CANDIDATE_CONF_THRESHOLD = 0.32
INIT_CONF_THRESHOLD = 0.50
REACQUIRE_CONF_THRESHOLD = 0.70
IOU_THRESHOLD = 0.35
MAX_DETECTIONS = 8
MAX_MISSES = 4
REFERENCE_FPS = 30.0
SOCCER_BALL_DIAMETER_METERS = 0.22
MEASUREMENT_NOISE_PX = 4.0
PROCESS_ACCEL_NOISE = 8.0
INITIAL_POSITION_VARIANCE = 100.0
INITIAL_VELOCITY_VARIANCE = 50.0
GRAVITY_MIN_PX_PER_FRAME2 = 0.75
GRAVITY_MAX_PX_PER_FRAME2 = 6.0
MOTION_DECAY = 0.82
CENTER_SMOOTHING = 0.65
VELOCITY_SMOOTHING = 0.55
RADIUS_SMOOTHING = 0.60
TRACK_GATE_RADIUS_MULTIPLIER = 5.0
TRACK_GATE_MIN_RADIUS = 55.0
TRACK_GATE_SPEED_FACTOR = 1.5
TRACK_GATE_MISS_PENALTY = 25.0
SCORE_WEIGHT_CONFIDENCE = 0.55
SCORE_WEIGHT_MOTION = 0.35
SCORE_WEIGHT_SIZE = 0.10
SCORE_PROXIMITY_BONUS_GATE_FRACTION = 0.4
SCORE_PROXIMITY_BONUS = 0.05
TRACK_SCORE_ACCEPT_THRESHOLD = 0.35
TRACK_REACQUIRE_MIN_MISSES = 2
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


@dataclass
class BallMotionState:
    state: np.ndarray
    covariance: np.ndarray
    last_time: float
    gravity_pf2: float


OBSERVATION_MATRIX = np.array([[1, 0, 0, 0], [0, 1, 0, 0]], dtype=float)
MEASUREMENT_COVARIANCE = np.diag([MEASUREMENT_NOISE_PX**2, MEASUREMENT_NOISE_PX**2]).astype(float)
IDENTITY_4 = np.eye(4, dtype=float)


def is_track_live(track: Optional[BallTrack], min_confirmed_frames: int = 0) -> bool:
    return (
        track is not None
        and track.misses == 0
        and track.confirmed_frames >= min_confirmed_frames
    )


def predicted_center(track: BallTrack) -> np.ndarray:
    # Track estimates are predicted to the current frame before association.
    return track.center


def track_gate_radius(track: BallTrack) -> float:
    speed = float(np.linalg.norm(track.velocity))
    base = max(track.radius * TRACK_GATE_RADIUS_MULTIPLIER, TRACK_GATE_MIN_RADIUS)
    return base + speed * TRACK_GATE_SPEED_FACTOR + track.misses * TRACK_GATE_MISS_PENALTY


def extract_candidates(results) -> list[DetectionCandidate]:
    if not results or results[0].boxes is None or not len(results[0].boxes):
        return []

    candidates: list[DetectionCandidate] = []
    for box in results[0].boxes:
        x1, y1, x2, y2 = (int(value) for value in box.xyxy[0])
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
    score = (
        candidate.confidence * SCORE_WEIGHT_CONFIDENCE
        + motion_score * SCORE_WEIGHT_MOTION
        + size_score * SCORE_WEIGHT_SIZE
    )

    if distance <= gate * SCORE_PROXIMITY_BONUS_GATE_FRACTION:
        score += SCORE_PROXIMITY_BONUS

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
    if best_score >= TRACK_SCORE_ACCEPT_THRESHOLD:
        return best_candidate

    if track.misses >= TRACK_REACQUIRE_MIN_MISSES and strongest.confidence >= REACQUIRE_CONF_THRESHOLD:
        return strongest

    return None


def predict_track(
    track: Optional[BallTrack],
    motion: Optional[BallMotionState],
    frame_time: float,
) -> tuple[Optional[BallTrack], Optional[BallMotionState]]:
    if track is None:
        return None, None

    if motion is None:
        motion = _bootstrap_motion_state(track, frame_time)
        return _track_from_motion_state(
            motion.state,
            radius=track.radius,
            confidence=track.confidence,
            track_id=track.track_id,
            misses=track.misses,
            confirmed_frames=track.confirmed_frames,
        ), motion

    dt_frames = max((float(frame_time) - motion.last_time) * REFERENCE_FPS, 0.0)
    gravity_pf2 = _gravity_from_radius(track.radius)
    if dt_frames <= 0.0:
        motion = BallMotionState(
            state=motion.state.copy(),
            covariance=motion.covariance.copy(),
            last_time=float(frame_time),
            gravity_pf2=gravity_pf2,
        )
    else:
        transition = _state_transition_matrix(dt_frames)
        predicted_state = transition @ motion.state
        predicted_state += np.array(
            (
                0.0,
                0.5 * dt_frames * dt_frames * gravity_pf2,
                0.0,
                dt_frames * gravity_pf2,
            ),
            dtype=float,
        )
        predicted_covariance = (
            transition @ motion.covariance @ transition.T + _process_noise_matrix(dt_frames)
        )
        motion = BallMotionState(
            state=predicted_state,
            covariance=_symmetrize(predicted_covariance),
            last_time=float(frame_time),
            gravity_pf2=gravity_pf2,
        )

    predicted_track = _track_from_motion_state(
        motion.state,
        radius=track.radius,
        confidence=track.confidence,
        track_id=track.track_id,
        misses=track.misses,
        confirmed_frames=track.confirmed_frames,
    )
    return predicted_track, motion


def update_track(
    track: Optional[BallTrack],
    motion: Optional[BallMotionState],
    candidate: DetectionCandidate,
    next_track_id: int,
    frame_time: float,
) -> tuple[BallTrack, BallMotionState, int]:
    if track is None:
        state = np.array(
            (candidate.center[0], candidate.center[1], 0.0, 0.0),
            dtype=float,
        )
        motion = BallMotionState(
            state=state,
            covariance=_initial_covariance_matrix(),
            last_time=float(frame_time),
            gravity_pf2=_gravity_from_radius(candidate.radius),
        )
        return (
            BallTrack(
                center=candidate.center.copy(),
                velocity=np.zeros(2, dtype=np.float32),
                radius=candidate.radius,
                confidence=candidate.confidence,
                track_id=next_track_id,
                confirmed_frames=1,
            ),
            motion,
            next_track_id + 1,
        )

    if motion is None:
        motion = _bootstrap_motion_state(track, frame_time)

    innovation = candidate.center.astype(float) - (OBSERVATION_MATRIX @ motion.state)
    innovation_covariance = (
        OBSERVATION_MATRIX @ motion.covariance @ OBSERVATION_MATRIX.T + MEASUREMENT_COVARIANCE
    )
    kalman_gain = motion.covariance @ OBSERVATION_MATRIX.T @ np.linalg.inv(innovation_covariance)
    updated_state = motion.state + kalman_gain @ innovation
    residual_transform = IDENTITY_4 - kalman_gain @ OBSERVATION_MATRIX
    updated_covariance = (
        residual_transform @ motion.covariance @ residual_transform.T
        + kalman_gain @ MEASUREMENT_COVARIANCE @ kalman_gain.T
    )
    blended_radius = track.radius * (1.0 - RADIUS_SMOOTHING) + candidate.radius * RADIUS_SMOOTHING
    updated_motion = BallMotionState(
        state=updated_state,
        covariance=_symmetrize(updated_covariance),
        last_time=motion.last_time,
        gravity_pf2=_gravity_from_radius(blended_radius),
    )

    return (
        _track_from_motion_state(
            updated_motion.state,
            radius=blended_radius,
            confidence=candidate.confidence,
            track_id=track.track_id,
            misses=0,
            confirmed_frames=track.confirmed_frames + 1,
        ),
        updated_motion,
        next_track_id,
    )


def advance_track(
    track: Optional[BallTrack],
    motion: Optional[BallMotionState],
) -> tuple[Optional[BallTrack], Optional[BallMotionState]]:
    if track is None or motion is None:
        return None, None

    misses = track.misses + 1
    if misses > MAX_MISSES:
        return None, None

    return _track_from_motion_state(
        motion.state,
        radius=track.radius,
        confidence=max(track.confidence * 0.92, 0.0),
        track_id=track.track_id,
        misses=misses,
        confirmed_frames=track.confirmed_frames,
    ), motion


def _bootstrap_motion_state(track: BallTrack, frame_time: float) -> BallMotionState:
    return BallMotionState(
        state=np.array(
            (track.center[0], track.center[1], track.velocity[0], track.velocity[1]),
            dtype=float,
        ),
        covariance=_initial_covariance_matrix(),
        last_time=float(frame_time),
        gravity_pf2=_gravity_from_radius(track.radius),
    )


def _initial_covariance_matrix() -> np.ndarray:
    return np.diag(
        (
            INITIAL_POSITION_VARIANCE,
            INITIAL_POSITION_VARIANCE,
            INITIAL_VELOCITY_VARIANCE,
            INITIAL_VELOCITY_VARIANCE,
        )
    ).astype(float)


def _state_transition_matrix(dt_frames: float) -> np.ndarray:
    return np.array(
        (
            (1.0, 0.0, dt_frames, 0.0),
            (0.0, 1.0, 0.0, dt_frames),
            (0.0, 0.0, 1.0, 0.0),
            (0.0, 0.0, 0.0, 1.0),
        ),
        dtype=float,
    )


def _process_noise_matrix(dt_frames: float) -> np.ndarray:
    dt2 = dt_frames * dt_frames
    dt3 = dt2 * dt_frames
    dt4 = dt2 * dt2
    sigma2 = PROCESS_ACCEL_NOISE**2
    return sigma2 * np.array(
        (
            (0.25 * dt4, 0.0, 0.5 * dt3, 0.0),
            (0.0, 0.25 * dt4, 0.0, 0.5 * dt3),
            (0.5 * dt3, 0.0, dt2, 0.0),
            (0.0, 0.5 * dt3, 0.0, dt2),
        ),
        dtype=float,
    )


def _gravity_from_radius(radius: float) -> float:
    diameter_px = max(float(radius) * 2.0, 1.0)
    pixels_per_meter = diameter_px / SOCCER_BALL_DIAMETER_METERS
    gravity_pf2 = 9.81 * pixels_per_meter / (REFERENCE_FPS**2)
    return float(np.clip(gravity_pf2, GRAVITY_MIN_PX_PER_FRAME2, GRAVITY_MAX_PX_PER_FRAME2))


def _symmetrize(matrix: np.ndarray) -> np.ndarray:
    return (matrix + matrix.T) * 0.5


def _track_from_motion_state(
    state: np.ndarray,
    *,
    radius: float,
    confidence: float,
    track_id: int,
    misses: int,
    confirmed_frames: int,
) -> BallTrack:
    return BallTrack(
        center=np.array(state[:2], dtype=np.float32),
        velocity=np.array(state[2:], dtype=np.float32),
        radius=float(radius),
        confidence=float(confidence),
        track_id=track_id,
        misses=misses,
        confirmed_frames=confirmed_frames,
    )
