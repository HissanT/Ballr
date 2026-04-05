import argparse

import torch
from ultralytics import YOLO


PRESETS = {
    "custom": {},
    "v4-tune": {
        "weights": "yolo11n.pt",
        "data": "dataset_prepared_v4_tune/data.yaml",
        "epochs": 120,
        "batch": 8,
        "imgsz": 832,
        "name": "ballr_v4_tune",
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
        "workers": 4,
    },
    "v4-final": {
        "weights": "runs/train/ballr_v4_tune/weights/best.pt",
        "data": "dataset_prepared_v4_all/data.yaml",
        "epochs": 20,
        "batch": 8,
        "imgsz": 832,
        "name": "ballr_v4",
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
        "workers": 4,
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


def parser_defaults(preset_name: str) -> dict:
    defaults = {
        "data": "data.yaml",
        "weights": "yolo11n.pt",
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
        help="Training preset. Use v4-tune then v4-final for the promoted workflow.",
    )
    bootstrap_args, remaining_argv = bootstrap.parse_known_args()
    defaults = parser_defaults(bootstrap_args.preset)

    parser = argparse.ArgumentParser(
        description="Fine-tune YOLO for soccer ball detection",
        parents=[bootstrap],
    )
    parser.add_argument(
        "--data",
        default=defaults["data"],
        help="Dataset yaml. For the promoted workflow, use dataset_tools.py prepare-v4 first.",
    )
    parser.add_argument("--weights", default=defaults["weights"])
    parser.add_argument("--epochs", type=int, default=defaults["epochs"])
    parser.add_argument("--batch", type=int, default=defaults["batch"])
    parser.add_argument("--imgsz", type=int, default=defaults["imgsz"])
    parser.add_argument("--name", default=defaults["name"])
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
        "project": "runs/train",
        "device": device,
        "cache": cache,
        "amp": True,
        "workers": preset.get("workers", 4),
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
    model.train(**train_kwargs)

    print("\nTraining complete.")
    print(f"Best weights: runs/train/{args.name}/weights/best.pt")
    print("Promoted production model path: runs/train/ballr_v4/weights/best.pt")


if __name__ == "__main__":
    main()
