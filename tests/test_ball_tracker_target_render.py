from pathlib import Path

import numpy as np
from PIL import Image

from ball_tracker import render_target_reference_rgb


def load_reference_image(name: str) -> np.ndarray:
    path = Path(__file__).resolve().parents[1] / name
    return np.array(Image.open(path).convert("RGB"), dtype=np.uint8)


def assert_reference_close(actual: np.ndarray, expected: np.ndarray) -> None:
    assert actual.shape == expected.shape
    diff = np.abs(actual.astype(np.int16) - expected.astype(np.int16))
    mean_diff = float(diff.mean())
    percentile_99_5 = float(np.percentile(diff, 99.5))
    max_diff = int(diff.max())

    assert mean_diff < 15.0
    assert percentile_99_5 < 190.0
    assert max_diff < 220


def test_idle_target_render_matches_reference_art():
    actual = render_target_reference_rgb(scoring_progress=0.0, idle_pulse=0.0)
    expected = load_reference_image("target_idle.png")

    assert_reference_close(actual, expected)


def test_scored_target_render_matches_reference_art():
    actual = render_target_reference_rgb(scoring_progress=1.0, idle_pulse=0.0)
    expected = load_reference_image("target_scored.png")

    assert_reference_close(actual, expected)
