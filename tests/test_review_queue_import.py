import shutil
from pathlib import Path
from uuid import uuid4

import cv2
import numpy as np
import pytest

from data_tools.review_queue import (
    DatasetReviewItem,
    NormalizedBox,
    collect_external_import_specs,
    import_external_yolo_dataset,
    load_manifest,
    load_progress,
    manifest_path,
    progress_path,
    save_manifest,
)


def create_image(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    assert cv2.imwrite(str(path), np.zeros((64, 64, 3), dtype=np.uint8))


@pytest.fixture
def workspace_tmp() -> Path:
    root = Path.cwd() / f"review_queue_import_{uuid4().hex}"
    root.mkdir(parents=True, exist_ok=False)
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_collect_external_import_specs_filters_ball_boxes_and_maps_splits(workspace_tmp: Path):
    external_root = workspace_tmp / "external"
    create_image(external_root / "train" / "images" / "sample.jpg")
    (external_root / "train" / "labels").mkdir(parents=True, exist_ok=True)
    (external_root / "train" / "labels" / "sample.txt").write_text(
        "\n".join(
            [
                "0 0.50 0.50 0.10 0.10",
                "1 0.40 0.40 0.20 0.20",
                "2 0.30 0.30 0.30 0.30",
                "0 0.60 0.60 0.10 0.10",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    create_image(external_root / "valid" / "images" / "skip.jpg")
    (external_root / "valid" / "labels").mkdir(parents=True, exist_ok=True)
    (external_root / "valid" / "labels" / "skip.txt").write_text(
        "1 0.40 0.40 0.20 0.20\n",
        encoding="utf-8",
    )

    specs, stats = collect_external_import_specs(
        external_root,
        {"train": "train", "valid": "val"},
        class_id=0,
        prefix="imported",
    )

    assert stats == {
        "images_scanned": 2,
        "missing_labels": 0,
        "without_ball": 1,
        "included_empty": 0,
    }
    assert len(specs) == 1
    assert specs[0].mapped_split == "train"
    assert specs[0].output_name == "imported_train_sample.jpg"
    assert [box.class_id for box in specs[0].boxes] == [0, 0]


def test_collect_external_import_specs_can_include_empty_labels(workspace_tmp: Path):
    external_root = workspace_tmp / "external"
    create_image(external_root / "train" / "images" / "empty.jpg")
    (external_root / "train" / "labels").mkdir(parents=True, exist_ok=True)
    (external_root / "train" / "labels" / "empty.txt").write_text("", encoding="utf-8")

    specs, stats = collect_external_import_specs(
        external_root,
        {"train": "train"},
        class_id=0,
        prefix="imported",
        include_empty=True,
    )

    assert stats == {
        "images_scanned": 1,
        "missing_labels": 0,
        "without_ball": 0,
        "included_empty": 1,
    }
    assert len(specs) == 1
    assert specs[0].output_name == "imported_train_empty.jpg"
    assert specs[0].boxes == []


def test_import_external_yolo_dataset_copies_filtered_files_and_appends_manifest(
    workspace_tmp: Path,
    monkeypatch,
):
    external_root = workspace_tmp / "external"
    create_image(external_root / "train" / "images" / "sample.jpg")
    (external_root / "train" / "labels").mkdir(parents=True, exist_ok=True)
    (external_root / "train" / "labels" / "sample.txt").write_text(
        "\n".join(
            [
                "0 0.50 0.50 0.10 0.10",
                "1 0.40 0.40 0.20 0.20",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    create_image(external_root / "valid" / "images" / "skip.jpg")
    (external_root / "valid" / "labels").mkdir(parents=True, exist_ok=True)
    (external_root / "valid" / "labels" / "skip.txt").write_text(
        "2 0.40 0.40 0.20 0.20\n",
        encoding="utf-8",
    )

    source_root = workspace_tmp / "source_dataset"
    output_root = workspace_tmp / "cleaned_dataset"
    (source_root / "images" / "train").mkdir(parents=True, exist_ok=True)
    (source_root / "labels" / "train").mkdir(parents=True, exist_ok=True)

    existing_item = DatasetReviewItem(
        item_id="train/existing.jpg",
        split="train",
        sequence_index=7,
        source_image_relpath="images/train/existing.jpg",
        source_label_relpath="labels/train/existing.txt",
        cleaned_image_relpath="images/train/existing.jpg",
        cleaned_label_relpath="labels/train/existing.txt",
        image_name="existing.jpg",
        label_count=1,
        label_geometry={},
        labels=[{"class_id": 0, "cx": 0.5, "cy": 0.5, "w": 0.1, "h": 0.1}],
        model_predictions=[],
        best_iou=None,
        suspicion_score=0,
        suspicion_reasons=[],
        review_status="kept",
    )
    save_manifest(manifest_path(output_root), [existing_item])
    progress_path(output_root).write_text(
        '{\n  "sort": "flagged",\n  "current_index": 0,\n  "current_item_id": "train/existing.jpg",\n  "pending_count": 0,\n  "flagged_pending_count": 0\n}\n',
        encoding="utf-8",
    )

    class FakeYOLO:
        def __init__(self, _model_path: str):
            pass

    monkeypatch.setattr("data_tools.review_queue.load_yolo_model", lambda _model_path: FakeYOLO(_model_path))
    monkeypatch.setattr("data_tools.review_queue.load_model_predictions", lambda *_args, **_kwargs: [])

    import_external_yolo_dataset(
        source_root=source_root,
        output_root=output_root,
        external_root=external_root,
        split_map={"train": "train", "valid": "val"},
        class_id=0,
        name_prefix="imported",
        model_path="runs/train/fake.pt",
    )

    imported_image = source_root / "images" / "train" / "imported_train_sample.jpg"
    imported_label = source_root / "labels" / "train" / "imported_train_sample.txt"
    cleaned_image = output_root / "images" / "train" / "imported_train_sample.jpg"
    cleaned_label = output_root / "labels" / "train" / "imported_train_sample.txt"

    assert imported_image.exists()
    assert cleaned_image.exists()
    assert imported_label.read_text(encoding="utf-8") == "0 0.500000 0.500000 0.100000 0.100000\n"
    assert cleaned_label.read_text(encoding="utf-8") == "0 0.500000 0.500000 0.100000 0.100000\n"

    items = load_manifest(manifest_path(output_root))
    assert [item.item_id for item in items] == ["train/existing.jpg", "train/imported_train_sample.jpg"]
    assert items[-1].sequence_index == 8
    assert items[-1].review_status == "pending"

    progress = load_progress(progress_path(output_root))
    assert progress["current_item_id"] == "train/existing.jpg"
    assert progress["pending_count"] == 1


def test_import_external_yolo_dataset_can_include_empty_labels(
    workspace_tmp: Path,
    monkeypatch,
):
    external_root = workspace_tmp / "external"
    create_image(external_root / "train" / "images" / "empty.jpg")
    (external_root / "train" / "labels").mkdir(parents=True, exist_ok=True)
    (external_root / "train" / "labels" / "empty.txt").write_text("", encoding="utf-8")

    source_root = workspace_tmp / "source_dataset"
    output_root = workspace_tmp / "cleaned_dataset"

    class FakeYOLO:
        def __init__(self, _model_path: str):
            pass

    monkeypatch.setattr("data_tools.review_queue.load_yolo_model", lambda _model_path: FakeYOLO(_model_path))
    monkeypatch.setattr("data_tools.review_queue.load_model_predictions", lambda *_args, **_kwargs: [])

    import_external_yolo_dataset(
        source_root=source_root,
        output_root=output_root,
        external_root=external_root,
        split_map={"train": "train"},
        class_id=0,
        name_prefix="imported",
        model_path="runs/train/fake.pt",
        include_empty=True,
    )

    imported_image = source_root / "images" / "train" / "imported_train_empty.jpg"
    imported_label = source_root / "labels" / "train" / "imported_train_empty.txt"
    cleaned_image = output_root / "images" / "train" / "imported_train_empty.jpg"
    cleaned_label = output_root / "labels" / "train" / "imported_train_empty.txt"

    assert imported_image.exists()
    assert cleaned_image.exists()
    assert imported_label.read_text(encoding="utf-8") == ""
    assert cleaned_label.read_text(encoding="utf-8") == ""

    items = load_manifest(manifest_path(output_root))
    assert [item.item_id for item in items] == ["train/imported_train_empty.jpg"]
    assert items[0].label_count == 0
    assert items[0].review_status == "pending"

    progress = load_progress(progress_path(output_root))
    assert progress["current_item_id"] == "train/imported_train_empty.jpg"
    assert progress["pending_count"] == 1
