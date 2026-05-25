import argparse
import json
import shutil
from collections import Counter
from pathlib import Path

from common.ballr_utils import training_path

IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png")


def image_paths(image_dir: Path) -> list[Path]:
    if not image_dir.exists():
        return []
    return sorted(
        path
        for path in image_dir.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
    )


def find_image_for_stem(image_dir: Path, stem: str) -> Path | None:
    for extension in IMAGE_EXTENSIONS:
        candidate = image_dir / f"{stem}{extension}"
        if candidate.exists():
            return candidate
    return None


def read_normalized_boxes(label_path: Path) -> list[dict[str, float | int]]:
    if not label_path.exists():
        return []

    boxes: list[dict[str, float | int]] = []
    for raw_line in label_path.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 5:
            continue
        try:
            class_id = int(parts[0])
            cx, cy, w, h = (float(value) for value in parts[1:5])
        except ValueError:
            continue
        box: dict[str, float | int] = {
            "class_id": class_id,
            "cx": cx,
            "cy": cy,
            "w": w,
            "h": h,
        }
        if len(parts) >= 6:
            try:
                box["conf"] = float(parts[5])
            except ValueError:
                pass
        boxes.append(box)
    return boxes


def _scan_viewer_items(root: Path) -> list[dict[str, object]]:
    items: list[dict[str, object]] = []
    images_root = root / "images"
    if not images_root.exists():
        return items

    for split_dir in sorted(path for path in images_root.iterdir() if path.is_dir()):
        split = split_dir.name
        label_dir = root / "labels" / split
        for image_path in image_paths(split_dir):
            items.append(
                {
                    "image": image_path.relative_to(root).as_posix(),
                    "split": split,
                    "image_name": image_path.name,
                    "labels": read_normalized_boxes(label_dir / f"{image_path.stem}.txt"),
                    "model_predictions": [],
                    "review_status": "unreviewed",
                    "suspicion_score": 0,
                    "suspicion_reasons": [],
                    "best_iou": None,
                }
            )
    return items


def _manifest_viewer_items(root: Path) -> list[dict[str, object]]:
    manifest = root / "review" / "manifest.jsonl"
    if not manifest.exists():
        return []

    items: list[dict[str, object]] = []
    for raw_line in manifest.read_text(encoding="utf-8-sig").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        payload = json.loads(line)
        image_relpath = payload.get("cleaned_image_relpath") or payload.get("source_image_relpath")
        if image_relpath is None:
            continue
        items.append(
            {
                "image": str(image_relpath),
                "split": str(payload.get("split", "")),
                "image_name": str(payload.get("image_name", Path(str(image_relpath)).name)),
                "labels": list(payload.get("labels", [])),
                "model_predictions": list(payload.get("model_predictions", [])),
                "review_status": str(payload.get("review_status", "pending")),
                "suspicion_score": int(payload.get("suspicion_score", 0)),
                "suspicion_reasons": list(payload.get("suspicion_reasons", [])),
                "best_iou": payload.get("best_iou"),
            }
        )
    return items


def build_label_viewer(root: Path) -> Path:
    root = Path(root)
    items = _manifest_viewer_items(root)
    if not items:
        items = _scan_viewer_items(root)

    payload = json.dumps(items, ensure_ascii=False, separators=(",", ":"))
    output_path = root / "label_overlay_viewer.html"
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{root.name} Label Viewer</title>
  <style>
    :root {{
      color-scheme: dark;
      --bg: #0f1217;
      --panel: #171c24;
      --border: #2c3542;
      --text: #edf2f7;
      --muted: #94a3b8;
      --accent: #f0b73f;
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      font-family: "Segoe UI", Tahoma, sans-serif;
      color: var(--text);
      background:
        radial-gradient(circle at top, rgba(240, 183, 63, 0.14), transparent 24%),
        linear-gradient(180deg, #0c0f14 0%, var(--bg) 100%);
    }}
    .shell {{
      display: grid;
      grid-template-columns: minmax(320px, 1fr) 320px;
      min-height: 100vh;
      gap: 18px;
      padding: 18px;
    }}
    .panel {{
      background: rgba(23, 28, 36, 0.94);
      border: 1px solid var(--border);
      border-radius: 16px;
      box-shadow: 0 18px 60px rgba(0, 0, 0, 0.28);
    }}
    .stage, .sidebar {{
      padding: 16px;
    }}
    .toolbar {{
      display: flex;
      gap: 10px;
      align-items: center;
      flex-wrap: wrap;
      margin-bottom: 14px;
    }}
    button {{
      border: 1px solid #3a4657;
      background: #0f141b;
      color: var(--text);
      border-radius: 10px;
      padding: 8px 12px;
      cursor: pointer;
    }}
    canvas {{
      width: 100%;
      height: auto;
      background: #050608;
      border-radius: 12px;
      display: block;
    }}
    .meta {{
      display: grid;
      gap: 8px;
      font-size: 14px;
      color: var(--muted);
    }}
    code {{
      color: var(--text);
      word-break: break-all;
    }}
  </style>
</head>
<body>
  <div class="shell">
    <section class="panel stage">
      <div class="toolbar">
        <button id="prev" type="button">Prev</button>
        <button id="next" type="button">Next</button>
        <span id="count"></span>
      </div>
      <canvas id="viewer" width="1280" height="720"></canvas>
    </section>
    <aside class="panel sidebar">
      <div class="meta">
        <div><strong id="image-name"></strong></div>
        <div>Path: <code id="image-path"></code></div>
        <div>Split: <span id="split"></span></div>
        <div>Review: <span id="review-status"></span></div>
        <div>Suspicion score: <span id="suspicion-score"></span></div>
        <div>Reasons: <span id="suspicion-reasons"></span></div>
        <div>Best IoU: <span id="best-iou"></span></div>
      </div>
    </aside>
  </div>
  <script>
    const ITEMS = {payload};
    const canvas = document.getElementById("viewer");
    const context = canvas.getContext("2d");
    const imageName = document.getElementById("image-name");
    const imagePath = document.getElementById("image-path");
    const split = document.getElementById("split");
    const reviewStatus = document.getElementById("review-status");
    const suspicionScore = document.getElementById("suspicion-score");
    const suspicionReasons = document.getElementById("suspicion-reasons");
    const bestIou = document.getElementById("best-iou");
    const count = document.getElementById("count");
    let index = 0;

    function drawBoxes(image, boxes, color) {{
      context.strokeStyle = color;
      context.lineWidth = 3;
      for (const box of boxes) {{
        const width = box.w * image.width;
        const height = box.h * image.height;
        const x = (box.cx * image.width) - (width / 2);
        const y = (box.cy * image.height) - (height / 2);
        context.strokeRect(x, y, width, height);
      }}
    }}

    function render() {{
      const item = ITEMS[index];
      count.textContent = ITEMS.length ? `${{index + 1}} / ${{ITEMS.length}}` : "0 / 0";
      if (!item) {{
        context.clearRect(0, 0, canvas.width, canvas.height);
        imageName.textContent = "No items";
        imagePath.textContent = "";
        split.textContent = "";
        reviewStatus.textContent = "";
        suspicionScore.textContent = "";
        suspicionReasons.textContent = "";
        bestIou.textContent = "";
        return;
      }}

      imageName.textContent = item.image_name;
      imagePath.textContent = item.image;
      split.textContent = item.split || "-";
      reviewStatus.textContent = item.review_status || "-";
      suspicionScore.textContent = String(item.suspicion_score ?? 0);
      suspicionReasons.textContent = (item.suspicion_reasons || []).join(", ") || "-";
      bestIou.textContent = item.best_iou == null ? "-" : String(item.best_iou);

      const image = new Image();
      image.onload = () => {{
        canvas.width = image.width;
        canvas.height = image.height;
        context.clearRect(0, 0, canvas.width, canvas.height);
        context.drawImage(image, 0, 0);
        drawBoxes(image, item.labels || [], "#f0b73f");
        drawBoxes(image, item.model_predictions || [], "#63c7ff");
      }};
      image.onerror = () => {{
        context.clearRect(0, 0, canvas.width, canvas.height);
        context.fillStyle = "#edf2f7";
        context.font = "20px Segoe UI";
        context.fillText(`Missing image: ${{item.image}}`, 24, 48);
      }};
      image.src = item.image;
    }}

    document.getElementById("prev").addEventListener("click", () => {{
      if (!ITEMS.length) return;
      index = (index - 1 + ITEMS.length) % ITEMS.length;
      render();
    }});
    document.getElementById("next").addEventListener("click", () => {{
      if (!ITEMS.length) return;
      index = (index + 1) % ITEMS.length;
      render();
    }});

    render();
  </script>
</body>
</html>
"""
    output_path.write_text(html, encoding="utf-8")
    return output_path


def summarize_split(root: Path, split: str) -> dict:
    image_dir = root / "images" / split
    label_dir = root / "labels" / split
    images = image_paths(image_dir)
    labels = sorted(label_dir.glob("*.txt")) if label_dir.exists() else []
    image_stems = {path.stem for path in images}
    label_stems = {path.stem for path in labels}

    empty_labels = 0
    multi_labels = 0
    for label_path in labels:
        lines = [line for line in label_path.read_text(encoding="utf-8").splitlines() if line.strip()]
        if not lines:
            empty_labels += 1
        elif len(lines) > 1:
            multi_labels += 1

    return {
        "images": len(images),
        "labels": len(labels),
        "missing_labels_for_images": len(image_stems - label_stems),
        "orphan_labels": len(label_stems - image_stems),
        "empty_labels": empty_labels,
        "multi_labels": multi_labels,
    }


def frame_timestamps(image_dir: Path) -> list[int]:
    timestamps: list[int] = []
    for path in image_paths(image_dir):
        if not path.name.startswith("frame_"):
            continue
        parts = path.stem.split("_")
        if len(parts) < 2:
            continue
        try:
            timestamps.append(int(parts[1]))
        except ValueError:
            continue
    return sorted(timestamps)


def nearest_gap_count(train_timestamps: list[int], val_timestamps: list[int], max_gap_ms: int) -> int:
    if not train_timestamps or not val_timestamps:
        return 0

    count = 0
    for timestamp in val_timestamps:
        lo = 0
        hi = len(train_timestamps)
        while lo < hi:
            mid = (lo + hi) // 2
            if train_timestamps[mid] < timestamp:
                lo = mid + 1
            else:
                hi = mid
        insert_at = lo

        neighbors: list[int] = []
        if insert_at < len(train_timestamps):
            neighbors.append(train_timestamps[insert_at])
        if insert_at > 0:
            neighbors.append(train_timestamps[insert_at - 1])
        if neighbors and min(abs(timestamp - neighbor) for neighbor in neighbors) <= max_gap_ms:
            count += 1

    return count


def audit_dataset(root: Path) -> None:
    for split in ("train", "val"):
        summary = summarize_split(root, split)
        print(f"[{split}] images={summary['images']} labels={summary['labels']}")
        print(
            f"[{split}] missing_labels_for_images={summary['missing_labels_for_images']} "
            f"orphan_labels={summary['orphan_labels']}"
        )
        print(
            f"[{split}] empty_labels={summary['empty_labels']} "
            f"multi_labels={summary['multi_labels']}"
        )

    train_frames = frame_timestamps(root / "images" / "train")
    val_frames = frame_timestamps(root / "images" / "val")
    if train_frames and val_frames:
        close_500 = nearest_gap_count(train_frames, val_frames, max_gap_ms=500)
        close_1000 = nearest_gap_count(train_frames, val_frames, max_gap_ms=1000)
        print(f"[leakage] val frame images within 500 ms of train: {close_500}/{len(val_frames)}")
        print(f"[leakage] val frame images within 1000 ms of train: {close_1000}/{len(val_frames)}")


def clean_orphans(root: Path, apply: bool) -> None:
    removed = 0
    for split in ("train", "val"):
        image_dir = root / "images" / split
        label_dir = root / "labels" / split
        if not image_dir.exists() or not label_dir.exists():
            continue
        for label_path in sorted(label_dir.glob("*.txt")):
            if find_image_for_stem(image_dir, label_path.stem) is not None:
                continue
            print(f"orphan label: {label_path}")
            if apply:
                label_path.unlink()
                removed += 1

    if apply:
        print(f"Removed {removed} orphan labels.")
    else:
        print("Dry run only. Re-run with --apply to delete orphan labels.")


def label_paths(label_dir: Path) -> set[Path]:
    return set(label_dir.glob("*.txt")) if label_dir.exists() else set()


def legacy_pairs(legacy_root: Path) -> list[tuple[Path, Path]]:
    pairs: list[tuple[Path, Path]] = []
    for split in ("train", "val"):
        image_dir = legacy_root / "images" / split
        label_dir = legacy_root / "labels" / split
        if not image_dir.exists() or not label_dir.exists():
            continue
        for image_path in image_paths(image_dir):
            label_path = label_dir / f"{image_path.stem}.txt"
            if label_path.exists():
                pairs.append((image_path, label_path))
    return pairs


def session_pairs(session_dir: Path) -> list[tuple[Path, Path]]:
    pairs: list[tuple[Path, Path]] = []
    image_dir = session_dir / "images"
    label_dir = session_dir / "labels"
    for image_path in image_paths(image_dir):
        label_path = label_dir / f"{image_path.stem}.txt"
        if label_path.exists():
            pairs.append((image_path, label_path))
    return pairs


def bucket_ranges(total: int, bucket_count: int) -> list[tuple[int, int]]:
    base = total // bucket_count
    remainder = total % bucket_count
    ranges: list[tuple[int, int]] = []
    start = 0
    for bucket in range(bucket_count):
        size = base + (1 if bucket < remainder else 0)
        end = start + size
        ranges.append((start, end))
        start = end
    return ranges


def split_session_pairs(
    pairs: list[tuple[Path, Path]], bucket_count: int, val_buckets: set[int]
) -> tuple[list[tuple[Path, Path]], list[tuple[Path, Path]], list[tuple[int, int]]]:
    ranges = bucket_ranges(len(pairs), bucket_count)
    train_pairs: list[tuple[Path, Path]] = []
    val_pairs: list[tuple[Path, Path]] = []
    for bucket_index, (start, end) in enumerate(ranges):
        bucket_pairs = pairs[start:end]
        if bucket_index in val_buckets:
            val_pairs.extend(bucket_pairs)
        else:
            train_pairs.extend(bucket_pairs)
    return train_pairs, val_pairs, ranges


def ensure_empty_output_root(output_root: Path) -> None:
    if output_root.exists() and any(output_root.iterdir()):
        raise SystemExit(
            f"Output directory '{output_root}' already exists and is not empty. "
            "Use a fresh path or remove the existing prepared dataset first."
        )


def copy_pairs_to_split(
    pairs: list[tuple[Path, Path]], output_root: Path, split: str
) -> int:
    image_output_dir = output_root / "images" / split
    label_output_dir = output_root / "labels" / split
    image_output_dir.mkdir(parents=True, exist_ok=True)
    label_output_dir.mkdir(parents=True, exist_ok=True)

    copied = 0
    for image_path, label_path in pairs:
        shutil.copy2(image_path, image_output_dir / image_path.name)
        shutil.copy2(label_path, label_output_dir / label_path.name)
        copied += 1
    return copied


def write_data_yaml(output_root: Path, train_images_path: str, val_images_path: str) -> None:
    content = "\n".join(
        [
            f"path: {output_root.as_posix()}",
            f"train: {train_images_path}",
            f"val: {val_images_path}",
            "",
            "nc: 1",
            "names:",
            "  0: soccer-ball",
            "",
        ]
    )
    (output_root / "data.yaml").write_text(content, encoding="utf-8")


def write_prep_summary(output_root: Path, summary: dict) -> None:
    lines = [f"{key}: {value}" for key, value in summary.items()]
    (output_root / "summary.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def prepare_v4_datasets(
    legacy_root: Path,
    captures_root: Path,
    session_name: str,
    tune_output_root: Path,
    all_output_root: Path,
    bucket_count: int,
    val_buckets: set[int],
) -> None:
    session_dir = captures_root / session_name
    if not session_dir.exists():
        raise SystemExit(f"Capture session '{session_name}' not found under '{captures_root}'.")

    ensure_empty_output_root(tune_output_root)
    ensure_empty_output_root(all_output_root)

    legacy = legacy_pairs(legacy_root)
    session = session_pairs(session_dir)
    if not session:
        raise SystemExit(f"No labeled session images found in '{session_dir}'.")

    train_session, val_session, ranges = split_session_pairs(session, bucket_count, val_buckets)

    tune_train_count = copy_pairs_to_split(legacy, tune_output_root, "train")
    tune_train_count += copy_pairs_to_split(train_session, tune_output_root, "train")
    tune_val_count = copy_pairs_to_split(val_session, tune_output_root, "val")
    write_data_yaml(tune_output_root, "images/train", "images/val")

    final_train_count = copy_pairs_to_split(legacy, all_output_root, "train")
    final_train_count += copy_pairs_to_split(session, all_output_root, "train")
    write_data_yaml(all_output_root, "images/train", "images/train")

    tune_summary = {
        "legacy_pairs": len(legacy),
        "session_pairs": len(session),
        "bucket_count": bucket_count,
        "val_buckets": ",".join(str(bucket) for bucket in sorted(val_buckets)),
        "bucket_ranges": ranges,
        "train_session_pairs": len(train_session),
        "val_session_pairs": len(val_session),
        "tune_train_pairs": tune_train_count,
        "tune_val_pairs": tune_val_count,
    }
    final_summary = {
        "legacy_pairs": len(legacy),
        "session_pairs": len(session),
        "final_train_pairs": final_train_count,
        "validation_mode": "train-set",
    }
    write_prep_summary(tune_output_root, tune_summary)
    write_prep_summary(all_output_root, final_summary)

    print(f"Tune dataset written to '{tune_output_root}'.")
    print(f"Final dataset written to '{all_output_root}'.")
    print(
        f"Tune counts: train={tune_train_count} val={tune_val_count} "
        f"(legacy={len(legacy)} session_train={len(train_session)} session_val={len(val_session)})"
    )
    print(f"Final counts: train={final_train_count}")


def parse_bucket_set(raw: str) -> set[int]:
    values = {int(part.strip()) for part in raw.split(",") if part.strip()}
    if not values:
        raise argparse.ArgumentTypeError("Expected at least one bucket index.")
    return values


def main() -> None:
    parser = argparse.ArgumentParser(description="Dataset cleanup and preparation utilities")
    subparsers = parser.add_subparsers(dest="command", required=True)

    audit_parser = subparsers.add_parser("audit", help="Summarize a prepared train/val dataset")
    audit_parser.add_argument("--root", default=str(training_path("dataset")), help="Prepared dataset root")

    clean_parser = subparsers.add_parser(
        "clean-orphans", help="Remove label files that do not have a matching image"
    )
    clean_parser.add_argument("--root", default=str(training_path("dataset")), help="Prepared dataset root")
    clean_parser.add_argument("--apply", action="store_true", help="Delete orphan labels")

    prepare_parser = subparsers.add_parser(
        "prepare-v4",
        help="Build the v4 tune/all datasets from legacy labels plus a reviewed capture session",
    )
    prepare_parser.add_argument("--legacy-root", default=str(training_path("dataset")), help="Legacy dataset root")
    prepare_parser.add_argument(
        "--captures-root",
        default=str(training_path("dataset", "captures")),
        help="Directory containing reviewed capture sessions",
    )
    prepare_parser.add_argument(
        "--session",
        default="tennis-court-passing-and-shooting",
        help="Capture session to merge into v4",
    )
    prepare_parser.add_argument(
        "--tune-output-root",
        default=str(training_path("dataset_prepared_v4_tune")),
        help="Destination for tune dataset",
    )
    prepare_parser.add_argument(
        "--all-output-root",
        default=str(training_path("dataset_prepared_v4_all")),
        help="Destination for the final all-data dataset",
    )
    prepare_parser.add_argument(
        "--bucket-count",
        type=int,
        default=10,
        help="Number of contiguous buckets to split the reviewed session into",
    )
    prepare_parser.add_argument(
        "--val-buckets",
        type=parse_bucket_set,
        default={2, 7},
        help="Comma-separated 0-based session bucket indices reserved for tune validation",
    )

    args = parser.parse_args()
    if args.command == "audit":
        audit_dataset(Path(args.root))
    elif args.command == "clean-orphans":
        clean_orphans(Path(args.root), apply=args.apply)
    elif args.command == "prepare-v4":
        prepare_v4_datasets(
            legacy_root=Path(args.legacy_root),
            captures_root=Path(args.captures_root),
            session_name=args.session,
            tune_output_root=Path(args.tune_output_root),
            all_output_root=Path(args.all_output_root),
            bucket_count=args.bucket_count,
            val_buckets=args.val_buckets,
        )


if __name__ == "__main__":
    main()
