import shutil
from pathlib import Path
from uuid import uuid4

import cv2
import numpy as np
import pytest

from dataset_tools import build_label_viewer


def create_image(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    assert cv2.imwrite(str(path), np.zeros((48, 64, 3), dtype=np.uint8))


@pytest.fixture
def workspace_tmp() -> Path:
    root = Path.cwd() / f"dataset_tools_{uuid4().hex}"
    root.mkdir(parents=True, exist_ok=False)
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_build_label_viewer_scans_dataset_without_review_manifest(workspace_tmp: Path):
    root = workspace_tmp / "dataset"
    create_image(root / "images" / "train" / "sample.jpg")
    label_dir = root / "labels" / "train"
    label_dir.mkdir(parents=True, exist_ok=True)
    (label_dir / "sample.txt").write_text("0 0.5 0.5 0.25 0.25\n", encoding="utf-8")

    output_path = build_label_viewer(root)

    html = output_path.read_text(encoding="utf-8")
    assert output_path == root / "label_overlay_viewer.html"
    assert '"image":"images/train/sample.jpg"' in html
    assert '"cx":0.5' in html
    assert "sample.jpg" in html


def test_build_label_viewer_prefers_review_manifest_metadata(workspace_tmp: Path):
    root = workspace_tmp / "dataset"
    create_image(root / "images" / "train" / "sample.jpg")
    review_dir = root / "review"
    review_dir.mkdir(parents=True, exist_ok=True)
    (review_dir / "manifest.jsonl").write_text(
        "\ufeff"
        + "\n".join(
            [
                (
                    '{"split":"train","image_name":"sample.jpg","review_status":"kept",'
                    '"suspicion_score":3,"suspicion_reasons":["low_frame_box"],'
                    '"best_iou":0.91,"cleaned_image_relpath":"images/train/sample.jpg",'
                    '"labels":[{"class_id":0,"cx":0.1,"cy":0.2,"w":0.3,"h":0.4}],'
                    '"model_predictions":[{"class_id":0,"cx":0.5,"cy":0.5,"w":0.2,"h":0.2,"conf":0.88}]}'
                )
            ]
        )
        + "\n",
        encoding="utf-8",
    )

    output_path = build_label_viewer(root)

    html = output_path.read_text(encoding="utf-8")
    assert '"review_status":"kept"' in html
    assert '"suspicion_score":3' in html
    assert '"model_predictions":[{"class_id":0,"cx":0.5,"cy":0.5,"w":0.2,"h":0.2,"conf":0.88}]' in html
