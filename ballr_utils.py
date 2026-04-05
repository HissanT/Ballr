from pathlib import Path

import cv2
import numpy as np


def parse_source(arg: str):
    return int(arg) if arg.isdigit() else arg


def ensure_dir(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def build_gamma_lut(gamma: float = 1.2) -> np.ndarray:
    table = np.array(
        [(i / 255.0) ** (1.0 / gamma) * 255 for i in range(256)], dtype=np.uint8
    )
    return table


def preprocess_frame(frame: np.ndarray, gamma_lut: np.ndarray, clahe: cv2.CLAHE) -> np.ndarray:
    # Normalize uneven lighting before detection.
    lab = cv2.cvtColor(frame, cv2.COLOR_BGR2LAB)
    l_channel, a_channel, b_channel = cv2.split(lab)
    l_channel = clahe.apply(l_channel)
    lab = cv2.merge((l_channel, a_channel, b_channel))
    enhanced = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)

    if enhanced.mean() < 100:
        enhanced = cv2.LUT(enhanced, gamma_lut)

    return enhanced
