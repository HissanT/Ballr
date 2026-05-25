import platform
from pathlib import Path

import cv2
import numpy as np

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ASSETS_DIR = PROJECT_ROOT / "assets"
MODELS_DIR = PROJECT_ROOT / "models"
TRAINING_DIR = PROJECT_ROOT / "training"
CAMERA_BACKEND_AUTO = "auto"
CAMERA_BACKEND_ANY = "any"
CAMERA_BACKEND_DSHOW = "dshow"
CAMERA_BACKEND_MSMF = "msmf"
CAMERA_BACKEND_CHOICES = (
    CAMERA_BACKEND_AUTO,
    CAMERA_BACKEND_ANY,
    CAMERA_BACKEND_DSHOW,
    CAMERA_BACKEND_MSMF,
)
_CAMERA_BACKEND_APIS = {
    CAMERA_BACKEND_ANY: cv2.CAP_ANY,
    CAMERA_BACKEND_DSHOW: cv2.CAP_DSHOW,
    CAMERA_BACKEND_MSMF: cv2.CAP_MSMF,
}


def parse_source(arg: str):
    return int(arg) if arg.isdigit() else arg


def _camera_backend_candidates(source, backend: str):
    if backend != CAMERA_BACKEND_AUTO:
        return ((backend, _CAMERA_BACKEND_APIS[backend]),)

    if isinstance(source, int) and platform.system() == "Windows":
        return (
            (CAMERA_BACKEND_DSHOW, _CAMERA_BACKEND_APIS[CAMERA_BACKEND_DSHOW]),
            (CAMERA_BACKEND_MSMF, _CAMERA_BACKEND_APIS[CAMERA_BACKEND_MSMF]),
            (CAMERA_BACKEND_ANY, _CAMERA_BACKEND_APIS[CAMERA_BACKEND_ANY]),
        )

    return ((CAMERA_BACKEND_ANY, _CAMERA_BACKEND_APIS[CAMERA_BACKEND_ANY]),)


def open_video_capture(source, backend: str = CAMERA_BACKEND_AUTO):
    last_capture = None
    last_backend_name = backend
    for backend_name, api_preference in _camera_backend_candidates(source, backend):
        capture = cv2.VideoCapture(source, api_preference)
        if capture.isOpened():
            return capture, backend_name
        capture.release()
        last_capture = capture
        last_backend_name = backend_name

    if last_capture is None:
        last_capture = cv2.VideoCapture(source, cv2.CAP_ANY)
        last_backend_name = CAMERA_BACKEND_ANY
    return last_capture, last_backend_name


def project_path(*parts: str) -> Path:
    return PROJECT_ROOT.joinpath(*parts)


def asset_path(*parts: str) -> Path:
    return ASSETS_DIR.joinpath(*parts)


def model_path(*parts: str) -> Path:
    return MODELS_DIR.joinpath(*parts)


def training_path(*parts: str) -> Path:
    return TRAINING_DIR.joinpath(*parts)


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
