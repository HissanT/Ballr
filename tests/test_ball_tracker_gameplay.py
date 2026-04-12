import numpy as np

from ball_tracker_targets import (
    TARGET_BALL_CLEARANCE,
    TARGET_COMBO_STREAK_STEP,
    TARGET_LIFETIME_SECONDS,
    TARGET_LOWER_Y_FRACTION,
    TARGET_MISS_PENALTY,
    TARGET_RESPAWN_DISTANCE_MULTIPLIER,
    TARGET_SCORE_BURST_SECONDS,
    TARGET_SCORE_EFFECT_SECONDS,
    TARGET_SCORE_POPUP_DELAY_SECONDS,
    TARGET_SCORE_POPUP_SECONDS,
    TargetState,
    combo_multiplier_for_streak,
    expire_target,
    next_combo_threshold_for_streak,
    score_target,
    scored_target_effect_burst_progress,
    scored_target_effect_is_active,
    scored_target_effect_popup_progress,
    spawn_initial_target,
    spawn_target,
    target_base_points,
    target_fade_alpha,
    target_has_expired,
    target_hit,
    target_spawn_bounds,
)
from ball_tracker_tracking import BallTrack


def make_track(
    center=(320.0, 360.0),
    radius=24.0,
    misses=0,
    confirmed_frames=2,
) -> BallTrack:
    return BallTrack(
        center=np.array(center, dtype=np.float32),
        velocity=np.zeros(2, dtype=np.float32),
        radius=radius,
        confidence=0.9,
        track_id=1,
        misses=misses,
        confirmed_frames=confirmed_frames,
    )


def make_target(center=(220.0, 320.0), radius=30, spawned_at=0.0) -> TargetState:
    return TargetState(
        center=np.array(center, dtype=np.float32),
        radius=radius,
        spawned_at=spawned_at,
    )


def test_spawn_target_stays_within_bounds():
    radius = 34
    frame_size = (480, 640)
    rng = np.random.default_rng(5)

    center = spawn_target(frame_size, radius, rng=rng)
    min_x, max_x, min_y, max_y = target_spawn_bounds(frame_size, radius)

    assert min_x <= center[0] <= max_x
    assert min_y <= center[1] <= max_y
    assert center[0] - radius >= 0
    assert center[0] + radius <= frame_size[1]
    assert center[1] - radius >= frame_size[0] * TARGET_LOWER_Y_FRACTION
    assert center[1] + radius <= frame_size[0]


def test_spawn_target_keeps_distance_from_previous_center():
    radius = 32
    frame_size = (480, 640)
    previous_center = np.array((320.0, 400.0), dtype=np.float32)
    rng = np.random.default_rng(9)

    center = spawn_target(frame_size, radius, rng=rng, previous_center=previous_center)

    assert np.linalg.norm(center - previous_center) >= TARGET_RESPAWN_DISTANCE_MULTIPLIER * radius


def test_spawn_target_keeps_clear_of_live_ball():
    radius = 30
    frame_size = (480, 640)
    ball_track = make_track(center=(320.0, 360.0), radius=26.0, misses=0, confirmed_frames=4)
    rng = np.random.default_rng(12)

    center = spawn_target(frame_size, radius, rng=rng, ball_track=ball_track)

    minimum_distance = ball_track.radius + radius + TARGET_BALL_CLEARANCE
    assert np.linalg.norm(center - ball_track.center) >= minimum_distance


def test_spawn_initial_target_sets_spawn_time():
    target = spawn_initial_target((480, 640), 30, timestamp=12.5, rng=np.random.default_rng(3))

    assert target.spawned_at == 12.5


def test_target_hit_counts_boundary_contact():
    track = make_track(center=(100.0, 200.0), radius=24.0, misses=0, confirmed_frames=3)
    target = make_target(center=(154.0, 200.0))

    assert target_hit(track, target)


def test_target_hit_ignores_held_track_predictions():
    track = make_track(center=(100.0, 200.0), radius=24.0, misses=1, confirmed_frames=3)
    target = make_target(center=(120.0, 200.0))

    assert not target_hit(track, target)


def test_target_hit_requires_confirmed_frames():
    track = make_track(center=(100.0, 200.0), radius=24.0, misses=0, confirmed_frames=1)
    target = make_target(center=(120.0, 200.0))

    assert not target_hit(track, target)


def test_target_base_points_follow_decay_bands():
    target = make_target(spawned_at=1.0)

    assert target_base_points(target, 3.00) == 5
    assert target_base_points(target, 3.01) == 4
    assert target_base_points(target, 3.40) == 4
    assert target_base_points(target, 3.41) == 3
    assert target_base_points(target, 3.81) == 2
    assert target_base_points(target, 4.21) == 1


def test_target_fades_and_expires_after_four_seconds():
    target = make_target(spawned_at=10.0)

    assert np.isclose(target_fade_alpha(target, 10.0), 1.0)
    assert 0.0 < target_fade_alpha(target, 12.0) < 1.0
    assert target_fade_alpha(target, 14.0) == 0.0
    assert not target_has_expired(target, 13.99)
    assert target_has_expired(target, 14.0)
    assert TARGET_LIFETIME_SECONDS == 4.0


def test_combo_multiplier_unlocks_every_ten_hits():
    assert combo_multiplier_for_streak(0) == 1
    assert combo_multiplier_for_streak(TARGET_COMBO_STREAK_STEP - 1) == 1
    assert combo_multiplier_for_streak(TARGET_COMBO_STREAK_STEP) == 2
    assert combo_multiplier_for_streak(TARGET_COMBO_STREAK_STEP * 2) == 3
    assert next_combo_threshold_for_streak(0) == 10
    assert next_combo_threshold_for_streak(10) == 20


def test_score_target_awards_dynamic_points_and_respawns_immediately():
    target = make_target(center=(220.0, 320.0), radius=30, spawned_at=11.4)
    ball_track = make_track(center=(220.0, 320.0), radius=24.0, misses=0, confirmed_frames=4)

    result = score_target(
        target,
        timestamp=12.5,
        frame_size=(480, 640),
        base_points=4,
        combo_multiplier=2,
        rng=np.random.default_rng(4),
        ball_track=ball_track,
    )

    assert result.awarded_points == 8
    assert result.base_points == 4
    assert result.target.radius == target.radius
    assert result.target.spawned_at == 12.5
    assert np.linalg.norm(result.target.center - target.center) >= (
        TARGET_RESPAWN_DISTANCE_MULTIPLIER * target.radius
    )
    assert np.array_equal(result.effect.center, np.array((220.0, 320.0), dtype=np.float32))
    assert result.effect.radius == 30
    assert result.effect.points == 8
    assert result.effect.started_at == 12.5


def test_score_target_respawn_stays_clear_of_live_ball():
    target = make_target(center=(320.0, 360.0), radius=30, spawned_at=7.0)
    ball_track = make_track(center=(320.0, 360.0), radius=26.0, misses=0, confirmed_frames=4)

    result = score_target(
        target,
        timestamp=8.0,
        frame_size=(480, 640),
        base_points=5,
        combo_multiplier=1,
        rng=np.random.default_rng(4),
        ball_track=ball_track,
    )

    minimum_distance = ball_track.radius + target.radius + TARGET_BALL_CLEARANCE
    assert np.linalg.norm(result.target.center - ball_track.center) >= minimum_distance


def test_expire_target_returns_penalty_and_respawns():
    target = make_target(center=(220.0, 320.0), radius=30, spawned_at=0.0)

    result = expire_target(
        target,
        timestamp=4.0,
        frame_size=(480, 640),
        rng=np.random.default_rng(2),
    )

    assert result.penalty_points == TARGET_MISS_PENALTY
    assert result.target.spawned_at == 4.0
    assert result.target.radius == target.radius
    assert result.effect.points == -TARGET_MISS_PENALTY
    assert not result.effect.show_burst


def test_scored_target_effect_lifecycle_transitions_from_burst_to_popup():
    result = score_target(
        make_target(center=(320.0, 360.0), radius=30, spawned_at=0.0),
        timestamp=1.0,
        frame_size=(480, 640),
        base_points=5,
        combo_multiplier=1,
        rng=np.random.default_rng(1),
    )
    effect = result.effect

    assert scored_target_effect_is_active(effect, 1.0)
    burst_midpoint = 1.0 + (TARGET_SCORE_BURST_SECONDS * 0.5)
    assert np.isclose(scored_target_effect_burst_progress(effect, burst_midpoint), 0.5)
    assert np.isclose(
        scored_target_effect_popup_progress(effect, 1.0 + TARGET_SCORE_POPUP_DELAY_SECONDS - 0.01),
        0.0,
    )

    popup_time = 1.0 + TARGET_SCORE_POPUP_DELAY_SECONDS + (TARGET_SCORE_POPUP_SECONDS * 0.25)
    assert np.isclose(scored_target_effect_popup_progress(effect, popup_time), 0.25)
    assert scored_target_effect_is_active(effect, 1.0 + TARGET_SCORE_EFFECT_SECONDS - 0.01)
    assert not scored_target_effect_is_active(effect, 1.0 + TARGET_SCORE_EFFECT_SECONDS)
