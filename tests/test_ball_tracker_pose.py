import numpy as np

from ball_tracker_pose import _knee_line_y


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
