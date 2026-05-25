from __future__ import annotations

import argparse
import json
import platform
import shutil
from pathlib import Path

from common.ballr_utils import model_path
from ball_tracker_tracking import (
    CANDIDATE_CONF_THRESHOLD,
    IOU_THRESHOLD,
    MODEL_PATH,
    SPORTS_BALL_CLASS_ID,
)

DEFAULT_IMG_SIZE = 768
DEFAULT_EXPORT_DIR = model_path("coreml")
DEFAULT_CLASS_LABELS = {SPORTS_BALL_CLASS_ID: "ball"}
SUPPORTED_EXPORT_PLATFORMS = {"Darwin", "Linux"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export the Ballr detector weights as a CoreML .mlpackage",
    )
    parser.add_argument(
        "--weights",
        default=MODEL_PATH,
        help="Path to the YOLO detector checkpoint to export.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_EXPORT_DIR),
        help="Directory where the exported .mlpackage and metadata sidecar will be written.",
    )
    parser.add_argument(
        "--name",
        help="Optional exported package name. Defaults to the checkpoint stem.",
    )
    parser.add_argument(
        "--imgsz",
        type=int,
        default=DEFAULT_IMG_SIZE,
        help="Square inference size baked into the exported CoreML package.",
    )
    parser.add_argument(
        "--device",
        default="cpu",
        help="Export device passed to Ultralytics. Use cpu unless you know you need otherwise.",
    )
    parser.add_argument(
        "--no-nms",
        action="store_true",
        help="Disable built-in NMS in the exported package.",
    )
    parser.add_argument(
        "--int8",
        action="store_true",
        help="Request INT8 quantization during export when supported.",
    )
    parser.add_argument(
        "--input-temporal-mode",
        choices=("single_rgb", "temporal_gray_3"),
        default="single_rgb",
        help="Meaning of the 3 input channels. Keep single_rgb for production v5.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Replace an existing exported package with the same destination name.",
    )
    return parser.parse_args()


def require_supported_platform(system_name: str | None = None) -> None:
    active_system = system_name or platform.system()
    if active_system in SUPPORTED_EXPORT_PLATFORMS:
        return
    raise SystemExit(
        "CoreML export is not supported on Windows by Ultralytics/coremltools. "
        "Run this script on macOS or Linux against the same checkpoint."
    )


def build_export_metadata(
    *,
    weights_path: Path,
    package_path: Path,
    imgsz: int,
    nms_enabled: bool,
    int8_enabled: bool,
    input_temporal_mode: str = "single_rgb",
) -> dict[str, object]:
    return {
        "format": "coreml",
        "task": "object_detection",
        "weights_path": str(weights_path),
        "package_path": str(package_path),
        "input": {
            "type": "image",
            "color_layout": "RGB",
            "temporal_mode": input_temporal_mode,
            "shape": [1, 3, imgsz, imgsz],
            "preprocess": "letterbox_preserve_aspect_ratio",
        },
        "output": {
            "includes_nms": nms_enabled,
            "class_labels": DEFAULT_CLASS_LABELS,
            "coordinate_space": "model_canvas",
        },
        "ballr_runtime_defaults": {
            "confidence_threshold": CANDIDATE_CONF_THRESHOLD,
            "iou_threshold": IOU_THRESHOLD,
            "ball_class_id": SPORTS_BALL_CLASS_ID,
        },
        "frontend_notes": {
            "vision_crop_and_scale": "scaleFit",
            "pass_capture_orientation": True,
            "mirror_preview_only": True,
            "map_boxes_back_to_preview": True,
        },
        "export": {
            "imgsz": imgsz,
            "int8": int8_enabled,
        },
    }


def remove_path(path: Path) -> None:
    if not path.exists():
        return
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()


def move_exported_package(exported_path: Path, destination_path: Path, overwrite: bool) -> Path:
    source = exported_path.resolve()
    destination = destination_path.resolve()
    if source == destination:
        return destination
    if destination.exists():
        if not overwrite:
            raise SystemExit(
                f"Refusing to overwrite existing export: {destination}. "
                "Re-run with --overwrite to replace it."
            )
        remove_path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(destination))
    return destination


def write_metadata(metadata_path: Path, payload: dict[str, object], overwrite: bool) -> None:
    if metadata_path.exists() and not overwrite:
        raise SystemExit(
            f"Refusing to overwrite existing metadata: {metadata_path}. "
            "Re-run with --overwrite to replace it."
        )
    metadata_path.parent.mkdir(parents=True, exist_ok=True)
    metadata_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    args = parse_args()
    require_supported_platform()

    weights_path = Path(args.weights)
    if not weights_path.exists():
        raise SystemExit(f"Checkpoint not found: {weights_path}")

    export_name = args.name or weights_path.stem
    output_dir = Path(args.output_dir)
    destination_path = output_dir / f"{export_name}.mlpackage"
    metadata_path = output_dir / f"{export_name}.json"

    from ultralytics import YOLO

    model = YOLO(str(weights_path))
    exported_path = model.export(
        format="coreml",
        imgsz=args.imgsz,
        device=args.device,
        nms=not args.no_nms,
        int8=args.int8,
    )
    final_package_path = move_exported_package(
        Path(str(exported_path)),
        destination_path,
        overwrite=args.overwrite,
    )
    metadata = build_export_metadata(
        weights_path=weights_path,
        package_path=final_package_path,
        imgsz=args.imgsz,
        nms_enabled=not args.no_nms,
        int8_enabled=args.int8,
        input_temporal_mode=args.input_temporal_mode,
    )
    write_metadata(metadata_path, metadata, overwrite=args.overwrite)

    print(f"Export complete: {final_package_path}")
    print(f"Metadata written: {metadata_path}")


if __name__ == "__main__":
    main()
