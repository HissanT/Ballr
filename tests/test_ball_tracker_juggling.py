import numpy as np

from ball_tracker_juggling import update_juggle_state
from ball_tracker_tracking import BallTrack

FRAME_SIZE = (480, 640)


def make_track(
    y: float,
    *,
    x: float = 320.0,
    radius: float = 22.0,
    misses: int = 0,
    confirmed_frames: int = 3,
) -> BallTrack:
    return BallTrack(
        center=np.array((x, y), dtype=np.float32),
        velocity=np.zeros(2, dtype=np.float32),
        radius=radius,
        confidence=0.9,
        track_id=1,
        misses=misses,
        confirmed_frames=confirmed_frames,
    )


def arm_state(started_at: float = 0.0):
    state = None
    timestamp = started_at
    warmup_sequence = [220, 225, 230, 235, 240, 245, 250, 255, 260, 265, 270, 275, 280]
    for y in warmup_sequence:
        state, _scored = update_juggle_state(state, make_track(y), timestamp, FRAME_SIZE)
        timestamp += 0.2

    assert state is not None
    assert state.armed
    return state, timestamp


def test_juggle_mode_scores_one_point_per_confirmed_rebound():
    state, timestamp = arm_state()

    for y in (226, 262, 304, 252):
        state, _scored = update_juggle_state(state, make_track(y), timestamp, FRAME_SIZE)
        timestamp += 0.1

    assert state.current_streak == 1
    assert state.best_streak == 1
    assert state.total_juggles == 1
    assert state.status_label == "Armed"


def test_juggle_mode_ignores_shallow_reversal_without_valid_rebound():
    state, timestamp = arm_state()

    for y in (228, 266, 302, 290, 294):
        state, _scored = update_juggle_state(state, make_track(y), timestamp, FRAME_SIZE)
        timestamp += 0.1

    state, _scored = update_juggle_state(state, make_track(296), timestamp + 0.7, FRAME_SIZE)

    assert state.current_streak == 0
    assert state.total_juggles == 0


def test_juggle_mode_resets_streak_after_low_drop_without_rebound():
    state, timestamp = arm_state()

    for y in (226, 262, 304, 252):
        state, _scored = update_juggle_state(state, make_track(y), timestamp, FRAME_SIZE)
        timestamp += 0.1

    assert state.current_streak == 1

    for y in (232, 270, 308, 304, 303):
        state, _scored = update_juggle_state(state, make_track(y), timestamp, FRAME_SIZE)
        timestamp += 0.1

    state, _scored = update_juggle_state(state, make_track(304), timestamp + 0.7, FRAME_SIZE)

    assert state.current_streak == 0
    assert state.best_streak == 1
    assert state.drop_resets == 1
    assert state.status_label == "Drop"


def test_juggle_mode_resets_after_low_loss_grace_expires():
    state, timestamp = arm_state()

    for y in (226, 262, 304, 252):
        state, _scored = update_juggle_state(state, make_track(y), timestamp, FRAME_SIZE)
        timestamp += 0.1

    assert state.current_streak == 1

    for y in (234, 274, 312):
        state, _scored = update_juggle_state(state, make_track(y), timestamp, FRAME_SIZE)
        timestamp += 0.1

    state, _scored = update_juggle_state(state, None, timestamp + 0.2, FRAME_SIZE)
    state, _scored = update_juggle_state(state, None, timestamp + 0.7, FRAME_SIZE)

    assert state.current_streak == 0
    assert state.loss_resets == 1
    assert state.status_label == "Lost"


def test_juggle_mode_preserves_streak_through_brief_tracking_loss():
    state, timestamp = arm_state()

    for y in (226, 262, 304, 252):
        state, _scored = update_juggle_state(state, make_track(y), timestamp, FRAME_SIZE)
        timestamp += 0.1

    assert state.current_streak == 1

    state, _scored = update_juggle_state(state, None, timestamp + 0.2, FRAME_SIZE)
    state, _scored = update_juggle_state(state, make_track(236), timestamp + 0.4, FRAME_SIZE)

    assert state.current_streak == 1
    assert state.loss_resets == 0
