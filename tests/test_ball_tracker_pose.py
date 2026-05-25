import numpy as np

from ball_tracker_pose import (
    PoseBackendResults,
    PoseObservation,
    _hip_line_y,
    _knee_line_y,
    _point_to_segment_distance,
    update_pose_state_from_backends,
)
from ball_tracker_tracking import BallTrack


def test_knee_line_uses_average_when_knees_are_close():
    keypoints = {
        "left_knee": np.array((320.0, 240.0), dtype=np.float32),
        "right_knee": np.array((350.0, 250.0), dtype=np.float32),
    }

    assert _knee_line_y(keypoints) == 245.0


def test_knee_line_switches_to_higher_knee_when_one_leg_is_raised():
    keypoints = {
        "left_knee": np.array((320.0, 200.0), dtype=np.float32),
        "right_knee": np.array((350.0, 250.0), dtype=np.float32),
    }

    assert _knee_line_y(keypoints) == 200.0


def test_hip_line_switches_to_higher_hip_when_one_side_is_raised():
    keypoints = {
        "left_hip": np.array((320.0, 176.0), dtype=np.float32),
        "right_hip": np.array((350.0, 210.0), dtype=np.float32),
    }

    assert _hip_line_y(keypoints) == 176.0


def test_point_to_segment_distance_projects_onto_thigh_segment():
    point = np.array((320.0, 210.0), dtype=np.float32)
    hip = np.array((300.0, 180.0), dtype=np.float32)
    knee = np.array((340.0, 260.0), dtype=np.float32)

    assert round(_point_to_segment_distance(point, hip, knee), 3) == 4.472


def test_pose_backends_merge_mediapipe_feet_with_yolo_knees_and_hips():
    mediapipe_person = PoseObservation(
        provider="mediapipe",
        keypoints={
            "left_ankle": np.array((320.0, 350.0), dtype=np.float32),
            "right_ankle": np.array((350.0, 348.0), dtype=np.float32),
        },
        confidences={"left_ankle": 0.95, "right_ankle": 0.94},
        box=(280.0, 200.0, 380.0, 360.0),
        box_confidence=0.92,
    )
    yolo_person = PoseObservation(
        provider="yolo",
        keypoints={
            "left_hip": np.array((300.0, 185.0), dtype=np.float32),
            "right_hip": np.array((346.0, 186.0), dtype=np.float32),
            "left_knee": np.array((316.0, 246.0), dtype=np.float32),
            "right_knee": np.array((352.0, 248.0), dtype=np.float32),
            "left_ankle": np.array((318.0, 352.0), dtype=np.float32),
        },
        confidences={
            "left_hip": 0.91,
            "right_hip": 0.90,
            "left_knee": 0.92,
            "right_knee": 0.91,
            "left_ankle": 0.89,
        },
        box=(280.0, 180.0, 382.0, 360.0),
        box_confidence=0.88,
    )
    backend_results = PoseBackendResults(
        mediapipe_person=mediapipe_person,
        yolo_people=(yolo_person,),
    )
    ball_track = BallTrack(
        center=np.array((320.0, 230.0), dtype=np.float32),
        velocity=np.array((0.0, 0.0), dtype=np.float32),
        width=40.0,
        height=40.0,
        radius=20.0,
        confidence=0.9,
        track_id=1,
        confirmed_frames=3,
    )

    state, pose_frame = update_pose_state_from_backends(
        None,
        backend_results,
        ball_track,
        (480, 640),
        1.0,
    )

    assert state.backend == "merged"
    assert pose_frame.available
    assert pose_frame.backend == "merged"
    assert "left_ankle" in pose_frame.keypoints
    assert "left_knee" in pose_frame.keypoints
    assert "left_hip" in pose_frame.keypoints
    assert pose_frame.hip_line_y == 185.5
