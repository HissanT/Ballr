import numpy as np

from ball_tracker_tracking import (
    CONTACT_HOLD_FRAMES,
    CONTACT_NIS_THRESHOLD,
    MAX_MISSES,
    REFERENCE_FPS,
    BallMotionState,
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
        width=radius * 2.0,
        height=radius * 2.0,
        radius=radius,
        confidence=confidence,
    )


def clone_motion_state(motion: BallMotionState) -> BallMotionState:
    return BallMotionState(
        state=motion.state.copy(),
        covariance=motion.covariance.copy(),
        last_time=motion.last_time,
        gravity_pf2=motion.gravity_pf2,
        last_measurement=(
            None if motion.last_measurement is None else motion.last_measurement.copy()
        ),
        last_measurement_time=motion.last_measurement_time,
        contact_countdown=motion.contact_countdown,
        nis=motion.nis,
        vy_raw=motion.vy_raw,
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
    assert track.nis == 0.0
    assert track.vy_raw is None
    assert motion is not None
    assert motion.last_time == 5.0
    assert motion.gravity_pf2 > 0.0
    assert motion.contact_countdown == 0
    assert motion.nis == 0.0
    assert motion.vy_raw is None
    assert motion.last_measurement_time == 5.0
    assert np.allclose(motion.last_measurement, np.array((320.0, 180.0)))


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
    assert track.velocity[1] > 0.0
    assert 200.0 < track.center[1] < 212.0
    assert np.isclose(track.vy_raw, 12.0 * REFERENCE_FPS)


def test_vy_raw_stays_constant_for_linear_measurements():
    start_time = 8.0
    step_y = 10.0
    track, motion, next_track_id = update_track(
        None,
        None,
        make_candidate(140.0),
        1,
        start_time,
    )
    raw_velocities: list[float] = []

    for frame_offset in range(1, 31):
        frame_time = start_time + (frame_offset / REFERENCE_FPS)
        predicted_track, motion = predict_track(track, motion, frame_time)
        track, motion, next_track_id = update_track(
            predicted_track,
            motion,
            make_candidate(140.0 + step_y * frame_offset),
            next_track_id,
            frame_time,
        )
        assert track.vy_raw is not None
        raw_velocities.append(track.vy_raw)

    assert next_track_id == 2
    assert max(abs(value - (step_y * REFERENCE_FPS)) for value in raw_velocities) < 1.0


def test_vy_raw_uses_minimum_dt_floor():
    start_time = 12.0
    track, motion, next_track_id = update_track(
        None,
        None,
        make_candidate(200.0),
        1,
        start_time,
    )

    frame_time = start_time + 1e-4
    predicted_track, motion = predict_track(track, motion, frame_time)
    track, motion, next_track_id = update_track(
        predicted_track,
        motion,
        make_candidate(210.0),
        next_track_id,
        frame_time,
    )

    assert next_track_id == 2
    assert np.isclose(track.vy_raw, 1200.0)


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
    prior_vy_raw = track.vy_raw
    held_centers: list[float] = []
    held_velocities: list[float] = []
    held_raw_velocities: list[float] = []

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
        assert track.vy_raw is not None
        held_raw_velocities.append(track.vy_raw)

    assert next_track_id == 2
    assert track is not None
    assert track.misses == 3
    assert held_centers[0] > prior_y
    assert held_centers[2] > held_centers[1] > held_centers[0]
    assert held_velocities[0] > prior_vy
    assert held_velocities[2] > held_velocities[1] > held_velocities[0]
    assert held_raw_velocities == [prior_vy_raw, prior_vy_raw, prior_vy_raw]


def test_vy_raw_recomputes_from_measurements_after_a_missed_frame():
    start_time = 14.0
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
        make_candidate(210.0),
        next_track_id,
        start_time + (1.0 / REFERENCE_FPS),
    )

    prior_vy_raw = track.vy_raw
    predicted_track, motion = predict_track(track, motion, start_time + (2.0 / REFERENCE_FPS))
    held_track, motion = advance_track(predicted_track, motion)
    assert held_track is not None
    assert held_track.vy_raw == prior_vy_raw

    predicted_track, motion = predict_track(held_track, motion, start_time + (3.0 / REFERENCE_FPS))
    track, motion, next_track_id = update_track(
        predicted_track,
        motion,
        make_candidate(220.0),
        next_track_id,
        start_time + (3.0 / REFERENCE_FPS),
    )

    assert next_track_id == 2
    assert np.isclose(track.vy_raw, 150.0)


def test_nis_stays_low_on_measurements_that_match_free_flight():
    start_time = 18.0
    track, motion, next_track_id = update_track(
        None,
        None,
        make_candidate(200.0),
        1,
        start_time,
    )
    assert motion is not None

    y_position = 200.0
    vertical_velocity = 4.0
    gravity_pf2 = motion.gravity_pf2
    motion.state = np.array((320.0, y_position, 0.0, vertical_velocity), dtype=float)
    nis_values: list[float] = []

    for frame_offset in range(1, 21):
        frame_time = start_time + (frame_offset / REFERENCE_FPS)
        y_position += vertical_velocity + (0.5 * gravity_pf2)
        vertical_velocity += gravity_pf2
        predicted_track, motion = predict_track(track, motion, frame_time)
        track, motion, next_track_id = update_track(
            predicted_track,
            motion,
            make_candidate(y_position),
            next_track_id,
            frame_time,
        )
        nis_values.append(track.nis)

    assert next_track_id == 2
    assert max(nis_values) < 2.0


def test_large_reversal_nis_rearms_contact_noise_and_inflates_next_prediction():
    start_time = 24.0
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

    predicted_track, motion = predict_track(track, motion, start_time + (2.0 / REFERENCE_FPS))
    track, motion, next_track_id = update_track(
        predicted_track,
        motion,
        make_candidate(150.0),
        next_track_id,
        start_time + (2.0 / REFERENCE_FPS),
    )

    assert motion is not None
    assert next_track_id == 2
    assert track.nis > CONTACT_NIS_THRESHOLD
    assert motion.contact_countdown == CONTACT_HOLD_FRAMES

    contact_motion = clone_motion_state(motion)
    nominal_motion = clone_motion_state(motion)
    nominal_motion.contact_countdown = 0

    _, contact_motion = predict_track(track, contact_motion, start_time + (3.0 / REFERENCE_FPS))
    _, nominal_motion = predict_track(track, nominal_motion, start_time + (3.0 / REFERENCE_FPS))

    assert contact_motion is not None
    assert nominal_motion is not None
    assert contact_motion.contact_countdown == CONTACT_HOLD_FRAMES - 1
    assert float(np.trace(contact_motion.covariance)) > float(np.trace(nominal_motion.covariance))


def test_track_recreation_resets_contact_metadata():
    start_time = 30.0
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
    predicted_track, motion = predict_track(track, motion, start_time + (2.0 / REFERENCE_FPS))
    track, motion, next_track_id = update_track(
        predicted_track,
        motion,
        make_candidate(150.0),
        next_track_id,
        start_time + (2.0 / REFERENCE_FPS),
    )

    assert motion is not None
    assert motion.contact_countdown == CONTACT_HOLD_FRAMES
    assert track.vy_raw is not None
    assert track.nis > CONTACT_NIS_THRESHOLD

    for frame_offset in range(3, MAX_MISSES + 5):
        track, motion = predict_track(track, motion, start_time + (frame_offset / REFERENCE_FPS))
        track, motion = advance_track(track, motion)

    assert track is None
    assert motion is None

    frame_time = start_time + ((MAX_MISSES + 5) / REFERENCE_FPS)
    track, motion, next_track_id = update_track(
        None,
        None,
        make_candidate(250.0),
        next_track_id,
        frame_time,
    )

    assert next_track_id == 3
    assert track.nis == 0.0
    assert track.vy_raw is None
    assert motion is not None
    assert motion.contact_countdown == 0
    assert motion.nis == 0.0
    assert motion.vy_raw is None
    assert motion.last_measurement_time == frame_time
    assert np.allclose(motion.last_measurement, np.array((320.0, 250.0)))


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
