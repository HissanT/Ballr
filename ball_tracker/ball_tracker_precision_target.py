from __future__ import annotations

import math
from collections import deque
from dataclasses import dataclass, field
from typing import Optional

import cv2
import numpy as np

from .ball_tracker_rendering import draw_label, draw_label_right
from .ball_tracker_tracking import BallTrack, DetectionCandidate, is_track_live

PRECISION_TARGET_PHASE_SELECT_CENTER = "select_bullseye_center"
PRECISION_TARGET_PHASE_REFERENCE = "capture_reference_depth"
PRECISION_TARGET_PHASE_CALIBRATION = "calibration_throw"
PRECISION_TARGET_PHASE_LIVE = "live_precision_target"

THROW_PHASE_IDLE = "idle"
THROW_PHASE_OUTBOUND_CANDIDATE = "outbound_candidate"
THROW_PHASE_OUTBOUND_CONFIRMED = "outbound_confirmed"
THROW_PHASE_IMPACT_LOCKED = "impact_locked"
THROW_PHASE_COOLDOWN = "cooldown"

DEFAULT_FOCAL_LENGTH_PX = 2400.0
FOCAL_LENGTH_REFERENCE_WIDTH_PX = 1920.0
BALL_SIZE_PRESETS_CM = {
    "3": 19.1,
    "4": 20.3,
    "5": 22.0,
}
RING_RADII_CM = (8.0, 16.0, 24.0, 32.0, 40.0)
REFERENCE_HOLD_SECONDS = 5.0
WALL_HOLD_SECONDS = 10.0
HOLD_COMPLETION_EPSILON_S = 1e-3
HOLD_MAX_MISSING_FRAMES = 15
HOLD_MAX_FRAME_DT_S = 0.1

CALIBRATION_SMOOTHING_ALPHA = 0.35
CALIBRATION_DECREASE_DELTA_PX = 1.0
CALIBRATION_JITTER_PX = 2.0
CALIBRATION_MIN_VALID_SAMPLES = 12
CALIBRATION_MIN_DIAMETER_PX = 16.0
CALIBRATION_MIN_DEPTH_DELTA_M = 1.5
CALIBRATION_REQUIRED_DECREASE_FRAMES = 6
CALIBRATION_REQUIRED_REBOUND_FRAMES = 2
CALIBRATION_MAX_DISAPPEAR_FRAMES = 4
CALIBRATION_MIN_WALL_DISTANCE_M = 1.5
CALIBRATION_MAX_WALL_DISTANCE_M = 12.0

THROW_OUTBOUND_MIN_FRAMES = 4
THROW_IMPACT_REVERSAL_M = 0.04
THROW_RESET_RETURN_DEPTH_M = 0.75
THROW_COOLDOWN_MISSING_FRAMES = 6

HUD_BASELINE_Y = 22
HUD_LINE_HEIGHT = 22
HUD_FONT_SCALE = 0.45
HUD_FONT_THICKNESS = 1
HUD_RIGHT_MARGIN = 8


@dataclass(frozen=True)
class BallSpec:
    label: str
    diameter_cm: float

    @property
    def diameter_m(self) -> float:
        return self.diameter_cm / 100.0


@dataclass(frozen=True)
class DepthEstimate:
    distance_m: float
    pixel_diameter_px: float


@dataclass(frozen=True)
class DepthSample:
    timestamp: float
    center: np.ndarray
    pixel_diameter_px: float
    smoothed_diameter_px: float
    raw_estimated_distance_m: float
    estimated_distance_m: float


@dataclass(frozen=True)
class WallCalibration:
    wall_distance_m: float
    impact_pixel_diameter_px: float
    impact_frame_time: float
    confidence: float


@dataclass(frozen=True)
class PrecisionImpact:
    center: np.ndarray
    radial_distance_cm: float
    dx_cm: float
    dy_cm: float
    score: int
    frame_time: float


@dataclass
class ThrowState:
    phase: str = THROW_PHASE_IDLE
    near_start_depth_m: Optional[float] = None
    outbound_frames: int = 0
    missing_frames: int = 0
    furthest_sample: Optional[DepthSample] = None
    eligible_samples: deque[DepthSample] = field(default_factory=lambda: deque(maxlen=12))


@dataclass
class PrecisionTargetState:
    phase: str = PRECISION_TARGET_PHASE_SELECT_CENTER
    ball_spec: Optional[BallSpec] = None
    focal_length_px: float = DEFAULT_FOCAL_LENGTH_PX
    bullseye_center: Optional[np.ndarray] = None
    wall_calibration: Optional[WallCalibration] = None
    current_depth: Optional[DepthEstimate] = None
    current_relative_depth_m: Optional[float] = None
    zero_reference_depth_m: Optional[float] = None
    reference_started_at: Optional[float] = None
    reference_elapsed_s: float = 0.0
    reference_missing_frames: int = 0
    reference_samples: deque[float] = field(default_factory=lambda: deque(maxlen=180))
    calibration_started_at: Optional[float] = None
    calibration_elapsed_s: float = 0.0
    calibration_depth_samples: deque[float] = field(default_factory=lambda: deque(maxlen=360))
    calibration_diameter_samples: deque[float] = field(default_factory=lambda: deque(maxlen=360))
    calibration_window: deque[float] = field(default_factory=lambda: deque(maxlen=5))
    calibration_samples: deque[DepthSample] = field(default_factory=lambda: deque(maxlen=90))
    calibration_smoothed_diameter_px: Optional[float] = None
    calibration_baseline_depth_m: Optional[float] = None
    calibration_outbound_frames: int = 0
    calibration_outbound_started: bool = False
    calibration_min_sample: Optional[DepthSample] = None
    calibration_rebound_frames: int = 0
    calibration_missing_frames: int = 0
    calibration_failures: int = 0
    throw_state: ThrowState = field(default_factory=ThrowState)
    score: int = 0
    scored_throws: int = 0
    last_impact: Optional[PrecisionImpact] = None
    last_score: int = 0
    status_text: str = "Click the bullseye center"


@dataclass(frozen=True)
class PrecisionTargetFrame:
    phase: str
    score: int
    status_text: str
    ball_spec_label: str
    focal_length_px: float
    bullseye_center: Optional[np.ndarray]
    wall_calibration: Optional[WallCalibration]
    current_depth: Optional[DepthEstimate]
    current_relative_depth_m: Optional[float]
    zero_reference_depth_m: Optional[float]
    last_impact: Optional[PrecisionImpact]
    last_score: int


def parse_ball_spec(ball_size: Optional[str], ball_diameter_cm: Optional[float]) -> BallSpec:
    if ball_diameter_cm is not None:
        diameter_cm = float(ball_diameter_cm)
        if diameter_cm <= 0.0:
            raise ValueError("Custom ball diameter must be positive.")
        return BallSpec(label=f"Custom {diameter_cm:.1f} cm", diameter_cm=diameter_cm)

    if ball_size is None:
        raise ValueError("Ball size is required for precision_target mode.")

    normalized = str(ball_size).strip().lower()
    if normalized in BALL_SIZE_PRESETS_CM:
        return BallSpec(label=f"Size {normalized}", diameter_cm=BALL_SIZE_PRESETS_CM[normalized])

    raise ValueError(f"Unsupported ball size preset: {ball_size}")


def estimate_distance_m(ball_diameter_m: float, focal_length_px: float, pixel_diameter_px: float) -> float:
    safe_diameter = max(float(pixel_diameter_px), 1e-6)
    return (float(ball_diameter_m) * float(focal_length_px)) / safe_diameter


def resolve_effective_focal_length_px(focal_length_px: float, frame_width_px: int) -> float:
    return float(focal_length_px) * max(float(frame_width_px), 1.0) / FOCAL_LENGTH_REFERENCE_WIDTH_PX


def pixel_offset_to_cm(pixel_offset: float, wall_distance_m: float, focal_length_px: float) -> float:
    return (float(pixel_offset) * float(wall_distance_m) / float(focal_length_px)) * 100.0


def score_from_radial_distance(radial_distance_cm: float) -> int:
    for index, radius_cm in enumerate(RING_RADII_CM):
        if radial_distance_cm < radius_cm:
            return 5 - index
    return 0


def set_bullseye_center(
    state: PrecisionTargetState,
    center: np.ndarray,
) -> PrecisionTargetState:
    updated_state = _ensure_ball_configured(state)
    updated_state.bullseye_center = center.astype(np.float32)
    updated_state.phase = PRECISION_TARGET_PHASE_REFERENCE
    updated_state.reference_started_at = None
    updated_state.reference_elapsed_s = 0.0
    updated_state.reference_missing_frames = 0
    updated_state.reference_samples.clear()
    updated_state.status_text = "Hold the ball at your passing spot for 5 seconds"
    return updated_state


def step_precision_target_mode(
    state: PrecisionTargetState,
    track: Optional[BallTrack],
    candidate: Optional[DetectionCandidate],
    frame_size: tuple[int, int],
    timestamp: float,
    *,
    ball_spec: BallSpec,
    focal_length_px: float,
    bullseye_click: Optional[np.ndarray] = None,
) -> tuple[PrecisionTargetState, PrecisionTargetFrame, bool]:
    updated_state = _ensure_ball_configured(state, ball_spec=ball_spec, focal_length_px=focal_length_px)

    if bullseye_click is not None and updated_state.phase == PRECISION_TARGET_PHASE_SELECT_CENTER:
        updated_state = set_bullseye_center(updated_state, bullseye_click)

    current_sample, current_depth, next_smoothed = _build_depth_sample(
        track,
        candidate,
        timestamp,
        updated_state.ball_spec,
        updated_state.focal_length_px,
        updated_state.calibration_window,
        updated_state.calibration_smoothed_diameter_px,
    )
    updated_state.current_depth = current_depth
    if current_depth is not None and updated_state.zero_reference_depth_m is not None:
        updated_state.current_relative_depth_m = max(
            current_depth.distance_m - updated_state.zero_reference_depth_m,
            0.0,
        )
    else:
        updated_state.current_relative_depth_m = None
    if next_smoothed is not None:
        updated_state.calibration_smoothed_diameter_px = next_smoothed

    did_score = False
    if updated_state.phase == PRECISION_TARGET_PHASE_SELECT_CENTER:
        updated_state.status_text = "Click the bullseye center"
    elif updated_state.phase == PRECISION_TARGET_PHASE_REFERENCE:
        updated_state = _step_reference_depth(updated_state, current_sample, timestamp)
    elif updated_state.phase == PRECISION_TARGET_PHASE_CALIBRATION:
        updated_state = _step_calibration(updated_state, current_sample)
    elif updated_state.phase == PRECISION_TARGET_PHASE_LIVE:
        updated_state, did_score = _step_live_precision(updated_state, current_sample)
    else:
        raise ValueError(f"Unsupported precision target phase: {updated_state.phase}")

    frame = PrecisionTargetFrame(
        phase=updated_state.phase,
        score=updated_state.score,
        status_text=updated_state.status_text,
        ball_spec_label=updated_state.ball_spec.label if updated_state.ball_spec is not None else "--",
        focal_length_px=updated_state.focal_length_px,
        bullseye_center=(
            None if updated_state.bullseye_center is None else updated_state.bullseye_center.copy()
        ),
        wall_calibration=updated_state.wall_calibration,
        current_depth=updated_state.current_depth,
        current_relative_depth_m=updated_state.current_relative_depth_m,
        zero_reference_depth_m=updated_state.zero_reference_depth_m,
        last_impact=updated_state.last_impact,
        last_score=updated_state.last_score,
    )
    return updated_state, frame, did_score


def draw_precision_target_mode(
    frame: np.ndarray,
    mode_frame: PrecisionTargetFrame,
) -> None:
    bullseye_center = mode_frame.bullseye_center
    wall_calibration = mode_frame.wall_calibration
    if bullseye_center is not None:
        center_xy = tuple(int(round(value)) for value in bullseye_center)
        if wall_calibration is not None and wall_calibration.wall_distance_m > 0.0:
            for score_index, radius_cm in enumerate(reversed(RING_RADII_CM), start=1):
                radius_px = int(
                    round((radius_cm / 100.0) * mode_frame.focal_length_px / wall_calibration.wall_distance_m)
                )
                radius_px = max(radius_px, 6)
                color = (
                    (40 + score_index * 35),
                    max(30, 255 - score_index * 28),
                    255 if score_index % 2 == 0 else 180,
                )
                cv2.circle(frame, center_xy, radius_px, color, 2, lineType=cv2.LINE_AA)
        cv2.drawMarker(
            frame,
            center_xy,
            (0, 220, 255),
            markerType=cv2.MARKER_CROSS,
            markerSize=18,
            thickness=2,
            line_type=cv2.LINE_AA,
        )
        cv2.circle(frame, center_xy, 4, (255, 255, 255), -1, lineType=cv2.LINE_AA)

    draw_label_right(
        frame,
        f"Precision Score: {mode_frame.score}",
        HUD_RIGHT_MARGIN,
        HUD_BASELINE_Y,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
    draw_label_right(
        frame,
        f"Phase: {_format_phase_label(mode_frame.phase)}",
        HUD_RIGHT_MARGIN,
        HUD_BASELINE_Y + HUD_LINE_HEIGHT,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
    draw_label_right(
        frame,
        f"Ball: {mode_frame.ball_spec_label}",
        HUD_RIGHT_MARGIN,
        HUD_BASELINE_Y + HUD_LINE_HEIGHT * 2,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
    if mode_frame.zero_reference_depth_m is not None:
        draw_label_right(
            frame,
            f"Zero: {mode_frame.zero_reference_depth_m:.2f} m",
            HUD_RIGHT_MARGIN,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 3,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
    if mode_frame.wall_calibration is not None:
        wall_relative_m = mode_frame.wall_calibration.wall_distance_m
        if mode_frame.zero_reference_depth_m is not None:
            wall_relative_m = max(wall_relative_m - mode_frame.zero_reference_depth_m, 0.0)
        draw_label_right(
            frame,
            f"Wall: {wall_relative_m:.2f} m",
            HUD_RIGHT_MARGIN,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 4,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
    if mode_frame.current_relative_depth_m is not None:
        draw_label_right(
            frame,
            f"Depth: {mode_frame.current_relative_depth_m:.2f} m",
            HUD_RIGHT_MARGIN,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 5,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
    if mode_frame.last_impact is not None:
        draw_label_right(
            frame,
            f"Last Shot: {mode_frame.last_impact.radial_distance_cm:.1f} cm",
            HUD_RIGHT_MARGIN,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 6,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
        draw_label_right(
            frame,
            f"Last Score: {mode_frame.last_score}",
            HUD_RIGHT_MARGIN,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 7,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )

    draw_label(
        frame,
        mode_frame.status_text,
        8,
        max(frame.shape[0] - 18, HUD_BASELINE_Y),
        font_scale=0.55,
        thickness=1,
    )


def _ensure_ball_configured(
    state: PrecisionTargetState,
    *,
    ball_spec: Optional[BallSpec] = None,
    focal_length_px: Optional[float] = None,
) -> PrecisionTargetState:
    if state.ball_spec is None and ball_spec is not None:
        state.ball_spec = ball_spec
    if focal_length_px is not None:
        state.focal_length_px = float(focal_length_px)
    return state


def _build_depth_sample(
    track: Optional[BallTrack],
    candidate: Optional[DetectionCandidate],
    timestamp: float,
    ball_spec: Optional[BallSpec],
    focal_length_px: float,
    window: deque[float],
    previous_smoothed: Optional[float],
) -> tuple[Optional[DepthSample], Optional[DepthEstimate], Optional[float]]:
    if ball_spec is None:
        return None, None, previous_smoothed

    center: Optional[np.ndarray] = None
    pixel_diameter_px: Optional[float] = None
    if candidate is not None:
        center = candidate.center.copy()
        pixel_diameter_px = max((float(candidate.width) + float(candidate.height)) * 0.5, 1.0)
    elif track is not None and (is_track_live(track, min_confirmed_frames=2) or track.confirmed_frames >= 1):
        center = track.center.copy()
        pixel_diameter_px = max((float(track.width) + float(track.height)) * 0.5, 1.0)
    else:
        return None, None, previous_smoothed

    window.append(pixel_diameter_px)
    median_px = float(np.median(np.array(window, dtype=np.float64)))
    smoothed_px = median_px if previous_smoothed is None else (
        previous_smoothed + (median_px - previous_smoothed) * CALIBRATION_SMOOTHING_ALPHA
    )
    depth_m = estimate_distance_m(ball_spec.diameter_m, focal_length_px, smoothed_px)
    raw_depth_m = estimate_distance_m(ball_spec.diameter_m, focal_length_px, pixel_diameter_px)
    depth_estimate = DepthEstimate(distance_m=depth_m, pixel_diameter_px=smoothed_px)
    sample = DepthSample(
        timestamp=timestamp,
        center=center,
        pixel_diameter_px=pixel_diameter_px,
        smoothed_diameter_px=smoothed_px,
        raw_estimated_distance_m=raw_depth_m,
        estimated_distance_m=depth_m,
    )
    return sample, depth_estimate, smoothed_px


def _step_calibration(
    state: PrecisionTargetState,
    sample: Optional[DepthSample],
) -> PrecisionTargetState:
    if sample is None:
        if state.calibration_elapsed_s <= 0.0:
            state.status_text = "Keep the ball visible at the wall for 10 seconds"
            return state
        state.calibration_missing_frames += 1
        if state.calibration_missing_frames > HOLD_MAX_MISSING_FRAMES:
            return _reset_calibration_attempt(
                state,
                "Wall hold lost too long. Hold the ball at the wall again.",
            )
        state.calibration_started_at = None
        remaining_s = max(WALL_HOLD_SECONDS - state.calibration_elapsed_s, 0.0)
        state.status_text = (
            f"Wall hold paused. Reacquire the ball to continue: {remaining_s:.1f}s remaining"
        )
        return state

    if state.calibration_started_at is None:
        state.calibration_started_at = sample.timestamp
    else:
        state.calibration_elapsed_s += min(
            max(sample.timestamp - state.calibration_started_at, 0.0),
            HOLD_MAX_FRAME_DT_S,
        )
        state.calibration_started_at = sample.timestamp
    state.calibration_missing_frames = 0

    state.calibration_depth_samples.append(sample.raw_estimated_distance_m)
    state.calibration_diameter_samples.append(sample.pixel_diameter_px)
    elapsed_s = state.calibration_elapsed_s
    remaining_s = max(WALL_HOLD_SECONDS - elapsed_s, 0.0)
    if elapsed_s + HOLD_COMPLETION_EPSILON_S < WALL_HOLD_SECONDS:
        state.status_text = f"Hold the ball at the wall: {remaining_s:.1f}s remaining"
        return state

    calibration = _build_wall_calibration_from_hold(state, confidence=0.95)
    if calibration is None:
        return _reset_calibration_attempt(
            state,
            "Wall hold calibration failed. Hold the ball at the wall again.",
        )

    state.wall_calibration = calibration
    state.phase = PRECISION_TARGET_PHASE_LIVE
    state.status_text = "Calibration locked. Hit the bullseye."
    state.throw_state = ThrowState()
    state.calibration_started_at = None
    state.calibration_elapsed_s = 0.0
    state.calibration_depth_samples.clear()
    state.calibration_diameter_samples.clear()
    state.calibration_missing_frames = 0
    return state


def _step_reference_depth(
    state: PrecisionTargetState,
    sample: Optional[DepthSample],
    timestamp: float,
) -> PrecisionTargetState:
    if sample is None:
        if state.reference_elapsed_s <= 0.0:
            state.status_text = "Keep the ball visible at your passing spot for 5 seconds"
            return state
        state.reference_missing_frames += 1
        if state.reference_missing_frames > HOLD_MAX_MISSING_FRAMES:
            state.reference_started_at = None
            state.reference_elapsed_s = 0.0
            state.reference_missing_frames = 0
            state.reference_samples.clear()
            state.status_text = "Passing spot hold lost too long. Hold the ball still and start again."
            return state
        state.reference_started_at = None
        remaining_s = max(REFERENCE_HOLD_SECONDS - state.reference_elapsed_s, 0.0)
        state.status_text = (
            f"Passing spot hold paused. Reacquire the ball to continue: {remaining_s:.1f}s remaining"
        )
        return state

    if state.reference_started_at is None:
        state.reference_started_at = timestamp
    else:
        state.reference_elapsed_s += min(
            max(timestamp - state.reference_started_at, 0.0),
            HOLD_MAX_FRAME_DT_S,
        )
        state.reference_started_at = timestamp
    state.reference_missing_frames = 0

    state.reference_samples.append(sample.raw_estimated_distance_m)
    elapsed_s = state.reference_elapsed_s
    remaining_s = max(REFERENCE_HOLD_SECONDS - elapsed_s, 0.0)
    if elapsed_s + HOLD_COMPLETION_EPSILON_S < REFERENCE_HOLD_SECONDS:
        state.status_text = (
            f"Hold the ball at your passing spot: {remaining_s:.1f}s remaining"
        )
        return state

    if not state.reference_samples:
        state.status_text = "Reference capture failed. Hold the ball still and try again."
        state.reference_started_at = None
        return state

    state.zero_reference_depth_m = float(np.median(np.array(state.reference_samples, dtype=np.float64)))
    state.phase = PRECISION_TARGET_PHASE_CALIBRATION
    state.status_text = "Reference locked. Hold the ball at the wall for 10 seconds"
    state.reference_started_at = None
    state.reference_elapsed_s = 0.0
    state.reference_missing_frames = 0
    state.reference_samples.clear()
    state.calibration_window.clear()
    state.calibration_smoothed_diameter_px = None
    state.calibration_started_at = None
    state.calibration_elapsed_s = 0.0
    state.calibration_depth_samples.clear()
    state.calibration_diameter_samples.clear()
    state.calibration_missing_frames = 0
    return state


def _build_wall_calibration_from_hold(
    state: PrecisionTargetState,
    *,
    confidence: float,
) -> Optional[WallCalibration]:
    if len(state.calibration_depth_samples) < CALIBRATION_MIN_VALID_SAMPLES:
        return None
    median_depth_m = float(np.median(np.array(state.calibration_depth_samples, dtype=np.float64)))
    median_diameter_px = float(np.median(np.array(state.calibration_diameter_samples, dtype=np.float64)))
    if median_diameter_px < CALIBRATION_MIN_DIAMETER_PX:
        return None
    wall_distance_m = median_depth_m
    if not (CALIBRATION_MIN_WALL_DISTANCE_M <= wall_distance_m <= CALIBRATION_MAX_WALL_DISTANCE_M):
        return None
    return WallCalibration(
        wall_distance_m=wall_distance_m,
        impact_pixel_diameter_px=median_diameter_px,
        impact_frame_time=state.calibration_started_at or 0.0,
        confidence=confidence,
    )


def _reset_calibration_attempt(state: PrecisionTargetState, message: str) -> PrecisionTargetState:
    state.calibration_window.clear()
    state.calibration_samples.clear()
    state.calibration_started_at = None
    state.calibration_elapsed_s = 0.0
    state.calibration_depth_samples.clear()
    state.calibration_diameter_samples.clear()
    state.calibration_smoothed_diameter_px = None
    state.calibration_baseline_depth_m = None
    state.calibration_outbound_frames = 0
    state.calibration_outbound_started = False
    state.calibration_min_sample = None
    state.calibration_rebound_frames = 0
    state.calibration_missing_frames = 0
    state.calibration_failures += 1
    state.current_depth = None
    state.current_relative_depth_m = None
    state.status_text = message
    return state


def _step_live_precision(
    state: PrecisionTargetState,
    sample: Optional[DepthSample],
) -> tuple[PrecisionTargetState, bool]:
    calibration = state.wall_calibration
    if calibration is None or state.bullseye_center is None:
        state.phase = PRECISION_TARGET_PHASE_CALIBRATION
        state.status_text = "Precision target needs calibration."
        return state, False

    throw_state = state.throw_state
    wall_distance_m = calibration.wall_distance_m
    zero_reference_depth_m = state.zero_reference_depth_m or 0.0
    wall_travel_m = max(wall_distance_m - zero_reference_depth_m, 0.5)
    impact_tolerance_m = max(0.20, wall_distance_m * 0.06)

    if sample is None:
        if throw_state.phase == THROW_PHASE_OUTBOUND_CONFIRMED and throw_state.furthest_sample is not None:
            throw_state.missing_frames += 1
            if (
                throw_state.missing_frames <= CALIBRATION_MAX_DISAPPEAR_FRAMES
                and throw_state.furthest_sample.raw_estimated_distance_m >= wall_distance_m - impact_tolerance_m
            ):
                return _lock_precision_impact(state, throw_state.furthest_sample), True
        elif throw_state.phase == THROW_PHASE_COOLDOWN:
            throw_state.missing_frames += 1
            if throw_state.missing_frames > THROW_COOLDOWN_MISSING_FRAMES:
                state.throw_state = ThrowState()
        return state, False

    throw_state.missing_frames = 0
    if throw_state.near_start_depth_m is None:
        throw_state.near_start_depth_m = sample.raw_estimated_distance_m
    else:
        throw_state.near_start_depth_m = min(throw_state.near_start_depth_m, sample.raw_estimated_distance_m)

    if throw_state.phase == THROW_PHASE_IDLE:
        throw_state.eligible_samples.clear()
        throw_state.outbound_frames = 0
        throw_state.furthest_sample = None
        if sample.raw_estimated_distance_m - throw_state.near_start_depth_m >= 0.12:
            throw_state.phase = THROW_PHASE_OUTBOUND_CANDIDATE
            throw_state.eligible_samples.append(sample)
            throw_state.outbound_frames = 1
            state.status_text = "Throw detected. Tracking wall approach."
        else:
            state.status_text = "Throw toward the wall"
        return state, False

    if throw_state.phase == THROW_PHASE_OUTBOUND_CANDIDATE:
        throw_state.eligible_samples.append(sample)
        if sample.raw_estimated_distance_m < throw_state.near_start_depth_m + 0.05:
            state.throw_state = ThrowState(near_start_depth_m=sample.raw_estimated_distance_m)
            state.status_text = "Throw toward the wall"
            return state, False

        previous_sample = (
            throw_state.eligible_samples[-2] if len(throw_state.eligible_samples) >= 2 else None
        )
        if (
            previous_sample is None
            or sample.raw_estimated_distance_m >= previous_sample.raw_estimated_distance_m - 0.02
        ):
            throw_state.outbound_frames += 1
        else:
            throw_state.outbound_frames = max(throw_state.outbound_frames - 1, 0)

        if (
            throw_state.outbound_frames >= THROW_OUTBOUND_MIN_FRAMES
            and (sample.raw_estimated_distance_m - throw_state.near_start_depth_m) >= wall_travel_m * 0.40
        ):
            throw_state.phase = THROW_PHASE_OUTBOUND_CONFIRMED
            throw_state.furthest_sample = sample
            state.status_text = "Outbound throw confirmed."
        return state, False

    if throw_state.phase == THROW_PHASE_OUTBOUND_CONFIRMED:
        throw_state.eligible_samples.append(sample)
        previous_sample = (
            throw_state.eligible_samples[-2] if len(throw_state.eligible_samples) >= 2 else None
        )
        if (
            throw_state.furthest_sample is None
            or sample.raw_estimated_distance_m > throw_state.furthest_sample.raw_estimated_distance_m
        ):
            throw_state.furthest_sample = sample

        furthest_sample = throw_state.furthest_sample
        if furthest_sample is None:
            return state, False

        if (
            furthest_sample.raw_estimated_distance_m >= wall_distance_m - impact_tolerance_m
            and (
                sample.raw_estimated_distance_m <= furthest_sample.raw_estimated_distance_m - THROW_IMPACT_REVERSAL_M
                or (
                    previous_sample is not None
                    and sample.raw_estimated_distance_m <= previous_sample.raw_estimated_distance_m - 0.03
                )
            )
        ):
            return _lock_precision_impact(state, furthest_sample), True

        if sample.raw_estimated_distance_m < throw_state.near_start_depth_m + 0.10:
            state.throw_state = ThrowState(near_start_depth_m=sample.raw_estimated_distance_m)
            state.status_text = "Throw toward the wall"
        return state, False

    if throw_state.phase == THROW_PHASE_IMPACT_LOCKED:
        throw_state.phase = THROW_PHASE_COOLDOWN
        state.status_text = "Impact locked."
        return state, False

    if throw_state.phase == THROW_PHASE_COOLDOWN:
        if sample.raw_estimated_distance_m <= max(wall_distance_m - THROW_RESET_RETURN_DEPTH_M, 0.0):
            state.throw_state = ThrowState(near_start_depth_m=sample.raw_estimated_distance_m)
            state.status_text = "Ready for the next throw"
        else:
            state.status_text = "Waiting for ball reset"
        return state, False

    return state, False


def _lock_precision_impact(
    state: PrecisionTargetState,
    impact_sample: DepthSample,
) -> PrecisionTargetState:
    throw_state = state.throw_state
    average_center = _average_recent_centers(throw_state.eligible_samples, impact_sample.timestamp)
    if not np.any(average_center):
        average_center = impact_sample.center.copy()
    bullseye_center = state.bullseye_center
    wall_distance_m = state.wall_calibration.wall_distance_m
    dx_cm = pixel_offset_to_cm(average_center[0] - bullseye_center[0], wall_distance_m, state.focal_length_px)
    dy_cm = pixel_offset_to_cm(average_center[1] - bullseye_center[1], wall_distance_m, state.focal_length_px)
    radial_distance_cm = math.hypot(dx_cm, dy_cm)
    score = score_from_radial_distance(radial_distance_cm)
    state.last_impact = PrecisionImpact(
        center=average_center,
        radial_distance_cm=radial_distance_cm,
        dx_cm=dx_cm,
        dy_cm=dy_cm,
        score=score,
        frame_time=impact_sample.timestamp,
    )
    state.last_score = score
    state.score += score
    state.scored_throws += 1
    throw_state.phase = THROW_PHASE_COOLDOWN
    throw_state.missing_frames = 0
    state.status_text = (
        f"Hit scored: {score}" if score > 0 else f"Missed: {radial_distance_cm:.1f} cm off center"
    )
    return state


def _average_recent_centers(samples: deque[DepthSample], impact_timestamp: float) -> np.ndarray:
    centers: list[np.ndarray] = []
    for sample in reversed(samples):
        if sample.timestamp > impact_timestamp:
            continue
        centers.append(sample.center)
        if len(centers) == 3:
            break
    if not centers:
        return np.zeros(2, dtype=np.float32)
    return np.mean(np.stack(list(reversed(centers))), axis=0).astype(np.float32)


def _format_phase_label(phase: str) -> str:
    if phase == PRECISION_TARGET_PHASE_SELECT_CENTER:
        return "Select Center"
    if phase == PRECISION_TARGET_PHASE_REFERENCE:
        return "Reference"
    if phase == PRECISION_TARGET_PHASE_CALIBRATION:
        return "Calibration"
    if phase == PRECISION_TARGET_PHASE_LIVE:
        return "Live"
    return phase.replace("_", " ").title()
