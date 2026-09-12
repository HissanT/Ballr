import shutil
from pathlib import Path
from uuid import uuid4

import pytest

from ball_tracker.ball_tracker_juggle_dataset import (
    JuggleCandidateRecord,
    labeled_records,
    load_manifest,
    manifest_path,
    merge_session_roots,
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
            predicted_event_label="ground",
            event_label="ground",
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
            predicted_event_label="count",
            predicted_body_part_label="foot",
            event_label="count",
            body_part_label="foot",
            review_status="reviewed",
        ),
        JuggleCandidateRecord(
            candidate_id="keep_hip",
            session_name="s",
            source="x",
            event_frame_index=3,
            event_time=0.3,
            clip_relpath="clips/keep_hip.mp4",
            features_relpath="features/keep_hip.npz",
            predicted_class="hip",
            predicted_confidence=0.82,
            probabilities={"hip": 0.82},
            predicted_event_label="count",
            predicted_body_part_label="hip",
            event_label="count",
            body_part_label="hip",
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
            predicted_event_label="other",
            event_label="ambiguous-skip",
            review_status="reviewed",
        ),
    ]

    assert [record.candidate_id for record in labeled_records(records)] == ["keep", "keep_hip"]


def test_load_manifest_migrates_legacy_flat_labels(workspace_tmp: Path):
    root = workspace_tmp / "legacy"
    path = manifest_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        '{"candidate_id":"sample","session_name":"s","source":"clip.mp4","event_frame_index":12,'
        '"event_time":0.4,"clip_relpath":"clips/sample.mp4","features_relpath":"features/sample.npz",'
        '"predicted_class":"foot","predicted_confidence":0.9,"probabilities":{"foot":0.9},"label":"foot",'
        '"review_status":"reviewed"}\n',
        encoding="utf-8",
    )

    [record] = load_manifest(path)

    assert record.predicted_event_label == "count"
    assert record.predicted_body_part_label == "foot"
    assert record.event_label == "count"
    assert record.body_part_label == "foot"


def test_merge_session_roots_copies_reviewed_items(workspace_tmp: Path):
    input_root = workspace_tmp / "input"
    session_a = input_root / "session_a"
    session_b = input_root / "session_b"
    for session_root in (session_a, session_b):
        (session_root / "clips").mkdir(parents=True, exist_ok=True)
        (session_root / "features").mkdir(parents=True, exist_ok=True)

    (session_a / "clips" / "a.mp4").write_bytes(b"a")
    (session_a / "features" / "a.npz").write_bytes(b"fa")
    (session_b / "clips" / "b.mp4").write_bytes(b"b")
    (session_b / "features" / "b.npz").write_bytes(b"fb")

    save_manifest(
        manifest_path(session_a),
        [
            JuggleCandidateRecord(
                candidate_id="a1",
                session_name="session_a",
                source="0",
                event_frame_index=10,
                event_time=0.33,
                clip_relpath="clips/a.mp4",
                features_relpath="features/a.npz",
                predicted_class="foot",
                predicted_confidence=0.8,
                probabilities={"foot": 0.8},
                predicted_event_label="count",
                predicted_body_part_label="foot",
                event_label="count",
                body_part_label="foot",
                review_status="reviewed",
            )
        ],
    )
    save_manifest(
        manifest_path(session_b),
        [
            JuggleCandidateRecord(
                candidate_id="b1",
                session_name="session_b",
                source="0",
                event_frame_index=11,
                event_time=0.36,
                clip_relpath="clips/b.mp4",
                features_relpath="features/b.npz",
                predicted_class="other",
                predicted_confidence=0.7,
                probabilities={"other": 0.7},
                predicted_event_label="other",
                event_label="other",
                review_status="pending",
            )
        ],
    )

    output_root = workspace_tmp / "merged"
    merged_records = merge_session_roots([session_a, session_b], output_root, reviewed_only=True)

    assert [record.candidate_id for record in merged_records] == ["a1"]
    assert (output_root / "clips" / "session_a__a.mp4").is_file()
    assert (output_root / "features" / "session_a__a.npz").is_file()
    [loaded_record] = load_manifest(manifest_path(output_root))
    assert loaded_record.clip_relpath == "clips\\session_a__a.mp4" or loaded_record.clip_relpath == "clips/session_a__a.mp4"
    assert loaded_record.features_relpath == "features\\session_a__a.npz" or loaded_record.features_relpath == "features/session_a__a.npz"
