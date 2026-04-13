import argparse
import json
from pathlib import Path

import torch
from ultralytics import YOLO

from common.ballr_utils import model_path, training_path


PRESETS = {
    "custom": {},
    "v4-tune": {
        "weights": str(model_path("yolo11n.pt")),
        "data": str(training_path("dataset_prepared_v4_tune_cleaned", "data.yaml")),
        "epochs": 90,
        "batch": 8,
        "imgsz": 768,
        "name": "ballr_v4_tune_cleaned",
        "optimizer": "AdamW",
        "lr0": 0.0008,
        "lrf": 0.01,
        "warmup_epochs": 3,
        "weight_decay": 0.0005,
        "patience": 25,
        "cos_lr": True,
        "hsv_h": 0.01,
        "hsv_s": 0.40,
        "hsv_v": 0.35,
        "degrees": 6.0,
        "translate": 0.08,
        "scale": 0.35,
        "perspective": 0.0008,
        "fliplr": 0.5,
        "flipud": 0.0,
        "mosaic": 0.35,
        "close_mosaic": 25,
        "mixup": 0.0,
        "copy_paste": 0.0,
        "erasing": 0.10,
        "auto_augment": None,
        "workers": 0,
    },
    "v4-final": {
        "weights": str(model_path("ballr_v4_tune_cleaned.pt")),
        "data": str(training_path("dataset_prepared_v4_all", "data.yaml")),
        "epochs": 15,
        "batch": 8,
        "imgsz": 768,
        "name": "ballr_v4_cleaned_final",
        "optimizer": "AdamW",
        "lr0": 0.0002,
        "lrf": 1.0,
        "warmup_epochs": 1,
        "weight_decay": 0.0005,
        "patience": 0,
        "cos_lr": False,
        "hsv_h": 0.0,
        "hsv_s": 0.0,
        "hsv_v": 0.0,
        "degrees": 0.0,
        "translate": 0.0,
        "scale": 0.0,
        "perspective": 0.0,
        "fliplr": 0.0,
        "flipud": 0.0,
        "mosaic": 0.0,
        "close_mosaic": 0,
        "mixup": 0.0,
        "copy_paste": 0.0,
        "erasing": 0.0,
        "auto_augment": None,
        "workers": 0,
    },
}


def detect_device(requested: str) -> str:
    """Return the best available device, respecting an explicit --device override."""
    if requested != "auto":
        return requested
    if torch.cuda.is_available():
        name = torch.cuda.get_device_name(0)
        vram = torch.cuda.get_device_properties(0).total_memory / 1024 ** 3
        print(f"GPU detected: {name} ({vram:.1f} GB VRAM) - using CUDA")
        return "0"
    print("No CUDA GPU found - falling back to CPU (training will be slow)")
    return "cpu"


def read_dataset_yaml(path: Path) -> dict[str, str]:
    payload: dict[str, str] = {}
    if not path.exists():
        return payload

    for raw_line in path.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        if key in {"path", "train", "val"}:
            payload[key] = value.strip()
    return payload


def warn_about_dataset_state(data_yaml: str) -> None:
    data_yaml_path = Path(data_yaml)
    if not data_yaml_path.exists():
        print(f"WARNING: dataset yaml '{data_yaml_path}' does not exist.")
        return

    dataset_meta = read_dataset_yaml(data_yaml_path)
    train_split = dataset_meta.get("train")
    val_split = dataset_meta.get("val")
    if train_split and val_split and train_split == val_split:
        print(
            "WARNING: this dataset yaml uses the train split for validation. "
            "Metrics will be optimistic and should not drive model selection."
        )

    dataset_root = Path(dataset_meta["path"]) if dataset_meta.get("path") else data_yaml_path.parent
    review_manifest_path = dataset_root / "review" / "manifest.jsonl"
    if not review_manifest_path.exists():
        return

    pending_total = 0
    pending_val = 0
    for line in review_manifest_path.read_text(encoding="utf-8-sig").splitlines():
        if not line.strip():
            continue
        item = json.loads(line)
        if item.get("review_status") != "pending":
            continue
        pending_total += 1
        if item.get("split") == "val":
            pending_val += 1

    if pending_total:
        print(
            f"WARNING: {pending_total} review items remain pending under '{dataset_root.name}'."
        )
    if pending_val:
        print(
            f"WARNING: {pending_val} validation images are still pending review. "
            "Finish reviewing val before trusting tune metrics."
        )


def parser_defaults(preset_name: str) -> dict:
    defaults = {
        "data": "data.yaml",
        "weights": str(model_path("yolo11n.pt")),
        "epochs": 80,
        "batch": 16,
        "imgsz": 640,
        "name": "ballr_custom",
    }
    defaults.update(PRESETS[preset_name])
    return defaults


def main() -> None:
    bootstrap = argparse.ArgumentParser(add_help=False)
    bootstrap.add_argument(
        "--preset",
        choices=sorted(PRESETS),
        default="custom",
        help="Training preset. Use v4-tune on the cleaned tune split, then v4-final for the post-review all-data pass.",
    )
    bootstrap_args, remaining_argv = bootstrap.parse_known_args()
    defaults = parser_defaults(bootstrap_args.preset)

    parser = argparse.ArgumentParser(
        description="Fine-tune YOLO for soccer ball detection",
        parents=[bootstrap],
    )
    parser.set_defaults(preset=bootstrap_args.preset)
    parser.add_argument(
        "--data",
        default=defaults["data"],
        help="Dataset yaml. The default tune preset targets training/dataset_prepared_v4_tune_cleaned/data.yaml.",
    )
    parser.add_argument("--weights", default=defaults["weights"])
    parser.add_argument("--epochs", type=int, default=defaults["epochs"])
    parser.add_argument("--batch", type=int, default=defaults["batch"])
    parser.add_argument("--imgsz", type=int, default=defaults["imgsz"])
    parser.add_argument("--name", default=defaults["name"])
    parser.add_argument(
        "--workers",
        type=int,
        default=defaults.get("workers", 4),
        help="Dataloader workers. Override to 0 when multiprocessing is restricted.",
    )
    parser.add_argument(
        "--device",
        default="auto",
        help="Device to train on: 'auto' (default), '0' (GPU), 'cpu'",
    )
    args = parser.parse_args(remaining_argv)

    device = detect_device(args.device)
    cache = "ram" if device != "cpu" else False
    preset = PRESETS[args.preset]

    model = YOLO(args.weights)
    train_kwargs = {
        "data": args.data,
        "epochs": args.epochs,
        "batch": args.batch,
        "imgsz": args.imgsz,
        "name": args.name,
        "project": str(training_path("runs", "train")),
        "device": device,
        "cache": cache,
        "amp": True,
        "workers": args.workers,
        "verbose": True,
        "exist_ok": False,
        "optimizer": preset.get("optimizer", "AdamW"),
        "lr0": preset.get("lr0", 0.001),
        "lrf": preset.get("lrf", 0.01),
        "warmup_epochs": preset.get("warmup_epochs", 3),
        "weight_decay": preset.get("weight_decay", 0.0005),
        "patience": preset.get("patience", 20),
        "cos_lr": preset.get("cos_lr", False),
        "hsv_h": preset.get("hsv_h", 0.015),
        "hsv_s": preset.get("hsv_s", 0.5),
        "hsv_v": preset.get("hsv_v", 0.6),
        "degrees": preset.get("degrees", 10.0),
        "translate": preset.get("translate", 0.1),
        "scale": preset.get("scale", 0.5),
        "perspective": preset.get("perspective", 0.0005),
        "fliplr": preset.get("fliplr", 0.5),
        "flipud": preset.get("flipud", 0.0),
        "mosaic": preset.get("mosaic", 1.0),
        "close_mosaic": preset.get("close_mosaic", 10),
        "mixup": preset.get("mixup", 0.1),
        "copy_paste": preset.get("copy_paste", 0.1),
        "erasing": preset.get("erasing", 0.2),
        "auto_augment": preset.get("auto_augment", "randaugment"),
        "rect": False,
    }

    print(
        f"Training preset: {args.preset} | weights={args.weights} | data={args.data} "
        f"| imgsz={args.imgsz} | batch={args.batch} | epochs={args.epochs}"
    )
    warn_about_dataset_state(args.data)
    model.train(**train_kwargs)

    print("\nTraining complete.")
    print(f"Best weights: {training_path('runs', 'train', args.name, 'weights', 'best.pt')}")
    print("Review validation results before promoting weights to the production model path.")


if __name__ == "__main__":
    main()
