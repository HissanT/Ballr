from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Optional

import numpy as np

from .ball_tracker_pose import PoseFrame
from .ball_tracker_tracking import BallTrack, is_track_live

try:
    import torch
    from torch import nn
except ImportError:  # pragma: no cover - torch is optional at runtime
    torch = None
    nn = None


JUGGLE_WARMUP_SECONDS = 0.5
JUGGLE_HISTORY_FRAMES = 120
JUGGLE_MIN_CONFIRMED_FRAMES = 2
JUGGLE_LOSS_RESET_SECONDS = 0.45
JUGGLE_LOOKAHEAD_FRAMES = 3
JUGGLE_LOOKBACK_FRAMES = JUGGLE_LOOKAHEAD_FRAMES
JUGGLE_APEX_WINDOW_FRAMES = (JUGGLE_LOOKAHEAD_FRAMES * 2) + 1
JUGGLE_APEX_CENTER_INDEX = JUGGLE_LOOKAHEAD_FRAMES
JUGGLE_PROOF_WINDOW_RADIUS = 2
JUGGLE_WINDOW_FRAMES = JUGGLE_APEX_WINDOW_FRAMES
JUGGLE_PROMINENCE_RADIUS_FRACTION = 0.20
JUGGLE_APEX_TOLERANCE_RADIUS_FRACTION = 0.20
JUGGLE_APEX_TRAVEL_RADIUS_FRACTION = 0.15
JUGGLE_PROOF_THRESHOLD = 0.48
JUGGLE_GROUND_REJECT_THRESHOLD = 0.72
JUGGLE_GROUND_MARGIN_RADIUS_FRACTION = 0.35
JUGGLE_GROUND_BAND_MIN = 8.0
JUGGLE_BODY_SCORE_MARGIN = 0.08
JUGGLE_GROUND_SCORE_MARGIN = 0.06
JUGGLE_REARM_CLEARANCE_RADIUS_FRACTION = 0.30
JUGGLE_REARM_DESCENT_VY = 0.15
JUGGLE_REARM_TIMEOUT_SECONDS = 0.35
JUGGLE_HAND_SUPPRESS_THRESHOLD = 0.55
JUGGLE_COUNT_THRESHOLD = JUGGLE_PROOF_THRESHOLD
JUGGLE_LAST_EVENT_DISPLAY_SECONDS = 1.0
JUGGLE_EVENT_MODEL_CLASSES = ("count", "hand", "ground", "other")


class JugglePhase(str, Enum):
    WARMUP = "Warmup"
    READY = "Ready"
    CANDIDATE = "Candidate"
    COUNTED = "Counted"
    GROUND_REJECT = "GroundReject"
    NO_POSE = "NoPose"


class JuggleEventClass(str, Enum):
    FOOT = "foot"
    KNEE = "knee"
    HIP = "hip"
    THIGH = "thigh"
    GROUND = "ground"
    OTHER = "other"


EVENT_CLASS_ORDER = (
    JuggleEventClass.FOOT,
    JuggleEventClass.KNEE,
    JuggleEventClass.HIP,
    JuggleEventClass.THIGH,
    JuggleEventClass.GROUND,
    JuggleEventClass.OTHER,
)

POSITIVE_EVENT_CLASSES = {
    JuggleEventClass.FOOT,
    JuggleEventClass.KNEE,
    JuggleEventClass.HIP,
}
POSITIVE_EVENT_PRIORITY = (
    JuggleEventClass.FOOT,
    JuggleEventClass.KNEE,
    JuggleEventClass.HIP,
)

FEATURE_NAMES = (
    "ball_y_norm",
    "vy_norm",
    "vy_raw_norm",
    "radius_norm",
    "misses_norm",
    "foot_score",
    "knee_score",
    "hip_score",
    "hand_score",
    "ground_score",
    "ground_gap_norm",
    "pose_available",
    "pose_quality",
)


@dataclass(frozen=True)
class JuggleFrameSample:
    frame_index: int
    timestamp: float
    frame_size: tuple[int, int]
    track: Optional[BallTrack]
    pose_frame: PoseFrame

    @property
    def live_track(self) -> bool:
        return has_live_juggle_track(self.track)

    @property
    def center(self) -> Optional[np.ndarray]:
        if self.track is None:
            return None
        return self.track.center

    @property
    def radius(self) -> float:
        if self.track is None:
            return 0.0
        return float(self.track.radius)

    @property
    def vy(self) -> float:
        if self.track is None:
            return 0.0
        return float(self.track.velocity[1])

    @property
    def vx(self) -> float:
        if self.track is None:
            return 0.0
        return float(self.track.velocity[0])

    @property
    def vy_raw(self) -> float:
        if self.track is None or self.track.vy_raw is None:
            return self.vy
        return float(self.track.vy_raw)

    @property
    def misses(self) -> int:
        if self.track is None:
            return 0
        return int(self.track.misses)

    @property
    def ball_bottom_y(self) -> Optional[float]:
        if self.center is None:
            return None
        return float(self.center[1] + self.radius)


@dataclass(frozen=True)
class PendingJuggleCandidate:
    event_frame_index: int
    event_time: float
    apex_window: tuple[JuggleFrameSample, ...]


@dataclass(frozen=True)
class JuggleEventPrediction:
    event_class: JuggleEventClass
    probabilities: dict[str, float]
    confidence: float
    counted: bool
    event_frame_index: int
    event_time: float
    feature_window: np.ndarray
    feature_names: tuple[str, ...]
    proof_scores: dict[str, float] = field(default_factory=dict)
    proof_zone_y: Optional[float] = None
    pose_backend: str = "none"
    pose_quality: float = 0.0


@dataclass
class JuggleState:
    history: deque[JuggleFrameSample] = field(default_factory=deque)
    pending_candidates: deque[PendingJuggleCandidate] = field(default_factory=deque)
    phase: JugglePhase = JugglePhase.WARMUP
    current_streak: int = 0
    best_streak: int = 0
    total_juggles: int = 0
    ground_suppressed_events: int = 0
    contact_candidates: int = 0
    pose_live_frames: int = 0
    pose_stale_frames: int = 0
    body_part_counts: dict[str, int] = field(default_factory=dict)
    warmup_started_at: Optional[float] = None
    armed_at: Optional[float] = None
    last_live_track_at: Optional[float] = None
    last_candidate_frame_index: Optional[int] = None
    last_prediction: Optional[JuggleEventPrediction] = None
    last_prediction_at: Optional[float] = None
    status_label: str = JugglePhase.WARMUP.value
    awaiting_rearm: bool = False
    rearm_zone_y: Optional[float] = None
    rearm_ball_radius: float = 0.0
    rearm_cleared: bool = False
    rearm_started_at: Optional[float] = None

    @property
    def armed(self) -> bool:
        return self.armed_at is not None


def has_live_juggle_track(track: Optional[BallTrack]) -> bool:
    return is_track_live(track, min_confirmed_frames=JUGGLE_MIN_CONFIRMED_FRAMES)


class RuleBasedJuggleEventClassifier:
    def classify(
        self,
        feature_window: np.ndarray,
        window_samples: list[JuggleFrameSample],
    ) -> tuple[JuggleEventClass, dict[str, float]]:
        del feature_window
        if not window_samples:
            return JuggleEventClass.OTHER, _normalize_scores({JuggleEventClass.OTHER: 1.0})
        return JuggleEventClass.OTHER, _normalize_scores({JuggleEventClass.OTHER: 1.0})


if nn is not None:
    class JuggleEventSequenceModel(nn.Module):
        def __init__(
            self,
            input_size: int,
            hidden_size: int = 48,
            num_layers: int = 2,
            dropout: float = 0.20,
            output_size: int = len(EVENT_CLASS_ORDER),
        ) -> None:
            super().__init__()
            gru_dropout = dropout if num_layers > 1 else 0.0
            self.encoder = nn.GRU(
                input_size=input_size,
                hidden_size=hidden_size,
                num_layers=num_layers,
                batch_first=True,
                dropout=gru_dropout,
            )
            self.head = nn.Sequential(
                nn.Linear(hidden_size, hidden_size),
                nn.ReLU(inplace=True),
                nn.Dropout(dropout),
                nn.Linear(hidden_size, output_size),
            )

        def forward(self, inputs):
            encoded, _ = self.encoder(inputs)
            return self.head(encoded[:, -1, :])
else:  # pragma: no cover - exercised only when torch is unavailable
    class JuggleEventSequenceModel:
        def __init__(self, *args, **kwargs) -> None:
            raise ImportError("torch is required to build JuggleEventSequenceModel")


class TorchJuggleEventClassifier:
    def __init__(self, model_path: str | Path, device: str = "cpu") -> None:
        if torch is None:
            raise ImportError("torch is required to load a juggle event checkpoint")

        checkpoint = torch.load(str(model_path), map_location=device)
        if not isinstance(checkpoint, dict) or "state_dict" not in checkpoint:
            raise ValueError(f"Invalid juggle event checkpoint: {model_path}")

        self._torch = torch
        self._device = device
        self._classes = tuple(str(label) for label in checkpoint.get("classes", JUGGLE_EVENT_MODEL_CLASSES))
        self._model = JuggleEventSequenceModel(
            input_size=len(FEATURE_NAMES),
            hidden_size=int(checkpoint.get("hidden_size", 48)),
            num_layers=int(checkpoint.get("num_layers", 2)),
            dropout=float(checkpoint.get("dropout", 0.20)),
            output_size=len(self._classes),
        ).to(device)
        self._model.load_state_dict(checkpoint["state_dict"])
        self._model.eval()

    def classify(
        self,
        feature_window: np.ndarray,
        window_samples: list[JuggleFrameSample],
    ) -> tuple[JuggleEventClass, dict[str, float]]:
        del window_samples
        with self._torch.no_grad():
            tensor = self._torch.tensor(feature_window, dtype=self._torch.float32, device=self._device)
            logits = self._model(tensor.unsqueeze(0)).squeeze(0)
            probabilities = self._torch.softmax(logits, dim=0).cpu().numpy()

        raw_scores = {
            label: float(probabilities[index])
            for index, label in enumerate(self._classes)
        }
        scores = {
            JuggleEventClass.FOOT.value: 0.0,
            JuggleEventClass.KNEE.value: 0.0,
            JuggleEventClass.HIP.value: 0.0,
            JuggleEventClass.THIGH.value: 0.0,
            JuggleEventClass.GROUND.value: raw_scores.get("ground", 0.0),
            JuggleEventClass.OTHER.value: raw_scores.get("other", 0.0) + raw_scores.get("hand", 0.0),
            "count": raw_scores.get("count", 0.0),
            "hand": raw_scores.get("hand", 0.0),
        }
        best_label = max(raw_scores, key=raw_scores.get)
        if best_label == "ground":
            best_class = JuggleEventClass.GROUND
        elif best_label in {"hand", "other"}:
            best_class = JuggleEventClass.OTHER
        else:
            best_class = JuggleEventClass.OTHER
        return best_class, scores


def load_juggle_event_classifier(
    model_path: Optional[str | Path],
    *,
    device: str = "cpu",
) -> RuleBasedJuggleEventClassifier | TorchJuggleEventClassifier:
    if model_path is None:
        return RuleBasedJuggleEventClassifier()
    candidate_path = Path(model_path)
    if not candidate_path.is_file():
        return RuleBasedJuggleEventClassifier()
    try:
        return TorchJuggleEventClassifier(candidate_path, device=device)
    except Exception:
        return RuleBasedJuggleEventClassifier()


def update_juggle_state(
    state: Optional[JuggleState],
    track: Optional[BallTrack],
    pose_frame: PoseFrame,
    timestamp: float,
    frame_size: tuple[int, int],
    *,
    frame_index: int,
    classifier: RuleBasedJuggleEventClassifier | TorchJuggleEventClassifier | None = None,
    count_threshold: float = JUGGLE_COUNT_THRESHOLD,
    lookahead_frames: int = JUGGLE_LOOKAHEAD_FRAMES,
    prominence_radius_fraction: float = JUGGLE_PROMINENCE_RADIUS_FRACTION,
    ground_margin_radius_fraction: float = JUGGLE_GROUND_MARGIN_RADIUS_FRACTION,
) -> tuple[JuggleState, Optional[JuggleEventPrediction]]:
    state = state or JuggleState()
    if state.warmup_started_at is None:
        state.warmup_started_at = timestamp

    sample = JuggleFrameSample(
        frame_index=frame_index,
        timestamp=timestamp,
        frame_size=frame_size,
        track=track,
        pose_frame=pose_frame,
    )
    state.history.append(sample)
    while len(state.history) > JUGGLE_HISTORY_FRAMES:
        state.history.popleft()

    while state.pending_candidates and frame_index - state.pending_candidates[0].event_frame_index > lookahead_frames:
        state.pending_candidates.popleft()

    if pose_frame.live:
        state.pose_live_frames += 1
    elif pose_frame.stale:
        state.pose_stale_frames += 1

    if has_live_juggle_track(track):
        state.last_live_track_at = timestamp
        if state.armed_at is None:
            state.armed_at = timestamp

    _update_rearm(state, sample)
    _check_ground_during_rearm(state, sample)

    if timestamp - state.warmup_started_at < JUGGLE_WARMUP_SECONDS or len(state.history) < max((lookahead_frames * 2) + 1, JUGGLE_APEX_WINDOW_FRAMES):
        state.phase = JugglePhase.WARMUP
        state.status_label = state.phase.value
        return state, None

    event: Optional[JuggleEventPrediction] = None
    if not state.awaiting_rearm:
        candidate = _detect_candidate(
            list(state.history),
            lookahead_frames=lookahead_frames,
            prominence_radius_fraction=prominence_radius_fraction,
        )
        if candidate is not None and candidate.event_frame_index != state.last_candidate_frame_index:
            state.last_candidate_frame_index = candidate.event_frame_index
            state.pending_candidates.append(candidate)
            state.contact_candidates += 1
            state.phase = JugglePhase.CANDIDATE
            state.status_label = state.phase.value
            event = _classify_candidate(
                candidate,
                classifier=classifier,
                proof_threshold=float(count_threshold),
                ground_margin_radius_fraction=ground_margin_radius_fraction,
            )
            if event is not None:
                state.last_prediction = event
                state.last_prediction_at = timestamp
                if event.counted:
                    state.total_juggles += 1
                    state.current_streak += 1
                    state.best_streak = max(state.best_streak, state.current_streak)
                    label = event.event_class.value.title()
                    state.body_part_counts[label] = state.body_part_counts.get(label, 0) + 1
                    state.phase = JugglePhase.COUNTED
                    state.awaiting_rearm = True
                elif event.event_class == JuggleEventClass.GROUND:
                    state.ground_suppressed_events += 1
                    state.phase = JugglePhase.GROUND_REJECT
                    state.awaiting_rearm = True
                elif not _proof_window_has_pose(candidate):
                    state.phase = JugglePhase.NO_POSE
                else:
                    state.phase = JugglePhase.CANDIDATE

                if state.awaiting_rearm:
                    state.rearm_zone_y = event.proof_zone_y
                    state.rearm_ball_radius = max(_apex_sample(candidate).radius, 1.0)
                    state.rearm_cleared = False
                    state.rearm_started_at = timestamp

                state.status_label = state.phase.value

    if event is None:
        _set_idle_phase(state, pose_frame)

    return state, event


def _set_idle_phase(state: JuggleState, pose_frame: PoseFrame) -> None:
    if state.awaiting_rearm and state.last_prediction is not None:
        if state.last_prediction.counted:
            state.phase = JugglePhase.COUNTED
        elif state.last_prediction.event_class == JuggleEventClass.GROUND:
            state.phase = JugglePhase.GROUND_REJECT
        else:
            state.phase = JugglePhase.CANDIDATE
    elif not pose_frame.available:
        state.phase = JugglePhase.NO_POSE
    else:
        state.phase = JugglePhase.READY
    state.status_label = state.phase.value


def _force_rearm_complete(state: JuggleState) -> None:
    state.awaiting_rearm = False
    state.rearm_cleared = False
    state.rearm_zone_y = None
    state.rearm_ball_radius = 0.0
    state.rearm_started_at = None


def _update_rearm(state: JuggleState, sample: JuggleFrameSample) -> None:
    if not state.awaiting_rearm or state.rearm_zone_y is None or sample.ball_bottom_y is None:
        return

    if state.rearm_started_at is not None and sample.timestamp - state.rearm_started_at >= JUGGLE_REARM_TIMEOUT_SECONDS:
        _force_rearm_complete(state)
        return

    clearance = max(state.rearm_ball_radius * JUGGLE_REARM_CLEARANCE_RADIUS_FRACTION, 6.0)
    if not state.rearm_cleared and sample.ball_bottom_y <= state.rearm_zone_y - clearance:
        state.rearm_cleared = True
        return

    if state.rearm_cleared and sample.vy >= JUGGLE_REARM_DESCENT_VY:
        _force_rearm_complete(state)


def _check_ground_during_rearm(state: JuggleState, sample: JuggleFrameSample) -> bool:
    if not state.awaiting_rearm:
        return False
    if sample.ball_bottom_y is None or sample.pose_frame.ground_y is None:
        return False
    band = max(sample.radius * JUGGLE_GROUND_MARGIN_RADIUS_FRACTION, JUGGLE_GROUND_BAND_MIN)
    distance = abs(sample.pose_frame.ground_y - sample.ball_bottom_y)
    if distance <= band * 0.5:
        state.ground_suppressed_events += 1
        state.phase = JugglePhase.GROUND_REJECT
        state.status_label = state.phase.value
        _force_rearm_complete(state)
        return True
    return False


def _detect_candidate(
    history: list[JuggleFrameSample],
    *,
    lookahead_frames: int,
    prominence_radius_fraction: float,
) -> Optional[PendingJuggleCandidate]:
    window_size = (lookahead_frames * 2) + 1
    if len(history) < window_size:
        return None

    window = history[-window_size:]
    if any(sample.center is None for sample in window):
        return None

    missed_frames = sum(1 for sample in window if (not sample.live_track) or sample.misses > 0)
    if missed_frames > 2:
        return None

    center_sample = window[lookahead_frames]
    radius = max(center_sample.radius, 1.0)
    tolerance = radius * JUGGLE_APEX_TOLERANCE_RADIUS_FRACTION
    y_values = [float(sample.center[1]) for sample in window if sample.center is not None]
    if len(y_values) != window_size:
        return None

    peak_y = y_values[lookahead_frames]
    if peak_y + tolerance < max(y_values):
        return None
    if peak_y + tolerance < y_values[lookahead_frames - 1] or peak_y + tolerance < y_values[lookahead_frames + 1]:
        return None

    pre_descent = np.mean(
        [
            y_values[lookahead_frames] - y_values[lookahead_frames - 1],
            y_values[lookahead_frames - 1] - y_values[lookahead_frames - 2],
        ]
    )
    post_rise = np.mean(
        [
            y_values[lookahead_frames] - y_values[lookahead_frames + 1],
            y_values[lookahead_frames + 1] - y_values[lookahead_frames + 2],
        ]
    )
    travel_threshold = radius * JUGGLE_APEX_TRAVEL_RADIUS_FRACTION
    if pre_descent < travel_threshold or post_rise < travel_threshold:
        return None

    prominence = radius * prominence_radius_fraction
    if peak_y - min(y_values[:lookahead_frames]) < prominence:
        return None
    if peak_y - min(y_values[lookahead_frames + 1 :]) < prominence:
        return None

    return PendingJuggleCandidate(
        event_frame_index=center_sample.frame_index,
        event_time=center_sample.timestamp,
        apex_window=tuple(window),
    )


def _classify_candidate(
    candidate: PendingJuggleCandidate,
    *,
    classifier: RuleBasedJuggleEventClassifier | TorchJuggleEventClassifier | None,
    proof_threshold: float,
    ground_margin_radius_fraction: float,
) -> Optional[JuggleEventPrediction]:
    proof_samples = _proof_window(candidate)
    if not proof_samples:
        return None

    proof_scores = {
        "foot": _foot_proof_score(proof_samples),
        "knee": _knee_proof_score(proof_samples),
        "hip": _hip_proof_score(proof_samples),
        "hand": _hand_proof_score(proof_samples),
        "ground": _ground_proof_score(
            proof_samples,
            ground_margin_radius_fraction=ground_margin_radius_fraction,
        ),
    }
    feature_window = _feature_window(candidate)
    if classifier is not None and not isinstance(classifier, RuleBasedJuggleEventClassifier):
        predicted_class, classifier_scores = classifier.classify(feature_window, list(candidate.apex_window))
        classifier_scores = {str(key): float(value) for key, value in classifier_scores.items()}
        predicted_event_label = _best_classifier_event_label(classifier_scores)
        if predicted_event_label == "count":
            best_body_class = _pick_positive_event_class(proof_scores)
            merged_scores = dict(proof_scores)
            merged_scores["count"] = classifier_scores.get("count", 0.0)
            merged_scores["hand"] = classifier_scores.get("hand", 0.0)
            return _build_event_prediction(
                candidate,
                event_class=best_body_class,
                proof_scores=merged_scores,
                counted=True,
                feature_window=feature_window,
            )
        if predicted_event_label == "ground":
            merged_scores = dict(proof_scores)
            merged_scores["count"] = classifier_scores.get("count", 0.0)
            merged_scores["hand"] = classifier_scores.get("hand", 0.0)
            return _build_event_prediction(
                candidate,
                event_class=JuggleEventClass.GROUND,
                proof_scores=merged_scores,
                counted=False,
                feature_window=feature_window,
            )
        merged_scores = dict(proof_scores)
        merged_scores["count"] = classifier_scores.get("count", 0.0)
        merged_scores["hand"] = classifier_scores.get("hand", 0.0)
        return _build_event_prediction(
            candidate,
            event_class=JuggleEventClass.OTHER,
            proof_scores=merged_scores,
            counted=False,
            feature_window=feature_window,
        )
    if proof_scores["hand"] >= JUGGLE_HAND_SUPPRESS_THRESHOLD:
        return _build_event_prediction(
            candidate,
            event_class=JuggleEventClass.OTHER,
            proof_scores=proof_scores,
            counted=False,
            feature_window=feature_window,
        )
    apex = _apex_sample(candidate)
    if apex.ball_bottom_y is not None and apex.pose_frame.ground_y is not None:
        band = max(apex.radius * ground_margin_radius_fraction, JUGGLE_GROUND_BAND_MIN)
        if abs(apex.pose_frame.ground_y - apex.ball_bottom_y) <= band * 0.5:
            return _build_event_prediction(
                candidate,
                event_class=JuggleEventClass.GROUND,
                proof_scores=proof_scores,
                counted=False,
                feature_window=feature_window,
            )

    best_body_class = _pick_positive_event_class(proof_scores)
    best_body_score = proof_scores[best_body_class.value]
    ground_score = proof_scores["ground"]

    if best_body_score >= proof_threshold and best_body_score + JUGGLE_BODY_SCORE_MARGIN >= ground_score:
        return _build_event_prediction(
            candidate,
            event_class=best_body_class,
            proof_scores=proof_scores,
            counted=True,
            feature_window=feature_window,
        )

    if ground_score >= JUGGLE_GROUND_REJECT_THRESHOLD and ground_score >= best_body_score + JUGGLE_GROUND_SCORE_MARGIN:
        return _build_event_prediction(
            candidate,
            event_class=JuggleEventClass.GROUND,
            proof_scores=proof_scores,
            counted=False,
            feature_window=feature_window,
        )

    if not _proof_window_has_pose(candidate):
        return _build_event_prediction(
            candidate,
            event_class=JuggleEventClass.OTHER,
            proof_scores=proof_scores,
            counted=False,
            feature_window=feature_window,
        )

    return None


def _build_event_prediction(
    candidate: PendingJuggleCandidate,
    *,
    event_class: JuggleEventClass,
    proof_scores: dict[str, float],
    counted: bool,
    feature_window: Optional[np.ndarray] = None,
) -> JuggleEventPrediction:
    scores = {
        JuggleEventClass.FOOT: proof_scores.get("foot", 0.0),
        JuggleEventClass.KNEE: proof_scores.get("knee", 0.0),
        JuggleEventClass.HIP: proof_scores.get("hip", 0.0),
        JuggleEventClass.THIGH: proof_scores.get("thigh", 0.0),
        JuggleEventClass.GROUND: proof_scores.get("ground", 0.0),
        JuggleEventClass.OTHER: max(0.0, 1.0 - max(proof_scores.values(), default=0.0)),
    }
    probabilities = _normalize_scores(scores)
    apex_sample = _apex_sample(candidate)
    feature_window = feature_window if feature_window is not None else _feature_window(candidate)
    pose_backend, pose_quality = _window_pose_summary(candidate.apex_window)
    return JuggleEventPrediction(
        event_class=event_class,
        probabilities=probabilities,
        confidence=float(probabilities[event_class.value]),
        counted=counted,
        event_frame_index=candidate.event_frame_index,
        event_time=candidate.event_time,
        feature_window=feature_window,
        feature_names=FEATURE_NAMES,
        proof_scores=dict(proof_scores),
        proof_zone_y=apex_sample.ball_bottom_y,
        pose_backend=pose_backend,
        pose_quality=pose_quality,
    )


def _normalize_scores(scores: dict[JuggleEventClass, float]) -> dict[str, float]:
    stable_scores = {event_class: max(float(score), 0.0) for event_class, score in scores.items()}
    total = sum(stable_scores.values())
    if total <= 1e-6:
        uniform = 1.0 / len(EVENT_CLASS_ORDER)
        return {event_class.value: uniform for event_class in EVENT_CLASS_ORDER}
    return {
        event_class.value: stable_scores.get(event_class, 0.0) / total
        for event_class in EVENT_CLASS_ORDER
    }


def _best_classifier_event_label(scores: dict[str, float]) -> str:
    candidate_scores = {
        label: float(scores.get(label, 0.0))
        for label in JUGGLE_EVENT_MODEL_CLASSES
    }
    return max(candidate_scores, key=candidate_scores.get)


def _pick_positive_event_class(proof_scores: dict[str, float]) -> JuggleEventClass:
    best_score = max(proof_scores.get(event_class.value, 0.0) for event_class in POSITIVE_EVENT_CLASSES)
    close_matches = [
        event_class
        for event_class in POSITIVE_EVENT_PRIORITY
        if best_score - proof_scores.get(event_class.value, 0.0) <= 0.15
    ]
    if close_matches:
        return close_matches[0]
    return max(POSITIVE_EVENT_CLASSES, key=lambda event_class: proof_scores[event_class.value])


def _proof_window(candidate: PendingJuggleCandidate) -> tuple[JuggleFrameSample, ...]:
    center = JUGGLE_APEX_CENTER_INDEX
    start = max(0, center - JUGGLE_PROOF_WINDOW_RADIUS)
    end = min(len(candidate.apex_window), center + JUGGLE_PROOF_WINDOW_RADIUS + 1)
    return candidate.apex_window[start:end]


def _proof_window_has_pose(candidate: PendingJuggleCandidate) -> bool:
    return any(sample.pose_frame.available for sample in _proof_window(candidate))


def _apex_sample(candidate: PendingJuggleCandidate) -> JuggleFrameSample:
    return candidate.apex_window[JUGGLE_APEX_CENTER_INDEX]


def _feature_window(candidate: PendingJuggleCandidate) -> np.ndarray:
    rows: list[list[float]] = []
    for sample in candidate.apex_window:
        frame_h, frame_w = sample.frame_size
        normalizer = max(frame_h, frame_w, 1)
        radius = max(sample.radius, 1.0)
        ground_gap_norm = 2.0
        if sample.ball_bottom_y is not None and sample.pose_frame.ground_y is not None:
            ground_gap_norm = float(
                np.clip((sample.pose_frame.ground_y - sample.ball_bottom_y) / radius, -2.0, 2.0)
            )
        rows.append(
            [
                0.0 if sample.center is None else float(sample.center[1] / max(frame_h, 1)),
                float(sample.vy / radius),
                float(sample.vy_raw / radius),
                float(radius / normalizer),
                float(min(sample.misses, 3) / 3.0),
                _foot_proof_score((sample,)),
                _knee_proof_score((sample,)),
                _hip_proof_score((sample,)),
                _hand_proof_score((sample,)),
                _ground_proof_score((sample,), ground_margin_radius_fraction=JUGGLE_GROUND_MARGIN_RADIUS_FRACTION),
                ground_gap_norm,
                1.0 if sample.pose_frame.available else 0.0,
                float(sample.pose_frame.quality),
            ]
        )
    return np.array(rows, dtype=np.float32)


def _window_pose_summary(samples: tuple[JuggleFrameSample, ...]) -> tuple[str, float]:
    live_samples = [sample.pose_frame for sample in samples if sample.pose_frame.available]
    if not live_samples:
        return "none", 0.0
    qualities = [frame.quality for frame in live_samples]
    backend_votes: dict[str, int] = {}
    for frame in live_samples:
        backend_votes[frame.backend] = backend_votes.get(frame.backend, 0) + 1
    backend = max(backend_votes, key=backend_votes.get)
    return backend, float(sum(qualities) / len(qualities))


def _proof_sample_weight(sample_index: int, total_samples: int) -> float:
    center_index = total_samples // 2
    distance = abs(sample_index - center_index)
    return float(max(0.45, 1.0 - (0.25 * distance)))


def _foot_proof_score(samples: tuple[JuggleFrameSample, ...]) -> float:
    return _point_contact_score(
        samples,
        point_names=("left_ankle", "right_ankle"),
        radius_factor=3.3,
        height_factor=0.11,
        include_ball_bottom=True,
    )


def _knee_proof_score(samples: tuple[JuggleFrameSample, ...]) -> float:
    return _point_contact_score(
        samples,
        point_names=("left_knee", "right_knee"),
        radius_factor=3.2,
        height_factor=0.12,
        include_ball_bottom=False,
    )


def _hip_proof_score(samples: tuple[JuggleFrameSample, ...]) -> float:
    best_score = 0.0
    for sample_index, sample in enumerate(samples):
        if sample.center is None or not sample.pose_frame.available:
            continue
        if (
            sample.ball_bottom_y is not None
            and sample.pose_frame.hip_line_y is not None
            and sample.pose_frame.knee_line_y is not None
            and sample.pose_frame.knee_line_y > sample.pose_frame.hip_line_y
        ):
            hip_band_limit = sample.pose_frame.hip_line_y + (
                (sample.pose_frame.knee_line_y - sample.pose_frame.hip_line_y) * 0.3
            )
            if sample.ball_bottom_y > hip_band_limit:
                continue
        left_hip = sample.pose_frame.keypoints.get("left_hip")
        right_hip = sample.pose_frame.keypoints.get("right_hip")
        if left_hip is None or right_hip is None:
            continue
        player_height = _player_height(sample.pose_frame)
        y_threshold = max(sample.radius * 3.0, player_height * 0.10)
        x_threshold = y_threshold * 1.35
        weight = _proof_sample_weight(sample_index, len(samples))
        targets = _contact_targets(sample, include_ball_bottom=True)
        best_score = max(
            best_score,
            _segment_contact_score(
                left_hip,
                right_hip,
                targets,
                x_threshold=x_threshold,
                y_threshold=y_threshold,
                weight=weight,
            ),
        )
    return best_score


def _hand_proof_score(samples: tuple[JuggleFrameSample, ...]) -> float:
    return _point_contact_score(
        samples,
        point_names=("left_wrist", "right_wrist"),
        radius_factor=3.2,
        height_factor=0.12,
        include_ball_bottom=True,
    )


def _ground_proof_score(
    samples: tuple[JuggleFrameSample, ...],
    *,
    ground_margin_radius_fraction: float,
) -> float:
    best_score = 0.0
    for sample_index, sample in enumerate(samples):
        if sample.ball_bottom_y is None or sample.pose_frame.ground_y is None:
            continue
        band = max(sample.radius * ground_margin_radius_fraction, JUGGLE_GROUND_BAND_MIN)
        distance = abs(sample.pose_frame.ground_y - sample.ball_bottom_y)
        weight = _proof_sample_weight(sample_index, len(samples))
        best_score = max(best_score, _distance_score(distance, band) * weight)
    return best_score


def _point_contact_score(
    samples: tuple[JuggleFrameSample, ...],
    *,
    point_names: tuple[str, ...],
    radius_factor: float,
    height_factor: float,
    include_ball_bottom: bool,
) -> float:
    best_score = 0.0
    for sample_index, sample in enumerate(samples):
        if sample.center is None or not sample.pose_frame.available:
            continue
        player_height = _player_height(sample.pose_frame)
        y_threshold = max(sample.radius * radius_factor, player_height * height_factor)
        x_threshold = y_threshold * 1.35
        weight = _proof_sample_weight(sample_index, len(samples))
        targets = _contact_targets(sample, include_ball_bottom=include_ball_bottom)
        for point_name in point_names:
            point = sample.pose_frame.keypoints.get(point_name)
            if point is None:
                continue
            best_score = max(
                best_score,
                _point_targets_contact_score(
                    point,
                    targets,
                    x_threshold=x_threshold,
                    y_threshold=y_threshold,
                    weight=weight,
                ),
            )
    return best_score


def _contact_targets(sample: JuggleFrameSample, *, include_ball_bottom: bool) -> tuple[np.ndarray, ...]:
    if sample.center is None:
        return ()
    targets = [sample.center]
    if include_ball_bottom:
        targets.append(np.array((sample.center[0], sample.center[1] + sample.radius), dtype=np.float32))
    return tuple(targets)


def _point_targets_contact_score(
    point: np.ndarray,
    targets: tuple[np.ndarray, ...],
    *,
    x_threshold: float,
    y_threshold: float,
    weight: float,
) -> float:
    best_score = 0.0
    for target in targets:
        dx = float(target[0] - point[0])
        dy = float(target[1] - point[1])
        best_score = max(best_score, _axis_distance_score(dx, dy, x_threshold, y_threshold) * weight)
    return best_score


def _segment_contact_score(
    segment_start: np.ndarray,
    segment_end: np.ndarray,
    targets: tuple[np.ndarray, ...],
    *,
    x_threshold: float,
    y_threshold: float,
    weight: float,
) -> float:
    best_score = 0.0
    for target in targets:
        dx, dy = _point_to_segment_offset(target, segment_start, segment_end)
        best_score = max(best_score, _axis_distance_score(dx, dy, x_threshold, y_threshold) * weight)
    return best_score


def _axis_distance_score(dx: float, dy: float, x_threshold: float, y_threshold: float) -> float:
    if x_threshold <= 1e-6 or y_threshold <= 1e-6:
        return 0.0
    normalized = np.sqrt((dx / x_threshold) ** 2 + (dy / y_threshold) ** 2)
    return float(np.clip(1.0 - normalized, 0.0, 1.0))


def _distance_score(distance: float, threshold: float) -> float:
    if threshold <= 1e-6:
        return 0.0
    return float(np.clip(1.0 - (distance / threshold), 0.0, 1.0))


def _point_to_segment_offset(
    point: np.ndarray,
    segment_start: np.ndarray,
    segment_end: np.ndarray,
) -> tuple[float, float]:
    segment = segment_end - segment_start
    segment_length2 = float(np.dot(segment, segment))
    if segment_length2 <= 1e-6:
        offset = point - segment_start
        return float(offset[0]), float(offset[1])
    projection = float(np.dot(point - segment_start, segment) / segment_length2)
    projection = float(np.clip(projection, 0.0, 1.0))
    closest = segment_start + projection * segment
    offset = point - closest
    return float(offset[0]), float(offset[1])


def _player_height(pose_frame: PoseFrame) -> float:
    if pose_frame.box is not None:
        return max(float(pose_frame.box[3] - pose_frame.box[1]), 1.0)

    points = list(pose_frame.keypoints.values())
    if not points:
        return 1.0
    ys = [float(point[1]) for point in points]
    return max(max(ys) - min(ys), 1.0)
