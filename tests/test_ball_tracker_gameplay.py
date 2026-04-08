import numpy as np

from ball_tracker import (
    BallTrack,
    ScoredTargetEffect,
    TargetState,
    TARGET_BALL_CLEARANCE,
    TARGET_LOWER_Y_FRACTION,
    TARGET_RESPAWN_DISTANCE_MULTIPLIER,
    TARGET_SCORE_BURST_SECONDS,
    TARGET_SCORE_EFFECT_SECONDS,
    TARGET_SCORE_POPUP_DELAY_SECONDS,
    TARGET_SCORE_POPUP_SECONDS,
    TARGET_SCORE_VALUE,
    score_target,
    scored_target_effect_burst_progress,
    scored_target_effect_is_active,
    scored_target_effect_popup_progress,
    spawn_target,
    target_hit,
    target_spawn_bounds,
)


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


def test_target_hit_counts_boundary_contact():
    track = make_track(center=(100.0, 200.0), radius=24.0, misses=0, confirmed_frames=3)
    target = TargetState(
        center=np.array((154.0, 200.0), dtype=np.float32),
        radius=30,
        score=0,
    )

    assert target_hit(track, target)


def test_target_hit_ignores_held_track_predictions():
    track = make_track(center=(100.0, 200.0), radius=24.0, misses=1, confirmed_frames=3)
    target = TargetState(
        center=np.array((120.0, 200.0), dtype=np.float32),
        radius=30,
        score=0,
    )

    assert not target_hit(track, target)


def test_target_hit_requires_confirmed_frames():
    track = make_track(center=(100.0, 200.0), radius=24.0, misses=0, confirmed_frames=1)
    target = TargetState(
        center=np.array((120.0, 200.0), dtype=np.float32),
        radius=30,
        score=0,
    )

    assert not target_hit(track, target)


def test_score_target_awards_points_and_respawns_immediately():
    target = TargetState(
        center=np.array((220.0, 320.0), dtype=np.float32),
        radius=30,
        score=10,
    )
    ball_track = make_track(center=(220.0, 320.0), radius=24.0, misses=0, confirmed_frames=4)

    updated_target, effect = score_target(
        target,
        timestamp=12.5,
        frame_size=(480, 640),
        rng=np.random.default_rng(4),
        ball_track=ball_track,
    )

    assert updated_target.score == 10 + TARGET_SCORE_VALUE
    assert updated_target.radius == target.radius
    assert np.linalg.norm(updated_target.center - target.center) >= (
        TARGET_RESPAWN_DISTANCE_MULTIPLIER * target.radius
    )
    assert np.array_equal(effect.center, np.array((220.0, 320.0), dtype=np.float32))
    assert effect.radius == 30
    assert effect.points == TARGET_SCORE_VALUE
    assert effect.started_at == 12.5


def test_score_target_respawn_stays_clear_of_live_ball():
    target = TargetState(
        center=np.array((320.0, 360.0), dtype=np.float32),
        radius=30,
        score=3,
    )
    ball_track = make_track(center=(320.0, 360.0), radius=26.0, misses=0, confirmed_frames=4)

    updated_target, _effect = score_target(
        target,
        timestamp=8.0,
        frame_size=(480, 640),
        rng=np.random.default_rng(4),
        ball_track=ball_track,
    )

    minimum_distance = ball_track.radius + target.radius + TARGET_BALL_CLEARANCE
    assert np.linalg.norm(updated_target.center - ball_track.center) >= minimum_distance


def test_scored_target_effect_lifecycle_transitions_from_burst_to_popup():
    effect = ScoredTargetEffect(
        center=np.array((320.0, 360.0), dtype=np.float32),
        radius=30,
        points=TARGET_SCORE_VALUE,
        started_at=1.0,
    )

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
