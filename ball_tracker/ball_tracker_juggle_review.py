from __future__ import annotations

import argparse
from pathlib import Path

import cv2

from .ball_tracker_juggle_dataset import (
    load_manifest,
    manifest_path,
    save_manifest,
)

WINDOW_NAME = "Juggle Candidate Review"
DEFAULT_PLAYBACK_MS = 85
KEY_TO_LABEL = {
    ord("1"): ("count", "foot"),
    ord("2"): ("count", "knee"),
    ord("3"): ("count", "hip"),
    ord("4"): ("hand", ""),
    ord("5"): ("ground", ""),
    ord("6"): ("other", ""),
    ord("7"): ("ambiguous-skip", ""),
    ord("8"): ("count", "unknown"),
}


def _display_label(item) -> str:
    if item.event_label == "count":
        return f"count/{item.body_part_label or 'unknown'}"
    return item.event_label or "(unlabeled)"


def _display_prediction(item) -> str:
    if item.predicted_event_label == "count":
        return f"count/{item.predicted_body_part_label or 'unknown'}"
    return item.predicted_event_label or item.predicted_class


def _draw_hud(
    frame,
    item_index: int,
    total: int,
    label: str,
    predicted: str,
    confidence: float,
    *,
    loop_enabled: bool,
    paused: bool,
) -> None:
    lines = [
        f"Item: {item_index + 1}/{total}",
        f"Pred: {predicted} {confidence:.2f}",
        f"Label: {label or '(unlabeled)'}",
        f"Loop: {'On' if loop_enabled else 'Off'}  Playback: {'Paused' if paused else 'Playing'}",
        "1 count/foot  2 count/knee  3 count/hip  4 hand",
        "5 ground  6 other  7 skip  8 count/unknown",
        "l toggle loop  space pause/play  q quit",
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
    parser.add_argument(
        "--playback-ms",
        type=int,
        default=DEFAULT_PLAYBACK_MS,
        help="Frame delay in milliseconds for review playback",
    )
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

            loop_enabled = False
            paused = False
            last_frame = None
            while True:
                if not paused:
                    ret, frame = cap.read()
                    if ret:
                        last_frame = frame
                    elif loop_enabled:
                        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                        ret, frame = cap.read()
                        if ret:
                            last_frame = frame
                    else:
                        paused = True

                if last_frame is None:
                    break

                display = last_frame.copy()
                _draw_hud(
                    display,
                    index,
                    len(items),
                    _display_label(item),
                    _display_prediction(item),
                    item.predicted_confidence,
                    loop_enabled=loop_enabled,
                    paused=paused,
                )
                cv2.imshow(WINDOW_NAME, display)
                key = cv2.waitKey(max(args.playback_ms, 1)) & 0xFF
                if key in KEY_TO_LABEL:
                    item.event_label, item.body_part_label = KEY_TO_LABEL[key]
                    item.label_quality = "clear"
                    item.review_status = "reviewed"
                    break
                if key == ord("l"):
                    loop_enabled = not loop_enabled
                    if loop_enabled and paused:
                        paused = False
                        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                    continue
                if key == ord(" "):
                    paused = not paused
                    continue
                if key == ord("q"):
                    save_manifest(path, items)
                    return
            cap.release()
            save_manifest(path, items)
    finally:
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
