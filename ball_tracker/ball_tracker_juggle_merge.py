from __future__ import annotations

import argparse
from pathlib import Path

from common.ballr_utils import training_path
from .ball_tracker_juggle_dataset import merge_session_roots


def main() -> None:
    parser = argparse.ArgumentParser(description="Merge reviewed juggle candidate sessions into one training root")
    parser.add_argument(
        "--input-root",
        default=str(training_path("dataset", "juggle_candidates")),
        help="Root containing per-session juggle candidate folders",
    )
    parser.add_argument(
        "--output",
        default=str(training_path("dataset", "juggle_candidates_merged")),
        help="Merged output root containing one manifest.jsonl",
    )
    parser.add_argument(
        "--include-pending",
        action="store_true",
        help="Include pending records instead of only reviewed items",
    )
    parser.add_argument(
        "--sessions",
        nargs="*",
        help="Optional explicit session folder names to merge. Defaults to all child folders with a manifest.",
    )
    args = parser.parse_args()

    input_root = Path(args.input_root)
    output_root = Path(args.output)
    if args.sessions:
        session_roots = [input_root / session_name for session_name in args.sessions]
    else:
        session_roots = sorted(
            session_root
            for session_root in input_root.iterdir()
            if session_root.is_dir() and (session_root / "manifest.jsonl").is_file()
        )

    if not session_roots:
        raise SystemExit(f"No session manifests found under '{input_root}'.")

    merged_records = merge_session_roots(
        session_roots,
        output_root,
        reviewed_only=not args.include_pending,
    )
    print(f"Merged {len(merged_records)} records into '{output_root}'.")


if __name__ == "__main__":
    main()
