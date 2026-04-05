import argparse
import torch
from ultralytics import YOLO


def detect_device(requested: str) -> str:
    """Return the best available device, respecting an explicit --device override."""
    if requested != "auto":
        return requested
    if torch.cuda.is_available():
        name = torch.cuda.get_device_name(0)
        vram = torch.cuda.get_device_properties(0).total_memory / 1024 ** 3
        print(f"GPU detected: {name} ({vram:.1f} GB VRAM) — using CUDA")
        return "0"
    print("No CUDA GPU found — falling back to CPU (training will be slow)")
    return "cpu"


def main() -> None:
    parser = argparse.ArgumentParser(description="Fine-tune YOLOv8n for soccer ball detection")
    parser.add_argument(
        "--data",
        default="data.yaml",
        help="Dataset yaml. For session captures, build one with dataset_tools.py build-splits.",
    )
    parser.add_argument("--weights", default="yolov8n.pt")
    parser.add_argument("--epochs",  type=int,   default=80)
    parser.add_argument("--batch",   type=int,   default=16)
    parser.add_argument("--imgsz",   type=int,   default=640)
    parser.add_argument("--name",    default="ballr_v1")
    parser.add_argument("--device",  default="auto",
                        help="Device to train on: 'auto' (default), '0' (GPU), 'cpu'")
    args = parser.parse_args()

    device = detect_device(args.device)

    # Use RAM cache when on GPU to eliminate disk I/O bottleneck during training
    cache = "ram" if device != "cpu" else False

    model = YOLO(args.weights)

    model.train(
        data=args.data,
        epochs=args.epochs,
        batch=args.batch,
        imgsz=args.imgsz,
        name=args.name,
        project="runs/train",
        device=device,

        # Optimizer
        optimizer="AdamW",
        lr0=0.001,
        lrf=0.01,           # final lr = lr0 * lrf → 1e-5
        warmup_epochs=3,
        weight_decay=0.0005,
        patience=20,        # early stop after 20 epochs with no val improvement

        # Augmentation — tuned for mixed lighting (outdoor / indoor / night)
        hsv_h=0.015,        # subtle hue shift
        hsv_s=0.5,          # saturation variation
        hsv_v=0.6,          # brightness variation ±60% — most important for this project
        degrees=10.0,
        translate=0.1,
        scale=0.5,          # ball at various distances
        perspective=0.0005, # slight perspective warp — simulates different camera angles
        fliplr=0.5,
        flipud=0.0,
        mosaic=1.0,
        close_mosaic=10,    # disable mosaic last 10 epochs to stabilise
        mixup=0.1,
        copy_paste=0.1,     # copies ball instances across images — helps small-object detection
        erasing=0.2,        # random erasing simulates partial occlusion
        auto_augment="randaugment",  # additional policy-based augmentation on top of manual settings

        rect=False,         # must be False for mosaic augmentation to work
        amp=True,           # mixed precision — faster and lower VRAM on CUDA
        cache=cache,
        workers=4,
        verbose=True,
        exist_ok=False,     # fail loudly if run name exists — forces versioning
    )

    print(f"\nTraining complete.")
    print(f"Best weights: runs/train/{args.name}/weights/best.pt")
    print(f"Update MODEL_PATH in ball_tracker.py to use the fine-tuned model.")


if __name__ == "__main__":
    main()
