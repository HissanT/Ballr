import numpy as np

from ball_tracker.ball_tracker_juggling import JuggleEventClass, update_juggle_state
from ball_tracker.ball_tracker_pose import PoseFrame
from ball_tracker.ball_tracker_tracking import BallTrack

FRAME_SIZE = (480, 640)


def make_track(
    y: float,
    *,
    previous_y: float | None = None,
    x: float = 320.0,
    radius: float = 20.0,
    misses: int = 0,
    confirmed_frames: int = 3,
) -> BallTrack:
    vy = 0.0 if previous_y is None else y - previous_y
    return BallTrack(
        center=np.array((x, y), dtype=np.float32),
        velocity=np.array((0.0, vy), dtype=np.float32),
        width=radius * 2.0,
        height=radius * 2.0,
        radius=radius,
        confidence=0.9,
        track_id=1,
        misses=misses,
        confirmed_frames=confirmed_frames,
        vy_raw=vy,
    )


def make_pose(
    track_y: float,
    *,
    kind: str = "foot",
    available: bool = True,
    backend: str = "merged",
    include_knees: bool = True,
    include_hips: bool = True,
    ground_y: float = 420.0,
) -> PoseFrame:
    if not available:
        return PoseFrame()

    keypoints: dict[str, np.ndarray] = {
        "left_ankle": np.array((320.0, track_y + 12.0 if kind == "foot" else 390.0), dtype=np.float32),
        "right_ankle": np.array((360.0, 390.0), dtype=np.float32),
    }
    confidences = {name: 0.95 for name in keypoints}

    if include_knees or kind in {"knee", "hip", "thigh"}:
        keypoints["left_knee"] = np.array((320.0, track_y + 10.0 if kind == "knee" else 250.0), dtype=np.float32)
        keypoints["right_knee"] = np.array((356.0, 252.0), dtype=np.float32)
        confidences["left_knee"] = 0.95
        confidences["right_knee"] = 0.95

    if include_hips or kind in {"hip", "thigh"}:
        keypoints["left_hip"] = np.array((304.0, 182.0), dtype=np.float32)
        keypoints["right_hip"] = np.array((346.0, 184.0), dtype=np.float32)
        confidences["left_hip"] = 0.95
        confidences["right_hip"] = 0.95

    if kind == "hip":
        keypoints["left_hip"] = np.array((304.0, track_y + 10.0), dtype=np.float32)
        keypoints["right_hip"] = np.array((346.0, track_y + 12.0), dtype=np.float32)
        keypoints["left_knee"] = np.array((320.0, 248.0), dtype=np.float32)
        keypoints["right_knee"] = np.array((356.0, 250.0), dtype=np.float32)

    if kind == "thigh":
        keypoints["left_knee"] = np.array((322.0, 246.0), dtype=np.float32)
        keypoints["left_hip"] = np.array((308.0, 178.0), dtype=np.float32)

    if kind == "ground":
        keypoints["left_ankle"] = np.array((250.0, 390.0), dtype=np.float32)
        keypoints["right_ankle"] = np.array((390.0, 390.0), dtype=np.float32)

    if kind == "hand":
        keypoints["left_wrist"] = np.array((320.0, track_y + 8.0), dtype=np.float32)
        keypoints["right_wrist"] = np.array((356.0, track_y + 10.0), dtype=np.float32)
        confidences["left_wrist"] = 0.95
        confidences["right_wrist"] = 0.95

    return PoseFrame(
        available=True,
        source="live",
        backend=backend,
        quality=min(len([name for name in ("left_hip", "right_hip", "left_knee", "right_knee", "left_ankle", "right_ankle") if name in keypoints]) / 6.0, 1.0),
        keypoints=keypoints,
        confidences=confidences,
        box=(260.0, 160.0, 390.0, 420.0),
        box_confidence=0.9,
        hip_line_y=(
            track_y + 11.0
            if kind == "hip"
            else 183.0
            if include_hips or kind == "thigh"
            else None
        ),
        knee_line_y=250.0 if include_knees or kind in {"knee", "thigh"} else None,
        ground_y=ground_y,
    )


def warm_state():
    state = None
    timestamp = 0.0
    previous_y = None
    for frame_index, y in enumerate((200.0, 201.0, 202.0, 203.0, 204.0, 205.0, 206.0, 207.0, 208.0, 209.0, 210.0), start=1):
        state, event = update_juggle_state(
            state,
            make_track(y, previous_y=previous_y),
            make_pose(y, available=False),
            timestamp,
            FRAME_SIZE,
            frame_index=frame_index,
        )
        assert event is None
        previous_y = y
        timestamp += 0.05
    assert state is not None
    return state, frame_index + 1, timestamp, previous_y


def run_sequence(state, frame_index: int, timestamp: float, previous_y: float, y_values: tuple[float, ...], *, kind: str, available: bool = True, include_knees: bool = True, include_hips: bool = True, ground_y: float = 420.0, x: float = 320.0):
    event = None
    for y in y_values:
        state, maybe_event = update_juggle_state(
            state,
            make_track(y, previous_y=previous_y, x=x),
            make_pose(
                y,
                kind=kind,
                available=available,
                include_knees=include_knees,
                include_hips=include_hips,
                ground_y=ground_y,
            ),
            timestamp,
            FRAME_SIZE,
            frame_index=frame_index,
        )
        if maybe_event is not None:
            event = maybe_event
        previous_y = y
        frame_index += 1
        timestamp += 0.05
    return state, event, frame_index, timestamp, previous_y


FOOT_APEX = (250.0, 265.0, 280.0, 296.0, 280.0, 264.0, 250.0)
LOW_AMPLITUDE_FOOT_APEX = (270.0, 276.0, 281.0, 286.0, 281.0, 276.0, 270.0)
KNEE_APEX = (200.0, 215.0, 230.0, 246.0, 230.0, 214.0, 200.0)
HIP_APEX = (120.0, 135.0, 150.0, 166.0, 150.0, 135.0, 120.0)
THIGH_APEX = (160.0, 175.0, 190.0, 206.0, 190.0, 174.0, 160.0)


class FakeEventClassifier:
    def __init__(self, scores: dict[str, float]) -> None:
        self._scores = scores

    def classify(self, _feature_window, _window_samples):
        return JuggleEventClass.OTHER, dict(self._scores)


def test_juggle_mode_counts_foot_contact():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(state, frame_index, timestamp, previous_y, FOOT_APEX, kind="foot")

    assert event is not None
    assert event.event_class == JuggleEventClass.FOOT
    assert event.counted
    assert state.total_juggles == 1
    assert state.current_streak == 1
    assert state.body_part_counts == {"Foot": 1}
    assert state.status_label == "Counted"


def test_juggle_mode_counts_foot_contact_with_missing_knees():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        FOOT_APEX,
        kind="foot",
        include_knees=False,
        include_hips=False,
    )

    assert event is not None
    assert event.event_class == JuggleEventClass.FOOT
    assert event.counted


def test_juggle_mode_counts_lower_amplitude_foot_contact():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        LOW_AMPLITUDE_FOOT_APEX,
        kind="foot",
        include_knees=False,
        include_hips=False,
    )

    assert event is not None
    assert event.event_class == JuggleEventClass.FOOT
    assert event.counted


def test_juggle_mode_counts_knee_contact():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(state, frame_index, timestamp, previous_y, KNEE_APEX, kind="knee")

    assert event is not None
    assert event.event_class == JuggleEventClass.KNEE
    assert event.counted


def test_juggle_mode_counts_hip_contact_for_higher_juggles():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(state, frame_index, timestamp, previous_y, HIP_APEX, kind="hip")

    assert event is not None
    assert event.event_class == JuggleEventClass.HIP
    assert event.counted
    assert state.body_part_counts == {"Hip": 1}


def test_juggle_mode_does_not_count_thigh_contact():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(state, frame_index, timestamp, previous_y, THIGH_APEX, kind="thigh")

    assert event is None
    assert state.total_juggles == 0
    assert state.current_streak == 0


def test_juggle_mode_suppresses_hand_contact():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(state, frame_index, timestamp, previous_y, FOOT_APEX, kind="hand")

    assert event is not None
    assert event.event_class == JuggleEventClass.OTHER
    assert not event.counted
    assert state.total_juggles == 0
    assert state.current_streak == 0


def test_model_classifier_can_force_count_event():
    state, frame_index, timestamp, previous_y = warm_state()
    classifier = FakeEventClassifier({"count": 0.92, "hand": 0.02, "ground": 0.03, "other": 0.03})
    event = None
    for y in FOOT_APEX:
        state, maybe_event = update_juggle_state(
            state,
            make_track(y, previous_y=previous_y),
            make_pose(y, kind="hand"),
            timestamp,
            FRAME_SIZE,
            frame_index=frame_index,
            classifier=classifier,
        )
        if maybe_event is not None:
            event = maybe_event
        previous_y = y
        frame_index += 1
        timestamp += 0.05

    assert event is not None
    assert event.counted
    assert event.event_class in {JuggleEventClass.FOOT, JuggleEventClass.KNEE, JuggleEventClass.HIP}
    assert state.total_juggles == 1


def test_model_classifier_can_force_hand_suppression():
    state, frame_index, timestamp, previous_y = warm_state()
    classifier = FakeEventClassifier({"count": 0.05, "hand": 0.90, "ground": 0.03, "other": 0.02})
    event = None
    for y in FOOT_APEX:
        state, maybe_event = update_juggle_state(
            state,
            make_track(y, previous_y=previous_y),
            make_pose(y, kind="foot"),
            timestamp,
            FRAME_SIZE,
            frame_index=frame_index,
            classifier=classifier,
        )
        if maybe_event is not None:
            event = maybe_event
        previous_y = y
        frame_index += 1
        timestamp += 0.05

    assert event is not None
    assert not event.counted
    assert event.event_class == JuggleEventClass.OTHER
    assert state.total_juggles == 0


def test_juggle_mode_rejects_ground_led_reversal():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        FOOT_APEX,
        kind="ground",
        ground_y=318.0,
    )

    assert event is not None
    assert event.event_class == JuggleEventClass.GROUND
    assert not event.counted
    assert state.total_juggles == 0
    assert state.ground_suppressed_events == 1
    assert state.current_streak == 0
    assert state.status_label == "GroundReject"


def test_juggle_mode_counts_off_axis_foot_contact_with_moderate_drift():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        FOOT_APEX,
        kind="foot",
        x=365.0,
    )

    assert event is not None
    assert event.event_class == JuggleEventClass.FOOT
    assert event.counted


def test_juggle_mode_still_rejects_large_off_axis_drift():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        FOOT_APEX,
        kind="foot",
        x=390.0,
    )

    assert event is None
    assert state.total_juggles == 0


def test_juggle_mode_ignores_flat_motion():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, *_ = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        (200.0, 203.0, 205.0, 206.0, 205.0, 203.0, 200.0),
        kind="foot",
    )

    assert event is None
    assert state.total_juggles == 0


def test_ground_rejection_does_not_reset_visible_count():
    state, frame_index, timestamp, previous_y = warm_state()
    state, counted_event, frame_index, timestamp, previous_y = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        FOOT_APEX,
        kind="foot",
    )
    assert counted_event is not None and counted_event.counted

    state, ground_event, *_ = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        FOOT_APEX,
        kind="ground",
        ground_y=318.0,
    )

    assert ground_event is not None
    assert ground_event.event_class == JuggleEventClass.GROUND
    assert not ground_event.counted
    assert state.current_streak == 1
    assert state.total_juggles == 1


def test_track_loss_does_not_reset_visible_count():
    state, frame_index, timestamp, previous_y = warm_state()
    state, counted_event, frame_index, timestamp, previous_y = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        FOOT_APEX,
        kind="foot",
    )
    assert counted_event is not None and counted_event.counted

    for _ in range(12):
        state, event = update_juggle_state(
            state,
            None,
            PoseFrame(),
            timestamp,
            FRAME_SIZE,
            frame_index=frame_index,
        )
        assert event is None
        frame_index += 1
        timestamp += 0.05

    assert state.current_streak == 1
    assert state.total_juggles == 1


def test_rearm_blocks_second_count_until_ball_rises_clear():
    state, frame_index, timestamp, previous_y = warm_state()
    state, event, frame_index, timestamp, previous_y = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        FOOT_APEX,
        kind="foot",
    )
    assert event is not None and event.counted

    state, second_event, *_ = run_sequence(
        state,
        frame_index,
        timestamp,
        previous_y,
        (252.0, 254.0, 255.0, 256.0, 255.0, 254.0, 252.0),
        kind="foot",
    )

    assert second_event is None
    assert state.total_juggles == 1
