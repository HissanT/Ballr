import argparse
import shutil
from dataclasses import dataclass
from pathlib import Path

import cv2

from ballr_utils import ensure_dir

IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png")


@dataclass
class ReviewItem:
    session_name: str
    image_path: Path
    label_path: Path
    capture_image_dir: Path
    capture_label_dir: Path


def image_paths(image_dir: Path) -> list[Path]:
    return sorted(
        path
        for path in image_dir.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
    )


def resolve_target_path(target_dir: Path, name: str) -> Path:
    candidate = target_dir / name
    if not candidate.exists():
        return candidate

    stem = candidate.stem
    suffix = candidate.suffix
    index = 1
    while True:
        candidate = target_dir / f"{stem}_reviewed_{index}{suffix}"
        if not candidate.exists():
            return candidate
        index += 1


def find_review_items(review_root: Path, session_name: str | None) -> list[ReviewItem]:
    items: list[ReviewItem] = []
    if not review_root.exists():
        return items

    session_dirs = sorted(path for path in review_root.iterdir() if path.is_dir())
    for session_dir in session_dirs:
        if session_name is not None and session_dir.name != session_name:
            continue

        image_dir = session_dir / "images"
        label_dir = session_dir / "labels"
        if not image_dir.exists() or not label_dir.exists():
            continue

        capture_image_dir = review_root.parent / "captures" / session_dir.name / "images"
        capture_label_dir = review_root.parent / "captures" / session_dir.name / "labels"
        for image_path in image_paths(image_dir):
            label_path = label_dir / f"{image_path.stem}.txt"
            if not label_path.exists():
                continue
            items.append(
                ReviewItem(
                    session_name=session_dir.name,
                    image_path=image_path,
                    label_path=label_path,
                    capture_image_dir=capture_image_dir,
                    capture_label_dir=capture_label_dir,
                )
            )

    return items


def read_boxes(label_path: Path, image_width: int, image_height: int) -> list[tuple[int, int, int, int]]:
    boxes: list[tuple[int, int, int, int]] = []
    for raw_line in label_path.read_text(encoding="utf-8").splitlines():
        parts = raw_line.split()
        if len(parts) != 5:
            continue

        _, center_x, center_y, width, height = parts
        cx = float(center_x) * image_width
        cy = float(center_y) * image_height
        box_width = float(width) * image_width
        box_height = float(height) * image_height

        x1 = max(int(round(cx - box_width / 2.0)), 0)
        y1 = max(int(round(cy - box_height / 2.0)), 0)
        x2 = min(int(round(cx + box_width / 2.0)), image_width - 1)
        y2 = min(int(round(cy + box_height / 2.0)), image_height - 1)
        boxes.append((x1, y1, x2, y2))

    return boxes


def draw_label(frame, text: str, x: int, y: int) -> None:
    (tw, th), baseline = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 2)
    y = max(y, th + baseline)
    cv2.rectangle(frame, (x, y - th - baseline), (x + tw, y + baseline), (0, 0, 0), -1)
    cv2.putText(frame, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 2)


def draw_review_frame(frame, boxes, item: ReviewItem, index: int, total: int) -> None:
    for box_index, (x1, y1, x2, y2) in enumerate(boxes, start=1):
        cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 215, 255), 2)
        draw_label(frame, f"Box {box_index}", x1, max(18, y1 - 6))

    draw_label(frame, f"{index + 1}/{total}", 8, 24)
    draw_label(frame, f"Session: {item.session_name}", 8, 52)
    draw_label(frame, f"File: {item.image_path.name}", 8, 80)
    draw_label(frame, f"Boxes: {len(boxes)}", 8, 108)
    draw_label(frame, "K keep  D delete  S skip  B back  Q quit", 8, frame.shape[0] - 16)


def promote_item(item: ReviewItem) -> None:
    ensure_dir(item.capture_image_dir)
    ensure_dir(item.capture_label_dir)

    target_image_path = resolve_target_path(item.capture_image_dir, item.image_path.name)
    target_label_path = resolve_target_path(item.capture_label_dir, item.label_path.name)
    shutil.move(str(item.image_path), str(target_image_path))
    shutil.move(str(item.label_path), str(target_label_path))


def delete_item(item: ReviewItem) -> None:
    if item.image_path.exists():
        item.image_path.unlink()
    if item.label_path.exists():
        item.label_path.unlink()


def main() -> None:
    parser = argparse.ArgumentParser(description="Visually review queued labels")
    parser.add_argument("--root", default="dataset/review", help="Review queue root")
    parser.add_argument("--session", help="Only review one session folder")
    args = parser.parse_args()

    review_root = Path(args.root)
    items = find_review_items(review_root, args.session)
    if not items:
        print(f"No review items found under '{review_root}'.")
        return

    cv2.namedWindow("Review Queue", cv2.WINDOW_NORMAL)
    index = 0
    kept = 0
    deleted = 0

    while 0 <= index < len(items):
        item = items[index]
        if not item.image_path.exists() or not item.label_path.exists():
            items.pop(index)
            if not items:
                break
            index = min(index, len(items) - 1)
            continue

        frame = cv2.imread(str(item.image_path))
        if frame is None:
            print(f"Unreadable image: {item.image_path}")
            index += 1
            continue

        boxes = read_boxes(item.label_path, frame.shape[1], frame.shape[0])
        display = frame.copy()
        draw_review_frame(display, boxes, item, index, len(items))
        cv2.imshow("Review Queue", display)

        key = cv2.waitKey(0) & 0xFF
        if key in (ord("q"), 27):
            break
        if key == ord("k"):
            promote_item(item)
            kept += 1
            items.pop(index)
            if not items:
                break
            index = min(index, len(items) - 1)
            continue
        if key == ord("d"):
            delete_item(item)
            deleted += 1
            items.pop(index)
            if not items:
                break
            index = min(index, len(items) - 1)
            continue
        if key == ord("b"):
            index = max(0, index - 1)
            continue

        index += 1

    cv2.destroyAllWindows()
    print(f"Review complete. Kept: {kept}, deleted: {deleted}, remaining: {len(items)}")


if __name__ == "__main__":
    main()
