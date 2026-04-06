import argparse
import json
import time
from pathlib import Path

import cv2
from ultralytics import YOLO

from ballr_utils import build_gamma_lut, ensure_dir, parse_source, preprocess_frame

SPORTS_BALL_CLASS_ID = 0
AUTO_LABEL_CLASS_ID = 0
MODEL_PATH = "runs/train/ballr_v4/weights/best.pt"
IOU_THRESHOLD = 0.35


def make_stem(frame_index: int) -> str:
    timestamp = int(time.time() * 1000)
    return f"frame_{timestamp}_{frame_index:06d}"


def save_sample(frame, boxes, image_dir: Path, label_dir: Path, stem: str) -> bool:
    img_path = image_dir / f"{stem}.jpg"
    label_path = label_dir / f"{stem}.txt"

    if not cv2.imwrite(str(img_path), frame):
        return False

    h, w = frame.shape[:2]
    with label_path.open("w", encoding="utf-8") as label_file:
        for box in boxes:
            x1, y1, x2, y2 = box.xyxy[0].tolist()
            cx = ((x1 + x2) / 2) / w
            cy = ((y1 + y2) / 2) / h
            bw = (x2 - x1) / w
            bh = (y2 - y1) / h
            label_file.write(
                f"{AUTO_LABEL_CLASS_ID} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}\n"
            )

    return True


def write_session_metadata(path: Path, metadata: dict) -> None:
    path.write_text(json.dumps(metadata, indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Collect session-based training data")
    parser.add_argument("--source", default="0", help="Webcam index or DroidCam URL")
    parser.add_argument("--output", default="dataset", help="Root dataset directory")
    parser.add_argument("--session", help="Optional session name (defaults to a timestamp)")
    parser.add_argument(
        "--conf",
        type=float,
        default=0.55,
        help="Minimum confidence for a frame to enter the capture set",
    )
    parser.add_argument(
        "--review-conf",
        type=float,
        default=0.25,
        help="Minimum confidence to retain a frame in the manual review queue",
    )
    parser.add_argument(
        "--interval",
        type=int,
        default=5,
        help="Run inference every N frames to capture fast airborne motion",
    )
    parser.add_argument(
        "--save-empty-interval",
        type=int,
        default=45,
        help="Save an empty-label background frame after this many frames without detections",
    )
    parser.add_argument(
        "--allow-multiple",
        action="store_true",
        help="Allow multi-box detections into the capture set instead of review only",
    )
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    args = parser.parse_args()

    session_name = args.session or time.strftime("%Y%m%d_%H%M%S")
    dataset_root = Path(args.output)
    capture_root = ensure_dir(dataset_root / "captures" / session_name)
    review_root = ensure_dir(dataset_root / "review" / session_name)
    capture_images = ensure_dir(capture_root / "images")
    capture_labels = ensure_dir(capture_root / "labels")
    review_images = ensure_dir(review_root / "images")
    review_labels = ensure_dir(review_root / "labels")

    model = YOLO(MODEL_PATH)
    gamma_lut = build_gamma_lut()
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    source = parse_source(args.source)
    cap = cv2.VideoCapture(source)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    if not cap.isOpened():
        print(f"ERROR: Could not open source '{args.source}'")
        return

    metadata = {
        "session": session_name,
        "source": str(args.source),
        "model_path": MODEL_PATH,
        "save_confidence": args.conf,
        "review_confidence": args.review_conf,
        "interval": args.interval,
        "save_empty_interval": args.save_empty_interval,
        "allow_multiple": args.allow_multiple,
        "frame_size": {"width": args.width, "height": args.height},
        "preprocessed_frames": True,
        "created_at": time.strftime("%Y-%m-%d %H:%M:%S"),
    }
    write_session_metadata(capture_root / "session.json", metadata)

    frame_count = 0
    accepted_saved = 0
    review_saved = 0
    empty_saved = 0
    skipped_multi = 0
    last_empty_save_frame = -args.save_empty_interval

    print(
        f"Collecting session '{session_name}' - conf>={args.conf:.2f}, "
        f"review>={args.review_conf:.2f}, every {args.interval} frames. Press 'q' to stop."
    )

    while True:
        ret, frame = cap.read()
        if not ret:
            print("ERROR: Failed to grab frame")
            break

        display = frame.copy()

        if frame_count % args.interval == 0:
            enhanced = preprocess_frame(frame, gamma_lut, clahe)
            results = model.predict(
                enhanced,
                conf=args.review_conf,
                iou=IOU_THRESHOLD,
                classes=[SPORTS_BALL_CLASS_ID],
                max_det=6,
                imgsz=max(args.width, args.height),
                verbose=False,
            )
            boxes = results[0].boxes if results and results[0].boxes is not None else []
            accepted = len(boxes) == 1 or (args.allow_multiple and len(boxes) > 1)

            if len(boxes) and accepted and all(float(box.conf[0]) >= args.conf for box in boxes):
                stem = make_stem(frame_count)
                if save_sample(enhanced, boxes, capture_images, capture_labels, stem):
                    accepted_saved += 1
            elif len(boxes):
                stem = make_stem(frame_count)
                if save_sample(enhanced, boxes, review_images, review_labels, stem):
                    review_saved += 1
                if len(boxes) > 1 and not args.allow_multiple:
                    skipped_multi += 1
            elif args.save_empty_interval > 0 and (
                frame_count - last_empty_save_frame >= args.save_empty_interval
            ):
                stem = make_stem(frame_count)
                if save_sample(enhanced, [], capture_images, capture_labels, stem):
                    empty_saved += 1
                    last_empty_save_frame = frame_count

            for box in boxes:
                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                conf = float(box.conf[0])
                color = (0, 255, 0) if conf >= args.conf and len(boxes) == 1 else (0, 215, 255)
                cv2.rectangle(display, (x1, y1), (x2, y2), color, 2)
                cv2.putText(
                    display,
                    f"{conf:.2f}",
                    (x1, max(16, y1 - 6)),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.55,
                    color,
                    2,
                )

        cv2.putText(
            display,
            f"Accepted: {accepted_saved}",
            (8, 24),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            2,
        )
        cv2.putText(
            display,
            f"Review: {review_saved}",
            (8, 52),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            2,
        )
        cv2.putText(
            display,
            f"Empty: {empty_saved}",
            (8, 80),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            2,
        )
        cv2.putText(
            display,
            f"Skip multi: {skipped_multi}",
            (8, 108),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.6,
            (255, 255, 255),
            2,
        )
        cv2.imshow("Collect Data - press q to stop", display)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

        frame_count += 1

    cap.release()
    cv2.destroyAllWindows()
    print(
        f"\nDone. Accepted: {accepted_saved}, review: {review_saved}, empty: {empty_saved}, "
        f"skipped multi: {skipped_multi}."
    )
    print(f"Capture session saved to '{capture_root}'.")
    print(f"Review queue saved to '{review_root}'.")


if __name__ == "__main__":
    main()
