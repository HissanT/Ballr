import shutil
from pathlib import Path
from uuid import uuid4

import cv2
import numpy as np
import pytest

from data_tools.eval_tools import (
    build_temporal_gray_dataset,
    collect_label_stats,
    create_heldout_validation_split,
    score_prediction_labels,
    temporal_sources_for_index,
)


@pytest.fixture
def workspace_tmp() -> Path:
    root = Path.cwd() / f"eval_tools_{uuid4().hex}"
    root.mkdir(parents=True, exist_ok=False)
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def write_image(path: Path, value: int = 0) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image = np.full((100, 100, 3), value, dtype=np.uint8)
    assert cv2.imwrite(str(path), image)


def write_label(path: Path, text: str = "") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def test_collect_label_stats_reports_sqrt_area_bins_and_empty_labels(workspace_tmp: Path):
    root = workspace_tmp / "dataset"
    write_image(root / "images" / "val" / "small.jpg")
    write_image(root / "images" / "val" / "empty.jpg")
    write_label(root / "labels" / "val" / "small.txt", "0 0.5 0.5 0.10 0.10\n")
    write_label(root / "labels" / "val" / "empty.txt", "")

    stats = collect_label_stats(root, "val")

    assert stats["images"] == 2
    assert stats["annotations"] == 1
    assert stats["empty_label_count"] == 1
    assert stats["sqrt_area_bins"]["<=12px"] == 1


def test_score_prediction_labels_tracks_small_recall_and_empty_false_positives(workspace_tmp: Path):
    dataset = workspace_tmp / "dataset"
    predictions = workspace_tmp / "predictions"
    write_image(dataset / "images" / "val" / "hit.jpg")
    write_image(dataset / "images" / "val" / "miss.jpg")
    write_image(dataset / "images" / "val" / "empty.jpg")
    write_label(dataset / "labels" / "val" / "hit.txt", "0 0.5 0.5 0.10 0.10\n")
    write_label(dataset / "labels" / "val" / "miss.txt", "0 0.5 0.5 0.20 0.20\n")
    write_label(dataset / "labels" / "val" / "empty.txt", "")
    write_label(predictions / "labels" / "val" / "hit.txt", "0 0.5 0.5 0.10 0.10 0.9\n")
    write_label(predictions / "labels" / "val" / "miss.txt", "")
    write_label(predictions / "labels" / "val" / "empty.txt", "0 0.1 0.1 0.10 0.10 0.8\n")

    score = score_prediction_labels(dataset, predictions, "val", fps=30)

    assert score["recall_by_size_bin"]["<=12px"] == 1.0
    assert score["small_ball_recall_<=20px"] == 0.5
    assert score["false_positives"] == 1
    assert score["empty_label_count"] == 1
    assert score["empty_frames_with_prediction"] == 1
    assert score["missed_gt_frames"] == 1


def test_create_heldout_validation_split_uses_contiguous_buckets(workspace_tmp: Path):
    source = workspace_tmp / "source"
    output = workspace_tmp / "heldout"
    for index in range(10):
        write_image(source / "images" / "train" / f"frame_{index:03d}.jpg")
        write_label(source / "labels" / "train" / f"frame_{index:03d}.txt", "")

    summary = create_heldout_validation_split(
        source,
        output,
        bucket_count=5,
        val_buckets={1, 3},
    )

    assert summary["train_images"] == 6
    assert summary["val_images"] == 4
    assert (output / "images" / "val" / "frame_002.jpg").exists()
    assert (output / "images" / "train" / "frame_000.jpg").exists()
    assert "val: images/val" in (output / "data.yaml").read_text(encoding="utf-8")


def test_temporal_sources_duplicate_current_when_history_is_stale(workspace_tmp: Path):
    images = [
        workspace_tmp / "session_000_review_frame_1000_000.jpg",
        workspace_tmp / "session_001_review_frame_4000_090.jpg",
    ]

    old_path, previous_path, current_path = temporal_sources_for_index(
        images,
        1,
        max_timestamp_gap_ms=1000,
        max_frame_gap=60,
    )

    assert old_path == images[1]
    assert previous_path == images[1]
    assert current_path == images[1]


def test_build_temporal_gray_dataset_writes_triplet_images_and_labels(workspace_tmp: Path):
    source = workspace_tmp / "source"
    output = workspace_tmp / "temporal"
    write_image(source / "images" / "train" / "session_000_review_frame_1000_000.jpg", value=10)
    write_image(source / "images" / "train" / "session_001_review_frame_1020_001.jpg", value=40)
    write_image(source / "images" / "train" / "session_002_review_frame_1040_002.jpg", value=90)
    for path in (source / "images" / "train").glob("*.jpg"):
        write_label(source / "labels" / "train" / f"{path.stem}.txt", "0 0.5 0.5 0.1 0.1\n")

    summary = build_temporal_gray_dataset(source, output, splits=["train"])

    assert summary["input_temporal_mode"] == "temporal_gray_3"
    result = cv2.imread(str(output / "images" / "train" / "session_002_review_frame_1040_002.jpg"))
    assert result is not None
    assert result[0, 0, 0] == 90
    assert result[0, 0, 1] == 40
    assert result[0, 0, 2] == 10
    assert (output / "labels" / "train" / "session_002_review_frame_1040_002.txt").exists()
