from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

import numpy as np

from ball_tracker_tracking import BallTrack

POSE_MODEL_PATH = "yolo11n-pose.pt"
POSE_CONF_THRESHOLD = 0.35
POSE_IMG_SIZE = 640
POSE_KEYPOINT_CONF_THRESHOLD = 0.35
POSE_SMOOTHING = 0.55
POSE_STALE_SECONDS = 0.20
POSE_HIGH_KNEE_SWITCH_PIXELS = 18.0

POSE_CONTACT_RADIUS_MULTIPLIERS = {
    "left_ankle": 2.0,
    "right_ankle": 2.0,
    "left_knee": 2.4,
    "right_knee": 2.4,
    "head": 2.8,
}

POSE_CONTACT_DISPLAY_NAMES = {
    "left_ankle": "L ankle",
    "right_ankle": "R ankle",
    "left_knee": "L knee",
    "right_knee": "R knee",
    "head": "Head",
}

_KEYPOINT_INDEX = {
    "head": 0,
    "left_knee": 13,
    "right_knee": 14,
    "left_ankle": 15,
    "right_ankle": 16,
}

_KNEE_KEYS = ("left_knee", "right_knee")
_ANKLE_KEYS = ("left_ankle", "right_ankle")
_CONTACT_KEYS = tuple(POSE_CONTACT_RADIUS_MULTIPLIERS)


@dataclass(frozen=True)
class PoseContactCandidate:
    name: str
    display_name: str
    point: np.ndarray
    confidence: float
    distance: float
    threshold: float

    @property
    def is_valid(self) -> bool:
        return self.distance <= self.threshold


@dataclass(frozen=True)
class PoseFrame:
    available: bool = False
    source: str = "none"
    keypoints: dict[str, np.ndarray] = field(default_factory=dict)
    confidences: dict[str, float] = field(default_factory=dict)
    box: Optional[tuple[float, float, float, float]] = None
    box_confidence: float = 0.0
    knee_line_y: Optional[float] = None
    ground_y: Optional[float] = None
    age_seconds: float = 0.0
    nearest_contact: Optional[PoseContactCandidate] = None
    contact_candidates: tuple[PoseContactCandidate, ...] = ()

    @property
    def live(self) -> bool:
        return self.source == "live" and self.available

    @property
    def stale(self) -> bool:
        return self.source == "held" and self.available


@dataclass
class PoseState:
    keypoints: dict[str, np.ndarray] = field(default_factory=dict)
    confidences: dict[str, float] = field(default_factory=dict)
    box: Optional[tuple[float, float, float, float]] = None
    box_confidence: float = 0.0
    last_live_at: Optional[float] = None


@dataclass(frozen=True)
class _PosePerson:
    box: tuple[float, float, float, float]
    box_confidence: float
    keypoints: dict[str, np.ndarray]
    confidences: dict[str, float]


def update_pose_state(
    state: Optional[PoseState],
    pose_results,
    ball_track: Optional[BallTrack],
    frame_size: tuple[int, int],
    timestamp: float,
) -> tuple[PoseState, PoseFrame]:
    state = state or PoseState()
    people = _extract_people(pose_results)

    if people:
        selected = max(people, key=lambda person: _score_person(person, ball_track))
        state.keypoints = _smooth_keypoints(state.keypoints, selected.keypoints)
        state.confidences = dict(selected.confidences)
        state.box = selected.box
        state.box_confidence = selected.box_confidence
        state.last_live_at = timestamp
        pose_frame = _build_pose_frame(
            state,
            source="live",
            frame_size=frame_size,
            age_seconds=0.0,
            ball_track=ball_track,
        )
        return state, pose_frame

    if state.last_live_at is not None and timestamp - state.last_live_at <= POSE_STALE_SECONDS:
        pose_frame = _build_pose_frame(
            state,
            source="held",
            frame_size=frame_size,
            age_seconds=timestamp - state.last_live_at,
            ball_track=ball_track,
        )
        return state, pose_frame

    return state, PoseFrame()


def _extract_people(results) -> list[_PosePerson]:
    if not results:
        return []

    result = results[0]
    boxes = getattr(result, "boxes", None)
    keypoints = getattr(result, "keypoints", None)
    if boxes is None or keypoints is None or not len(boxes):
        return []

    boxes_xyxy = boxes.xyxy.cpu().numpy()
    box_confidences = (
        boxes.conf.cpu().numpy()
        if getattr(boxes, "conf", None) is not None
        else np.ones(len(boxes_xyxy), dtype=np.float32)
    )
    keypoint_xy = keypoints.xy.cpu().numpy()
    keypoint_conf = (
        keypoints.conf.cpu().numpy()
        if getattr(keypoints, "conf", None) is not None
        else np.ones(keypoint_xy.shape[:2], dtype=np.float32)
    )

    people: list[_PosePerson] = []
    for index in range(min(len(boxes_xyxy), len(keypoint_xy))):
        raw_points: dict[str, np.ndarray] = {}
        raw_confidences: dict[str, float] = {}
        for name, keypoint_index in _KEYPOINT_INDEX.items():
            confidence = float(keypoint_conf[index][keypoint_index])
            if confidence < POSE_KEYPOINT_CONF_THRESHOLD:
                continue
            raw_points[name] = np.array(keypoint_xy[index][keypoint_index], dtype=np.float32)
            raw_confidences[name] = confidence

        x1, y1, x2, y2 = (float(value) for value in boxes_xyxy[index].tolist())
        people.append(
            _PosePerson(
                box=(x1, y1, x2, y2),
                box_confidence=float(box_confidences[index]),
                keypoints=raw_points,
                confidences=raw_confidences,
            )
        )

    return people


def _score_person(person: _PosePerson, ball_track: Optional[BallTrack]) -> float:
    score = person.box_confidence
    if "left_ankle" in person.keypoints or "right_ankle" in person.keypoints:
        score += 0.25
    if "left_knee" in person.keypoints or "right_knee" in person.keypoints:
        score += 0.25

    if ball_track is None:
        return score

    x1, y1, x2, y2 = person.box
    ball_x = float(ball_track.center[0])
    ball_y = float(ball_track.center[1])
    if x1 <= ball_x <= x2 and y1 <= ball_y <= y2:
        score += 3.0

    box_center = np.array(((x1 + x2) / 2.0, (y1 + y2) / 2.0), dtype=np.float32)
    box_size = np.array((x2 - x1, y2 - y1), dtype=np.float32)
    normalizer = max(float(np.linalg.norm(box_size)), 1.0)
    distance = float(np.linalg.norm(box_center - ball_track.center))
    score += max(0.0, 1.5 - distance / normalizer)
    return score


def _smooth_keypoints(
    previous: dict[str, np.ndarray],
    current: dict[str, np.ndarray],
) -> dict[str, np.ndarray]:
    smoothed: dict[str, np.ndarray] = {}
    for name, point in current.items():
        earlier = previous.get(name)
        if earlier is None:
            smoothed[name] = point.copy()
            continue
        smoothed[name] = earlier * (1.0 - POSE_SMOOTHING) + point * POSE_SMOOTHING
    return smoothed


def _build_pose_frame(
    state: PoseState,
    *,
    source: str,
    frame_size: tuple[int, int],
    age_seconds: float,
    ball_track: Optional[BallTrack],
) -> PoseFrame:
    del frame_size
    knee_line_y = _knee_line_y(state.keypoints)
    ground_y = _max_axis(state.keypoints, _ANKLE_KEYS, axis=1)
    available = knee_line_y is not None and ground_y is not None and bool(state.keypoints)
    candidates = _contact_candidates(state.keypoints, state.confidences, ball_track)
    nearest_contact = None
    valid_candidates = [candidate for candidate in candidates if candidate.is_valid]
    if valid_candidates:
        nearest_contact = valid_candidates[0]
    elif candidates:
        nearest_contact = candidates[0]

    return PoseFrame(
        available=available,
        source=source if available else "none",
        keypoints={name: point.copy() for name, point in state.keypoints.items()},
        confidences=dict(state.confidences),
        box=state.box,
        box_confidence=state.box_confidence,
        knee_line_y=knee_line_y,
        ground_y=ground_y,
        age_seconds=max(age_seconds, 0.0),
        nearest_contact=nearest_contact,
        contact_candidates=tuple(candidates),
    )


def _contact_candidates(
    keypoints: dict[str, np.ndarray],
    confidences: dict[str, float],
    ball_track: Optional[BallTrack],
) -> list[PoseContactCandidate]:
    if ball_track is None:
        return []

    candidates: list[PoseContactCandidate] = []
    ball_center = ball_track.center
    for name in _CONTACT_KEYS:
        point = keypoints.get(name)
        if point is None:
            continue
        confidence = float(confidences.get(name, 0.0))
        threshold = max(
            float(ball_track.radius) * POSE_CONTACT_RADIUS_MULTIPLIERS[name],
            12.0,
        )
        distance = float(np.linalg.norm(point - ball_center))
        candidates.append(
            PoseContactCandidate(
                name=name,
                display_name=POSE_CONTACT_DISPLAY_NAMES[name],
                point=point.copy(),
                confidence=confidence,
                distance=distance,
                threshold=threshold,
            )
        )

    candidates.sort(
        key=lambda candidate: (
            0 if candidate.is_valid else 1,
            candidate.distance / max(candidate.threshold, 1e-6),
            candidate.distance,
        )
    )
    return candidates


def _mean_axis(
    keypoints: dict[str, np.ndarray],
    names: tuple[str, ...],
    *,
    axis: int,
) -> Optional[float]:
    values = [float(keypoints[name][axis]) for name in names if name in keypoints]
    if not values:
        return None
    return float(sum(values) / len(values))


def _knee_line_y(keypoints: dict[str, np.ndarray]) -> Optional[float]:
    knees = [float(keypoints[name][1]) for name in _KNEE_KEYS if name in keypoints]
    if not knees:
        return None
    if len(knees) == 1:
        return knees[0]

    higher_knee = min(knees)
    lower_knee = max(knees)
    if lower_knee - higher_knee >= POSE_HIGH_KNEE_SWITCH_PIXELS:
        return higher_knee
    return float(sum(knees) / len(knees))


def _max_axis(
    keypoints: dict[str, np.ndarray],
    names: tuple[str, ...],
    *,
    axis: int,
) -> Optional[float]:
    values = [float(keypoints[name][axis]) for name in names if name in keypoints]
    if not values:
        return None
    return float(max(values))
