from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Optional

import numpy as np

from common.ballr_utils import model_path
from ball_tracker_tracking import BallTrack

POSE_MODEL_PATH = str(model_path("yolo11n-pose.pt"))
POSE_CONF_THRESHOLD = 0.35
POSE_IMG_SIZE = 640
POSE_KEYPOINT_CONF_THRESHOLD = 0.35
POSE_STALE_SECONDS = 0.20
POSE_HIGH_KNEE_SWITCH_PIXELS = 18.0
POSE_SMOOTHING = 0.55

POSE_BACKEND_AUTO = "auto"
POSE_BACKEND_MEDIAPIPE = "mediapipe"
POSE_BACKEND_YOLO = "yolo"
POSE_BACKEND_CHOICES = (POSE_BACKEND_AUTO, POSE_BACKEND_MEDIAPIPE, POSE_BACKEND_YOLO)

POSE_CONTACT_RADIUS_MULTIPLIERS = {
    "left_ankle": 2.0,
    "right_ankle": 2.0,
    "left_knee": 2.4,
    "right_knee": 2.4,
    "left_thigh": 2.8,
    "right_thigh": 2.8,
}

POSE_CONTACT_DISPLAY_NAMES = {
    "left_ankle": "L foot",
    "right_ankle": "R foot",
    "left_knee": "L knee",
    "right_knee": "R knee",
    "left_thigh": "L thigh",
    "right_thigh": "R thigh",
}

POSE_CONTACT_KINDS = {
    "left_ankle": "foot",
    "right_ankle": "foot",
    "left_knee": "knee",
    "right_knee": "knee",
    "left_thigh": "thigh",
    "right_thigh": "thigh",
}

_YOLO_KEYPOINT_INDEX = {
    "left_hip": 11,
    "right_hip": 12,
    "left_knee": 13,
    "right_knee": 14,
    "left_ankle": 15,
    "right_ankle": 16,
}

_MEDIAPIPE_KEYPOINT_INDEX = {
    "left_hip": 23,
    "right_hip": 24,
    "left_knee": 25,
    "right_knee": 26,
    "left_ankle": 27,
    "right_ankle": 28,
    "left_foot_index": 31,
    "right_foot_index": 32,
}

_KNEE_KEYS = ("left_knee", "right_knee")
_GROUND_KEYS = ("left_ankle", "right_ankle", "left_foot_index", "right_foot_index")
_PRIMARY_KEYS = ("left_hip", "right_hip", "left_knee", "right_knee", "left_ankle", "right_ankle")


@dataclass(frozen=True)
class PoseContactCandidate:
    name: str
    display_name: str
    kind: str
    confidence: float
    distance: float
    threshold: float
    point: Optional[np.ndarray] = None
    segment_start: Optional[np.ndarray] = None
    segment_end: Optional[np.ndarray] = None

    @property
    def is_valid(self) -> bool:
        return self.distance <= self.threshold


@dataclass(frozen=True)
class PoseFrame:
    available: bool = False
    source: str = "none"
    backend: str = "none"
    quality: float = 0.0
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

    @property
    def has_contact_geometry(self) -> bool:
        return bool(self.contact_candidates)

    @property
    def has_reference_geometry(self) -> bool:
        return self.ground_y is not None or self.knee_line_y is not None


@dataclass
class PoseState:
    keypoints: dict[str, np.ndarray] = field(default_factory=dict)
    confidences: dict[str, float] = field(default_factory=dict)
    box: Optional[tuple[float, float, float, float]] = None
    box_confidence: float = 0.0
    backend: str = "none"
    quality: float = 0.0
    last_live_at: Optional[float] = None


@dataclass(frozen=True)
class PoseObservation:
    provider: str
    keypoints: dict[str, np.ndarray]
    confidences: dict[str, float]
    box: Optional[tuple[float, float, float, float]] = None
    box_confidence: float = 0.0


@dataclass(frozen=True)
class PoseBackendResults:
    yolo_people: tuple[PoseObservation, ...] = ()
    mediapipe_person: Optional[PoseObservation] = None


@dataclass
class PoseRuntimeContext:
    backend_mode: str
    yolo_model: Any = None
    yolo_predict_kwargs: Optional[dict[str, Any]] = None
    mediapipe_pose: Any = None
    mediapipe_available: bool = False
    mediapipe_variant: str = "none"


def create_pose_runtime(
    backend_mode: str,
    *,
    yolo_model=None,
    yolo_predict_kwargs: Optional[dict[str, Any]] = None,
) -> PoseRuntimeContext:
    normalized_backend = str(backend_mode).lower()
    if normalized_backend not in POSE_BACKEND_CHOICES:
        raise ValueError(f"Unsupported pose backend: {backend_mode}")

    runtime = PoseRuntimeContext(
        backend_mode=normalized_backend,
        yolo_model=yolo_model,
        yolo_predict_kwargs=yolo_predict_kwargs,
    )

    if normalized_backend in {POSE_BACKEND_AUTO, POSE_BACKEND_MEDIAPIPE}:
        try:
            import mediapipe as mp
        except ImportError:
            runtime.mediapipe_pose = None
            runtime.mediapipe_available = False
        else:
            solutions = getattr(mp, "solutions", None)
            pose_namespace = getattr(solutions, "pose", None) if solutions is not None else None
            pose_ctor = getattr(pose_namespace, "Pose", None) if pose_namespace is not None else None
            if callable(pose_ctor):
                runtime.mediapipe_pose = pose_ctor(
                    static_image_mode=False,
                    model_complexity=1,
                    enable_segmentation=False,
                    min_detection_confidence=0.4,
                    min_tracking_confidence=0.4,
                )
                runtime.mediapipe_available = True
                runtime.mediapipe_variant = "solutions"
            else:
                runtime.mediapipe_pose = None
                runtime.mediapipe_available = False
                runtime.mediapipe_variant = "tasks-only"

    return runtime


def close_pose_runtime(runtime: Optional[PoseRuntimeContext]) -> None:
    if runtime is None or runtime.mediapipe_pose is None:
        return

    close = getattr(runtime.mediapipe_pose, "close", None)
    if callable(close):
        close()


def infer_pose_backends(frame: np.ndarray, runtime: Optional[PoseRuntimeContext]) -> PoseBackendResults:
    if runtime is None:
        return PoseBackendResults()

    yolo_people: tuple[PoseObservation, ...] = ()
    mediapipe_person: Optional[PoseObservation] = None

    if runtime.backend_mode in {POSE_BACKEND_AUTO, POSE_BACKEND_YOLO}:
        if runtime.yolo_model is not None and runtime.yolo_predict_kwargs is not None:
            yolo_results = runtime.yolo_model.predict(frame, **runtime.yolo_predict_kwargs)
            yolo_people = tuple(_extract_yolo_people(yolo_results))

    if runtime.backend_mode in {POSE_BACKEND_AUTO, POSE_BACKEND_MEDIAPIPE} and runtime.mediapipe_available:
        mediapipe_person = _extract_mediapipe_person(frame, runtime.mediapipe_pose)

    return PoseBackendResults(yolo_people=yolo_people, mediapipe_person=mediapipe_person)


def update_pose_state(
    state: Optional[PoseState],
    pose_results,
    ball_track: Optional[BallTrack],
    frame_size: tuple[int, int],
    timestamp: float,
) -> tuple[PoseState, PoseFrame]:
    backend_results = PoseBackendResults(yolo_people=tuple(_extract_yolo_people(pose_results)))
    return update_pose_state_from_backends(state, backend_results, ball_track, frame_size, timestamp)


def update_pose_state_from_backends(
    state: Optional[PoseState],
    backend_results: Optional[PoseBackendResults],
    ball_track: Optional[BallTrack],
    frame_size: tuple[int, int],
    timestamp: float,
) -> tuple[PoseState, PoseFrame]:
    state = state or PoseState()
    backend_results = backend_results or PoseBackendResults()

    selected = _select_observation(backend_results, ball_track)
    if selected is not None:
        state.keypoints = _smooth_keypoints(state.keypoints, selected.keypoints)
        state.confidences = dict(selected.confidences)
        state.box = selected.box
        state.box_confidence = selected.box_confidence
        state.backend = selected.provider
        state.quality = _pose_quality(state.keypoints)
        state.last_live_at = timestamp
        return state, _build_pose_frame(
            state,
            source="live",
            frame_size=frame_size,
            age_seconds=0.0,
            ball_track=ball_track,
        )

    if state.last_live_at is not None and timestamp - state.last_live_at <= POSE_STALE_SECONDS:
        return state, _build_pose_frame(
            state,
            source="held",
            frame_size=frame_size,
            age_seconds=timestamp - state.last_live_at,
            ball_track=ball_track,
        )

    return state, PoseFrame()


def _extract_yolo_people(results) -> list[PoseObservation]:
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

    people: list[PoseObservation] = []
    for index in range(min(len(boxes_xyxy), len(keypoint_xy))):
        raw_points: dict[str, np.ndarray] = {}
        raw_confidences: dict[str, float] = {}
        for name, keypoint_index in _YOLO_KEYPOINT_INDEX.items():
            confidence = float(keypoint_conf[index][keypoint_index])
            if confidence < POSE_KEYPOINT_CONF_THRESHOLD:
                continue
            raw_points[name] = np.array(keypoint_xy[index][keypoint_index], dtype=np.float32)
            raw_confidences[name] = confidence

        x1, y1, x2, y2 = (float(value) for value in boxes_xyxy[index].tolist())
        people.append(
            PoseObservation(
                provider=POSE_BACKEND_YOLO,
                box=(x1, y1, x2, y2),
                box_confidence=float(box_confidences[index]),
                keypoints=raw_points,
                confidences=raw_confidences,
            )
        )

    return people


def _extract_mediapipe_person(frame: np.ndarray, pose_model) -> Optional[PoseObservation]:
    if pose_model is None:
        return None

    rgb_frame = frame[:, :, ::-1]
    results = pose_model.process(rgb_frame)
    landmarks = getattr(results, "pose_landmarks", None)
    if landmarks is None or not getattr(landmarks, "landmark", None):
        return None

    frame_h, frame_w = frame.shape[:2]
    keypoints: dict[str, np.ndarray] = {}
    confidences: dict[str, float] = {}
    for name, landmark_index in _MEDIAPIPE_KEYPOINT_INDEX.items():
        landmark = landmarks.landmark[landmark_index]
        visibility = float(getattr(landmark, "visibility", 0.0))
        presence = float(getattr(landmark, "presence", visibility))
        confidence = max(visibility, presence)
        if confidence < 0.35:
            continue
        x = float(np.clip(landmark.x, 0.0, 1.0) * frame_w)
        y = float(np.clip(landmark.y, 0.0, 1.0) * frame_h)
        keypoints[name] = np.array((x, y), dtype=np.float32)
        confidences[name] = confidence

    if not keypoints:
        return None

    xs = [float(point[0]) for point in keypoints.values()]
    ys = [float(point[1]) for point in keypoints.values()]
    box = (min(xs), min(ys), max(xs), max(ys))
    return PoseObservation(
        provider=POSE_BACKEND_MEDIAPIPE,
        keypoints=keypoints,
        confidences=confidences,
        box=box,
        box_confidence=float(np.mean(list(confidences.values()))),
    )


def _select_observation(
    backend_results: PoseBackendResults,
    ball_track: Optional[BallTrack],
) -> Optional[PoseObservation]:
    yolo_selected = None
    if backend_results.yolo_people:
        yolo_selected = max(
            backend_results.yolo_people,
            key=lambda observation: _score_observation(observation, ball_track),
        )

    mediapipe_selected = backend_results.mediapipe_person
    mediapipe_has_feet = _observation_has_feet(mediapipe_selected)

    if mediapipe_selected is not None and mediapipe_has_feet:
        if yolo_selected is not None:
            return _merge_observations(mediapipe_selected, yolo_selected)
        return mediapipe_selected

    if yolo_selected is not None:
        if mediapipe_selected is not None:
            return _merge_observations(yolo_selected, mediapipe_selected)
        return yolo_selected

    return mediapipe_selected


def _merge_observations(primary: PoseObservation, secondary: PoseObservation) -> PoseObservation:
    keypoints = {name: point.copy() for name, point in primary.keypoints.items()}
    confidences = dict(primary.confidences)
    for name, point in secondary.keypoints.items():
        if name in keypoints:
            continue
        keypoints[name] = point.copy()
        confidences[name] = float(secondary.confidences.get(name, 0.0))

    box = primary.box if primary.box is not None else secondary.box
    if box is None and keypoints:
        xs = [float(point[0]) for point in keypoints.values()]
        ys = [float(point[1]) for point in keypoints.values()]
        box = (min(xs), min(ys), max(xs), max(ys))

    provider = primary.provider
    if primary.provider != secondary.provider and secondary.keypoints:
        provider = "merged"

    return PoseObservation(
        provider=provider,
        keypoints=keypoints,
        confidences=confidences,
        box=box,
        box_confidence=max(primary.box_confidence, secondary.box_confidence),
    )


def _observation_has_feet(observation: Optional[PoseObservation]) -> bool:
    if observation is None:
        return False
    return any(name in observation.keypoints for name in ("left_ankle", "right_ankle", "left_foot_index", "right_foot_index"))


def _score_observation(observation: PoseObservation, ball_track: Optional[BallTrack]) -> float:
    score = observation.box_confidence
    if "left_ankle" in observation.keypoints or "right_ankle" in observation.keypoints:
        score += 0.30
    if "left_knee" in observation.keypoints or "right_knee" in observation.keypoints:
        score += 0.20
    if "left_hip" in observation.keypoints or "right_hip" in observation.keypoints:
        score += 0.15

    if observation.box is None or ball_track is None:
        return score

    x1, y1, x2, y2 = observation.box
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
    ground_y = _max_axis(state.keypoints, _GROUND_KEYS, axis=1)
    candidates = _contact_candidates(state.keypoints, state.confidences, ball_track)
    available = _pose_quality(state.keypoints) > 0.0 and (
        bool(candidates)
        or ground_y is not None
        or any(name in state.keypoints for name in ("left_knee", "right_knee", "left_hip", "right_hip"))
    )

    nearest_contact = None
    valid_candidates = [candidate for candidate in candidates if candidate.is_valid]
    if valid_candidates:
        nearest_contact = valid_candidates[0]
    elif candidates:
        nearest_contact = candidates[0]

    return PoseFrame(
        available=available,
        source=source if available else "none",
        backend=state.backend if available else "none",
        quality=_pose_quality(state.keypoints) if available else 0.0,
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
    radius = max(float(ball_track.radius), 1.0)

    for name in ("left_ankle", "right_ankle", "left_knee", "right_knee"):
        point = keypoints.get(name)
        if point is None:
            continue
        confidence = float(confidences.get(name, 0.0))
        threshold = max(radius * POSE_CONTACT_RADIUS_MULTIPLIERS[name], 12.0)
        distance = float(np.linalg.norm(point - ball_center))
        candidates.append(
            PoseContactCandidate(
                name=name,
                display_name=POSE_CONTACT_DISPLAY_NAMES[name],
                kind=POSE_CONTACT_KINDS[name],
                point=point.copy(),
                confidence=confidence,
                distance=distance,
                threshold=threshold,
            )
        )

    for side in ("left", "right"):
        hip = keypoints.get(f"{side}_hip")
        knee = keypoints.get(f"{side}_knee")
        if hip is None or knee is None:
            continue
        name = f"{side}_thigh"
        confidence = min(
            float(confidences.get(f"{side}_hip", 0.0)),
            float(confidences.get(f"{side}_knee", 0.0)),
        )
        threshold = max(radius * POSE_CONTACT_RADIUS_MULTIPLIERS[name], 12.0)
        distance = _point_to_segment_distance(ball_center, hip, knee)
        candidates.append(
            PoseContactCandidate(
                name=name,
                display_name=POSE_CONTACT_DISPLAY_NAMES[name],
                kind=POSE_CONTACT_KINDS[name],
                confidence=confidence,
                distance=distance,
                threshold=threshold,
                segment_start=hip.copy(),
                segment_end=knee.copy(),
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


def _pose_quality(keypoints: dict[str, np.ndarray]) -> float:
    if not keypoints:
        return 0.0
    present = sum(1 for name in _PRIMARY_KEYS if name in keypoints)
    return float(np.clip(present / len(_PRIMARY_KEYS), 0.0, 1.0))


def _point_to_segment_distance(
    point: np.ndarray,
    segment_start: np.ndarray,
    segment_end: np.ndarray,
) -> float:
    segment = segment_end - segment_start
    segment_length2 = float(np.dot(segment, segment))
    if segment_length2 <= 1e-6:
        return float(np.linalg.norm(point - segment_start))
    projection = float(np.dot(point - segment_start, segment) / segment_length2)
    projection = float(np.clip(projection, 0.0, 1.0))
    closest = segment_start + projection * segment
    return float(np.linalg.norm(point - closest))


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
