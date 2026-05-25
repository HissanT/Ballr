import shutil
from pathlib import Path
from uuid import uuid4

import cv2
import numpy as np
import pytest

from data_tools.augment_tools import (
    AugmentConfig,
    build_augmented_train_dataset,
    transformed_zoom_out_boxes,
)


@pytest.fixture
def workspace_tmp() -> Path:
    root = Path.cwd() / f"augment_tools_{uuid4().hex}"
    root.mkdir(parents=True, exist_ok=False)
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def write_image(path: Path, value: int = 128) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = np.full((80, 100, 3), value, dtype=np.uint8)
    assert cv2.imwrite(str(path), image)


def write_label(path: Path, text: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def test_transformed_zoom_out_boxes_scales_label_dimensions():
    boxes = [{"class_id": 0, "cx": 0.5, "cy": 0.5, "w": 0.2, "h": 0.1}]

    transformed = transformed_zoom_out_boxes(
        boxes,
        scale=0.8,
        offset_x=10,
        offset_y=4,
        width=100,
        height=80,
    )

    assert transformed[0]["w"] == pytest.approx(0.16)
    assert transformed[0]["h"] == pytest.approx(0.08)
    assert transformed[0]["cx"] == pytest.approx(0.5)
    assert transformed[0]["cy"] == pytest.approx(0.45)


def test_build_augmented_train_dataset_keeps_val_unaugmented(workspace_tmp: Path):
    source = workspace_tmp / "source"
    output = workspace_tmp / "aug"
    write_image(source / "images" / "train" / "train_a.jpg")
    write_label(source / "labels" / "train" / "train_a.txt", "0 0.5 0.5 0.2 0.2\n")
    write_image(source / "images" / "val" / "val_a.jpg")
    write_label(source / "labels" / "val" / "val_a.txt", "0 0.5 0.5 0.2 0.2\n")

    summary = build_augmented_train_dataset(
        source,
        output,
        AugmentConfig(
            variants_per_image=1,
            seed=7,
            blur_probability=0,
            motion_blur_probability=0,
            zoom_out_probability=1,
            noise_probability=0,
            jpeg_probability=0,
            min_zoom_scale=0.8,
            max_zoom_scale=0.8,
        ),
    )

    assert summary["original_train_images"] == 1
    assert summary["augmented_train_images"] == 1
    assert summary["val_images"] == 1
    assert (output / "images" / "train" / "train_a.jpg").exists()
    assert (output / "images" / "train" / "train_a_aug1.jpg").exists()
    assert not (output / "images" / "val" / "val_a_aug1.jpg").exists()
    label = (output / "labels" / "train" / "train_a_aug1.txt").read_text(encoding="utf-8")
    assert "0 " in label
    assert "0.160000" in label
    assert "val: images/val" in (output / "data.yaml").read_text(encoding="utf-8")
