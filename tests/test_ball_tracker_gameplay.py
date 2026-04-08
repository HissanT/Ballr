import numpy as np

from ball_tracker import (
    BallTrack,
    TargetState,
    TARGET_BALL_CLEARANCE,
    TARGET_LOWER_Y_FRACTION,
    TARGET_PHASE_SCORING,
    TARGET_RESPAWN_DISTANCE_MULTIPLIER,
    TARGET_SCORE_ANIMATION_SECONDS,
    advance_target_state,
    begin_target_scoring,
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


def test_target_hit_ignores_scoring_targets():
    track = make_track(center=(100.0, 200.0), radius=24.0, misses=0, confirmed_frames=3)
    target = TargetState(
        center=np.array((120.0, 200.0), dtype=np.float32),
        radius=30,
        score=0,
        phase=TARGET_PHASE_SCORING,
        phase_started_at=1.0,
    )

    assert not target_hit(track, target)


def test_begin_target_scoring_increments_score_and_locks_target():
    target = TargetState(
        center=np.array((220.0, 320.0), dtype=np.float32),
        radius=30,
        score=4,
    )

    updated = begin_target_scoring(target, timestamp=12.5)

    assert updated.score == 5
    assert updated.phase == TARGET_PHASE_SCORING
    assert updated.phase_started_at == 12.5
    assert np.array_equal(updated.center, target.center)


def test_advance_target_state_respawns_after_scoring_animation():
    target = TargetState(
        center=np.array((320.0, 360.0), dtype=np.float32),
        radius=30,
        score=3,
        phase=TARGET_PHASE_SCORING,
        phase_started_at=1.0,
    )
    ball_track = make_track(center=(320.0, 360.0), radius=26.0, misses=0, confirmed_frames=4)
    rng = np.random.default_rng(4)

    updated = advance_target_state(
        target,
        timestamp=1.0 + TARGET_SCORE_ANIMATION_SECONDS + 0.01,
        frame_size=(480, 640),
        rng=rng,
        ball_track=ball_track,
    )

    assert updated.score == target.score
    assert updated.phase != TARGET_PHASE_SCORING
    assert np.linalg.norm(updated.center - target.center) >= TARGET_RESPAWN_DISTANCE_MULTIPLIER * target.radius


def test_advance_target_state_holds_target_until_animation_completes():
    target = TargetState(
        center=np.array((320.0, 360.0), dtype=np.float32),
        radius=30,
        score=3,
        phase=TARGET_PHASE_SCORING,
        phase_started_at=1.0,
    )

    updated = advance_target_state(
        target,
        timestamp=1.0 + TARGET_SCORE_ANIMATION_SECONDS - 0.02,
        frame_size=(480, 640),
        rng=np.random.default_rng(4),
    )

    assert np.array_equal(updated.center, target.center)
    assert updated.phase == TARGET_PHASE_SCORING
