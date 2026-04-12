from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path

LABEL_OPTIONS = ("foot", "knee", "thigh", "ground", "other", "ambiguous-skip")


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
    label: str = ""
    review_status: str = "pending"

    def to_dict(self) -> dict:
        payload = asdict(self)
        payload["event_time"] = round(self.event_time, 6)
        payload["predicted_confidence"] = round(self.predicted_confidence, 6)
        payload["probabilities"] = {
            key: round(float(value), 6) for key, value in sorted(self.probabilities.items())
        }
        return payload

    @classmethod
    def from_dict(cls, payload: dict) -> "JuggleCandidateRecord":
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
            label=str(payload.get("label", "")),
            review_status=str(payload.get("review_status", "pending")),
        )


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
        if record.label in LABEL_OPTIONS and record.label != "ambiguous-skip"
    ]
