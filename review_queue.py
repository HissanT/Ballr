import argparse
import json
import shutil
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import cv2

from ball_tracker_tracking import MODEL_PATH as DEFAULT_MODEL_PATH
from ballr_utils import build_gamma_lut, ensure_dir, preprocess_frame

IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png")
DEFAULT_DATASET_SPLITS = ("train", "val")
REVIEW_WINDOW_NAME = "Review Queue"
DATASET_WINDOW_NAME = "Dataset Review"
PREDICTION_CONF_THRESHOLD = 0.35
LOW_IOU_THRESHOLD = 0.35
LOW_CENTER_Y_THRESHOLD = 0.70
LOW_BOTTOM_Y_THRESHOLD = 0.92
LOW_ASPECT_THRESHOLD = 0.74
HIGH_ASPECT_THRESHOLD = 1.35
LOW_AREA_THRESHOLD = 0.0035
HIGH_AREA_THRESHOLD = 0.06
SOCCER_BALL_CLASS_ID = 0

SUSPICION_REASON_LABELS = {
    "empty_label_with_prediction": "Empty label + model hit",
    "positive_label_without_prediction": "Positive label + no model hit",
    "positive_label_low_iou": "Positive label + low IoU",
    "multi_box_label": "Multi-box label",
    "low_frame_box": "Low-frame box",
    "extreme_aspect_ratio": "Extreme aspect ratio",
    "extreme_box_area": "Extreme box area",
}


@dataclass
class QueueReviewItem:
    session_name: str
    image_path: Path
    label_path: Path
    capture_image_dir: Path
    capture_label_dir: Path


@dataclass(frozen=True)
class NormalizedBox:
    class_id: int
    cx: float
    cy: float
    w: float
    h: float
    conf: float | None = None

    @property
    def x1(self) -> float:
        return self.cx - (self.w / 2.0)

    @property
    def y1(self) -> float:
        return self.cy - (self.h / 2.0)

    @property
    def x2(self) -> float:
        return self.cx + (self.w / 2.0)

    @property
    def y2(self) -> float:
        return self.cy + (self.h / 2.0)

    def as_dict(self) -> dict[str, Any]:
        payload = {
            "class_id": self.class_id,
            "cx": round(self.cx, 6),
            "cy": round(self.cy, 6),
            "w": round(self.w, 6),
            "h": round(self.h, 6),
        }
        if self.conf is not None:
            payload["conf"] = round(self.conf, 6)
        return payload

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "NormalizedBox":
        return cls(
            class_id=int(payload["class_id"]),
            cx=float(payload["cx"]),
            cy=float(payload["cy"]),
            w=float(payload["w"]),
            h=float(payload["h"]),
            conf=float(payload["conf"]) if payload.get("conf") is not None else None,
        )


@dataclass
class DatasetReviewItem:
    item_id: str
    split: str
    sequence_index: int
    source_image_relpath: str
    source_label_relpath: str
    cleaned_image_relpath: str
    cleaned_label_relpath: str
    image_name: str
    label_count: int
    label_geometry: dict[str, Any]
    labels: list[dict[str, Any]]
    model_predictions: list[dict[str, Any]]
    best_iou: float | None
    suspicion_score: int
    suspicion_reasons: list[str]
    review_status: str = "pending"

    def to_dict(self) -> dict[str, Any]:
        payload = asdict(self)
        if self.best_iou is not None:
            payload["best_iou"] = round(self.best_iou, 6)
        return payload

    @classmethod
    def from_dict(cls, payload: dict[str, Any]) -> "DatasetReviewItem":
        return cls(
            item_id=str(payload["item_id"]),
            split=str(payload["split"]),
            sequence_index=int(payload["sequence_index"]),
            source_image_relpath=str(payload["source_image_relpath"]),
            source_label_relpath=str(payload["source_label_relpath"]),
            cleaned_image_relpath=str(payload["cleaned_image_relpath"]),
            cleaned_label_relpath=str(payload["cleaned_label_relpath"]),
            image_name=str(payload["image_name"]),
            label_count=int(payload["label_count"]),
            label_geometry=dict(payload["label_geometry"]),
            labels=list(payload["labels"]),
            model_predictions=list(payload["model_predictions"]),
            best_iou=float(payload["best_iou"]) if payload.get("best_iou") is not None else None,
            suspicion_score=int(payload["suspicion_score"]),
            suspicion_reasons=list(payload["suspicion_reasons"]),
            review_status=str(payload.get("review_status", "pending")),
        )


@dataclass
class BoxDrawerState:
    boxes: list[tuple[int, int, int, int]]
    drawing: bool = False
    start_x: int = 0
    start_y: int = 0
    current_x: int = 0
    current_y: int = 0


def image_paths(image_dir: Path) -> list[Path]:
    if not image_dir.exists():
        return []
    return sorted(
        path
        for path in image_dir.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
    )


def resolve_target_path(target_dir: Path, name: str) -> Path:
    candidate = target_dir / name
    if not candidate.exists():
        return candidate

    stem = candidate.stem
    suffix = candidate.suffix
    index = 1
    while True:
        candidate = target_dir / f"{stem}_reviewed_{index}{suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def find_review_items(review_root: Path, session_name: str | None) -> list[QueueReviewItem]:
    items: list[QueueReviewItem] = []
    if not review_root.exists():
        return items

    session_dirs = sorted(path for path in review_root.iterdir() if path.is_dir())
    for session_dir in session_dirs:
        if session_name is not None and session_dir.name != session_name:
            continue

        image_dir = session_dir / "images"
        label_dir = session_dir / "labels"
        if not image_dir.exists() or not label_dir.exists():
            continue

        capture_image_dir = review_root.parent / "captures" / session_dir.name / "images"
        capture_label_dir = review_root.parent / "captures" / session_dir.name / "labels"
        for image_path in image_paths(image_dir):
            label_path = label_dir / f"{image_path.stem}.txt"
            if not label_path.exists():
                continue
            items.append(
                QueueReviewItem(
                    session_name=session_dir.name,
                    image_path=image_path,
                    label_path=label_path,
                    capture_image_dir=capture_image_dir,
                    capture_label_dir=capture_label_dir,
                )
            )

    return items


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def parse_split_list(raw: str) -> tuple[str, ...]:
    splits = tuple(part.strip() for part in raw.split(",") if part.strip())
    if not splits:
        raise argparse.ArgumentTypeError("Expected at least one split name.")
    return splits


def normalize_box(
    *,
    class_id: int,
    cx: float,
    cy: float,
    w: float,
    h: float,
    conf: float | None = None,
) -> NormalizedBox:
    return NormalizedBox(
        class_id=class_id,
        cx=clamp01(cx),
        cy=clamp01(cy),
        w=max(0.0, min(1.0, w)),
        h=max(0.0, min(1.0, h)),
        conf=conf,
    )


def read_normalized_boxes(label_path: Path) -> list[NormalizedBox]:
    if not label_path.exists():
        return []

    boxes: list[NormalizedBox] = []
    for raw_line in label_path.read_text(encoding="utf-8").splitlines():
        parts = raw_line.split()
        if len(parts) != 5:
            continue
        boxes.append(
            normalize_box(
                class_id=int(parts[0]),
                cx=float(parts[1]),
                cy=float(parts[2]),
                w=float(parts[3]),
                h=float(parts[4]),
            )
        )

    return boxes


def write_normalized_boxes(label_path: Path, boxes: list[NormalizedBox]) -> None:
    ensure_dir(label_path.parent)
    with label_path.open("w", encoding="utf-8") as handle:
        for box in boxes:
            handle.write(
                f"{box.class_id} {box.cx:.6f} {box.cy:.6f} {box.w:.6f} {box.h:.6f}\n"
            )


def normalized_box_to_pixels(
    box: NormalizedBox,
    image_width: int,
    image_height: int,
) -> tuple[int, int, int, int]:
    x1 = max(int(round(box.x1 * image_width)), 0)
    y1 = max(int(round(box.y1 * image_height)), 0)
    x2 = min(int(round(box.x2 * image_width)), image_width - 1)
    y2 = min(int(round(box.y2 * image_height)), image_height - 1)
    return x1, y1, x2, y2


def pixels_to_normalized_boxes(
    pixel_boxes: list[tuple[int, int, int, int]],
    image_width: int,
    image_height: int,
    class_id: int = SOCCER_BALL_CLASS_ID,
) -> list[NormalizedBox]:
    boxes: list[NormalizedBox] = []
    for x1, y1, x2, y2 in pixel_boxes:
        if x2 <= x1 or y2 <= y1:
            continue
        boxes.append(
            normalize_box(
                class_id=class_id,
                cx=((x1 + x2) / 2.0) / image_width,
                cy=((y1 + y2) / 2.0) / image_height,
                w=(x2 - x1) / image_width,
                h=(y2 - y1) / image_height,
            )
        )
    return boxes


def read_boxes(label_path: Path, image_width: int, image_height: int) -> list[tuple[int, int, int, int]]:
    return [
        normalized_box_to_pixels(box, image_width, image_height)
        for box in read_normalized_boxes(label_path)
    ]


def box_aspect_ratio(box: NormalizedBox) -> float:
    return box.w / max(box.h, 1e-6)


def box_area(box: NormalizedBox) -> float:
    return box.w * box.h


def box_bottom(box: NormalizedBox) -> float:
    return box.cy + (box.h / 2.0)


def summarize_label_geometry(boxes: list[NormalizedBox]) -> dict[str, Any]:
    return {
        "centers_y": [round(box.cy, 6) for box in boxes],
        "bottoms_y": [round(box_bottom(box), 6) for box in boxes],
        "aspects": [round(box_aspect_ratio(box), 6) for box in boxes],
        "areas": [round(box_area(box), 6) for box in boxes],
    }


def box_iou(left: NormalizedBox, right: NormalizedBox) -> float:
    inter_x1 = max(left.x1, right.x1)
    inter_y1 = max(left.y1, right.y1)
    inter_x2 = min(left.x2, right.x2)
    inter_y2 = min(left.y2, right.y2)
    inter_w = max(0.0, inter_x2 - inter_x1)
    inter_h = max(0.0, inter_y2 - inter_y1)
    if inter_w <= 0.0 or inter_h <= 0.0:
        return 0.0

    intersection = inter_w * inter_h
    union = box_area(left) + box_area(right) - intersection
    if union <= 0.0:
        return 0.0
    return intersection / union


def best_box_iou(labels: list[NormalizedBox], predictions: list[NormalizedBox]) -> float | None:
    if not labels or not predictions:
        return None
    return max(box_iou(label, prediction) for label in labels for prediction in predictions)


def score_suspicious_item(
    *,
    label_count: int,
    label_geometry: dict[str, Any],
    predictions: list[NormalizedBox],
    best_iou: float | None,
) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []
    centers_y = [float(value) for value in label_geometry.get("centers_y", [])]
    bottoms_y = [float(value) for value in label_geometry.get("bottoms_y", [])]
    aspects = [float(value) for value in label_geometry.get("aspects", [])]
    areas = [float(value) for value in label_geometry.get("areas", [])]

    if label_count == 0 and predictions:
        score += 10
        reasons.append("empty_label_with_prediction")
    if label_count > 0 and not predictions:
        score += 8
        reasons.append("positive_label_without_prediction")
    if label_count > 0 and predictions and best_iou is not None and best_iou < LOW_IOU_THRESHOLD:
        score += 8
        reasons.append("positive_label_low_iou")
    if label_count > 1:
        score += 6
        reasons.append("multi_box_label")
    if any(value >= LOW_CENTER_Y_THRESHOLD for value in centers_y) or any(
        value >= LOW_BOTTOM_Y_THRESHOLD for value in bottoms_y
    ):
        score += 4
        reasons.append("low_frame_box")
    if any(value <= LOW_ASPECT_THRESHOLD or value >= HIGH_ASPECT_THRESHOLD for value in aspects):
        score += 2
        reasons.append("extreme_aspect_ratio")
    if any(value <= LOW_AREA_THRESHOLD or value >= HIGH_AREA_THRESHOLD for value in areas):
        score += 2
        reasons.append("extreme_box_area")
    return score, reasons


def build_dataset_review_item(
    *,
    source_root: Path,
    output_root: Path,
    split: str,
    sequence_index: int,
    image_path: Path,
    label_boxes: list[NormalizedBox],
    model_predictions: list[NormalizedBox],
) -> DatasetReviewItem:
    source_image_relpath = image_path.relative_to(source_root).as_posix()
    source_label_relpath = f"labels/{split}/{image_path.stem}.txt"
    cleaned_image_relpath = f"images/{split}/{image_path.name}"
    cleaned_label_relpath = f"labels/{split}/{image_path.stem}.txt"
    label_geometry = summarize_label_geometry(label_boxes)
    best_iou = best_box_iou(label_boxes, model_predictions)
    suspicion_score, suspicion_reasons = score_suspicious_item(
        label_count=len(label_boxes),
        label_geometry=label_geometry,
        predictions=model_predictions,
        best_iou=best_iou,
    )
    _ = output_root
    return DatasetReviewItem(
        item_id=f"{split}/{image_path.name}",
        split=split,
        sequence_index=sequence_index,
        source_image_relpath=source_image_relpath,
        source_label_relpath=source_label_relpath,
        cleaned_image_relpath=cleaned_image_relpath,
        cleaned_label_relpath=cleaned_label_relpath,
        image_name=image_path.name,
        label_count=len(label_boxes),
        label_geometry=label_geometry,
        labels=[box.as_dict() for box in label_boxes],
        model_predictions=[box.as_dict() for box in model_predictions],
        best_iou=best_iou,
        suspicion_score=suspicion_score,
        suspicion_reasons=suspicion_reasons,
        review_status="pending",
    )


def manifest_path(output_root: Path) -> Path:
    return output_root / "review" / "manifest.jsonl"


def progress_path(output_root: Path) -> Path:
    return output_root / "review" / "progress.json"


def save_manifest(path: Path, items: list[DatasetReviewItem]) -> None:
    ensure_dir(path.parent)
    with path.open("w", encoding="utf-8") as handle:
        for item in items:
            handle.write(json.dumps(item.to_dict(), sort_keys=True) + "\n")


def load_manifest(path: Path) -> list[DatasetReviewItem]:
    if not path.exists():
        return []
    items: list[DatasetReviewItem] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        raw_line = raw_line.strip()
        if not raw_line:
            continue
        items.append(DatasetReviewItem.from_dict(json.loads(raw_line)))
    return items


def load_progress(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def pending_item_count(items: list[DatasetReviewItem]) -> int:
    return sum(item.review_status == "pending" for item in items)


def flagged_pending_count(items: list[DatasetReviewItem]) -> int:
    return sum(
        item.review_status == "pending" and item.suspicion_score > 0
        for item in items
    )


def save_progress(
    path: Path,
    items: list[DatasetReviewItem],
    current_index: int | None,
    sort_mode: str,
) -> None:
    current_item_id = None
    if current_index is not None and 0 <= current_index < len(items):
        current_item_id = items[current_index].item_id
    payload = {
        "sort": sort_mode,
        "current_index": current_index,
        "current_item_id": current_item_id,
        "pending_count": pending_item_count(items),
        "flagged_pending_count": flagged_pending_count(items),
    }
    ensure_dir(path.parent)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def order_dataset_items(items: list[DatasetReviewItem], sort_mode: str) -> list[DatasetReviewItem]:
    def key(item: DatasetReviewItem) -> tuple[Any, ...]:
        if item.review_status != "pending":
            return (2, item.sequence_index)
        if sort_mode == "flagged" and item.suspicion_score > 0:
            return (0, -item.suspicion_score, item.sequence_index)
        return (1, item.sequence_index)

    return sorted(items, key=key)


def first_pending_index(items: list[DatasetReviewItem]) -> int | None:
    for index, item in enumerate(items):
        if item.review_status == "pending":
            return index
    return None


def next_pending_index(items: list[DatasetReviewItem], start_index: int) -> int | None:
    for index in range(max(start_index, 0), len(items)):
        if items[index].review_status == "pending":
            return index
    return None


def determine_start_index(
    items: list[DatasetReviewItem],
    progress: dict[str, Any],
    resume: bool,
) -> int | None:
    if resume:
        resume_item_id = progress.get("current_item_id")
        if resume_item_id is not None:
            for index, item in enumerate(items):
                if item.item_id == resume_item_id:
                    return index
    return first_pending_index(items)


def ensure_clean_dataset_copy(
    source_root: Path,
    output_root: Path,
    splits: tuple[str, ...],
) -> None:
    ensure_dir(output_root)
    ensure_dir(output_root / "review")
    source_yaml = source_root / "data.yaml"
    target_yaml = output_root / "data.yaml"
    if source_yaml.exists() and not target_yaml.exists():
        shutil.copy2(source_yaml, target_yaml)

    for split in splits:
        source_image_dir = source_root / "images" / split
        source_label_dir = source_root / "labels" / split
        target_image_dir = ensure_dir(output_root / "images" / split)
        target_label_dir = ensure_dir(output_root / "labels" / split)

        for image_path in image_paths(source_image_dir):
            target_image_path = target_image_dir / image_path.name
            if not target_image_path.exists():
                shutil.copy2(image_path, target_image_path)

            source_label_path = source_label_dir / f"{image_path.stem}.txt"
            target_label_path = target_label_dir / f"{image_path.stem}.txt"
            if source_label_path.exists():
                if not target_label_path.exists():
                    shutil.copy2(source_label_path, target_label_path)
            elif not target_label_path.exists():
                write_normalized_boxes(target_label_path, [])


def load_model_predictions(model, image_path: Path, gamma_lut, clahe) -> list[NormalizedBox]:
    frame = cv2.imread(str(image_path))
    if frame is None:
        return []

    enhanced = preprocess_frame(frame, gamma_lut, clahe)
    results = model.predict(
        enhanced,
        conf=PREDICTION_CONF_THRESHOLD,
        iou=LOW_IOU_THRESHOLD,
        classes=[SOCCER_BALL_CLASS_ID],
        max_det=8,
        verbose=False,
    )
    if not results or results[0].boxes is None:
        return []

    image_height, image_width = enhanced.shape[:2]
    predictions: list[NormalizedBox] = []
    for prediction in results[0].boxes:
        x1, y1, x2, y2 = prediction.xyxy[0].tolist()
        predictions.append(
            normalize_box(
                class_id=int(prediction.cls[0]) if prediction.cls is not None else SOCCER_BALL_CLASS_ID,
                cx=((x1 + x2) / 2.0) / image_width,
                cy=((y1 + y2) / 2.0) / image_height,
                w=(x2 - x1) / image_width,
                h=(y2 - y1) / image_height,
                conf=float(prediction.conf[0]) if prediction.conf is not None else None,
            )
        )
    return predictions


def build_dataset_manifest(
    source_root: Path,
    output_root: Path,
    splits: tuple[str, ...],
    model_path: str,
) -> list[DatasetReviewItem]:
    from ultralytics import YOLO

    ensure_clean_dataset_copy(source_root, output_root, splits)

    image_specs: list[tuple[int, str, Path, Path]] = []
    sequence_index = 0
    for split in splits:
        source_image_dir = source_root / "images" / split
        source_label_dir = source_root / "labels" / split
        for image_path in image_paths(source_image_dir):
            image_specs.append(
                (
                    sequence_index,
                    split,
                    image_path,
                    source_label_dir / f"{image_path.stem}.txt",
                )
            )
            sequence_index += 1

    print(
        f"Building dataset review manifest for '{source_root}' with {len(image_specs)} images "
        f"using '{model_path}'."
    )
    model = YOLO(model_path)
    gamma_lut = build_gamma_lut()
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    items: list[DatasetReviewItem] = []

    for index, (sequence_index, split, image_path, label_path) in enumerate(image_specs, start=1):
        label_boxes = read_normalized_boxes(label_path)
        model_predictions = load_model_predictions(model, image_path, gamma_lut, clahe)
        items.append(
            build_dataset_review_item(
                source_root=source_root,
                output_root=output_root,
                split=split,
                sequence_index=sequence_index,
                image_path=image_path,
                label_boxes=label_boxes,
                model_predictions=model_predictions,
            )
        )
        if index % 100 == 0 or index == len(image_specs):
            print(f"Scored {index}/{len(image_specs)} images...")

    save_manifest(manifest_path(output_root), items)
    save_progress(progress_path(output_root), items, first_pending_index(items), "flagged")
    return items


def load_or_create_dataset_manifest(
    source_root: Path,
    output_root: Path,
    splits: tuple[str, ...],
    model_path: str,
) -> list[DatasetReviewItem]:
    ensure_clean_dataset_copy(source_root, output_root, splits)
    path = manifest_path(output_root)
    items = load_manifest(path)
    if items:
        return items
    return build_dataset_manifest(source_root, output_root, splits, model_path)


def dataset_item_source_image_path(item: DatasetReviewItem, source_root: Path) -> Path:
    return source_root / Path(item.source_image_relpath)


def dataset_item_source_label_path(item: DatasetReviewItem, source_root: Path) -> Path:
    return source_root / Path(item.source_label_relpath)


def dataset_item_output_image_path(item: DatasetReviewItem, output_root: Path) -> Path:
    return output_root / Path(item.cleaned_image_relpath)


def dataset_item_output_label_path(item: DatasetReviewItem, output_root: Path) -> Path:
    return output_root / Path(item.cleaned_label_relpath)


def model_predictions_for_item(item: DatasetReviewItem) -> list[NormalizedBox]:
    return [NormalizedBox.from_dict(payload) for payload in item.model_predictions]


def refresh_item_boxes(
    item: DatasetReviewItem,
    boxes: list[NormalizedBox],
    review_status: str,
) -> DatasetReviewItem:
    label_geometry = summarize_label_geometry(boxes)
    predictions = model_predictions_for_item(item)
    best_iou = best_box_iou(boxes, predictions)
    suspicion_score, suspicion_reasons = score_suspicious_item(
        label_count=len(boxes),
        label_geometry=label_geometry,
        predictions=predictions,
        best_iou=best_iou,
    )
    item.labels = [box.as_dict() for box in boxes]
    item.label_count = len(boxes)
    item.label_geometry = label_geometry
    item.best_iou = best_iou
    item.suspicion_score = suspicion_score
    item.suspicion_reasons = suspicion_reasons
    item.review_status = review_status
    return item


def ensure_output_image_from_source(
    item: DatasetReviewItem,
    source_root: Path,
    output_root: Path,
) -> None:
    source_image_path = dataset_item_source_image_path(item, source_root)
    output_image_path = dataset_item_output_image_path(item, output_root)
    ensure_dir(output_image_path.parent)
    shutil.copy2(source_image_path, output_image_path)


def apply_keep_action(
    item: DatasetReviewItem,
    source_root: Path,
    output_root: Path,
) -> DatasetReviewItem:
    ensure_output_image_from_source(item, source_root, output_root)
    source_boxes = read_normalized_boxes(dataset_item_source_label_path(item, source_root))
    write_normalized_boxes(dataset_item_output_label_path(item, output_root), source_boxes)
    return refresh_item_boxes(item, source_boxes, "kept")


def apply_empty_action(
    item: DatasetReviewItem,
    source_root: Path,
    output_root: Path,
) -> DatasetReviewItem:
    ensure_output_image_from_source(item, source_root, output_root)
    write_normalized_boxes(dataset_item_output_label_path(item, output_root), [])
    return refresh_item_boxes(item, [], "empty")


def apply_redraw_action(
    item: DatasetReviewItem,
    source_root: Path,
    output_root: Path,
    boxes: list[NormalizedBox],
) -> DatasetReviewItem:
    ensure_output_image_from_source(item, source_root, output_root)
    write_normalized_boxes(dataset_item_output_label_path(item, output_root), boxes)
    return refresh_item_boxes(item, boxes, "redrawn")


def apply_exclude_action(
    item: DatasetReviewItem,
    output_root: Path,
) -> DatasetReviewItem:
    output_image_path = dataset_item_output_image_path(item, output_root)
    output_label_path = dataset_item_output_label_path(item, output_root)
    if output_image_path.exists():
        output_image_path.unlink()
    if output_label_path.exists():
        output_label_path.unlink()
    return refresh_item_boxes(item, [], "excluded")


def draw_label(frame, text: str, x: int, y: int) -> None:
    (text_width, text_height), baseline = cv2.getTextSize(
        text,
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        2,
    )
    y = max(y, text_height + baseline)
    cv2.rectangle(
        frame,
        (x, y - text_height - baseline),
        (x + text_width, y + baseline),
        (0, 0, 0),
        -1,
    )
    cv2.putText(
        frame,
        text,
        (x, y),
        cv2.FONT_HERSHEY_SIMPLEX,
        0.55,
        (255, 255, 255),
        2,
    )


def draw_box_list(
    frame,
    boxes: list[NormalizedBox],
    color: tuple[int, int, int],
    prefix: str,
    image_width: int,
    image_height: int,
) -> None:
    for box_index, box in enumerate(boxes, start=1):
        x1, y1, x2, y2 = normalized_box_to_pixels(box, image_width, image_height)
        cv2.rectangle(frame, (x1, y1), (x2, y2), color, 2)
        label = f"{prefix} {box_index}"
        if box.conf is not None:
            label = f"{label} {box.conf:.2f}"
        draw_label(frame, label, x1, max(18, y1 - 6))


def draw_queue_review_frame(frame, boxes, item: QueueReviewItem, index: int, total: int) -> None:
    for box_index, (x1, y1, x2, y2) in enumerate(boxes, start=1):
        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 215, 255), 2)
        draw_label(frame, f"Box {box_index}", x1, max(18, y1 - 6))

    draw_label(frame, f"{index + 1}/{total}", 8, 24)
    draw_label(frame, f"Session: {item.session_name}", 8, 52)
    draw_label(frame, f"File: {item.image_path.name}", 8, 80)
    draw_label(frame, f"Boxes: {len(boxes)}", 8, 108)
    draw_label(frame, "K keep  D delete  S skip  B back  Q quit", 8, frame.shape[0] - 16)


def humanize_reasons(reasons: list[str]) -> str:
    if not reasons:
        return "None"
    return ", ".join(SUSPICION_REASON_LABELS.get(reason, reason) for reason in reasons)


def draw_dataset_review_frame(
    frame,
    item: DatasetReviewItem,
    index: int,
    total: int,
    flagged_remaining: int,
) -> None:
    image_height, image_width = frame.shape[:2]
    current_boxes = [NormalizedBox.from_dict(payload) for payload in item.labels]
    predictions = model_predictions_for_item(item)
    draw_box_list(frame, current_boxes, (0, 215, 255), "Label", image_width, image_height)
    draw_box_list(frame, predictions, (255, 180, 0), "Pred", image_width, image_height)

    draw_label(frame, f"{index + 1}/{total}", 8, 24)
    draw_label(frame, f"Split: {item.split}", 8, 52)
    draw_label(frame, f"File: {item.image_name}", 8, 80)
    draw_label(frame, f"Status: {item.review_status}", 8, 108)
    draw_label(frame, f"Labels: {item.label_count}", 8, 136)
    draw_label(frame, f"Predictions: {len(predictions)}", 8, 164)
    draw_label(frame, f"Flagged remaining: {flagged_remaining}", 8, 192)
    draw_label(
        frame,
        f"Score: {item.suspicion_score} | Best IoU: {item.best_iou if item.best_iou is not None else 'n/a'}",
        8,
        220,
    )
    draw_label(frame, f"Reasons: {humanize_reasons(item.suspicion_reasons)}", 8, 248)
    draw_label(
        frame,
        "K keep  R redraw  E empty  X exclude  S skip  B back  Q quit",
        8,
        frame.shape[0] - 16,
    )


def draw_redraw_overlay(
    frame,
    existing_boxes: list[NormalizedBox],
    model_predictions: list[NormalizedBox],
    draft_boxes: list[tuple[int, int, int, int]],
    draft_box: tuple[int, int, int, int] | None,
) -> None:
    image_height, image_width = frame.shape[:2]
    draw_box_list(frame, existing_boxes, (0, 215, 255), "Saved", image_width, image_height)
    draw_box_list(frame, model_predictions, (255, 180, 0), "Pred", image_width, image_height)
    for box_index, (x1, y1, x2, y2) in enumerate(draft_boxes, start=1):
        cv2.rectangle(frame, (x1, y1), (x2, y2), (255, 0, 255), 2)
        draw_label(frame, f"New {box_index}", x1, max(18, y1 - 6))
    if draft_box is not None:
        x1, y1, x2, y2 = draft_box
        cv2.rectangle(frame, (x1, y1), (x2, y2), (255, 0, 255), 1)

    draw_label(frame, "Redraw mode: drag boxes, U undo, Enter save, Esc cancel", 8, 24)


def redraw_mouse_handler(event, x, y, _flags, state: BoxDrawerState) -> None:
    if event == cv2.EVENT_LBUTTONDOWN:
        state.drawing = True
        state.start_x = x
        state.start_y = y
        state.current_x = x
        state.current_y = y
        return

    if event == cv2.EVENT_MOUSEMOVE and state.drawing:
        state.current_x = x
        state.current_y = y
        return

    if event == cv2.EVENT_LBUTTONUP and state.drawing:
        state.drawing = False
        state.current_x = x
        state.current_y = y
        x1 = min(state.start_x, x)
        y1 = min(state.start_y, y)
        x2 = max(state.start_x, x)
        y2 = max(state.start_y, y)
        if (x2 - x1) >= 3 and (y2 - y1) >= 3:
            state.boxes.append((x1, y1, x2, y2))


def redraw_boxes(
    window_name: str,
    frame,
    existing_boxes: list[NormalizedBox],
    model_predictions: list[NormalizedBox],
) -> list[NormalizedBox] | None:
    state = BoxDrawerState(boxes=[])
    cv2.setMouseCallback(window_name, redraw_mouse_handler, state)
    try:
        while True:
            display = frame.copy()
            draft_box = None
            if state.drawing:
                draft_box = (
                    min(state.start_x, state.current_x),
                    min(state.start_y, state.current_y),
                    max(state.start_x, state.current_x),
                    max(state.start_y, state.current_y),
                )
            draw_redraw_overlay(display, existing_boxes, model_predictions, state.boxes, draft_box)
            cv2.imshow(window_name, display)

            key = cv2.waitKey(20) & 0xFF
            if key in (13, 10):
                return pixels_to_normalized_boxes(
                    state.boxes,
                    frame.shape[1],
                    frame.shape[0],
                )
            if key == ord("u") and state.boxes:
                state.boxes.pop()
            if key in (27, ord("c")):
                return None
    finally:
        cv2.setMouseCallback(window_name, lambda *_args: None)


def promote_item(item: QueueReviewItem) -> None:
    ensure_dir(item.capture_image_dir)
    ensure_dir(item.capture_label_dir)

    target_image_path = resolve_target_path(item.capture_image_dir, item.image_path.name)
    target_label_path = resolve_target_path(item.capture_label_dir, item.label_path.name)
    shutil.move(str(item.image_path), str(target_image_path))
    shutil.move(str(item.label_path), str(target_label_path))


def delete_item(item: QueueReviewItem) -> None:
    if item.image_path.exists():
        item.image_path.unlink()
    if item.label_path.exists():
        item.label_path.unlink()


def run_queue_mode(review_root: Path, session_name: str | None) -> None:
    items = find_review_items(review_root, session_name)
    if not items:
        print(f"No review items found under '{review_root}'.")
        return

    cv2.namedWindow(REVIEW_WINDOW_NAME, cv2.WINDOW_NORMAL)
    index = 0
    kept = 0
    deleted = 0

    while 0 <= index < len(items):
        item = items[index]
        if not item.image_path.exists() or not item.label_path.exists():
            items.pop(index)
            if not items:
                break
            index = min(index, len(items) - 1)
            continue

        frame = cv2.imread(str(item.image_path))
        if frame is None:
            print(f"Unreadable image: {item.image_path}")
            index += 1
            continue

        boxes = read_boxes(item.label_path, frame.shape[1], frame.shape[0])
        display = frame.copy()
        draw_queue_review_frame(display, boxes, item, index, len(items))
        cv2.imshow(REVIEW_WINDOW_NAME, display)

        key = cv2.waitKey(0) & 0xFF
        if key in (ord("q"), 27):
            break
        if key == ord("k"):
            promote_item(item)
            kept += 1
            items.pop(index)
            if not items:
                break
            index = min(index, len(items) - 1)
            continue
        if key == ord("d"):
            delete_item(item)
            deleted += 1
            items.pop(index)
            if not items:
                break
            index = min(index, len(items) - 1)
            continue
        if key == ord("b"):
            index = max(0, index - 1)
            continue

        index += 1

    cv2.destroyAllWindows()
    print(f"Review complete. Kept: {kept}, deleted: {deleted}, remaining: {len(items)}")


def run_dataset_mode(
    source_root: Path,
    output_root: Path,
    splits: tuple[str, ...],
    model_path: str,
    sort_mode: str,
    resume: bool,
) -> None:
    items = load_or_create_dataset_manifest(source_root, output_root, splits, model_path)
    ordered_items = order_dataset_items(items, sort_mode)
    if not ordered_items:
        print(f"No dataset items found under '{source_root}'.")
        return

    progress = load_progress(progress_path(output_root))
    index = determine_start_index(ordered_items, progress, resume)
    if index is None:
        print("No pending dataset review items remain.")
        return

    cv2.namedWindow(DATASET_WINDOW_NAME, cv2.WINDOW_NORMAL)

    while 0 <= index < len(ordered_items):
        item = ordered_items[index]
        source_image_path = dataset_item_source_image_path(item, source_root)
        frame = cv2.imread(str(source_image_path))
        if frame is None:
            print(f"Unreadable image: {source_image_path}")
            next_index = next_pending_index(ordered_items, index + 1)
            if next_index is None:
                break
            index = next_index
            continue

        display = frame.copy()
        draw_dataset_review_frame(
            display,
            item,
            index,
            len(ordered_items),
            flagged_pending_count(ordered_items),
        )
        cv2.imshow(DATASET_WINDOW_NAME, display)
        save_progress(progress_path(output_root), ordered_items, index, sort_mode)

        key = cv2.waitKey(0) & 0xFF
        if key in (ord("q"), 27):
            break
        if key == ord("b"):
            index = max(0, index - 1)
            continue
        if key == ord("s"):
            next_index = next_pending_index(ordered_items, index + 1)
            if next_index is None:
                break
            index = next_index
            continue
        if key == ord("k"):
            apply_keep_action(item, source_root, output_root)
            save_manifest(manifest_path(output_root), items)
            next_index = next_pending_index(ordered_items, index + 1)
            if next_index is None:
                break
            index = next_index
            continue
        if key == ord("e"):
            apply_empty_action(item, source_root, output_root)
            save_manifest(manifest_path(output_root), items)
            next_index = next_pending_index(ordered_items, index + 1)
            if next_index is None:
                break
            index = next_index
            continue
        if key == ord("x"):
            apply_exclude_action(item, output_root)
            save_manifest(manifest_path(output_root), items)
            next_index = next_pending_index(ordered_items, index + 1)
            if next_index is None:
                break
            index = next_index
            continue
        if key == ord("r"):
            new_boxes = redraw_boxes(
                DATASET_WINDOW_NAME,
                frame,
                [NormalizedBox.from_dict(payload) for payload in item.labels],
                model_predictions_for_item(item),
            )
            if new_boxes is not None:
                apply_redraw_action(item, source_root, output_root, new_boxes)
                save_manifest(manifest_path(output_root), items)
                next_index = next_pending_index(ordered_items, index + 1)
                if next_index is None:
                    break
                index = next_index
            continue

    save_manifest(manifest_path(output_root), items)
    final_index = min(index, len(ordered_items) - 1) if ordered_items else None
    save_progress(progress_path(output_root), ordered_items, final_index, sort_mode)
    cv2.destroyAllWindows()
    print(
        f"Dataset review complete. Pending: {pending_item_count(ordered_items)}, "
        f"flagged pending: {flagged_pending_count(ordered_items)}."
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Review queued labels or a full labeled dataset")
    parser.add_argument(
        "mode",
        nargs="?",
        choices=("queue", "dataset"),
        default="queue",
        help="Review the manual queue or a full dataset root",
    )
    parser.add_argument("--root", help="Review root. Defaults to dataset/review or dataset based on mode.")
    parser.add_argument("--session", help="Only review one queue session folder")
    parser.add_argument(
        "--output-root",
        default="dataset_cleaned",
        help="Destination for cleaned dataset review output",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_MODEL_PATH,
        help="Detector weights for dataset scoring overlays",
    )
    parser.add_argument(
        "--splits",
        default=",".join(DEFAULT_DATASET_SPLITS),
        help="Comma-separated dataset splits to review in dataset mode",
    )
    parser.add_argument(
        "--sort",
        choices=("flagged", "sequential"),
        default="flagged",
        help="Review ordering for dataset mode",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume dataset review from the saved progress item",
    )
    args = parser.parse_args()

    if args.mode == "queue":
        review_root = Path(args.root or "dataset/review")
        run_queue_mode(review_root, args.session)
        return

    source_root = Path(args.root or "dataset")
    run_dataset_mode(
        source_root=source_root,
        output_root=Path(args.output_root),
        splits=parse_split_list(args.splits),
        model_path=args.model,
        sort_mode=args.sort,
        resume=args.resume,
    )


if __name__ == "__main__":
    main()
