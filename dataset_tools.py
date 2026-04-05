import argparse
import shutil
from collections import Counter
from pathlib import Path


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
    audit_parser.add_argument("--root", default="dataset", help="Prepared dataset root")

    clean_parser = subparsers.add_parser(
        "clean-orphans", help="Remove label files that do not have a matching image"
    )
    clean_parser.add_argument("--root", default="dataset", help="Prepared dataset root")
    clean_parser.add_argument("--apply", action="store_true", help="Delete orphan labels")

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
