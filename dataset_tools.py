import argparse
import random
import shutil
from collections import Counter
from pathlib import Path


IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png")


def image_paths(image_dir: Path) -> list[Path]:
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


def summarize_split(root: Path, split: str) -> dict:
    image_dir = root / "images" / split
    label_dir = root / "labels" / split
    images = image_paths(image_dir)
    labels = sorted(label_dir.glob("*.txt"))
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
        insert_at = 0
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


def capture_sessions(captures_root: Path) -> list[Path]:
    sessions: list[Path] = []
    for session_dir in sorted(captures_root.iterdir()):
        if not session_dir.is_dir():
            continue
        image_dir = session_dir / "images"
        label_dir = session_dir / "labels"
        if image_dir.exists() and label_dir.exists():
            sessions.append(session_dir)
    return sessions


def session_pairs(session_dir: Path) -> list[tuple[Path, Path]]:
    pairs: list[tuple[Path, Path]] = []
    image_dir = session_dir / "images"
    label_dir = session_dir / "labels"
    for image_path in image_paths(image_dir):
        label_path = label_dir / f"{image_path.stem}.txt"
        if label_path.exists():
            pairs.append((image_path, label_path))
    return pairs


def write_data_yaml(output_root: Path) -> None:
    content = "\n".join(
        [
            f"path: {output_root.as_posix()}",
            "train: images/train",
            "val: images/val",
            "",
            "nc: 1",
            "names:",
            "  0: soccer-ball",
            "",
        ]
    )
    (output_root / "data.yaml").write_text(content, encoding="utf-8")


def build_splits(captures_root: Path, output_root: Path, val_ratio: float, seed: int) -> None:
    sessions = capture_sessions(captures_root)
    if not sessions:
        raise SystemExit(f"No capture sessions found under '{captures_root}'.")

    if output_root.exists() and any(output_root.iterdir()):
        raise SystemExit(
            f"Output directory '{output_root}' already exists and is not empty. "
            "Use a fresh path to avoid overwriting prepared data."
        )

    rng = random.Random(seed)
    rng.shuffle(sessions)

    if len(sessions) == 1:
        val_count = 0
    else:
        val_count = max(1, round(len(sessions) * val_ratio))
        val_count = min(val_count, len(sessions) - 1)

    val_sessions = {session.name for session in sessions[:val_count]}
    split_counts = Counter()

    for split in ("train", "val"):
        (output_root / "images" / split).mkdir(parents=True, exist_ok=True)
        (output_root / "labels" / split).mkdir(parents=True, exist_ok=True)

    for session_dir in sorted(sessions):
        split = "val" if session_dir.name in val_sessions else "train"
        for image_path, label_path in session_pairs(session_dir):
            shutil.copy2(image_path, output_root / "images" / split / image_path.name)
            shutil.copy2(label_path, output_root / "labels" / split / label_path.name)
            split_counts[split] += 1

    write_data_yaml(output_root)
    print(f"Prepared dataset written to '{output_root}'.")
    print(f"Sessions: total={len(sessions)} train={len(sessions) - val_count} val={val_count}")
    print(f"Samples: train={split_counts['train']} val={split_counts['val']}")
    print(f"Training config: {output_root / 'data.yaml'}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Dataset cleanup and split utilities")
    subparsers = parser.add_subparsers(dest="command", required=True)

    audit_parser = subparsers.add_parser("audit", help="Summarize a prepared train/val dataset")
    audit_parser.add_argument("--root", default="dataset", help="Prepared dataset root")

    clean_parser = subparsers.add_parser(
        "clean-orphans", help="Remove label files that do not have a matching image"
    )
    clean_parser.add_argument("--root", default="dataset", help="Prepared dataset root")
    clean_parser.add_argument("--apply", action="store_true", help="Delete orphan labels")

    build_parser = subparsers.add_parser(
        "build-splits",
        help="Build leak-free train/val splits from session-based captures",
    )
    build_parser.add_argument(
        "--captures-root",
        default="dataset/captures",
        help="Directory containing session capture folders",
    )
    build_parser.add_argument(
        "--output-root",
        default="dataset_prepared",
        help="Destination for the prepared train/val dataset",
    )
    build_parser.add_argument("--val-ratio", type=float, default=0.2, help="Session-level val split")
    build_parser.add_argument("--seed", type=int, default=0, help="Shuffle seed")

    args = parser.parse_args()
    if args.command == "audit":
        audit_dataset(Path(args.root))
    elif args.command == "clean-orphans":
        clean_orphans(Path(args.root), apply=args.apply)
    elif args.command == "build-splits":
        build_splits(Path(args.captures_root), Path(args.output_root), args.val_ratio, args.seed)


if __name__ == "__main__":
    main()
