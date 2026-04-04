import argparse
import os
import random
import time

import cv2
from ultralytics import YOLO

SPORTS_BALL_CLASS_ID = 0
AUTO_LABEL_CLASS_ID = 0


def parse_source(arg: str):
    return int(arg) if arg.isdigit() else arg


def save_sample(frame, boxes, dataset_dir: str, split: str) -> None:
    """Save JPEG + YOLO label file into dataset_dir/images/<split>/ and labels/<split>/."""
    ts = int(time.time() * 1000)
    stem = f"frame_{ts}"
    img_path   = os.path.join(dataset_dir, "images", split, f"{stem}.jpg")
    label_path = os.path.join(dataset_dir, "labels", split, f"{stem}.txt")

    cv2.imwrite(img_path, frame)

    h, w = frame.shape[:2]
    with open(label_path, "w") as f:
        for box in boxes:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            cx = ((x1 + x2) / 2) / w
            cy = ((y1 + y2) / 2) / h
            bw = (x2 - x1) / w
            bh = (y2 - y1) / h
            f.write(f"{AUTO_LABEL_CLASS_ID} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Auto-label frames for fine-tuning")
    parser.add_argument("--source",    default="0",       help="Webcam index or DroidCam URL")
    parser.add_argument("--output",    default="dataset", help="Root dataset directory")
    parser.add_argument("--conf",      type=float, default=0.70, help="Min confidence to save a frame")
    parser.add_argument("--interval",  type=int,   default=15,   help="Run inference every N frames")
    parser.add_argument("--val-split", type=float, default=0.2,  help="Fraction routed to val/")
    parser.add_argument("--width",     type=int,   default=640)
    parser.add_argument("--height",    type=int,   default=640)
    args = parser.parse_args()

    for split in ("train", "val"):
        os.makedirs(os.path.join(args.output, "images", split), exist_ok=True)
        os.makedirs(os.path.join(args.output, "labels", split), exist_ok=True)

    model  = YOLO("runs/train/ballr_v3/weights/best.pt")
    source = parse_source(args.source)
    cap    = cv2.VideoCapture(source)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH,  args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    if not cap.isOpened():
        print(f"ERROR: Could not open source '{args.source}'")
        return

    frame_count = saved = 0
    print(f"Auto-labeling — conf≥{args.conf}, every {args.interval} frames. Press 'q' to stop.")

    while True:
        ret, frame = cap.read()
        if not ret:
            print("ERROR: Failed to grab frame")
            break

        display = frame.copy()

        if frame_count % args.interval == 0:
            results = model.predict(
                frame,
                conf=args.conf,
                classes=[SPORTS_BALL_CLASS_ID],
                verbose=False,
            )
            boxes = results[0].boxes if results and results[0].boxes is not None else []

            if len(boxes):
                split = "val" if random.random() < args.val_split else "train"
                save_sample(frame, boxes, args.output, split)
                saved += 1
                print(f"\rSaved {saved} samples", end="", flush=True)

                for box in boxes:
                    x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                    cv2.rectangle(display, (x1, y1), (x2, y2), (0, 255, 0), 2)
                    cv2.putText(display, f"{float(box.conf[0]):.2f}",
                                (x1, y1 - 6), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 255, 0), 2)

        cv2.putText(display, f"Saved: {saved}", (8, 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)
        cv2.imshow("Auto-Labeling — press q to stop", display)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

        frame_count += 1

    cap.release()
    cv2.destroyAllWindows()
    print(f"\nDone. {saved} labeled samples saved to '{args.output}'.")


if __name__ == "__main__":
    main()
