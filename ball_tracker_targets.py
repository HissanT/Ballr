import math
from dataclasses import dataclass
from typing import Literal, Optional

import numpy as np

from ball_tracker_tracking import BallTrack

TARGET_LOWER_Y_FRACTION = 0.50
TARGET_RADIUS_RATIO = 0.091
TARGET_MIN_RADIUS = 36
TARGET_MAX_RADIUS = 62
TARGET_RESPAWN_DISTANCE_MULTIPLIER = 3.0
TARGET_BALL_CLEARANCE = 20.0
TARGET_SPAWN_ATTEMPTS = 64
TARGET_IDLE_PULSE_PERIOD_SECONDS = 0.90
TARGET_IDLE_PULSE_SCALE = 0.02
TARGET_SCORE_ANIMATION_SECONDS = 0.18

TARGET_PHASE_IDLE = "idle"
TARGET_PHASE_SCORING = "scoring"
TargetPhase = Literal["idle", "scoring"]


@dataclass
class TargetState:
    center: np.ndarray
    radius: int
    score: int = 0
    phase: TargetPhase = TARGET_PHASE_IDLE
    phase_started_at: float = 0.0


def clamp_unit(value: float) -> float:
    return max(0.0, min(1.0, value))


def target_radius_for_frame(frame_shape: tuple[int, ...]) -> int:
    frame_h, frame_w = frame_shape[:2]
    scaled_radius = round(min(frame_w, frame_h) * TARGET_RADIUS_RATIO)
    return int(np.clip(scaled_radius, TARGET_MIN_RADIUS, TARGET_MAX_RADIUS))


def has_live_track(track: Optional[BallTrack]) -> bool:
    return track is not None and track.misses == 0


def can_score_with_track(track: Optional[BallTrack]) -> bool:
    return track is not None and track.misses == 0 and track.confirmed_frames >= 2


def target_spawn_bounds(frame_size: tuple[int, int], radius: int) -> tuple[int, int, int, int]:
    frame_h, frame_w = frame_size
    min_x = radius
    max_x = max(radius, frame_w - radius)
    min_y = int(math.ceil(frame_h * TARGET_LOWER_Y_FRACTION + radius))
    max_y = max(radius, frame_h - radius)
    min_y = min(min_y, max_y)
    return min_x, max_x, min_y, max_y


def _distance_between(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.linalg.norm(a - b))


def _target_position_quality(
    center: np.ndarray,
    previous_center: Optional[np.ndarray],
    ball_track: Optional[BallTrack],
    radius: int,
) -> float:
    previous_distance = (
        _distance_between(center, previous_center) if previous_center is not None else radius * 10.0
    )

    if has_live_track(ball_track):
        ball_distance = _distance_between(center, ball_track.center)
        ball_clearance = max(ball_distance - ball_track.radius - radius, 0.0)
    else:
        ball_clearance = radius * 10.0

    return previous_distance + ball_clearance


def _target_position_is_valid(
    center: np.ndarray,
    previous_center: Optional[np.ndarray],
    ball_track: Optional[BallTrack],
    radius: int,
) -> bool:
    if previous_center is not None:
        minimum_previous_distance = TARGET_RESPAWN_DISTANCE_MULTIPLIER * radius
        if _distance_between(center, previous_center) < minimum_previous_distance:
            return False

    if has_live_track(ball_track):
        minimum_ball_distance = ball_track.radius + radius + TARGET_BALL_CLEARANCE
        if _distance_between(center, ball_track.center) < minimum_ball_distance:
            return False

    return True


def spawn_target(
    frame_size: tuple[int, int],
    radius: int,
    rng: Optional[np.random.Generator] = None,
    previous_center: Optional[np.ndarray] = None,
    ball_track: Optional[BallTrack] = None,
) -> np.ndarray:
    rng = rng or np.random.default_rng()
    min_x, max_x, min_y, max_y = target_spawn_bounds(frame_size, radius)

    best_candidate: Optional[np.ndarray] = None
    best_quality = float("-inf")

    for _ in range(TARGET_SPAWN_ATTEMPTS):
        candidate = np.array(
            [
                rng.integers(min_x, max_x + 1),
                rng.integers(min_y, max_y + 1),
            ],
            dtype=np.float32,
        )
        quality = _target_position_quality(candidate, previous_center, ball_track, radius)
        if quality > best_quality:
            best_candidate = candidate
            best_quality = quality

        if _target_position_is_valid(candidate, previous_center, ball_track, radius):
            return candidate

    fallback_candidates = (
        np.array((min_x, min_y), dtype=np.float32),
        np.array((min_x, max_y), dtype=np.float32),
        np.array((max_x, min_y), dtype=np.float32),
        np.array((max_x, max_y), dtype=np.float32),
        np.array(((min_x + max_x) / 2.0, min_y), dtype=np.float32),
        np.array(((min_x + max_x) / 2.0, max_y), dtype=np.float32),
    )
    for candidate in fallback_candidates:
        quality = _target_position_quality(candidate, previous_center, ball_track, radius)
        if quality > best_quality:
            best_candidate = candidate
            best_quality = quality

        if _target_position_is_valid(candidate, previous_center, ball_track, radius):
            return candidate

    if best_candidate is None:
        best_candidate = np.array(((min_x + max_x) / 2.0, (min_y + max_y) / 2.0), dtype=np.float32)

    return best_candidate


def target_animation_progress(target: TargetState, timestamp: float) -> float:
    if target.phase != TARGET_PHASE_SCORING:
        return 0.0

    return clamp_unit((timestamp - target.phase_started_at) / TARGET_SCORE_ANIMATION_SECONDS)


def begin_target_scoring(target: TargetState, timestamp: float) -> TargetState:
    return TargetState(
        center=target.center.copy(),
        radius=target.radius,
        score=target.score + 1,
        phase=TARGET_PHASE_SCORING,
        phase_started_at=timestamp,
    )


def advance_target_state(
    target: TargetState,
    timestamp: float,
    frame_size: tuple[int, int],
    rng: Optional[np.random.Generator] = None,
    ball_track: Optional[BallTrack] = None,
) -> TargetState:
    if target.phase != TARGET_PHASE_SCORING:
        return target

    if target_animation_progress(target, timestamp) < 1.0:
        return target

    return TargetState(
        center=spawn_target(
            frame_size,
            target.radius,
            rng=rng,
            previous_center=target.center,
            ball_track=ball_track,
        ),
        radius=target.radius,
        score=target.score,
        phase=TARGET_PHASE_IDLE,
        phase_started_at=0.0,
    )


def target_hit(track: Optional[BallTrack], target: TargetState) -> bool:
    if target.phase != TARGET_PHASE_IDLE or not can_score_with_track(track):
        return False

    return _distance_between(track.center, target.center) <= track.radius + target.radius
