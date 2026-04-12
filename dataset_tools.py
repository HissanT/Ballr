import argparse
import html
import json
import shutil
from collections import Counter
from pathlib import Path


IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png")
DEFAULT_DATASET_SPLITS = ("train", "val")


def image_paths(image_dir: Path) -> list[Path]:
    if not image_dir.exists():
        return []
    return sorted(
        path
        for path in image_dir.iterdir()
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS
    )


def parse_split_list(raw: str) -> tuple[str, ...]:
    parts = tuple(part.strip() for part in raw.split(",") if part.strip())
    if not parts:
        raise argparse.ArgumentTypeError("Expected at least one split name.")
    return parts


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
    for line in label_path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) != 5:
            continue
        try:
            class_id = int(parts[0])
            cx, cy, w, h = (float(value) for value in parts[1:])
        except ValueError:
            continue
        boxes.append(
            {
                "class_id": class_id,
                "cx": round(cx, 6),
                "cy": round(cy, 6),
                "w": round(w, 6),
                "h": round(h, 6),
            }
        )
    return boxes


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


def _viewer_item_from_manifest(root: Path, payload: dict, splits: set[str]) -> dict | None:
    split = str(payload.get("split", ""))
    if split not in splits:
        return None

    preferred_relpath = str(payload.get("cleaned_image_relpath") or payload.get("source_image_relpath") or "")
    if not preferred_relpath:
        return None

    image_path = root / preferred_relpath
    if not image_path.exists():
        fallback_relpath = str(payload.get("source_image_relpath") or "")
        if not fallback_relpath:
            return None
        fallback_path = root / fallback_relpath
        if not fallback_path.exists():
            return None
        preferred_relpath = fallback_relpath

    return {
        "image": preferred_relpath.replace("\\", "/"),
        "split": split,
        "image_name": str(payload.get("image_name", Path(preferred_relpath).name)),
        "review_status": str(payload.get("review_status", "")),
        "suspicion_score": int(payload.get("suspicion_score", 0)),
        "suspicion_reasons": list(payload.get("suspicion_reasons", [])),
        "best_iou": payload.get("best_iou"),
        "labels": list(payload.get("labels", [])),
        "model_predictions": list(payload.get("model_predictions", [])),
    }


def viewer_items_from_review_manifest(root: Path, splits: tuple[str, ...]) -> list[dict]:
    manifest_path = root / "review" / "manifest.jsonl"
    if not manifest_path.exists():
        return []

    split_set = set(splits)
    items: list[dict] = []
    for line in manifest_path.read_text(encoding="utf-8-sig").splitlines():
        if not line.strip():
            continue
        payload = json.loads(line)
        item = _viewer_item_from_manifest(root, payload, split_set)
        if item is not None:
            items.append(item)
    return items


def viewer_items_from_dataset(root: Path, splits: tuple[str, ...]) -> list[dict]:
    items: list[dict] = []
    for split in splits:
        image_dir = root / "images" / split
        label_dir = root / "labels" / split
        for image_path in image_paths(image_dir):
            label_path = label_dir / f"{image_path.stem}.txt"
            items.append(
                {
                    "image": image_path.relative_to(root).as_posix(),
                    "split": split,
                    "image_name": image_path.name,
                    "review_status": "",
                    "suspicion_score": 0,
                    "suspicion_reasons": [],
                    "best_iou": None,
                    "labels": read_normalized_boxes(label_path),
                    "model_predictions": [],
                }
            )
    return items


def build_label_viewer_html(root: Path, items: list[dict]) -> str:
    dataset_name = html.escape(root.name or root.as_posix())
    serialized_items = json.dumps(items, separators=(",", ":")).replace("</", "<\\/")
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{dataset_name} Label Viewer</title>
  <style>
    :root {{
      color-scheme: dark;
      --bg: #111318;
      --panel: #1a1f27;
      --panel-border: #2b3340;
      --text: #edf2f7;
      --muted: #9aa7b8;
      --accent: #e8b931;
      --accent-2: #63c7ff;
    }}
    * {{
      box-sizing: border-box;
    }}
    body {{
      margin: 0;
      font-family: "Segoe UI", Tahoma, sans-serif;
      background:
        radial-gradient(circle at top, rgba(232, 185, 49, 0.10), transparent 28%),
        linear-gradient(180deg, #0f1217 0%, #111318 100%);
      color: var(--text);
      min-height: 100vh;
    }}
    .shell {{
      display: grid;
      grid-template-columns: minmax(340px, 1fr) 320px;
      min-height: 100vh;
    }}
    .stage {{
      padding: 20px;
    }}
    .panel {{
      background: rgba(26, 31, 39, 0.92);
      border: 1px solid var(--panel-border);
      border-radius: 16px;
      box-shadow: 0 18px 50px rgba(0, 0, 0, 0.28);
    }}
    .toolbar {{
      display: flex;
      gap: 10px;
      align-items: center;
      flex-wrap: wrap;
      padding: 14px;
      margin-bottom: 16px;
    }}
    button, select, input {{
      background: #0e1218;
      color: var(--text);
      border: 1px solid #354151;
      border-radius: 10px;
      padding: 8px 12px;
      font: inherit;
    }}
    button {{
      cursor: pointer;
    }}
    .count {{
      color: var(--muted);
      margin-left: auto;
    }}
    .viewer {{
      padding: 14px;
    }}
    canvas {{
      width: 100%;
      height: auto;
      display: block;
      background: #050608;
      border-radius: 14px;
    }}
    .sidebar {{
      padding: 20px 20px 20px 0;
    }}
    .meta {{
      padding: 18px;
      position: sticky;
      top: 20px;
    }}
    h1 {{
      margin: 0 0 12px;
      font-size: 1.1rem;
    }}
    .hint {{
      color: var(--muted);
      font-size: 0.92rem;
      margin: 0 0 16px;
    }}
    .meta-line {{
      margin: 0 0 10px;
      line-height: 1.45;
      word-break: break-word;
    }}
    .legend {{
      display: flex;
      gap: 12px;
      flex-wrap: wrap;
      margin: 14px 0 18px;
      color: var(--muted);
      font-size: 0.92rem;
    }}
    .swatch {{
      display: inline-block;
      width: 12px;
      height: 12px;
      border-radius: 999px;
      margin-right: 6px;
      vertical-align: middle;
    }}
    .saved {{
      background: var(--accent);
    }}
    .pred {{
      background: var(--accent-2);
    }}
    @media (max-width: 1080px) {{
      .shell {{
        grid-template-columns: 1fr;
      }}
      .sidebar {{
        padding: 0 20px 20px;
      }}
      .meta {{
        position: static;
      }}
      .count {{
        margin-left: 0;
      }}
    }}
  </style>
</head>
<body>
  <div class="shell">
    <main class="stage">
      <div class="toolbar panel">
        <button id="prevBtn" type="button">Prev</button>
        <button id="nextBtn" type="button">Next</button>
        <label>Split
          <select id="splitFilter">
            <option value="all">All</option>
            <option value="train">Train</option>
            <option value="val">Val</option>
          </select>
        </label>
        <label>Jump
          <input id="jumpInput" type="number" min="1" step="1" value="1">
        </label>
        <label><input id="showLabels" type="checkbox" checked> Saved labels</label>
        <label><input id="showPredictions" type="checkbox" checked> Model preds</label>
        <div class="count" id="countLabel"></div>
      </div>
      <div class="viewer panel">
        <canvas id="canvas"></canvas>
      </div>
    </main>
    <aside class="sidebar">
      <div class="meta panel">
        <h1>{dataset_name} Label Viewer</h1>
        <p class="hint">Arrow keys move through images. Home and End jump to the start or end of the current filter.</p>
        <div class="legend">
          <span><span class="swatch saved"></span>Saved labels</span>
          <span><span class="swatch pred"></span>Model predictions</span>
        </div>
        <p class="meta-line" id="metaFile"></p>
        <p class="meta-line" id="metaStatus"></p>
        <p class="meta-line" id="metaLabels"></p>
        <p class="meta-line" id="metaPredictions"></p>
        <p class="meta-line" id="metaReasons"></p>
      </div>
    </aside>
  </div>

  <script id="viewer-data" type="application/json">{serialized_items}</script>
  <script>
    const items = JSON.parse(document.getElementById("viewer-data").textContent);
    const canvas = document.getElementById("canvas");
    const ctx = canvas.getContext("2d");
    const image = new Image();
    const state = {{ index: 0, filter: "all" }};

    const prevBtn = document.getElementById("prevBtn");
    const nextBtn = document.getElementById("nextBtn");
    const splitFilter = document.getElementById("splitFilter");
    const jumpInput = document.getElementById("jumpInput");
    const showLabels = document.getElementById("showLabels");
    const showPredictions = document.getElementById("showPredictions");
    const countLabel = document.getElementById("countLabel");

    const metaFile = document.getElementById("metaFile");
    const metaStatus = document.getElementById("metaStatus");
    const metaLabels = document.getElementById("metaLabels");
    const metaPredictions = document.getElementById("metaPredictions");
    const metaReasons = document.getElementById("metaReasons");

    function filteredItems() {{
      if (state.filter === "all") {{
        return items;
      }}
      return items.filter((item) => item.split === state.filter);
    }}

    function currentItems() {{
      const list = filteredItems();
      if (!list.length) {{
        return list;
      }}
      state.index = Math.min(Math.max(state.index, 0), list.length - 1);
      return list;
    }}

    function currentItem() {{
      const list = currentItems();
      return list.length ? list[state.index] : null;
    }}

    function drawBoxes(boxes, color, labelPrefix) {{
      if (!boxes || !boxes.length) {{
        return;
      }}
      ctx.strokeStyle = color;
      ctx.fillStyle = color;
      ctx.lineWidth = 2;
      ctx.font = "14px Segoe UI";
      for (const [boxIndex, box] of boxes.entries()) {{
        const x = (box.cx - box.w / 2) * canvas.width;
        const y = (box.cy - box.h / 2) * canvas.height;
        const w = box.w * canvas.width;
        const h = box.h * canvas.height;
        ctx.strokeRect(x, y, w, h);
        const suffix = box.conf !== undefined ? ` ${{Number(box.conf).toFixed(2)}}` : "";
        const text = `${{labelPrefix}} ${{boxIndex + 1}}${{suffix}}`;
        const textWidth = ctx.measureText(text).width + 10;
        const textY = Math.max(18, y - 6);
        ctx.fillRect(x, textY - 16, textWidth, 18);
        ctx.fillStyle = "#111318";
        ctx.fillText(text, x + 5, textY - 3);
        ctx.fillStyle = color;
      }}
    }}

    function updateMeta(item, visibleCount) {{
      countLabel.textContent = visibleCount ? `${{state.index + 1}} / ${{visibleCount}}` : "0 / 0";
      jumpInput.value = visibleCount ? String(state.index + 1) : "0";
      metaFile.textContent = item ? `File: ${{item.image_name}} (${{item.split}})` : "No images for this filter.";
      metaStatus.textContent = item
        ? `Status: ${{item.review_status || "n/a"}} | Score: ${{item.suspicion_score ?? 0}} | Best IoU: ${{item.best_iou ?? "n/a"}}`
        : "";
      metaLabels.textContent = item ? `Saved labels: ${{item.labels.length}}` : "";
      metaPredictions.textContent = item ? `Model predictions: ${{(item.model_predictions || []).length}}` : "";
      metaReasons.textContent = item
        ? `Reasons: ${{item.suspicion_reasons && item.suspicion_reasons.length ? item.suspicion_reasons.join(", ") : "none"}}`
        : "";
    }}

    function renderCurrent() {{
      const list = currentItems();
      const item = currentItem();
      updateMeta(item, list.length);
      if (!item) {{
        canvas.width = 1280;
        canvas.height = 720;
        ctx.fillStyle = "#050608";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.fillStyle = "#edf2f7";
        ctx.font = "20px Segoe UI";
        ctx.fillText("No images available for the selected filter.", 40, 80);
        return;
      }}
      image.src = item.image;
    }}

    image.onload = () => {{
      canvas.width = image.naturalWidth;
      canvas.height = image.naturalHeight;
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(image, 0, 0);
      const item = currentItem();
      if (!item) {{
        return;
      }}
      if (showLabels.checked) {{
        drawBoxes(item.labels || [], "#e8b931", "Label");
      }}
      if (showPredictions.checked) {{
        drawBoxes(item.model_predictions || [], "#63c7ff", "Pred");
      }}
    }};

    function step(delta) {{
      const list = currentItems();
      if (!list.length) {{
        return;
      }}
      state.index = (state.index + delta + list.length) % list.length;
      renderCurrent();
    }}

    prevBtn.addEventListener("click", () => step(-1));
    nextBtn.addEventListener("click", () => step(1));
    showLabels.addEventListener("change", renderCurrent);
    showPredictions.addEventListener("change", renderCurrent);
    splitFilter.addEventListener("change", () => {{
      state.filter = splitFilter.value;
      state.index = 0;
      renderCurrent();
    }});
    jumpInput.addEventListener("change", () => {{
      const list = currentItems();
      if (!list.length) {{
        return;
      }}
      const requestedIndex = Number.parseInt(jumpInput.value, 10);
      if (Number.isNaN(requestedIndex)) {{
        return;
      }}
      state.index = Math.min(Math.max(requestedIndex - 1, 0), list.length - 1);
      renderCurrent();
    }});

    document.addEventListener("keydown", (event) => {{
      if (event.target && ["INPUT", "SELECT"].includes(event.target.tagName)) {{
        return;
      }}
      if (event.key === "ArrowRight") {{
        step(1);
      }} else if (event.key === "ArrowLeft") {{
        step(-1);
      }} else if (event.key === "Home") {{
        state.index = 0;
        renderCurrent();
      }} else if (event.key === "End") {{
        const list = currentItems();
        if (!list.length) {{
          return;
        }}
        state.index = list.length - 1;
        renderCurrent();
      }}
    }});

    renderCurrent();
  </script>
</body>
</html>
"""


def build_label_viewer(root: Path, output_path: Path | None = None, splits: tuple[str, ...] = DEFAULT_DATASET_SPLITS) -> Path:
    viewer_items = viewer_items_from_review_manifest(root, splits)
    if not viewer_items:
        viewer_items = viewer_items_from_dataset(root, splits)
    if not viewer_items:
        raise SystemExit(f"No dataset images found under '{root}'.")

    resolved_output = output_path or (root / "label_overlay_viewer.html")
    resolved_output.write_text(build_label_viewer_html(root, viewer_items), encoding="utf-8")
    return resolved_output


def main() -> None:
    parser = argparse.ArgumentParser(description="Dataset cleanup and preparation utilities")
    subparsers = parser.add_subparsers(dest="command", required=True)

    audit_parser = subparsers.add_parser("audit", help="Summarize a prepared train/val dataset")
    audit_parser.add_argument("--root", default="dataset", help="Prepared dataset root")

    clean_parser = subparsers.add_parser(
        "clean-orphans", help="Remove label files that do not have a matching image"
    )
    clean_parser.add_argument("--root", default="dataset", help="Prepared dataset root")
    clean_parser.add_argument("--apply", action="store_true", help="Delete orphan labels")

    viewer_parser = subparsers.add_parser(
        "build-label-viewer",
        help="Generate a static HTML viewer for a labeled dataset with overlay boxes",
    )
    viewer_parser.add_argument("--root", default="dataset", help="Prepared dataset root")
    viewer_parser.add_argument(
        "--output",
        help="Output HTML path. Defaults to <root>/label_overlay_viewer.html",
    )
    viewer_parser.add_argument(
        "--splits",
        type=parse_split_list,
        default=DEFAULT_DATASET_SPLITS,
        help="Comma-separated dataset splits to include in the viewer",
    )

    prepare_parser = subparsers.add_parser(
        "prepare-v4",
        help="Build the v4 tune/all datasets from legacy labels plus a reviewed capture session",
    )
    prepare_parser.add_argument("--legacy-root", default="dataset", help="Legacy dataset root")
    prepare_parser.add_argument(
        "--captures-root",
        default="dataset/captures",
        help="Directory containing reviewed capture sessions",
    )
    prepare_parser.add_argument(
        "--session",
        default="tennis-court-passing-and-shooting",
        help="Capture session to merge into v4",
    )
    prepare_parser.add_argument(
        "--tune-output-root",
        default="dataset_prepared_v4_tune",
        help="Destination for the tune dataset",
    )
    prepare_parser.add_argument(
        "--all-output-root",
        default="dataset_prepared_v4_all",
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
    elif args.command == "build-label-viewer":
        output_path = build_label_viewer(
            root=Path(args.root),
            output_path=Path(args.output) if args.output else None,
            splits=args.splits,
        )
        print(f"Label viewer written to '{output_path}'.")
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
