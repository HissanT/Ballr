from __future__ import annotations

import argparse
from pathlib import Path

import cv2

from ball_tracker_juggle_dataset import LABEL_OPTIONS, load_manifest, manifest_path, save_manifest

WINDOW_NAME = "Juggle Candidate Review"
KEY_TO_LABEL = {
    ord("1"): "foot",
    ord("2"): "knee",
    ord("3"): "thigh",
    ord("4"): "ground",
    ord("5"): "other",
    ord("6"): "ambiguous-skip",
}


def _draw_hud(frame, item_index: int, total: int, label: str, predicted: str, confidence: float) -> None:
    lines = [
        f"Item: {item_index + 1}/{total}",
        f"Pred: {predicted} {confidence:.2f}",
        f"Label: {label or '(unlabeled)'}",
        "1 foot  2 knee  3 thigh  4 ground  5 other  6 skip  q quit",
    ]
    y = 24
    for line in lines:
        cv2.putText(
            frame,
            line,
            (8, y),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.55,
            (255, 255, 255),
            2,
            lineType=cv2.LINE_AA,
        )
        y += 24


def main() -> None:
    parser = argparse.ArgumentParser(description="Review exported juggle event candidates")
    parser.add_argument("--root", required=True, help="Candidate export root containing manifest.jsonl")
    parser.add_argument("--resume-reviewed", action="store_true", help="Include already reviewed items")
    args = parser.parse_args()

    root = Path(args.root)
    path = manifest_path(root)
    items = load_manifest(path)
    if not items:
        raise SystemExit(f"No manifest items found under '{root}'.")

    if not args.resume_reviewed:
        items = [item for item in items if item.review_status != "reviewed"]
        if not items:
            raise SystemExit("No pending review items remain.")

    cv2.namedWindow(WINDOW_NAME, cv2.WINDOW_NORMAL)
    try:
        for index, item in enumerate(items):
            clip_path = root / item.clip_relpath
            cap = cv2.VideoCapture(str(clip_path))
            if not cap.isOpened():
                continue

            while True:
                ret, frame = cap.read()
                if not ret:
                    cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                    continue
                display = frame.copy()
                _draw_hud(
                    display,
                    index,
                    len(items),
                    item.label,
                    item.predicted_class,
                    item.predicted_confidence,
                )
                cv2.imshow(WINDOW_NAME, display)
                key = cv2.waitKey(33) & 0xFF
                if key in KEY_TO_LABEL:
                    item.label = KEY_TO_LABEL[key]
                    item.review_status = "reviewed"
                    break
                if key == ord("q"):
                    save_manifest(path, items)
                    return
            cap.release()
            save_manifest(path, items)
    finally:
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
