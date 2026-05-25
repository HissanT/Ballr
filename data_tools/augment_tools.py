from __future__ import annotations

import argparse
import json
import random
import shutil
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np

from common.ballr_utils import training_path
from data_tools.dataset_tools import ensure_empty_output_root, image_paths, read_normalized_boxes
from data_tools.eval_tools import image_size


@dataclass(frozen=True)
class AugmentConfig:
    variants_per_image: int = 1
    seed: int = 42
    blur_probability: float = 0.25
    motion_blur_probability: float = 0.25
    zoom_out_probability: float = 0.35
    noise_probability: float = 0.20
    jpeg_probability: float = 0.25
    min_zoom_scale: float = 0.78
    max_zoom_scale: float = 0.94


def clamp01(value: float) -> float:
    return min(max(value, 0.0), 1.0)


def encode_label(boxes: list[dict[str, float | int]]) -> str:
    lines: list[str] = []
    for box in boxes:
        line = (
            f"{int(box['class_id'])} "
            f"{float(box['cx']):.6f} "
            f"{float(box['cy']):.6f} "
            f"{float(box['w']):.6f} "
            f"{float(box['h']):.6f}"
        )
        if "conf" in box:
            line += f" {float(box['conf']):.6f}"
        lines.append(line)
    return "\n".join(lines) + ("\n" if lines else "")


def transformed_zoom_out_boxes(
    boxes: list[dict[str, float | int]],
    *,
    scale: float,
    offset_x: int,
    offset_y: int,
    width: int,
    height: int,
) -> list[dict[str, float | int]]:
    transformed: list[dict[str, float | int]] = []
    for box in boxes:
        new_box = dict(box)
        new_box["cx"] = clamp01((float(box["cx"]) * width * scale + offset_x) / width)
        new_box["cy"] = clamp01((float(box["cy"]) * height * scale + offset_y) / height)
        new_box["w"] = clamp01(float(box["w"]) * scale)
        new_box["h"] = clamp01(float(box["h"]) * scale)
        if float(new_box["w"]) > 0 and float(new_box["h"]) > 0:
            transformed.append(new_box)
    return transformed


def apply_zoom_out(
    image: np.ndarray,
    boxes: list[dict[str, float | int]],
    rng: random.Random,
    config: AugmentConfig,
) -> tuple[np.ndarray, list[dict[str, float | int]], dict[str, object]]:
    height, width = image.shape[:2]
    scale = rng.uniform(config.min_zoom_scale, config.max_zoom_scale)
    scaled_width = max(1, int(round(width * scale)))
    scaled_height = max(1, int(round(height * scale)))
    offset_x = rng.randint(0, width - scaled_width)
    offset_y = rng.randint(0, height - scaled_height)

    background = cv2.GaussianBlur(image, (0, 0), sigmaX=5.0, sigmaY=5.0)
    background = cv2.resize(
        cv2.resize(background, (max(1, width // 3), max(1, height // 3))),
        (width, height),
        interpolation=cv2.INTER_LINEAR,
    )
    scaled = cv2.resize(image, (scaled_width, scaled_height), interpolation=cv2.INTER_AREA)
    output = background.copy()
    output[offset_y : offset_y + scaled_height, offset_x : offset_x + scaled_width] = scaled
    return (
        output,
        transformed_zoom_out_boxes(
            boxes,
            scale=scale,
            offset_x=offset_x,
            offset_y=offset_y,
            width=width,
            height=height,
        ),
        {"type": "zoom_out", "scale": scale, "offset_x": offset_x, "offset_y": offset_y},
    )


def motion_blur_kernel(size: int, angle_degrees: float) -> np.ndarray:
    kernel = np.zeros((size, size), dtype=np.float32)
    kernel[size // 2, :] = 1.0
    rotation = cv2.getRotationMatrix2D((size / 2 - 0.5, size / 2 - 0.5), angle_degrees, 1.0)
    kernel = cv2.warpAffine(kernel, rotation, (size, size))
    total = kernel.sum()
    return kernel / total if total > 0 else kernel


def apply_motion_blur(image: np.ndarray, rng: random.Random) -> tuple[np.ndarray, dict[str, object]]:
    size = rng.choice((3, 5, 7))
    angle = rng.uniform(0.0, 180.0)
    kernel = motion_blur_kernel(size, angle)
    return cv2.filter2D(image, -1, kernel), {"type": "motion_blur", "size": size, "angle": angle}


def apply_defocus_blur(image: np.ndarray, rng: random.Random) -> tuple[np.ndarray, dict[str, object]]:
    kernel_size = rng.choice((3, 5))
    sigma = rng.uniform(0.4, 1.1)
    return (
        cv2.GaussianBlur(image, (kernel_size, kernel_size), sigmaX=sigma, sigmaY=sigma),
        {"type": "defocus_blur", "size": kernel_size, "sigma": sigma},
    )


def apply_noise(image: np.ndarray, rng: random.Random) -> tuple[np.ndarray, dict[str, object]]:
    sigma = rng.uniform(2.0, 6.0)
    noise = np.random.default_rng(rng.randint(0, 2**32 - 1)).normal(0.0, sigma, image.shape)
    output = np.clip(image.astype(np.float32) + noise, 0, 255).astype(np.uint8)
    return output, {"type": "noise", "sigma": sigma}


def apply_jpeg(image: np.ndarray, rng: random.Random) -> tuple[np.ndarray, dict[str, object]]:
    quality = rng.randint(68, 88)
    ok, encoded = cv2.imencode(".jpg", image, [int(cv2.IMWRITE_JPEG_QUALITY), quality])
    if not ok:
        return image, {"type": "jpeg", "quality": quality, "skipped": True}
    decoded = cv2.imdecode(encoded, cv2.IMREAD_COLOR)
    return decoded if decoded is not None else image, {"type": "jpeg", "quality": quality}


def augment_image(
    image: np.ndarray,
    boxes: list[dict[str, float | int]],
    rng: random.Random,
    config: AugmentConfig,
) -> tuple[np.ndarray, list[dict[str, float | int]], list[dict[str, object]]]:
    output = image.copy()
    output_boxes = [dict(box) for box in boxes]
    operations: list[dict[str, object]] = []

    if rng.random() < config.zoom_out_probability:
        output, output_boxes, operation = apply_zoom_out(output, output_boxes, rng, config)
        operations.append(operation)
    if rng.random() < config.motion_blur_probability:
        output, operation = apply_motion_blur(output, rng)
        operations.append(operation)
    if rng.random() < config.blur_probability:
        output, operation = apply_defocus_blur(output, rng)
        operations.append(operation)
    if rng.random() < config.noise_probability:
        output, operation = apply_noise(output, rng)
        operations.append(operation)
    if rng.random() < config.jpeg_probability:
        output, operation = apply_jpeg(output, rng)
        operations.append(operation)

    if not operations:
        output, operation = apply_defocus_blur(output, rng)
        operations.append(operation)

    return output, output_boxes, operations


def copy_split(source_root: Path, output_root: Path, split: str) -> int:
    image_dir = source_root / "images" / split
    label_dir = source_root / "labels" / split
    output_image_dir = output_root / "images" / split
    output_label_dir = output_root / "labels" / split
    output_image_dir.mkdir(parents=True, exist_ok=True)
    output_label_dir.mkdir(parents=True, exist_ok=True)

    count = 0
    for image_path in image_paths(image_dir):
        label_path = label_dir / f"{image_path.stem}.txt"
        shutil.copy2(image_path, output_image_dir / image_path.name)
        if label_path.exists():
            shutil.copy2(label_path, output_label_dir / label_path.name)
        else:
            (output_label_dir / f"{image_path.stem}.txt").write_text("", encoding="utf-8")
        count += 1
    return count


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


def build_augmented_train_dataset(
    source_root: Path,
    output_root: Path,
    config: AugmentConfig,
    *,
    resume: bool = False,
) -> dict[str, object]:
    if resume:
        output_root.mkdir(parents=True, exist_ok=True)
    else:
        ensure_empty_output_root(output_root)

    original_train = copy_split(source_root, output_root, "train") if not resume else 0
    val_count = copy_split(source_root, output_root, "val") if not resume else 0
    train_image_dir = source_root / "images" / "train"
    train_label_dir = source_root / "labels" / "train"
    output_image_dir = output_root / "images" / "train"
    output_label_dir = output_root / "labels" / "train"
    output_image_dir.mkdir(parents=True, exist_ok=True)
    output_label_dir.mkdir(parents=True, exist_ok=True)

    rng = random.Random(config.seed)
    augmented_count = 0
    operation_counts: dict[str, int] = {}
    manifest_path = output_root / "augmentation_manifest.jsonl"
    manifest_mode = "a" if resume and manifest_path.exists() else "w"
    with manifest_path.open(manifest_mode, encoding="utf-8") as manifest:
        for image_index, image_path in enumerate(image_paths(train_image_dir)):
            label_path = train_label_dir / f"{image_path.stem}.txt"
            boxes = read_normalized_boxes(label_path)
            for variant_index in range(config.variants_per_image):
                output_name = f"{image_path.stem}_aug{variant_index + 1}{image_path.suffix.lower()}"
                output_image_path = output_image_dir / output_name
                output_label_path = output_label_dir / f"{Path(output_name).stem}.txt"
                if resume and output_image_path.exists() and output_label_path.exists():
                    augmented_count += 1
                    continue
                image = cv2.imread(str(image_path), cv2.IMREAD_COLOR)
                if image is None:
                    raise ValueError(f"Unable to read image: {image_path}")
                _width, _height = image_size(image_path)
                augmented, augmented_boxes, operations = augment_image(image, boxes, rng, config)
                if not cv2.imwrite(str(output_image_path), augmented):
                    raise ValueError(f"Unable to write augmented image: {output_image_path}")
                output_label_path.write_text(encode_label(augmented_boxes), encoding="utf-8")
                for operation in operations:
                    operation_counts[str(operation["type"])] = operation_counts.get(str(operation["type"]), 0) + 1
                manifest.write(
                    json.dumps(
                        {
                            "source": str(image_path.relative_to(source_root)),
                            "output": str(output_image_path.relative_to(output_root)),
                            "label": str(output_label_path.relative_to(output_root)),
                            "image_index": image_index,
                            "variant_index": variant_index,
                            "operations": operations,
                        },
                        separators=(",", ":"),
                    )
                    + "\n"
                )
                augmented_count += 1

    write_data_yaml(output_root)
    total_train = len(image_paths(output_root / "images" / "train"))
    if resume:
        val_count = len(image_paths(output_root / "images" / "val"))
        original_train = total_train - augmented_count
    summary = {
        "source_root": str(source_root),
        "output_root": str(output_root),
        "original_train_images": original_train,
        "augmented_train_images": augmented_count,
        "total_train_images": total_train,
        "val_images": val_count,
        "validation_augmented": False,
        "config": config.__dict__,
        "operation_counts": operation_counts,
    }
    (output_root / "augmentation_summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description="Build mild Ballr-specific offline training augmentations")
    parser.add_argument("--source-root", default=str(training_path("dataset_prepared_v5_eval")))
    parser.add_argument("--output-root", default=str(training_path("dataset_prepared_v5_eval_aug")))
    parser.add_argument("--variants-per-image", type=int, default=1)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--output")
    args = parser.parse_args()

    summary = build_augmented_train_dataset(
        Path(args.source_root),
        Path(args.output_root),
        AugmentConfig(variants_per_image=args.variants_per_image, seed=args.seed),
        resume=args.resume,
    )
    text = json.dumps(summary, indent=2) + "\n"
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
    print(text, end="")


if __name__ == "__main__":
    main()
