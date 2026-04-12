import shutil
from pathlib import Path
from uuid import uuid4

import cv2
import numpy as np
import pytest

from review_queue import (
    DatasetReviewItem,
    NormalizedBox,
    apply_empty_action,
    apply_exclude_action,
    apply_keep_action,
    apply_redraw_action,
    build_dataset_review_item,
    determine_start_index,
    ensure_clean_dataset_copy,
    order_dataset_items,
    read_normalized_boxes,
    suggest_tight_ball_box,
    write_normalized_boxes,
)


def create_source_sample(tmp_path: Path, split: str = "train", stem: str = "sample"):
    source_root = tmp_path / "dataset"
    image_dir = source_root / "images" / split
    label_dir = source_root / "labels" / split
    image_dir.mkdir(parents=True, exist_ok=True)
    label_dir.mkdir(parents=True, exist_ok=True)
    (source_root / "data.yaml").write_text(
        "path: dataset\ntrain: images/train\nval: images/val\n\nnc: 1\nnames:\n  0: soccer-ball\n",
        encoding="utf-8",
    )

    image_path = image_dir / f"{stem}.jpg"
    label_path = label_dir / f"{stem}.txt"
    assert cv2.imwrite(str(image_path), np.zeros((100, 100, 3), dtype=np.uint8))
    return source_root, image_path, label_path


@pytest.fixture
def workspace_tmp() -> Path:
    root = Path.cwd() / f"review_queue_{uuid4().hex}"
    root.mkdir(parents=True, exist_ok=False)
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def make_item(name: str, sequence_index: int, suspicion_score: int, review_status: str = "pending"):
    return DatasetReviewItem(
        item_id=name,
        split="train",
        sequence_index=sequence_index,
        source_image_relpath=f"images/train/{name}.jpg",
        source_label_relpath=f"labels/train/{name}.txt",
        cleaned_image_relpath=f"images/train/{name}.jpg",
        cleaned_label_relpath=f"labels/train/{name}.txt",
        image_name=f"{name}.jpg",
        label_count=0,
        label_geometry={},
        labels=[],
        model_predictions=[],
        best_iou=None,
        suspicion_score=suspicion_score,
        suspicion_reasons=[],
        review_status=review_status,
    )


def test_build_dataset_review_item_scores_low_frame_false_positive(workspace_tmp: Path):
    source_root, image_path, _label_path = create_source_sample(workspace_tmp)
    output_root = workspace_tmp / "dataset_cleaned"
    label_boxes = [NormalizedBox(0, 0.50, 0.82, 0.04, 0.08)]
    model_predictions = [NormalizedBox(0, 0.15, 0.15, 0.04, 0.04, conf=0.91)]

    item = build_dataset_review_item(
        source_root=source_root,
        output_root=output_root,
        split="train",
        sequence_index=0,
        image_path=image_path,
        label_boxes=label_boxes,
        model_predictions=model_predictions,
    )

    assert item.label_count == 1
    assert item.best_iou == 0.0
    assert item.suspicion_score == 16
    assert set(item.suspicion_reasons) == {
        "positive_label_low_iou",
        "low_frame_box",
        "extreme_aspect_ratio",
        "extreme_box_area",
    }


def test_apply_empty_action_preserves_source_and_writes_empty_cleaned_copy(workspace_tmp: Path):
    source_root, image_path, label_path = create_source_sample(workspace_tmp)
    output_root = workspace_tmp / "dataset_cleaned"
    original_boxes = [NormalizedBox(0, 0.50, 0.45, 0.12, 0.12)]
    write_normalized_boxes(label_path, original_boxes)

    ensure_clean_dataset_copy(source_root, output_root, ("train",))
    item = build_dataset_review_item(
        source_root=source_root,
        output_root=output_root,
        split="train",
        sequence_index=0,
        image_path=image_path,
        label_boxes=original_boxes,
        model_predictions=[],
    )

    apply_empty_action(item, source_root, output_root)

    assert read_normalized_boxes(label_path) == original_boxes
    assert read_normalized_boxes(output_root / "labels" / "train" / "sample.txt") == []
    assert (output_root / "images" / "train" / "sample.jpg").exists()
    assert (output_root / "data.yaml").exists()
    assert item.review_status == "empty"


def test_exclude_keep_and_redraw_only_touch_cleaned_copy(workspace_tmp: Path):
    source_root, image_path, label_path = create_source_sample(workspace_tmp)
    output_root = workspace_tmp / "dataset_cleaned"
    original_boxes = [NormalizedBox(0, 0.48, 0.44, 0.10, 0.10)]
    redraw_boxes = [NormalizedBox(0, 0.62, 0.40, 0.08, 0.08)]
    write_normalized_boxes(label_path, original_boxes)

    ensure_clean_dataset_copy(source_root, output_root, ("train",))
    item = build_dataset_review_item(
        source_root=source_root,
        output_root=output_root,
        split="train",
        sequence_index=0,
        image_path=image_path,
        label_boxes=original_boxes,
        model_predictions=[],
    )

    apply_exclude_action(item, output_root)
    assert not (output_root / "images" / "train" / "sample.jpg").exists()
    assert not (output_root / "labels" / "train" / "sample.txt").exists()

    apply_keep_action(item, source_root, output_root)
    assert read_normalized_boxes(output_root / "labels" / "train" / "sample.txt") == original_boxes
    assert read_normalized_boxes(label_path) == original_boxes
    assert item.review_status == "kept"

    apply_redraw_action(item, source_root, output_root, redraw_boxes)
    assert read_normalized_boxes(output_root / "labels" / "train" / "sample.txt") == redraw_boxes
    assert read_normalized_boxes(label_path) == original_boxes
    assert item.review_status == "redrawn"


def test_suggest_tight_ball_box_fits_synthetic_circle():
    frame = np.zeros((400, 400, 3), dtype=np.uint8)
    true_center = (220, 180)
    true_radius = 24
    cv2.circle(frame, true_center, true_radius, (255, 255, 255), thickness=-1)

    # Deliberately oversized seed: 4x the true diameter, slightly off-center.
    seed_w = (true_radius * 2 * 4) / 400
    seed_h = (true_radius * 2 * 4) / 400
    seed = NormalizedBox(
        class_id=0,
        cx=(true_center[0] + 6) / 400,
        cy=(true_center[1] - 4) / 400,
        w=seed_w,
        h=seed_h,
    )

    suggestion = suggest_tight_ball_box(frame, seed)

    assert suggestion is not None
    suggested_cx_px = suggestion.cx * 400
    suggested_cy_px = suggestion.cy * 400
    suggested_w_px = suggestion.w * 400
    # Should converge from the offset seed (cx+6, cy-4) toward the true center.
    seed_offset_x = abs((true_center[0] + 6) - true_center[0])
    seed_offset_y = abs((true_center[1] - 4) - true_center[1])
    assert abs(suggested_cx_px - true_center[0]) < seed_offset_x
    assert abs(suggested_cy_px - true_center[1]) < seed_offset_y
    assert abs(suggested_w_px - true_radius * 2) <= true_radius * 0.30


def test_order_dataset_items_and_resume_prioritize_flagged_pending_items():
    reviewed = make_item("reviewed", 0, 20, review_status="kept")
    clean = make_item("clean", 3, 0)
    high = make_item("high", 1, 12)
    low = make_item("low", 2, 4)

    ordered = order_dataset_items([clean, reviewed, low, high], "flagged")

    assert [item.item_id for item in ordered] == ["high", "low", "clean", "reviewed"]
    assert determine_start_index(ordered, {"current_item_id": "clean"}, resume=True) == 2
    assert determine_start_index(ordered, {"current_item_id": "reviewed"}, resume=True) == 0
    assert determine_start_index(ordered, {}, resume=False) == 0
