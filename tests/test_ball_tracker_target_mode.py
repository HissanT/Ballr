import numpy as np

from ball_tracker import ball_tracker_target_mode
from ball_tracker.ball_tracker_rendering import RenderCache
from ball_tracker.ball_tracker_target_mode import (
    TargetModeFrame,
    TargetModeState,
    draw_target_mode,
    step_target_mode,
)
from ball_tracker.ball_tracker_targets import TargetState
from ball_tracker.ball_tracker_tracking import BallTrack


def make_track(
    center=(320.0, 360.0),
    radius=24.0,
    misses=0,
    confirmed_frames=3,
) -> BallTrack:
    return BallTrack(
        center=np.array(center, dtype=np.float32),
        velocity=np.zeros(2, dtype=np.float32),
        width=radius * 2.0,
        height=radius * 2.0,
        radius=radius,
        confidence=0.9,
        track_id=1,
        misses=misses,
        confirmed_frames=confirmed_frames,
    )


def make_target(center=(320.0, 360.0), radius=30, spawned_at=0.0) -> TargetState:
    return TargetState(
        center=np.array(center, dtype=np.float32),
        radius=radius,
        spawned_at=spawned_at,
    )


def test_step_target_mode_scores_hit_and_unlocks_next_multiplier():
    state = TargetModeState(
        target=make_target(spawned_at=11.5),
        score=20,
        hit_streak=9,
    )

    next_state, frame, did_score = step_target_mode(
        state,
        make_track(),
        (480, 640),
        12.5,
        np.random.default_rng(4),
        RenderCache(),
    )

    assert did_score
    assert next_state.score == 25
    assert next_state.hit_streak == 10
    assert frame.combo_multiplier == 2
    assert frame.next_combo_threshold == 20
    assert frame.score_effects[-1].points == 5
    assert frame.combo_effects[-1].points == 1


def test_step_target_mode_applies_new_multiplier_on_following_hit():
    state = TargetModeState(
        target=make_target(spawned_at=20.0),
        score=25,
        hit_streak=10,
    )

    next_state, frame, did_score = step_target_mode(
        state,
        make_track(),
        (480, 640),
        20.5,
        np.random.default_rng(5),
        RenderCache(),
    )

    assert did_score
    assert next_state.score == 35
    assert next_state.hit_streak == 11
    assert frame.combo_multiplier == 2
    assert frame.score_effects[-1].points == 10
    assert frame.combo_effects[-1].points == 1


def test_step_target_mode_expires_target_before_hit_resolution():
    state = TargetModeState(
        target=make_target(spawned_at=8.0),
        score=10,
        hit_streak=4,
    )

    next_state, frame, did_score = step_target_mode(
        state,
        make_track(),
        (480, 640),
        12.0,
        np.random.default_rng(6),
        RenderCache(),
    )

    assert not did_score
    assert next_state.score == 9
    assert next_state.hit_streak == 0
    assert frame.combo_multiplier == 1
    assert frame.target.spawned_at == 12.0
    assert frame.score_effects[-1].points == -1


def test_step_target_mode_clamps_score_at_zero_on_miss():
    state = TargetModeState(
        target=make_target(spawned_at=1.0),
        score=1,
        hit_streak=7,
    )

    next_state, frame, _did_score = step_target_mode(
        state,
        None,
        (480, 640),
        5.0,
        np.random.default_rng(7),
        RenderCache(),
    )

    assert next_state.score == 0
    assert next_state.hit_streak == 0
    assert frame.combo_multiplier == 1
    assert frame.score_effects[-1].points == -1


def test_step_target_mode_spawns_initial_target_when_missing():
    next_state, frame, did_score = step_target_mode(
        TargetModeState(),
        None,
        (480, 640),
        5.0,
        np.random.default_rng(8),
        RenderCache(),
    )

    assert not did_score
    assert next_state.target is not None
    assert frame.target.spawned_at == 5.0
    assert frame.score == 0


def test_draw_target_mode_renders_combo_badge_when_streak_is_active(monkeypatch):
    labels: list[str] = []
    popup_destinations: list[np.ndarray] = []

    monkeypatch.setattr(ball_tracker_target_mode, "draw_target", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        ball_tracker_target_mode,
        "draw_scored_target_effects",
        lambda _frame, _effects, _timestamp, **kwargs: popup_destinations.append(kwargs["popup_destination"]),
    )
    monkeypatch.setattr(
        ball_tracker_target_mode,
        "draw_label_right",
        lambda _frame, text, *_args, **_kwargs: labels.append(text),
    )

    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    draw_target_mode(
        frame,
        TargetModeFrame(
            target=make_target(spawned_at=5.0),
            score_effects=[],
            combo_effects=[],
            score=42,
            hit_streak=17,
            combo_multiplier=2,
            next_combo_threshold=20,
            target_fade_alpha=0.5,
        ),
        5.5,
        render_cache=RenderCache(),
    )

    assert labels == ["Score: 42", "Combo: 17/20", "x2"]
    assert np.array_equal(popup_destinations[0], np.array((536.0, 40.0), dtype=np.float32))
    assert np.array_equal(popup_destinations[1], np.array((104.0, 40.0), dtype=np.float32))
