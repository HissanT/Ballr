import numpy as np

from ball_tracker_juggling import update_juggle_state
from ball_tracker_pose import PoseContactCandidate, PoseFrame
from ball_tracker_tracking import BallTrack

FRAME_SIZE = (480, 640)


def make_track(
    y: float,
    *,
    x: float = 320.0,
    radius: float = 22.0,
    vx: float = 0.0,
    vy: float = 0.0,
    misses: int = 0,
    confirmed_frames: int = 3,
) -> BallTrack:
    return BallTrack(
        center=np.array((x, y), dtype=np.float32),
        velocity=np.array((vx, vy), dtype=np.float32),
        radius=radius,
        confidence=0.9,
        track_id=1,
        misses=misses,
        confirmed_frames=confirmed_frames,
    )


def make_pose(
    track_y: float,
    *,
    source: str = "live",
    valid_contact: bool = True,
    landmark: str = "L ankle",
) -> PoseFrame:
    landmark_map = {
        "L ankle": ("left_ankle", np.array((320.0, track_y + 6.0), dtype=np.float32)),
        "L knee": ("left_knee", np.array((320.0, track_y + 6.0), dtype=np.float32)),
        "Head": ("head", np.array((320.0, track_y + 6.0), dtype=np.float32)),
    }
    name, point = landmark_map[landmark]
    distance = 6.0 if valid_contact else 120.0
    threshold = 44.0
    candidate = PoseContactCandidate(
        name=name,
        display_name=landmark,
        point=point,
        confidence=0.9,
        distance=distance,
        threshold=threshold,
    )

    keypoints = {
        "left_knee": np.array((320.0, 240.0), dtype=np.float32),
        "right_knee": np.array((350.0, 240.0), dtype=np.float32),
        "left_ankle": np.array((320.0, 360.0), dtype=np.float32),
        "right_ankle": np.array((350.0, 360.0), dtype=np.float32),
        "head": np.array((335.0, 120.0), dtype=np.float32),
    }
    keypoints[name] = point

    confidences = {name: 0.9 for name in keypoints}
    return PoseFrame(
        available=True,
        source=source,
        keypoints=keypoints,
        confidences=confidences,
        knee_line_y=240.0,
        ground_y=360.0,
        nearest_contact=candidate,
        contact_candidates=(candidate,),
    )


def arm_state(started_at: float = 0.0):
    state = None
    timestamp = started_at
    for y in [250, 252, 254, 256, 258, 260]:
        state, _ = update_juggle_state(state, make_track(y), make_pose(y), timestamp, FRAME_SIZE)
        timestamp += 0.1

    assert state is not None
    assert state.status_label == "Ready"
    return state, timestamp


def run_contact_sequence(state, timestamp: float, *, landmark: str = "L ankle", source: str = "live"):
    for y, vy in ((233, -0.8), (260, 1.6), (228, -1.6)):
        state, scored = update_juggle_state(
            state,
            make_track(y, vy=vy),
            make_pose(y, source=source, landmark=landmark),
            timestamp,
            FRAME_SIZE,
        )
        timestamp += 0.1
    return state, timestamp, scored


def test_juggle_mode_counts_one_ankle_contact():
    state, timestamp = arm_state()

    state, timestamp, scored = run_contact_sequence(state, timestamp)

    assert scored
    assert state.current_streak == 1
    assert state.best_streak == 1
    assert state.total_juggles == 1
    assert state.body_part_counts == {"L ankle": 1}
    assert state.status_label == "RiseWindow"


def test_juggle_mode_tracks_knee_contact_attribution():
    state, timestamp = arm_state()

    state, timestamp, scored = run_contact_sequence(state, timestamp, landmark="L knee")

    assert scored
    assert state.total_juggles == 1
    assert state.body_part_counts == {"L knee": 1}


def test_juggle_mode_tracks_head_contact_attribution():
    state, timestamp = arm_state()

    state, timestamp, scored = run_contact_sequence(state, timestamp, landmark="Head")

    assert scored
    assert state.total_juggles == 1
    assert state.body_part_counts == {"Head": 1}


def test_juggle_mode_suppresses_ground_bounces_without_contact():
    state, timestamp = arm_state()

    for y, vy in ((300, 1.8), (342, 2.2), (330, -2.0), (330, 0.0)):
        state, scored = update_juggle_state(
            state,
            make_track(y, vy=vy),
            make_pose(y, valid_contact=False),
            timestamp,
            FRAME_SIZE,
        )
        timestamp += 0.1

    assert not scored
    assert state.total_juggles == 0
    assert state.ground_suppressed_events == 1
    assert state.drop_resets == 1
    assert state.status_label == "DropPending"


def test_juggle_mode_blocks_new_contacts_while_pose_is_stale():
    state, timestamp = arm_state()
    state, timestamp, _ = run_contact_sequence(state, timestamp)

    for y, vy, source in ((200, -0.8, "live"), (260, 1.6, "held"), (228, -1.6, "held")):
        state, scored = update_juggle_state(
            state,
            make_track(y, vy=vy),
            make_pose(y, source=source),
            timestamp,
            FRAME_SIZE,
        )
        timestamp += 0.1

    assert not scored
    assert state.total_juggles == 1
    assert state.contact_candidates == 1
    assert state.current_streak == 1
    assert state.status_label == "Ready"

    state, timestamp, scored = run_contact_sequence(state, timestamp)
    assert scored
    assert state.total_juggles == 2


def test_juggle_mode_preserves_streak_through_brief_rise_window_tracking_loss():
    state, timestamp = arm_state()
    state, timestamp, _ = run_contact_sequence(state, timestamp)

    state, _ = update_juggle_state(state, None, make_pose(228), timestamp, FRAME_SIZE)
    state, _ = update_juggle_state(state, None, make_pose(228), timestamp + 0.2, FRAME_SIZE)
    state, _ = update_juggle_state(
        state,
        make_track(210, vy=-0.8),
        make_pose(210),
        timestamp + 0.3,
        FRAME_SIZE,
    )

    assert state.current_streak == 1
    assert state.loss_resets == 0
    assert state.status_label == "RiseWindow"


def test_juggle_mode_resets_streak_after_ground_dwell_without_new_contact():
    state, timestamp = arm_state()
    state, timestamp, _ = run_contact_sequence(state, timestamp)

    for y, vy in ((210, -0.8), (340, 2.4), (340, 0.0), (340, 0.0)):
        state, _ = update_juggle_state(
            state,
            make_track(y, vy=vy),
            make_pose(y, valid_contact=False),
            timestamp,
            FRAME_SIZE,
        )
        timestamp += 0.1

    assert state.current_streak == 0
    assert state.best_streak == 1
    assert state.drop_resets == 1
    assert state.status_label == "DropPending"


def test_juggle_mode_velocity_hysteresis_filters_apex_noise():
    state, timestamp = arm_state()

    frames = (
        (260, 1.6, True, False),
        (260, 0.7, True, False),
        (260, 0.4, False, False),
        (240, -1.6, False, True),
        (240, -0.7, False, True),
        (240, -0.4, False, False),
    )
    for y, vy, descending_active, rising_active in frames:
        state, _ = update_juggle_state(
            state,
            make_track(y, vy=vy),
            make_pose(y, valid_contact=False),
            timestamp,
            FRAME_SIZE,
        )
        timestamp += 0.1
        assert state.descending_active is descending_active
        assert state.rising_active is rising_active
