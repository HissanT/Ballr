import math
from dataclasses import dataclass
from typing import Optional

import numpy as np

from ball_tracker_tracking import BallTrack, is_track_live

TARGET_LOWER_Y_FRACTION = 0.65
TARGET_RADIUS_RATIO = 0.091
TARGET_MIN_RADIUS = 36
TARGET_MAX_RADIUS = 62
TARGET_RESPAWN_DISTANCE_MULTIPLIER = 3.0
TARGET_BALL_CLEARANCE = 20.0
TARGET_SPAWN_ATTEMPTS = 64
TARGET_IDLE_PULSE_PERIOD_SECONDS = 0.90
TARGET_IDLE_PULSE_SCALE = 0.02
TARGET_SCORE_VALUE = 5
TARGET_SCORE_BURST_SECONDS = 0.35
TARGET_SCORE_POPUP_DELAY_SECONDS = 0.20
TARGET_SCORE_POPUP_SECONDS = 0.75
TARGET_SCORE_EFFECT_SECONDS = max(
    TARGET_SCORE_BURST_SECONDS,
    TARGET_SCORE_POPUP_DELAY_SECONDS + TARGET_SCORE_POPUP_SECONDS,
)
TARGET_LIFETIME_SECONDS = 4.0
TARGET_FULL_VALUE_WINDOW_SECONDS = 2.0
TARGET_SCORE_STEP_SECONDS = 0.40
TARGET_MIN_BASE_POINTS = 1
TARGET_MISS_PENALTY = 1
TARGET_COMBO_STREAK_STEP = 10
TARGET_COMBO_POPUP_SCALE = 0.72


@dataclass(frozen=True)
class TargetState:
    center: np.ndarray
    radius: int
    spawned_at: float


@dataclass(frozen=True)
class ScoredTargetEffect:
    center: np.ndarray
    radius: int
    points: int
    started_at: float
    show_burst: bool = True
    popup_scale: float = 1.0


@dataclass(frozen=True)
class TargetHitResult:
    target: TargetState
    effect: ScoredTargetEffect
    base_points: int
    awarded_points: int


@dataclass(frozen=True)
class TargetMissResult:
    target: TargetState
    penalty_points: int
    effect: ScoredTargetEffect


def clamp_unit(value: float) -> float:
    return max(0.0, min(1.0, value))


def target_radius_for_frame(frame_shape: tuple[int, ...]) -> int:
    frame_h, frame_w = frame_shape[:2]
    scaled_radius = round(min(frame_w, frame_h) * TARGET_RADIUS_RATIO)
    return int(np.clip(scaled_radius, TARGET_MIN_RADIUS, TARGET_MAX_RADIUS))


def has_live_track(track: Optional[BallTrack]) -> bool:
    return is_track_live(track)


def can_score_with_track(track: Optional[BallTrack]) -> bool:
    return is_track_live(track, min_confirmed_frames=2)


def target_spawn_bounds(frame_size: tuple[int, int], radius: int) -> tuple[int, int, int, int]:
    frame_h, frame_w = frame_size
    min_x = radius
    max_x = max(radius, frame_w - radius)
    min_y = int(math.ceil(frame_h * TARGET_LOWER_Y_FRACTION + radius))
    max_y = max(radius, frame_h - radius)
    min_y = min(min_y, max_y)
    return min_x, max_x, min_y, max_y


def target_age_seconds(target: TargetState, timestamp: float) -> float:
    return max(0.0, timestamp - target.spawned_at)


def target_fade_alpha(target: TargetState, timestamp: float) -> float:
    age = target_age_seconds(target, timestamp)
    return 1.0 - clamp_unit(age / TARGET_LIFETIME_SECONDS)


def target_has_expired(target: TargetState, timestamp: float) -> bool:
    return target_age_seconds(target, timestamp) >= TARGET_LIFETIME_SECONDS


def target_base_points(target: TargetState, timestamp: float) -> int:
    age = target_age_seconds(target, timestamp)
    if age <= TARGET_FULL_VALUE_WINDOW_SECONDS:
        return TARGET_SCORE_VALUE

    epsilon = 1e-9
    elapsed_after_full_value = age - TARGET_FULL_VALUE_WINDOW_SECONDS
    steps = int(math.floor((elapsed_after_full_value - epsilon) / TARGET_SCORE_STEP_SECONDS)) + 1
    return max(TARGET_MIN_BASE_POINTS, TARGET_SCORE_VALUE - steps)


def combo_multiplier_for_streak(streak: int) -> int:
    return 1 + max(streak, 0) // TARGET_COMBO_STREAK_STEP


def next_combo_threshold_for_streak(streak: int) -> int:
    return (max(streak, 0) // TARGET_COMBO_STREAK_STEP + 1) * TARGET_COMBO_STREAK_STEP


def _distance_between(a: np.ndarray, b: np.ndarray) -> float:
    return float(np.linalg.norm(a - b))


def _evaluate_target_position(
    center: np.ndarray,
    previous_center: Optional[np.ndarray],
    ball_track: Optional[BallTrack],
    radius: int,
) -> tuple[float, bool]:
    previous_distance = (
        _distance_between(center, previous_center) if previous_center is not None else None
    )
    live_ball_track = has_live_track(ball_track)
    ball_distance = _distance_between(center, ball_track.center) if live_ball_track else None

    quality = previous_distance if previous_distance is not None else radius * 10.0
    if ball_distance is not None:
        quality += max(ball_distance - ball_track.radius - radius, 0.0)
    else:
        quality += radius * 10.0

    if previous_distance is not None:
        minimum_previous_distance = TARGET_RESPAWN_DISTANCE_MULTIPLIER * radius
        if previous_distance < minimum_previous_distance:
            return quality, False

    if ball_distance is not None:
        minimum_ball_distance = ball_track.radius + radius + TARGET_BALL_CLEARANCE
        if ball_distance < minimum_ball_distance:
            return quality, False

    return quality, True


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
        quality, is_valid = _evaluate_target_position(candidate, previous_center, ball_track, radius)
        if quality > best_quality:
            best_candidate = candidate
            best_quality = quality

        if is_valid:
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
        quality, is_valid = _evaluate_target_position(candidate, previous_center, ball_track, radius)
        if quality > best_quality:
            best_candidate = candidate
            best_quality = quality

        if is_valid:
            return candidate

    if best_candidate is None:
        best_candidate = np.array(((min_x + max_x) / 2.0, (min_y + max_y) / 2.0), dtype=np.float32)

    return best_candidate


def spawn_initial_target(
    frame_size: tuple[int, int],
    radius: int,
    timestamp: float,
    rng: Optional[np.random.Generator] = None,
    ball_track: Optional[BallTrack] = None,
) -> TargetState:
    return TargetState(
        center=spawn_target(frame_size, radius, rng=rng, ball_track=ball_track),
        radius=radius,
        spawned_at=timestamp,
    )


def respawn_target(
    target: TargetState,
    timestamp: float,
    frame_size: tuple[int, int],
    rng: Optional[np.random.Generator] = None,
    ball_track: Optional[BallTrack] = None,
) -> TargetState:
    return TargetState(
        center=spawn_target(
            frame_size,
            target.radius,
            rng=rng,
            previous_center=target.center,
            ball_track=ball_track,
        ),
        radius=target.radius,
        spawned_at=timestamp,
    )


def score_target(
    target: TargetState,
    timestamp: float,
    frame_size: tuple[int, int],
    *,
    base_points: int,
    combo_multiplier: int,
    rng: Optional[np.random.Generator] = None,
    ball_track: Optional[BallTrack] = None,
) -> TargetHitResult:
    awarded_points = max(base_points, 0) * max(combo_multiplier, 1)
    effect = ScoredTargetEffect(
        center=target.center.copy(),
        radius=target.radius,
        points=awarded_points,
        started_at=timestamp,
    )
    return TargetHitResult(
        target=respawn_target(
            target,
            timestamp,
            frame_size,
            rng=rng,
            ball_track=ball_track,
        ),
        effect=effect,
        base_points=base_points,
        awarded_points=awarded_points,
    )


def expire_target(
    target: TargetState,
    timestamp: float,
    frame_size: tuple[int, int],
    *,
    rng: Optional[np.random.Generator] = None,
    ball_track: Optional[BallTrack] = None,
) -> TargetMissResult:
    effect = ScoredTargetEffect(
        center=target.center.copy(),
        radius=target.radius,
        points=-TARGET_MISS_PENALTY,
        started_at=timestamp,
        show_burst=False,
    )
    return TargetMissResult(
        target=respawn_target(
            target,
            timestamp,
            frame_size,
            rng=rng,
            ball_track=ball_track,
        ),
        penalty_points=TARGET_MISS_PENALTY,
        effect=effect,
    )


def scored_target_effect_elapsed(effect: ScoredTargetEffect, timestamp: float) -> float:
    return max(0.0, timestamp - effect.started_at)


def scored_target_effect_is_active(effect: ScoredTargetEffect, timestamp: float) -> bool:
    return scored_target_effect_elapsed(effect, timestamp) < TARGET_SCORE_EFFECT_SECONDS


def scored_target_effect_burst_progress(effect: ScoredTargetEffect, timestamp: float) -> float:
    return clamp_unit(scored_target_effect_elapsed(effect, timestamp) / TARGET_SCORE_BURST_SECONDS)


def scored_target_effect_popup_progress(effect: ScoredTargetEffect, timestamp: float) -> float:
    popup_elapsed = scored_target_effect_elapsed(effect, timestamp) - TARGET_SCORE_POPUP_DELAY_SECONDS
    return clamp_unit(popup_elapsed / TARGET_SCORE_POPUP_SECONDS)


def target_hit(track: Optional[BallTrack], target: TargetState) -> bool:
    if not can_score_with_track(track):
        return False

    return _distance_between(track.center, target.center) <= track.radius + target.radius
