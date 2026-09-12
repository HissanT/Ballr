import numpy as np

from ball_tracker.ball_tracker_precision_target import (
    DEFAULT_FOCAL_LENGTH_PX,
    FOCAL_LENGTH_REFERENCE_WIDTH_PX,
    PRECISION_TARGET_PHASE_REFERENCE,
    PRECISION_TARGET_PHASE_CALIBRATION,
    PRECISION_TARGET_PHASE_LIVE,
    BallSpec,
    PrecisionTargetState,
    WallCalibration,
    parse_ball_spec,
    pixel_offset_to_cm,
    resolve_effective_focal_length_px,
    score_from_radial_distance,
    step_precision_target_mode,
)
from ball_tracker.ball_tracker_tracking import BallTrack


def make_track(
    diameter_px: float,
    *,
    center=(320.0, 240.0),
    confidence: float = 0.95,
    confirmed_frames: int = 3,
) -> BallTrack:
    radius = diameter_px / 2.0
    return BallTrack(
        center=np.array(center, dtype=np.float32),
        velocity=np.zeros(2, dtype=np.float32),
        width=diameter_px,
        height=diameter_px,
        radius=radius,
        confidence=confidence,
        track_id=1,
        confirmed_frames=confirmed_frames,
    )


def make_live_state(
    *,
    wall_distance_m: float = 5.0,
    bullseye_center=(500.0, 400.0),
    ball_spec: BallSpec | None = None,
) -> PrecisionTargetState:
    return PrecisionTargetState(
        phase=PRECISION_TARGET_PHASE_LIVE,
        ball_spec=ball_spec or BallSpec(label="Size 5", diameter_cm=22.0),
        focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        bullseye_center=np.array(bullseye_center, dtype=np.float32),
        zero_reference_depth_m=1.0,
        wall_calibration=WallCalibration(
            wall_distance_m=wall_distance_m,
            impact_pixel_diameter_px=105.6,
            impact_frame_time=1.0,
            confidence=0.95,
        ),
        status_text="Calibration locked. Hit the bullseye.",
    )


def make_calibration_state(
    *,
    ball_spec: BallSpec | None = None,
) -> PrecisionTargetState:
    return PrecisionTargetState(
        phase=PRECISION_TARGET_PHASE_CALIBRATION,
        ball_spec=ball_spec or BallSpec(label="Size 5", diameter_cm=22.0),
        focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        bullseye_center=np.array((400.0, 240.0), dtype=np.float32),
        zero_reference_depth_m=1.0,
        status_text="Reference locked. Hold the ball at the wall for 10 seconds",
    )


def test_parse_ball_spec_supports_presets_and_custom_sizes():
    preset = parse_ball_spec("5", None)
    custom = parse_ball_spec("custom", 18.4)

    assert preset.label == "Size 5"
    assert preset.diameter_cm == 22.0
    assert custom.label == "Custom 18.4 cm"
    assert custom.diameter_cm == 18.4


def test_pixel_offset_conversion_matches_wall_geometry():
    horizontal_cm = pixel_offset_to_cm(40.0, 5.0, DEFAULT_FOCAL_LENGTH_PX)
    vertical_cm = pixel_offset_to_cm(20.0, 5.0, DEFAULT_FOCAL_LENGTH_PX)

    assert round(horizontal_cm, 3) == 8.333
    assert round(vertical_cm, 3) == 4.167


def test_effective_focal_length_scales_with_frame_width():
    effective_focal_px = resolve_effective_focal_length_px(2400.0, 640)

    assert FOCAL_LENGTH_REFERENCE_WIDTH_PX == 1920.0
    assert round(effective_focal_px, 3) == 800.0


def test_reference_hold_phase_locks_zero_depth_after_five_seconds():
    state = PrecisionTargetState()
    ball_spec = BallSpec(label="Size 5", diameter_cm=22.0)
    timestamp = 0.0

    state, frame, _ = step_precision_target_mode(
        state,
        make_track(86.0),
        None,
        (480, 640),
        timestamp,
        ball_spec=ball_spec,
        focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        bullseye_click=np.array((400.0, 240.0), dtype=np.float32),
    )

    assert frame.phase == PRECISION_TARGET_PHASE_REFERENCE

    for _ in range(151):
        timestamp += 1.0 / 30.0
        state, frame, _ = step_precision_target_mode(
            state,
            make_track(86.0),
            None,
            (480, 640),
            timestamp,
            ball_spec=ball_spec,
            focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        )

    assert frame.phase == PRECISION_TARGET_PHASE_CALIBRATION
    assert frame.zero_reference_depth_m is not None


def test_wall_hold_calibration_locks_wall_distance_after_ten_seconds():
    state = make_calibration_state()
    ball_spec = state.ball_spec
    timestamp = 0.0

    for _ in range(301):
        timestamp += 1.0 / 30.0
        state, frame, _ = step_precision_target_mode(
            state,
            make_track(52.0),
            None,
            (480, 640),
            timestamp,
            ball_spec=ball_spec,
            focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        )

    assert frame.phase == PRECISION_TARGET_PHASE_LIVE
    assert frame.wall_calibration is not None
    assert 9.0 < frame.wall_calibration.wall_distance_m < 11.0


def test_wall_hold_calibration_pauses_through_brief_disappearance():
    state = make_calibration_state()
    ball_spec = state.ball_spec
    timestamp = 0.0

    for _ in range(120):
        timestamp += 1.0 / 30.0
        state, _frame, _ = step_precision_target_mode(
            state,
            make_track(52.0),
            None,
            (480, 640),
            timestamp,
            ball_spec=ball_spec,
            focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        )

    for _ in range(5):
        timestamp += 1.0 / 30.0
        state, frame, _ = step_precision_target_mode(
            state,
            None,
            None,
            (480, 640),
            timestamp,
            ball_spec=ball_spec,
            focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        )

    assert frame.phase == PRECISION_TARGET_PHASE_CALIBRATION
    assert frame.wall_calibration is None
    assert "paused" in frame.status_text.lower()

    for _ in range(185):
        timestamp += 1.0 / 30.0
        state, frame, _ = step_precision_target_mode(
            state,
            make_track(52.0),
            None,
            (480, 640),
            timestamp,
            ball_spec=ball_spec,
            focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        )

    assert frame.phase == PRECISION_TARGET_PHASE_LIVE
    assert frame.wall_calibration is not None


def test_wall_hold_calibration_resets_after_long_disappearance():
    state = make_calibration_state()
    ball_spec = state.ball_spec
    timestamp = 0.0

    for _ in range(60):
        timestamp += 1.0 / 30.0
        state, _frame, _ = step_precision_target_mode(
            state,
            make_track(52.0),
            None,
            (480, 640),
            timestamp,
            ball_spec=ball_spec,
            focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        )

    for _ in range(16):
        timestamp += 1.0 / 30.0
        state, frame, _ = step_precision_target_mode(
            state,
            None,
            None,
            (480, 640),
            timestamp,
            ball_spec=ball_spec,
            focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        )

    assert frame.phase == PRECISION_TARGET_PHASE_CALIBRATION
    assert frame.wall_calibration is None
    assert "lost too long" in frame.status_text.lower()


def test_live_precision_target_scores_once_for_wall_impact():
    state = make_live_state()
    timestamp = 0.0
    wall_distance_m = state.wall_calibration.wall_distance_m
    impact_diameters = []
    for depth_m in (2.0, 2.5, 3.2, 4.0, 4.6, 5.05, 5.15, 4.85, 4.0, 3.0):
        impact_diameters.append((0.22 * DEFAULT_FOCAL_LENGTH_PX) / depth_m)

    last_frame = None
    for index, diameter_px in enumerate(impact_diameters):
        timestamp += 1.0 / 30.0
        x = 528.0 if index >= 5 else 526.0
        y = 414.0 if index >= 5 else 412.0
        state, last_frame, _ = step_precision_target_mode(
            state,
            make_track(diameter_px, center=(x, y)),
            None,
            (480, 640),
            timestamp,
            ball_spec=state.ball_spec,
            focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        )

    assert wall_distance_m == 5.0
    assert last_frame is not None
    assert last_frame.last_impact is not None
    assert last_frame.last_impact.score == 5
    assert state.score == 5
    assert state.scored_throws == 1

    for depth_m in (3.2, 2.6, 2.1, 1.8):
        timestamp += 1.0 / 30.0
        state, _frame, _ = step_precision_target_mode(
            state,
            make_track((0.22 * DEFAULT_FOCAL_LENGTH_PX) / depth_m, center=(540.0, 420.0)),
            None,
            (480, 640),
            timestamp,
            ball_spec=state.ball_spec,
            focal_length_px=DEFAULT_FOCAL_LENGTH_PX,
        )

    assert state.score == 5
    assert state.scored_throws == 1


def test_score_from_radial_distance_uses_outer_band_on_boundaries():
    assert score_from_radial_distance(7.9) == 5
    assert score_from_radial_distance(8.0) == 4
    assert score_from_radial_distance(16.0) == 3
    assert score_from_radial_distance(24.0) == 2
    assert score_from_radial_distance(32.0) == 1
    assert score_from_radial_distance(40.0) == 0
