from __future__ import annotations

import argparse
import struct
import json
import math
import re
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import cv2
import numpy as np

from common.ballr_utils import training_path
from data_tools.dataset_tools import (
    IMAGE_EXTENSIONS,
    ensure_empty_output_root,
    image_paths,
    read_normalized_boxes,
)

SIZE_BINS: tuple[tuple[str, float, float], ...] = (
    ("<=12px", 0.0, 12.0),
    ("12-20px", 12.0, 20.0),
    ("20-30px", 20.0, 30.0),
    ("30-60px", 30.0, 60.0),
    (">60px", 60.0, math.inf),
)
FRAME_RE = re.compile(
    r"(?P<prefix>.*?)(?:review_frame|saved_frame|frame)_(?P<timestamp>\d+)(?:_(?P<frame>\d+))?",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class PixelBox:
    class_id: int
    x1: float
    y1: float
    x2: float
    y2: float
    confidence: float | None = None

    @property
    def area(self) -> float:
        return max(self.x2 - self.x1, 0.0) * max(self.y2 - self.y1, 0.0)

    @property
    def sqrt_area(self) -> float:
        return math.sqrt(self.area)


@dataclass(frozen=True)
class FrameIdentity:
    sequence_key: str
    timestamp_ms: int | None
    frame_number: int | None


def image_size(image_path: Path) -> tuple[int, int]:
    header_size = image_size_from_header(image_path)
    if header_size is not None:
        return header_size
    image = cv2.imread(str(image_path))
    if image is None:
        raise ValueError(f"Unable to read image: {image_path}")
    height, width = image.shape[:2]
    return width, height


def image_size_from_header(image_path: Path) -> tuple[int, int] | None:
    suffix = image_path.suffix.lower()
    try:
        if suffix == ".png":
            with image_path.open("rb") as handle:
                header = handle.read(24)
            if header.startswith(b"\x89PNG\r\n\x1a\n") and len(header) >= 24:
                width, height = struct.unpack(">II", header[16:24])
                return int(width), int(height)
        if suffix in {".jpg", ".jpeg"}:
            with image_path.open("rb") as handle:
                if handle.read(2) != b"\xff\xd8":
                    return None
                while True:
                    marker_start = handle.read(1)
                    if not marker_start:
                        return None
                    if marker_start != b"\xff":
                        continue
                    marker = handle.read(1)
                    while marker == b"\xff":
                        marker = handle.read(1)
                    if not marker or marker in {b"\xd8", b"\xd9"}:
                        continue
                    segment_length_bytes = handle.read(2)
                    if len(segment_length_bytes) != 2:
                        return None
                    segment_length = struct.unpack(">H", segment_length_bytes)[0]
                    if marker in {
                        b"\xc0",
                        b"\xc1",
                        b"\xc2",
                        b"\xc3",
                        b"\xc5",
                        b"\xc6",
                        b"\xc7",
                        b"\xc9",
                        b"\xca",
                        b"\xcb",
                        b"\xcd",
                        b"\xce",
                        b"\xcf",
                    }:
                        data = handle.read(5)
                        if len(data) != 5:
                            return None
                        height, width = struct.unpack(">HH", data[1:5])
                        return int(width), int(height)
                    handle.seek(max(segment_length - 2, 0), 1)
    except OSError:
        return None
    return None


def normalized_to_pixel_boxes(label_path: Path, width: int, height: int) -> list[PixelBox]:
    boxes: list[PixelBox] = []
    for box in read_normalized_boxes(label_path):
        box_width = float(box["w"]) * width
        box_height = float(box["h"]) * height
        cx = float(box["cx"]) * width
        cy = float(box["cy"]) * height
        boxes.append(
            PixelBox(
                class_id=int(box["class_id"]),
                x1=cx - box_width / 2.0,
                y1=cy - box_height / 2.0,
                x2=cx + box_width / 2.0,
                y2=cy + box_height / 2.0,
                confidence=float(box["conf"]) if "conf" in box else None,
            )
        )
    return boxes


def size_bin_name(sqrt_area: float) -> str:
    for name, lower, upper in SIZE_BINS:
        if lower <= sqrt_area <= upper if upper == 12.0 else lower < sqrt_area <= upper:
            return name
    return SIZE_BINS[-1][0]


def empty_bin_counts() -> dict[str, int]:
    return {name: 0 for name, _lower, _upper in SIZE_BINS}


def collect_label_stats(dataset_root: Path, split: str) -> dict[str, object]:
    image_dir = dataset_root / "images" / split
    label_dir = dataset_root / "labels" / split
    images = image_paths(image_dir)
    bins = empty_bin_counts()
    annotations = 0
    empty_labels = 0
    missing_labels = 0
    sqrt_area_values: list[float] = []

    for image_path in images:
        label_path = label_dir / f"{image_path.stem}.txt"
        if not label_path.exists():
            missing_labels += 1
            empty_labels += 1
            continue
        width, height = image_size(image_path)
        boxes = normalized_to_pixel_boxes(label_path, width, height)
        if not boxes:
            empty_labels += 1
            continue
        for box in boxes:
            sqrt_area = box.sqrt_area
            sqrt_area_values.append(sqrt_area)
            bins[size_bin_name(sqrt_area)] += 1
            annotations += 1

    return {
        "dataset_root": str(dataset_root),
        "split": split,
        "images": len(images),
        "annotations": annotations,
        "empty_label_count": empty_labels,
        "missing_label_count": missing_labels,
        "sqrt_area_bins": bins,
        "sqrt_area_min": min(sqrt_area_values) if sqrt_area_values else None,
        "sqrt_area_median": float(np.median(sqrt_area_values)) if sqrt_area_values else None,
        "sqrt_area_max": max(sqrt_area_values) if sqrt_area_values else None,
    }


def box_iou(a: PixelBox, b: PixelBox) -> float:
    ix1 = max(a.x1, b.x1)
    iy1 = max(a.y1, b.y1)
    ix2 = min(a.x2, b.x2)
    iy2 = min(a.y2, b.y2)
    intersection = max(ix2 - ix1, 0.0) * max(iy2 - iy1, 0.0)
    union = a.area + b.area - intersection
    return intersection / union if union > 0 else 0.0


def score_prediction_labels(
    dataset_root: Path,
    predictions_root: Path,
    split: str,
    *,
    iou_threshold: float = 0.35,
    fps: float = 30.0,
) -> dict[str, object]:
    image_dir = dataset_root / "images" / split
    gt_label_dir = dataset_root / "labels" / split
    prediction_label_dir = predictions_root / "labels" / split
    images = image_paths(image_dir)
    gt_by_bin = empty_bin_counts()
    matched_by_bin = empty_bin_counts()
    false_positives = 0
    empty_frames = 0
    empty_frames_with_prediction = 0
    missed_gt_frames = 0

    for image_path in images:
        width, height = image_size(image_path)
        gt_boxes = normalized_to_pixel_boxes(gt_label_dir / f"{image_path.stem}.txt", width, height)
        pred_boxes = normalized_to_pixel_boxes(
            prediction_label_dir / f"{image_path.stem}.txt",
            width,
            height,
        )
        pred_order = sorted(
            range(len(pred_boxes)),
            key=lambda index: pred_boxes[index].confidence or 0.0,
            reverse=True,
        )
        matched_gt: set[int] = set()
        matched_pred: set[int] = set()

        if not gt_boxes:
            empty_frames += 1
            if pred_boxes:
                empty_frames_with_prediction += 1

        for gt_index, gt_box in enumerate(gt_boxes):
            gt_by_bin[size_bin_name(gt_box.sqrt_area)] += 1
            best_pred_index: int | None = None
            best_iou = 0.0
            for pred_index in pred_order:
                if pred_index in matched_pred:
                    continue
                iou = box_iou(gt_box, pred_boxes[pred_index])
                if iou > best_iou:
                    best_iou = iou
                    best_pred_index = pred_index
            if best_pred_index is not None and best_iou >= iou_threshold:
                matched_gt.add(gt_index)
                matched_pred.add(best_pred_index)
                matched_by_bin[size_bin_name(gt_box.sqrt_area)] += 1

        false_positives += len(pred_boxes) - len(matched_pred)
        if gt_boxes and not matched_gt:
            missed_gt_frames += 1

    minutes = (len(images) / fps / 60.0) if fps > 0 else 0.0
    recall_by_bin = {
        name: (matched_by_bin[name] / gt_by_bin[name] if gt_by_bin[name] else None)
        for name in gt_by_bin
    }
    return {
        "dataset_root": str(dataset_root),
        "predictions_root": str(predictions_root),
        "split": split,
        "images": len(images),
        "ground_truth_by_bin": gt_by_bin,
        "matched_by_bin": matched_by_bin,
        "recall_by_size_bin": recall_by_bin,
        "small_ball_recall_<=20px": _combined_recall(gt_by_bin, matched_by_bin, ("<=12px", "12-20px")),
        "false_positives": false_positives,
        "false_positives_per_minute": false_positives / minutes if minutes > 0 else None,
        "empty_label_count": empty_frames,
        "empty_frames_with_prediction": empty_frames_with_prediction,
        "missed_gt_frames": missed_gt_frames,
    }


def _combined_recall(
    gt_by_bin: dict[str, int],
    matched_by_bin: dict[str, int],
    names: Iterable[str],
) -> float | None:
    gt_total = sum(gt_by_bin[name] for name in names)
    matched_total = sum(matched_by_bin[name] for name in names)
    return matched_total / gt_total if gt_total else None


def bucket_ranges(total: int, bucket_count: int) -> list[tuple[int, int]]:
    base = total // bucket_count
    remainder = total % bucket_count
    ranges: list[tuple[int, int]] = []
    start = 0
    for bucket_index in range(bucket_count):
        size = base + (1 if bucket_index < remainder else 0)
        end = start + size
        ranges.append((start, end))
        start = end
    return ranges


def copy_dataset_pair(image_path: Path, label_path: Path, output_root: Path, split: str) -> None:
    image_output_dir = output_root / "images" / split
    label_output_dir = output_root / "labels" / split
    image_output_dir.mkdir(parents=True, exist_ok=True)
    label_output_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(image_path, image_output_dir / image_path.name)
    if label_path.exists():
        shutil.copy2(label_path, label_output_dir / label_path.name)
    else:
        (label_output_dir / f"{image_path.stem}.txt").write_text("", encoding="utf-8")


def write_data_yaml(output_root: Path) -> None:
    content = "\n".join(
        [
            f"path: {output_root.as_posix()}",
            "train: images/train",
            "val: images/val",
            "",
            "nc: 1",
            "names:",
            "  0: soccer-ball",
            "",
        ]
    )
    (output_root / "data.yaml").write_text(content, encoding="utf-8")


def create_heldout_validation_split(
    source_root: Path,
    output_root: Path,
    *,
    source_split: str = "train",
    bucket_count: int = 10,
    val_buckets: set[int] | None = None,
) -> dict[str, object]:
    val_buckets = val_buckets or {8, 9}
    if any(bucket < 0 or bucket >= bucket_count for bucket in val_buckets):
        raise ValueError("Validation bucket indexes must be within bucket_count.")
    ensure_empty_output_root(output_root)

    image_dir = source_root / "images" / source_split
    label_dir = source_root / "labels" / source_split
    images = image_paths(image_dir)
    ranges = bucket_ranges(len(images), bucket_count)
    train_count = 0
    val_count = 0
    for bucket_index, (start, end) in enumerate(ranges):
        target_split = "val" if bucket_index in val_buckets else "train"
        for image_path in images[start:end]:
            copy_dataset_pair(image_path, label_dir / f"{image_path.stem}.txt", output_root, target_split)
            if target_split == "val":
                val_count += 1
            else:
                train_count += 1

    write_data_yaml(output_root)
    summary = {
        "source_root": str(source_root),
        "source_split": source_split,
        "output_root": str(output_root),
        "bucket_count": bucket_count,
        "val_buckets": sorted(val_buckets),
        "bucket_ranges": ranges,
        "train_images": train_count,
        "val_images": val_count,
    }
    (output_root / "split_summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def frame_identity(path: Path) -> FrameIdentity:
    match = FRAME_RE.search(path.stem)
    if not match:
        return FrameIdentity(path.parent.as_posix(), None, None)
    prefix = match.group("prefix").strip("_- ")
    prefix = re.sub(r"(^\d+[_-]+|[_-]+\d+$)", "", prefix).strip("_- ")
    return FrameIdentity(
        sequence_key=prefix or path.parent.as_posix(),
        timestamp_ms=int(match.group("timestamp")),
        frame_number=int(match.group("frame")) if match.group("frame") else None,
    )


def frames_are_close(
    current: FrameIdentity,
    previous: FrameIdentity,
    *,
    max_timestamp_gap_ms: int,
    max_frame_gap: int,
) -> bool:
    if current.sequence_key != previous.sequence_key:
        return False
    if current.timestamp_ms is not None and previous.timestamp_ms is not None:
        if current.timestamp_ms - previous.timestamp_ms > max_timestamp_gap_ms:
            return False
    if current.frame_number is not None and previous.frame_number is not None:
        if current.frame_number - previous.frame_number > max_frame_gap:
            return False
    return True


def gray_frame(image_path: Path) -> np.ndarray:
    image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
    if image is None:
        raise ValueError(f"Unable to read image: {image_path}")
    return cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)


def compose_temporal_image(old_path: Path, previous_path: Path, current_path: Path) -> np.ndarray:
    old_gray = gray_frame(old_path)
    previous_gray = gray_frame(previous_path)
    current_gray = gray_frame(current_path)
    return compose_temporal_arrays(old_gray, previous_gray, current_gray)


def compose_temporal_arrays(
    old_gray: np.ndarray,
    previous_gray: np.ndarray,
    current_gray: np.ndarray,
) -> np.ndarray:
    if old_gray.shape != current_gray.shape:
        old_gray = cv2.resize(old_gray, (current_gray.shape[1], current_gray.shape[0]))
    if previous_gray.shape != current_gray.shape:
        previous_gray = cv2.resize(previous_gray, (current_gray.shape[1], current_gray.shape[0]))
    # OpenCV writes BGR. Ultralytics reads BGR and converts to RGB, so this yields
    # model channels [gray_t-2, gray_t-1, gray_t].
    return cv2.merge((current_gray, previous_gray, old_gray))


def temporal_sources_for_index(
    images: list[Path],
    index: int,
    *,
    max_timestamp_gap_ms: int,
    max_frame_gap: int,
) -> tuple[Path, Path, Path]:
    current = images[index]
    current_identity = frame_identity(current)
    history: list[Path] = []
    for candidate in reversed(images[:index]):
        if frames_are_close(
            current_identity,
            frame_identity(candidate),
            max_timestamp_gap_ms=max_timestamp_gap_ms,
            max_frame_gap=max_frame_gap,
        ):
            history.append(candidate)
            if len(history) == 2:
                break
    if len(history) < 2:
        history.extend([current] * (2 - len(history)))
    return history[1], history[0], current


def build_temporal_gray_dataset(
    source_root: Path,
    output_root: Path,
    *,
    splits: Iterable[str] = ("train", "val"),
    max_timestamp_gap_ms: int = 1000,
    max_frame_gap: int = 60,
    resume: bool = False,
) -> dict[str, object]:
    if resume:
        output_root.mkdir(parents=True, exist_ok=True)
    else:
        ensure_empty_output_root(output_root)
    counts: dict[str, int] = {}
    duplicated_history = 0

    for split in splits:
        image_dir = source_root / "images" / split
        label_dir = source_root / "labels" / split
        images = image_paths(image_dir)
        gray_cache: dict[Path, np.ndarray] = {}
        counts[split] = 0
        for index, image_path in enumerate(images):
            old_path, previous_path, current_path = temporal_sources_for_index(
                images,
                index,
                max_timestamp_gap_ms=max_timestamp_gap_ms,
                max_frame_gap=max_frame_gap,
            )
            duplicated_history += int(old_path == current_path) + int(previous_path == current_path)
            output_image_dir = output_root / "images" / split
            output_label_dir = output_root / "labels" / split
            output_image_dir.mkdir(parents=True, exist_ok=True)
            output_label_dir.mkdir(parents=True, exist_ok=True)
            output_image_path = output_image_dir / image_path.name
            output_label_path = output_label_dir / f"{image_path.stem}.txt"
            if resume and output_image_path.exists() and output_label_path.exists():
                counts[split] += 1
                continue
            output_image = compose_temporal_arrays(
                _cached_gray_frame(old_path, gray_cache),
                _cached_gray_frame(previous_path, gray_cache),
                _cached_gray_frame(current_path, gray_cache),
            )
            for cached_path in list(gray_cache):
                if cached_path not in {old_path, previous_path, current_path}:
                    gray_cache.pop(cached_path, None)
            if not cv2.imwrite(str(output_image_path), output_image):
                raise ValueError(f"Unable to write temporal image for {image_path}")
            source_label = label_dir / f"{image_path.stem}.txt"
            if source_label.exists():
                shutil.copy2(source_label, output_label_path)
            else:
                output_label_path.write_text("", encoding="utf-8")
            counts[split] += 1

    write_data_yaml(output_root)
    summary = {
        "source_root": str(source_root),
        "output_root": str(output_root),
        "splits": counts,
        "input_temporal_mode": "temporal_gray_3",
        "channel_order": ["gray_t-2", "gray_t-1", "gray_t"],
        "duplicated_history_channels": duplicated_history,
        "max_timestamp_gap_ms": max_timestamp_gap_ms,
        "max_frame_gap": max_frame_gap,
    }
    (output_root / "temporal_summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def _cached_gray_frame(image_path: Path, cache: dict[Path, np.ndarray]) -> np.ndarray:
    if image_path not in cache:
        cache[image_path] = gray_frame(image_path)
    return cache[image_path]


def parse_bucket_set(raw: str) -> set[int]:
    return {int(part.strip()) for part in raw.split(",") if part.strip()}


def emit_json(payload: dict[str, object], output: str | None) -> None:
    text = json.dumps(payload, indent=2) + "\n"
    if output:
        Path(output).write_text(text, encoding="utf-8")
    print(text, end="")


def main() -> None:
    parser = argparse.ArgumentParser(description="Ballr detector evaluation and temporal dataset tooling")
    subparsers = parser.add_subparsers(dest="command", required=True)

    stats_parser = subparsers.add_parser("stats", help="Report label counts and sqrt-area bins")
    stats_parser.add_argument("--root", default=str(training_path("dataset_prepared_v5_all")))
    stats_parser.add_argument("--split", default="train")
    stats_parser.add_argument("--output")

    score_parser = subparsers.add_parser("score-labels", help="Score YOLO prediction labels against ground truth")
    score_parser.add_argument("--root", required=True)
    score_parser.add_argument("--predictions-root", required=True)
    score_parser.add_argument("--split", default="val")
    score_parser.add_argument("--iou", type=float, default=0.35)
    score_parser.add_argument("--fps", type=float, default=30.0)
    score_parser.add_argument("--output")

    split_parser = subparsers.add_parser("split-heldout", help="Create a deterministic train/val split from footage buckets")
    split_parser.add_argument("--source-root", default=str(training_path("dataset_prepared_v5_all")))
    split_parser.add_argument("--output-root", default=str(training_path("dataset_prepared_v5_eval")))
    split_parser.add_argument("--source-split", default="train")
    split_parser.add_argument("--bucket-count", type=int, default=10)
    split_parser.add_argument("--val-buckets", type=parse_bucket_set, default={8, 9})
    split_parser.add_argument("--output")

    temporal_parser = subparsers.add_parser("build-temporal", help="Build RGB files carrying [gray_t-2, gray_t-1, gray_t]")
    temporal_parser.add_argument("--source-root", default=str(training_path("dataset_prepared_v5_eval")))
    temporal_parser.add_argument("--output-root", default=str(training_path("dataset_prepared_v6_temporal_768")))
    temporal_parser.add_argument("--splits", default="train,val")
    temporal_parser.add_argument("--max-timestamp-gap-ms", type=int, default=1000)
    temporal_parser.add_argument("--max-frame-gap", type=int, default=60)
    temporal_parser.add_argument("--resume", action="store_true", help="Continue a partial temporal dataset build")
    temporal_parser.add_argument("--output")

    args = parser.parse_args()
    if args.command == "stats":
        emit_json(collect_label_stats(Path(args.root), args.split), args.output)
    elif args.command == "score-labels":
        emit_json(
            score_prediction_labels(
                Path(args.root),
                Path(args.predictions_root),
                args.split,
                iou_threshold=args.iou,
                fps=args.fps,
            ),
            args.output,
        )
    elif args.command == "split-heldout":
        emit_json(
            create_heldout_validation_split(
                Path(args.source_root),
                Path(args.output_root),
                source_split=args.source_split,
                bucket_count=args.bucket_count,
                val_buckets=args.val_buckets,
            ),
            args.output,
        )
    elif args.command == "build-temporal":
        emit_json(
            build_temporal_gray_dataset(
                Path(args.source_root),
                Path(args.output_root),
                splits=[split.strip() for split in args.splits.split(",") if split.strip()],
                max_timestamp_gap_ms=args.max_timestamp_gap_ms,
                max_frame_gap=args.max_frame_gap,
                resume=args.resume,
            ),
            args.output,
        )


if __name__ == "__main__":
    main()
