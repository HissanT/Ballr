from __future__ import annotations

import json
import shutil
from dataclasses import asdict, dataclass
from pathlib import Path

EVENT_LABEL_OPTIONS = ("count", "hand", "ground", "other", "ambiguous-skip")
BODY_PART_LABEL_OPTIONS = ("foot", "knee", "hip", "unknown")
LEGACY_LABEL_OPTIONS = ("foot", "knee", "hip", "thigh", "ground", "other", "ambiguous-skip")


def normalize_event_label(event_label: str, body_part_label: str = "") -> tuple[str, str]:
    normalized_event = str(event_label or "").strip().lower()
    normalized_body_part = str(body_part_label or "").strip().lower()

    if normalized_event == "count":
        if normalized_body_part not in BODY_PART_LABEL_OPTIONS:
            normalized_body_part = "unknown"
        return normalized_event, normalized_body_part

    if normalized_event in {"hand", "ground", "other", "ambiguous-skip"}:
        return normalized_event, ""

    if normalized_event in {"foot", "knee", "hip", "thigh"}:
        mapped_body_part = normalized_event if normalized_event in BODY_PART_LABEL_OPTIONS else "unknown"
        return "count", mapped_body_part

    return "", ""


@dataclass
class JuggleCandidateRecord:
    candidate_id: str
    session_name: str
    source: str
    event_frame_index: int
    event_time: float
    clip_relpath: str
    features_relpath: str
    predicted_class: str
    predicted_confidence: float
    probabilities: dict[str, float]
    predicted_event_label: str = ""
    predicted_body_part_label: str = ""
    event_label: str = ""
    body_part_label: str = ""
    label_quality: str = "clear"
    review_status: str = "pending"

    def to_dict(self) -> dict:
        predicted_event_label, predicted_body_part_label = normalize_event_label(
            self.predicted_event_label or self.predicted_class,
            self.predicted_body_part_label,
        )
        event_label, body_part_label = normalize_event_label(
            self.event_label or getattr(self, "label", ""),
            self.body_part_label,
        )
        self.predicted_event_label = predicted_event_label
        self.predicted_body_part_label = predicted_body_part_label
        self.event_label = event_label
        self.body_part_label = body_part_label
        payload = asdict(self)
        payload["event_time"] = round(self.event_time, 6)
        payload["predicted_confidence"] = round(self.predicted_confidence, 6)
        payload["probabilities"] = {
            key: round(float(value), 6) for key, value in sorted(self.probabilities.items())
        }
        payload["label"] = (
            body_part_label if event_label == "count" and body_part_label in BODY_PART_LABEL_OPTIONS else event_label
        )
        return payload

    @classmethod
    def from_dict(cls, payload: dict) -> "JuggleCandidateRecord":
        event_label, body_part_label = normalize_event_label(
            str(payload.get("event_label", payload.get("label", ""))),
            str(payload.get("body_part_label", "")),
        )
        predicted_event_label, predicted_body_part_label = normalize_event_label(
            str(payload.get("predicted_event_label", payload.get("predicted_class", ""))),
            str(payload.get("predicted_body_part_label", "")),
        )
        return cls(
            candidate_id=str(payload["candidate_id"]),
            session_name=str(payload["session_name"]),
            source=str(payload["source"]),
            event_frame_index=int(payload["event_frame_index"]),
            event_time=float(payload["event_time"]),
            clip_relpath=str(payload["clip_relpath"]),
            features_relpath=str(payload["features_relpath"]),
            predicted_class=str(payload["predicted_class"]),
            predicted_confidence=float(payload["predicted_confidence"]),
            probabilities={str(key): float(value) for key, value in dict(payload["probabilities"]).items()},
            predicted_event_label=predicted_event_label,
            predicted_body_part_label=predicted_body_part_label,
            event_label=event_label,
            body_part_label=body_part_label,
            label_quality=str(payload.get("label_quality", "clear")),
            review_status=str(payload.get("review_status", "pending")),
        )

    @property
    def label(self) -> str:
        if self.event_label == "count":
            return self.body_part_label or "unknown"
        return self.event_label

    @label.setter
    def label(self, value: str) -> None:
        self.event_label, self.body_part_label = normalize_event_label(value)

    @property
    def training_event_label(self) -> str:
        return self.event_label


def manifest_path(root: Path) -> Path:
    return root / "manifest.jsonl"


def load_manifest(path: Path) -> list[JuggleCandidateRecord]:
    if not path.exists():
        return []
    records: list[JuggleCandidateRecord] = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        if not raw_line.strip():
            continue
        records.append(JuggleCandidateRecord.from_dict(json.loads(raw_line)))
    return records


def save_manifest(path: Path, records: list[JuggleCandidateRecord]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record.to_dict(), sort_keys=True) + "\n")


def labeled_records(records: list[JuggleCandidateRecord]) -> list[JuggleCandidateRecord]:
    return [
        record
        for record in records
        if record.training_event_label in EVENT_LABEL_OPTIONS and record.training_event_label != "ambiguous-skip"
    ]


def merge_session_roots(
    session_roots: list[Path],
    output_root: Path,
    *,
    reviewed_only: bool = True,
) -> list[JuggleCandidateRecord]:
    clips_dir = output_root / "clips"
    features_dir = output_root / "features"
    clips_dir.mkdir(parents=True, exist_ok=True)
    features_dir.mkdir(parents=True, exist_ok=True)

    merged_records: list[JuggleCandidateRecord] = []
    seen_candidate_ids: set[str] = set()

    for session_root in session_roots:
        records = load_manifest(manifest_path(session_root))
        for record in records:
            if reviewed_only and record.review_status != "reviewed":
                continue
            if record.candidate_id in seen_candidate_ids:
                continue

            source_clip_path = session_root / record.clip_relpath
            source_features_path = session_root / record.features_relpath
            if not source_clip_path.is_file() or not source_features_path.is_file():
                continue

            clip_filename = f"{record.session_name}__{source_clip_path.name}"
            features_filename = f"{record.session_name}__{source_features_path.name}"
            output_clip_path = clips_dir / clip_filename
            output_features_path = features_dir / features_filename
            shutil.copy2(source_clip_path, output_clip_path)
            shutil.copy2(source_features_path, output_features_path)

            merged_records.append(
                JuggleCandidateRecord(
                    candidate_id=record.candidate_id,
                    session_name=record.session_name,
                    source=record.source,
                    event_frame_index=record.event_frame_index,
                    event_time=record.event_time,
                    clip_relpath=str(output_clip_path.relative_to(output_root)),
                    features_relpath=str(output_features_path.relative_to(output_root)),
                    predicted_class=record.predicted_class,
                    predicted_confidence=record.predicted_confidence,
                    probabilities=dict(record.probabilities),
                    predicted_event_label=record.predicted_event_label,
                    predicted_body_part_label=record.predicted_body_part_label,
                    event_label=record.event_label,
                    body_part_label=record.body_part_label,
                    label_quality=record.label_quality,
                    review_status=record.review_status,
                )
            )
            seen_candidate_ids.add(record.candidate_id)

    save_manifest(manifest_path(output_root), merged_records)
    return merged_records
