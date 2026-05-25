import numpy as np

from ball_tracker import mirror_frame


def test_mirror_frame_flips_columns_left_to_right():
    frame = np.array(
        [
            [[1, 0, 0], [2, 0, 0], [3, 0, 0]],
            [[4, 0, 0], [5, 0, 0], [6, 0, 0]],
        ],
        dtype=np.uint8,
    )

    mirrored = mirror_frame(frame)

    expected = np.array(
        [
            [[3, 0, 0], [2, 0, 0], [1, 0, 0]],
            [[6, 0, 0], [5, 0, 0], [4, 0, 0]],
        ],
        dtype=np.uint8,
    )
    assert np.array_equal(mirrored, expected)
