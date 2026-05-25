import shutil
from pathlib import Path
from uuid import uuid4

import pytest

from ball_tracker_juggle_dataset import (
    JuggleCandidateRecord,
    labeled_records,
    load_manifest,
    manifest_path,
    save_manifest,
)


@pytest.fixture
def workspace_tmp() -> Path:
    root = Path.cwd() / f"juggle_dataset_{uuid4().hex}"
    root.mkdir(parents=True, exist_ok=False)
    try:
        yield root
    finally:
        shutil.rmtree(root, ignore_errors=True)


def test_manifest_round_trip(workspace_tmp: Path):
    root = workspace_tmp / "juggle"
    records = [
        JuggleCandidateRecord(
            candidate_id="sample_001",
            session_name="session_a",
            source="clip.mp4",
            event_frame_index=42,
            event_time=1.4,
            clip_relpath="clips/sample_001.mp4",
            features_relpath="features/sample_001.npz",
            predicted_class="ground",
            predicted_confidence=0.88,
            probabilities={"foot": 0.01, "ground": 0.88, "other": 0.11},
            label="ground",
            review_status="reviewed",
        )
    ]

    save_manifest(manifest_path(root), records)
    loaded = load_manifest(manifest_path(root))

    assert [record.to_dict() for record in loaded] == [record.to_dict() for record in records]


def test_labeled_records_excludes_ambiguous_skip():
    records = [
        JuggleCandidateRecord(
            candidate_id="keep",
            session_name="s",
            source="x",
            event_frame_index=1,
            event_time=0.1,
            clip_relpath="clips/keep.mp4",
            features_relpath="features/keep.npz",
            predicted_class="foot",
            predicted_confidence=0.7,
            probabilities={"foot": 0.7},
            label="foot",
            review_status="reviewed",
        ),
        JuggleCandidateRecord(
            candidate_id="skip",
            session_name="s",
            source="x",
            event_frame_index=2,
            event_time=0.2,
            clip_relpath="clips/skip.mp4",
            features_relpath="features/skip.npz",
            predicted_class="other",
            predicted_confidence=0.6,
            probabilities={"other": 0.6},
            label="ambiguous-skip",
            review_status="reviewed",
        ),
    ]

    assert [record.candidate_id for record in labeled_records(records)] == ["keep"]
