import numpy as np

from ball_tracker_tracking import (
    MAX_MISSES,
    REFERENCE_FPS,
    DetectionCandidate,
    advance_track,
    predict_track,
    update_track,
)


def make_candidate(
    y: float,
    *,
    x: float = 320.0,
    radius: float = 22.0,
    confidence: float = 0.9,
) -> DetectionCandidate:
    return DetectionCandidate(
        x1=int(x - radius),
        y1=int(y - radius),
        x2=int(x + radius),
        y2=int(y + radius),
        center=np.array((x, y), dtype=np.float32),
        radius=radius,
        confidence=confidence,
    )


def test_update_track_initializes_motion_state():
    track, motion, next_track_id = update_track(
        None,
        None,
        make_candidate(180.0),
        1,
        5.0,
    )

    assert next_track_id == 2
    assert np.allclose(track.center, np.array((320.0, 180.0), dtype=np.float32))
    assert np.allclose(track.velocity, np.zeros(2, dtype=np.float32))
    assert motion is not None
    assert motion.last_time == 5.0
    assert motion.gravity_pf2 > 0.0


def test_update_track_produces_smoothed_nonzero_velocity():
    start_time = 2.0
    track, motion, next_track_id = update_track(
        None,
        None,
        make_candidate(200.0),
        1,
        start_time,
    )
    predicted_track, motion = predict_track(track, motion, start_time + (1.0 / REFERENCE_FPS))
    track, motion, next_track_id = update_track(
        predicted_track,
        motion,
        make_candidate(212.0),
        next_track_id,
        start_time + (1.0 / REFERENCE_FPS),
    )

    assert motion is not None
    assert next_track_id == 2
    assert 0.0 < track.velocity[1] < 12.0
    assert 200.0 < track.center[1] < 212.0


def test_predict_only_mode_carries_track_through_short_occlusion():
    start_time = 10.0
    track, motion, next_track_id = update_track(
        None,
        None,
        make_candidate(200.0),
        1,
        start_time,
    )
    predicted_track, motion = predict_track(track, motion, start_time + (1.0 / REFERENCE_FPS))
    track, motion, next_track_id = update_track(
        predicted_track,
        motion,
        make_candidate(212.0),
        next_track_id,
        start_time + (1.0 / REFERENCE_FPS),
    )

    prior_y = float(track.center[1])
    prior_vy = float(track.velocity[1])
    held_centers: list[float] = []
    held_velocities: list[float] = []

    for frame_offset in range(2, 5):
        predicted_track, motion = predict_track(
            track,
            motion,
            start_time + (frame_offset / REFERENCE_FPS),
        )
        track, motion = advance_track(predicted_track, motion)
        assert track is not None
        held_centers.append(float(track.center[1]))
        held_velocities.append(float(track.velocity[1]))

    assert next_track_id == 2
    assert track is not None
    assert track.misses == 3
    assert held_centers[0] > prior_y
    assert held_centers[2] > held_centers[1] > held_centers[0]
    assert held_velocities[0] > prior_vy
    assert held_velocities[2] > held_velocities[1] > held_velocities[0]


def test_advance_track_drops_state_after_max_misses():
    start_time = 20.0
    track, motion, next_track_id = update_track(
        None,
        None,
        make_candidate(200.0),
        1,
        start_time,
    )

    for frame_offset in range(1, MAX_MISSES + 2):
        track, motion = predict_track(track, motion, start_time + (frame_offset / REFERENCE_FPS))
        track, motion = advance_track(track, motion)

    assert next_track_id == 2
    assert track is None
    assert motion is None
