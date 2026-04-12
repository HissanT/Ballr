import argparse
import json
import threading
import time
from collections import deque
from dataclasses import dataclass, field, replace
from pathlib import Path
from typing import Any, Callable, Generic, Optional, TypeVar

import cv2
import numpy as np

from ball_tracker_audio import (
    COMBO_SOUNDTRACK_DIR,
    TARGET_SOUND_PATH,
    combo_sound_path_for_streak,
    play_score_sound as _play_score_sound,
)
from ball_tracker_juggling import (
    JUGGLE_COUNT_THRESHOLD,
    JUGGLE_GROUND_MARGIN_RADIUS_FRACTION,
    JUGGLE_LAST_EVENT_DISPLAY_SECONDS,
    JUGGLE_LOOKAHEAD_FRAMES,
    JUGGLE_PROMINENCE_RADIUS_FRACTION,
    JuggleEventPrediction,
    JuggleState,
    update_juggle_state,
)
from ball_tracker_pose import (
    POSE_BACKEND_AUTO,
    POSE_BACKEND_CHOICES,
    POSE_CONF_THRESHOLD,
    POSE_IMG_SIZE,
    POSE_MODEL_PATH,
    PoseBackendResults,
    PoseFrame,
    PoseRuntimeContext,
    PoseState,
    close_pose_runtime,
    create_pose_runtime,
    infer_pose_backends,
    update_pose_state_from_backends,
)
from ball_tracker_target_mode import (
    TargetModeFrame,
    TargetModeState,
    draw_target_mode,
    step_target_mode,
)
from ball_tracker_rendering import (
    RenderCache,
    draw_label,
    draw_label_right,
    draw_pose_overlay,
    draw_track,
    mirror_frame,
    render_target_reference_rgb,
)
from ball_tracker_targets import (
    ScoredTargetEffect,
    TargetState,
    target_radius_for_frame,
)
from ball_tracker_tracking import (
    CANDIDATE_CONF_THRESHOLD,
    BallMotionState,
    IOU_THRESHOLD,
    MAX_DETECTIONS,
    MODEL_PATH,
    SPORTS_BALL_CLASS_ID,
    BallTrack,
    advance_track,
    choose_primary_candidate,
    extract_candidates,
    predict_track,
    update_track,
)
from ballr_utils import build_gamma_lut, parse_source, preprocess_frame

try:
    import winsound
except ImportError:
    winsound = None


T = TypeVar("T")
GAME_MODE_TARGET = "target"
GAME_MODE_JUGGLE = "juggle"

HUD_BASELINE_Y = 22
HUD_LINE_HEIGHT = 22
HUD_FONT_SCALE = 0.45
HUD_FONT_THICKNESS = 1


def play_score_sound(sound_path: Path = TARGET_SOUND_PATH) -> None:
    _play_score_sound(sound_path, winsound_module=winsound)


def play_combo_sound(hit_streak: int, soundtrack_dir: Path = COMBO_SOUNDTRACK_DIR) -> None:
    _play_score_sound(
        combo_sound_path_for_streak(hit_streak, soundtrack_dir=soundtrack_dir),
        winsound_module=winsound,
    )


def play_target_score_sound(_hit_streak: int) -> None:
    play_score_sound()


class LatestValueStore(Generic[T]):
    def __init__(self) -> None:
        self._condition = threading.Condition()
        self._item: Optional[T] = None
        self._version = 0
        self._closed = False
        self._dropped_count = 0

    def put(self, item: T) -> None:
        with self._condition:
            if self._closed:
                return
            if self._item is not None:
                self._dropped_count += 1
            self._item = item
            self._version += 1
            self._condition.notify_all()

    def get_latest(self, last_version: int, timeout_s: float = 0.1) -> tuple[int, Optional[T]]:
        with self._condition:
            deadline = time.perf_counter() + max(timeout_s, 0.0)
            while not self._closed and self._version == last_version:
                remaining = deadline - time.perf_counter()
                if remaining <= 0.0:
                    return last_version, None
                self._condition.wait(remaining)

            if self._version == last_version:
                return last_version, None

            version = self._version
            item = self._item
            self._item = None
            return version, item

    def close(self) -> None:
        with self._condition:
            self._closed = True
            self._condition.notify_all()

    @property
    def dropped_count(self) -> int:
        with self._condition:
            return self._dropped_count

    @property
    def closed(self) -> bool:
        with self._condition:
            return self._closed


@dataclass(frozen=True)
class CapturePacket:
    frame_index: int
    frame: np.ndarray
    capture_started_at: float
    capture_finished_at: float

    @property
    def capture_ms(self) -> float:
        return (self.capture_finished_at - self.capture_started_at) * 1000.0


@dataclass
class PipelineCounters:
    total_frames: int = 0
    matched_frames: int = 0
    held_frames: int = 0
    active_frames: int = 0
    hit_frames: int = 0
    pose_live_frames: int = 0
    pose_stale_frames: int = 0


@dataclass
class TrackerRuntimeState:
    track: Optional[BallTrack] = None
    motion: Optional[BallMotionState] = None
    target_mode: TargetModeState = field(default_factory=TargetModeState)
    juggle_mode: JuggleState = field(default_factory=JuggleState)
    pose: PoseState = field(default_factory=PoseState)
    next_track_id: int = 1
    counters: PipelineCounters = field(default_factory=PipelineCounters)


@dataclass
class StageTimings:
    capture_ms: float = 0.0
    preprocess_ms: float = 0.0
    inference_ms: float = 0.0
    candidate_ms: float = 0.0
    tracking_ms: float = 0.0
    render_ms: float = 0.0
    display_ms: float = 0.0
    pipeline_ms: float = 0.0


@dataclass
class ProcessedFrame:
    frame_index: int
    frame: np.ndarray
    frame_time: float
    stage_timings: StageTimings
    track: Optional[BallTrack]
    target: Optional[TargetState]
    score_effects: list[ScoredTargetEffect]
    candidates_count: int
    primary_candidate_confidence: Optional[float]
    counters: PipelineCounters
    game_mode: str = GAME_MODE_TARGET
    target_mode: Optional[TargetModeFrame] = None
    pose_frame: Optional[PoseFrame] = None
    juggle_event: Optional[JuggleEventPrediction] = None
    current_score: int = 0
    best_score: int = 0
    total_score_events: int = 0
    status_label: str = ""
    body_part_counts: dict[str, int] = field(default_factory=dict)
    ground_suppressed_events: int = 0
    contact_candidates: int = 0
    pending_candidates: int = 0
    pose_backend: str = "none"
    pose_quality: float = 0.0
    displayed_juggle_event: Optional[JuggleEventPrediction] = None


@dataclass
class BenchmarkAccumulator:
    wall_started_at: float = 0.0
    wall_finished_at: float = 0.0
    capture_ms: list[float] = field(default_factory=list)
    preprocess_ms: list[float] = field(default_factory=list)
    inference_ms: list[float] = field(default_factory=list)
    candidate_ms: list[float] = field(default_factory=list)
    tracking_ms: list[float] = field(default_factory=list)
    render_ms: list[float] = field(default_factory=list)
    display_ms: list[float] = field(default_factory=list)
    pipeline_ms: list[float] = field(default_factory=list)
    candidate_counts: list[int] = field(default_factory=list)
    primary_confidences: list[float] = field(default_factory=list)
    final_counters: PipelineCounters = field(default_factory=PipelineCounters)
    final_frame: Optional[ProcessedFrame] = None

    def add(self, frame_result: ProcessedFrame) -> None:
        self.capture_ms.append(frame_result.stage_timings.capture_ms)
        self.preprocess_ms.append(frame_result.stage_timings.preprocess_ms)
        self.inference_ms.append(frame_result.stage_timings.inference_ms)
        self.candidate_ms.append(frame_result.stage_timings.candidate_ms)
        self.tracking_ms.append(frame_result.stage_timings.tracking_ms)
        self.render_ms.append(frame_result.stage_timings.render_ms)
        self.display_ms.append(frame_result.stage_timings.display_ms)
        self.pipeline_ms.append(frame_result.stage_timings.pipeline_ms)
        self.candidate_counts.append(frame_result.candidates_count)
        if frame_result.primary_candidate_confidence is not None:
            self.primary_confidences.append(frame_result.primary_candidate_confidence)
        self.final_counters = replace(frame_result.counters)
        self.final_frame = frame_result

    def summary(
        self,
        *,
        source: str,
        frame_size: tuple[int, int],
        mode: str = GAME_MODE_TARGET,
        queue_drops: Optional[dict[str, int]] = None,
    ) -> dict[str, Any]:
        frames_processed = len(self.capture_ms)
        wall_seconds = max(self.wall_finished_at - self.wall_started_at, 1e-9)
        counters = self.final_counters

        def stage(values: list[float]) -> dict[str, float]:
            if not values:
                return {"avg": 0.0, "p95": 0.0, "max": 0.0}
            array = np.array(values, dtype=np.float64)
            return {
                "avg": round(float(array.mean()), 3),
                "p95": round(float(np.percentile(array, 95)), 3),
                "max": round(float(array.max()), 3),
            }

        summary = {
            "source": source,
            "mode": mode,
            "frame_size": [frame_size[0], frame_size[1]],
            "frames_processed": frames_processed,
            "avg_fps": round(frames_processed / wall_seconds, 3),
            "stage_timings_ms": {
                "capture": stage(self.capture_ms),
                "preprocess": stage(self.preprocess_ms),
                "inference": stage(self.inference_ms),
                "candidate_extraction": stage(self.candidate_ms),
                "tracking": stage(self.tracking_ms),
                "render": stage(self.render_ms),
                "display": stage(self.display_ms),
                "pipeline": stage(self.pipeline_ms),
            },
            "tracking_metrics": {
                "detected_frames": counters.matched_frames,
                "held_frames": counters.held_frames,
                "active_frames": counters.active_frames,
                "hit_frames": counters.hit_frames,
                "pose_live_frames": counters.pose_live_frames,
                "pose_stale_frames": counters.pose_stale_frames,
                "detection_rate_pct": round(_rate(counters.matched_frames, counters.total_frames), 3),
                "hold_rate_pct": round(_rate(counters.held_frames, counters.total_frames), 3),
                "lock_rate_pct": round(_rate(counters.active_frames, counters.total_frames), 3),
                "pose_live_rate_pct": round(_rate(counters.pose_live_frames, counters.total_frames), 3),
                "pose_stale_rate_pct": round(_rate(counters.pose_stale_frames, counters.total_frames), 3),
                "avg_candidates_per_frame": round(_mean_or_zero(self.candidate_counts), 3),
                "avg_primary_confidence": round(_mean_or_zero(self.primary_confidences), 4),
            },
            "queue_drops": queue_drops or {"capture_to_inference": 0, "inference_to_render": 0},
        }
        if self.final_frame is not None and mode == GAME_MODE_TARGET:
            summary["target_metrics"] = {
                "score": self.final_frame.current_score,
            }
        if self.final_frame is not None and mode == GAME_MODE_JUGGLE:
            summary["juggle_metrics"] = {
                "current_streak": self.final_frame.current_score,
                "best_streak": self.final_frame.best_score,
                "juggles_scored": self.final_frame.total_score_events,
                "status": self.final_frame.status_label,
                "pose_live_rate_pct": round(_rate(counters.pose_live_frames, counters.total_frames), 3),
                "pose_stale_rate_pct": round(_rate(counters.pose_stale_frames, counters.total_frames), 3),
                "contact_candidates": self.final_frame.contact_candidates,
                "pending_candidates": self.final_frame.pending_candidates,
                "ground_suppressed_events": self.final_frame.ground_suppressed_events,
                "body_part_counts": self.final_frame.body_part_counts,
                "pose_backend": self.final_frame.pose_backend,
                "pose_quality": round(self.final_frame.pose_quality, 3),
            }
        return summary


def _mean_or_zero(values: list[float] | list[int]) -> float:
    if not values:
        return 0.0
    return float(sum(values) / len(values))


def _rate(count: int, total: int) -> float:
    if total <= 0:
        return 0.0
    return count / total * 100.0


def _copy_counters(counters: PipelineCounters) -> PipelineCounters:
    return replace(counters)


def _select_inference_device() -> tuple[Any, str]:
    try:
        import torch
    except ImportError:
        return "cpu", "cpu"

    if torch.cuda.is_available():
        torch.backends.cudnn.benchmark = True
        return 0, torch.cuda.get_device_name(0)

    return "cpu", "cpu"


def _build_predict_kwargs(width: int, height: int) -> tuple[dict[str, Any], str]:
    device, device_name = _select_inference_device()
    predict_kwargs: dict[str, Any] = {
        "conf": CANDIDATE_CONF_THRESHOLD,
        "iou": IOU_THRESHOLD,
        "classes": [SPORTS_BALL_CLASS_ID],
        "max_det": MAX_DETECTIONS,
        "imgsz": max(width, height),
        "verbose": False,
        "device": device,
    }
    return predict_kwargs, device_name


def _build_pose_predict_kwargs(device: Any, pose_imgsz: int, pose_conf: float) -> dict[str, Any]:
    return {
        "conf": pose_conf,
        "imgsz": pose_imgsz,
        "verbose": False,
        "device": device,
        "classes": [0],
    }


def _warmup_detector(model, predict_kwargs: dict[str, Any], width: int, height: int) -> None:
    warmup_frame = np.zeros((height, width, 3), dtype=np.uint8)
    model.predict(warmup_frame, **predict_kwargs)


def process_capture_packet(
    packet: CapturePacket,
    state: TrackerRuntimeState,
    model,
    predict_kwargs: dict[str, Any],
    pose_runtime: Optional[PoseRuntimeContext],
    gamma_lut: np.ndarray,
    clahe: cv2.CLAHE,
    rng: np.random.Generator,
    render_cache: RenderCache,
    *,
    game_mode: str = GAME_MODE_TARGET,
    juggle_count_threshold: float = JUGGLE_COUNT_THRESHOLD,
    juggle_lookahead_frames: int = JUGGLE_LOOKAHEAD_FRAMES,
    juggle_prominence_radius_fraction: float = JUGGLE_PROMINENCE_RADIUS_FRACTION,
    juggle_ground_margin_radius_fraction: float = JUGGLE_GROUND_MARGIN_RADIUS_FRACTION,
    on_score: Optional[Callable[[int], None]] = None,
) -> tuple[TrackerRuntimeState, ProcessedFrame]:
    frame_time = packet.capture_finished_at
    stage_timings = StageTimings(capture_ms=packet.capture_ms)
    counters = state.counters
    counters.total_frames += 1

    preprocess_started_at = time.perf_counter()
    enhanced = preprocess_frame(packet.frame, gamma_lut, clahe)
    stage_timings.preprocess_ms = (time.perf_counter() - preprocess_started_at) * 1000.0

    inference_started_at = time.perf_counter()
    results = model.predict(enhanced, **predict_kwargs)
    pose_results: Optional[PoseBackendResults] = None
    if game_mode == GAME_MODE_JUGGLE and pose_runtime is not None:
        pose_results = infer_pose_backends(packet.frame, pose_runtime)
    stage_timings.inference_ms = (time.perf_counter() - inference_started_at) * 1000.0

    tracking_started_at = time.perf_counter()
    track = state.track
    motion = state.motion
    next_track_id = state.next_track_id
    track, motion = predict_track(track, motion, frame_time)

    candidate_started_at = time.perf_counter()
    candidates = extract_candidates(results)
    primary_candidate = choose_primary_candidate(candidates, track)
    stage_timings.candidate_ms = (time.perf_counter() - candidate_started_at) * 1000.0

    if primary_candidate is not None:
        track, motion, next_track_id = update_track(
            track,
            motion,
            primary_candidate,
            next_track_id,
            frame_time,
        )
        counters.matched_frames += 1
    else:
        track, motion = advance_track(track, motion)
        if track is not None:
            counters.held_frames += 1

    target_mode_state = state.target_mode
    target_mode_frame: Optional[TargetModeFrame] = None
    juggle_mode_state = state.juggle_mode
    pose_state = state.pose
    pose_frame: Optional[PoseFrame] = None
    juggle_event: Optional[JuggleEventPrediction] = None
    current_score = 0
    best_score = 0
    total_score_events = counters.hit_frames
    status_label = game_mode.title()
    body_part_counts: dict[str, int] = {}
    ground_suppressed_events = 0
    contact_candidates = 0
    pending_candidates = 0
    pose_backend = "none"
    pose_quality = 0.0
    displayed_juggle_event: Optional[JuggleEventPrediction] = None

    if game_mode == GAME_MODE_TARGET:
        target_mode_state, target_mode_frame, target_scored = step_target_mode(
            state.target_mode,
            track,
            packet.frame.shape[:2],
            frame_time,
            rng,
            render_cache,
        )
        if target_scored:
            counters.hit_frames += 1
            if on_score is not None:
                on_score(target_mode_frame.hit_streak)
        current_score = target_mode_frame.score
        total_score_events = counters.hit_frames
        status_label = "Target"
    elif game_mode == GAME_MODE_JUGGLE:
        pose_state, pose_frame = update_pose_state_from_backends(
            state.pose,
            pose_results,
            track,
            packet.frame.shape[:2],
            frame_time,
        )
        if pose_frame.live:
            counters.pose_live_frames += 1
        elif pose_frame.stale:
            counters.pose_stale_frames += 1
        juggle_mode_state, juggle_event = update_juggle_state(
            state.juggle_mode,
            track,
            pose_frame,
            frame_time,
            packet.frame.shape[:2],
            frame_index=packet.frame_index,
            count_threshold=juggle_count_threshold,
            lookahead_frames=juggle_lookahead_frames,
            prominence_radius_fraction=juggle_prominence_radius_fraction,
            ground_margin_radius_fraction=juggle_ground_margin_radius_fraction,
        )
        if juggle_event is not None and juggle_event.counted:
            counters.hit_frames += 1
            if on_score is not None:
                on_score(juggle_mode_state.current_streak)

        current_score = juggle_mode_state.current_streak
        best_score = juggle_mode_state.best_streak
        total_score_events = juggle_mode_state.total_juggles
        status_label = juggle_mode_state.status_label
        body_part_counts = dict(juggle_mode_state.body_part_counts)
        ground_suppressed_events = juggle_mode_state.ground_suppressed_events
        contact_candidates = juggle_mode_state.contact_candidates
        pending_candidates = len(juggle_mode_state.pending_candidates)
        pose_backend = pose_frame.backend if pose_frame is not None else "none"
        pose_quality = pose_frame.quality if pose_frame is not None else 0.0
        if juggle_event is not None:
            displayed_juggle_event = juggle_event
        elif (
            juggle_mode_state.last_prediction is not None
            and juggle_mode_state.last_prediction_at is not None
            and frame_time - juggle_mode_state.last_prediction_at <= JUGGLE_LAST_EVENT_DISPLAY_SECONDS
        ):
            displayed_juggle_event = juggle_mode_state.last_prediction
    else:
        raise ValueError(f"Unsupported game mode: {game_mode}")

    if track is not None:
        counters.active_frames += 1

    stage_timings.tracking_ms = (time.perf_counter() - tracking_started_at) * 1000.0
    stage_timings.pipeline_ms = (time.perf_counter() - packet.capture_started_at) * 1000.0

    updated_state = TrackerRuntimeState(
        track=track,
        motion=motion,
        target_mode=target_mode_state,
        juggle_mode=juggle_mode_state,
        pose=pose_state,
        next_track_id=next_track_id,
        counters=counters,
    )
    frame_result = ProcessedFrame(
        frame_index=packet.frame_index,
        frame=packet.frame,
        frame_time=frame_time,
        stage_timings=stage_timings,
        track=track,
        target=target_mode_frame.target if target_mode_frame is not None else None,
        score_effects=target_mode_frame.score_effects if target_mode_frame is not None else [],
        game_mode=game_mode,
        target_mode=target_mode_frame,
        pose_frame=pose_frame,
        juggle_event=juggle_event,
        candidates_count=len(candidates),
        primary_candidate_confidence=(
            float(primary_candidate.confidence) if primary_candidate is not None else None
        ),
        counters=_copy_counters(counters),
        current_score=current_score,
        best_score=best_score,
        total_score_events=total_score_events,
        status_label=status_label,
        body_part_counts=body_part_counts,
        ground_suppressed_events=ground_suppressed_events,
        contact_candidates=contact_candidates,
        pending_candidates=pending_candidates,
        pose_backend=pose_backend,
        pose_quality=pose_quality,
        displayed_juggle_event=displayed_juggle_event,
    )
    return updated_state, frame_result


def render_processed_frame(
    frame_result: ProcessedFrame,
    render_cache: RenderCache,
    *,
    fps: float,
) -> tuple[np.ndarray, float]:
    render_started_at = time.perf_counter()
    frame = frame_result.frame

    if frame_result.track is not None:
        draw_track(frame, frame_result.track)
    if frame_result.game_mode == GAME_MODE_JUGGLE:
        draw_pose_overlay(frame, frame_result.pose_frame)
    elif frame_result.target_mode is not None:
        draw_target_mode(
            frame,
            frame_result.target_mode,
            frame_result.frame_time,
            render_cache=render_cache,
        )

    counters = frame_result.counters
    draw_label(
        frame,
        f"FPS: {fps:.1f}",
        8,
        HUD_BASELINE_Y,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
    draw_label(
        frame,
        f"Det: {_rate(counters.matched_frames, counters.total_frames):.1f}%",
        8,
        HUD_BASELINE_Y + HUD_LINE_HEIGHT,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
    draw_label(
        frame,
        f"Hold: {_rate(counters.held_frames, counters.total_frames):.1f}%",
        8,
        HUD_BASELINE_Y + HUD_LINE_HEIGHT * 2,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
    draw_label(
        frame,
        f"Lock: {_rate(counters.active_frames, counters.total_frames):.1f}%",
        8,
        HUD_BASELINE_Y + HUD_LINE_HEIGHT * 3,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
    draw_label(
        frame,
        f"Cands: {frame_result.candidates_count}",
        8,
        HUD_BASELINE_Y + HUD_LINE_HEIGHT * 4,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
    if frame_result.primary_candidate_confidence is not None:
        draw_label(
            frame,
            f"Conf: {frame_result.primary_candidate_confidence:.2f}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 5,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )

    if frame_result.game_mode == GAME_MODE_TARGET:
        draw_label_right(
            frame,
            f"Score: {frame_result.current_score}",
            8,
            HUD_BASELINE_Y,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
    elif frame_result.game_mode == GAME_MODE_JUGGLE:
        draw_label_right(
            frame,
            f"Current: {frame_result.current_score}",
            8,
            HUD_BASELINE_Y,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
        draw_label_right(
            frame,
            f"Best: {frame_result.best_score}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
        pose_source = "None"
        if frame_result.pose_frame is not None and frame_result.pose_frame.available:
            freshness = "Live" if frame_result.pose_frame.live else "Held"
            pose_source = f"{frame_result.pose_backend.title()} {freshness}"
        draw_label_right(
            frame,
            f"Pose: {pose_source}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 2,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
        draw_label_right(
            frame,
            f"Pose Q: {frame_result.pose_quality:.2f}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 3,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
        event_label = "None"
        if frame_result.displayed_juggle_event is not None:
            event_label = frame_result.displayed_juggle_event.event_class.value.title()
        draw_label_right(
            frame,
            f"Event: {event_label}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 4,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
        draw_label_right(
            frame,
            f"State: {frame_result.status_label}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 5,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
        draw_label_right(
            frame,
            f"Pending: {frame_result.pending_candidates}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 6,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )

    render_ms = (time.perf_counter() - render_started_at) * 1000.0
    return frame, render_ms


def run_benchmark(
    cap: cv2.VideoCapture,
    *,
    source_label: str,
    game_mode: str,
    model,
    predict_kwargs: dict[str, Any],
    pose_runtime: Optional[PoseRuntimeContext],
    gamma_lut: np.ndarray,
    clahe: cv2.CLAHE,
    rng: np.random.Generator,
    render_cache: RenderCache,
    juggle_count_threshold: float,
    juggle_lookahead_frames: int,
    juggle_prominence_radius_fraction: float,
    juggle_ground_margin_radius_fraction: float,
    max_frames: Optional[int],
    benchmark_output: Optional[str],
) -> dict[str, Any]:
    runtime_state = TrackerRuntimeState()
    benchmark = BenchmarkAccumulator(wall_started_at=time.perf_counter())
    fps_history: deque[float] = deque(maxlen=10)
    previous_frame_time: Optional[float] = None

    frame_index = 0
    while True:
        if max_frames is not None and frame_index >= max_frames:
            break

        capture_started_at = time.perf_counter()
        ret, frame = cap.read()
        capture_finished_at = time.perf_counter()
        if not ret:
            break

        frame_index += 1
        frame = mirror_frame(frame)
        packet = CapturePacket(
            frame_index=frame_index,
            frame=frame,
            capture_started_at=capture_started_at,
            capture_finished_at=capture_finished_at,
        )
        runtime_state, frame_result = process_capture_packet(
            packet,
            runtime_state,
            model,
            predict_kwargs,
            pose_runtime,
            gamma_lut,
            clahe,
            rng,
            render_cache,
            game_mode=game_mode,
            juggle_count_threshold=juggle_count_threshold,
            juggle_lookahead_frames=juggle_lookahead_frames,
            juggle_prominence_radius_fraction=juggle_prominence_radius_fraction,
            juggle_ground_margin_radius_fraction=juggle_ground_margin_radius_fraction,
        )

        if previous_frame_time is not None:
            fps_history.append(1.0 / max(frame_result.frame_time - previous_frame_time, 1e-6))
        previous_frame_time = frame_result.frame_time
        fps = sum(fps_history) / len(fps_history) if fps_history else 0.0

        _rendered_frame, render_ms = render_processed_frame(
            frame_result,
            render_cache,
            fps=fps,
        )
        frame_result.stage_timings.render_ms = render_ms
        benchmark.add(frame_result)

    benchmark.wall_finished_at = time.perf_counter()
    frame_size = (int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)))
    summary = benchmark.summary(source=source_label, frame_size=frame_size, mode=game_mode)
    summary_json = json.dumps(summary, indent=2)
    print(summary_json)

    if benchmark_output:
        Path(benchmark_output).write_text(summary_json + "\n", encoding="utf-8")

    return summary


def _capture_worker(
    cap: cv2.VideoCapture,
    frame_store: LatestValueStore[CapturePacket],
    stop_event: threading.Event,
    max_frames: Optional[int],
) -> None:
    frame_index = 0
    try:
        while not stop_event.is_set():
            if max_frames is not None and frame_index >= max_frames:
                break

            capture_started_at = time.perf_counter()
            ret, frame = cap.read()
            capture_finished_at = time.perf_counter()
            if not ret:
                break

            frame_index += 1
            frame_store.put(
                CapturePacket(
                    frame_index=frame_index,
                    frame=mirror_frame(frame),
                    capture_started_at=capture_started_at,
                    capture_finished_at=capture_finished_at,
                )
            )
    finally:
        stop_event.set()
        frame_store.close()


def _inference_worker(
    frame_store: LatestValueStore[CapturePacket],
    result_store: LatestValueStore[ProcessedFrame],
    stop_event: threading.Event,
    *,
    game_mode: str,
    model,
    predict_kwargs: dict[str, Any],
    pose_runtime: Optional[PoseRuntimeContext],
    gamma_lut: np.ndarray,
    clahe: cv2.CLAHE,
    rng: np.random.Generator,
    render_cache: RenderCache,
    juggle_count_threshold: float,
    juggle_lookahead_frames: int,
    juggle_prominence_radius_fraction: float,
    juggle_ground_margin_radius_fraction: float,
    on_score: Optional[Callable[[int], None]],
) -> None:
    runtime_state = TrackerRuntimeState()
    last_version = 0
    try:
        while not stop_event.is_set():
            last_version, packet = frame_store.get_latest(last_version, timeout_s=0.1)
            if packet is None:
                if frame_store.closed:
                    break
                continue

            runtime_state, frame_result = process_capture_packet(
                packet,
                runtime_state,
                model,
                predict_kwargs,
                pose_runtime,
                gamma_lut,
                clahe,
                rng,
                render_cache,
                game_mode=game_mode,
                juggle_count_threshold=juggle_count_threshold,
                juggle_lookahead_frames=juggle_lookahead_frames,
                juggle_prominence_radius_fraction=juggle_prominence_radius_fraction,
                juggle_ground_margin_radius_fraction=juggle_ground_margin_radius_fraction,
                on_score=on_score,
            )
            result_store.put(frame_result)
    finally:
        result_store.close()


def run_live_tracker(
    cap: cv2.VideoCapture,
    *,
    source_label: str,
    game_mode: str,
    model,
    predict_kwargs: dict[str, Any],
    pose_runtime: Optional[PoseRuntimeContext],
    gamma_lut: np.ndarray,
    clahe: cv2.CLAHE,
    rng: np.random.Generator,
    render_cache: RenderCache,
    juggle_count_threshold: float,
    juggle_lookahead_frames: int,
    juggle_prominence_radius_fraction: float,
    juggle_ground_margin_radius_fraction: float,
    max_frames: Optional[int],
    display: bool,
) -> None:
    frame_store: LatestValueStore[CapturePacket] = LatestValueStore()
    result_store: LatestValueStore[ProcessedFrame] = LatestValueStore()
    stop_event = threading.Event()
    capture_thread = threading.Thread(
        target=_capture_worker,
        args=(cap, frame_store, stop_event, max_frames),
        daemon=True,
    )
    inference_thread = threading.Thread(
        target=_inference_worker,
        args=(frame_store, result_store, stop_event),
        kwargs={
            "game_mode": game_mode,
            "model": model,
            "predict_kwargs": predict_kwargs,
            "pose_runtime": pose_runtime,
            "gamma_lut": gamma_lut,
            "clahe": clahe,
            "rng": rng,
            "render_cache": render_cache,
            "juggle_count_threshold": juggle_count_threshold,
            "juggle_lookahead_frames": juggle_lookahead_frames,
            "juggle_prominence_radius_fraction": juggle_prominence_radius_fraction,
            "juggle_ground_margin_radius_fraction": juggle_ground_margin_radius_fraction,
            "on_score": (
                play_target_score_sound if game_mode == GAME_MODE_TARGET else None
            ),
        },
        daemon=True,
    )

    if display:
        cv2.namedWindow("Ball Tracker", cv2.WINDOW_NORMAL)

    capture_thread.start()
    inference_thread.start()

    fps_history: deque[float] = deque(maxlen=10)
    previous_frame_time: Optional[float] = None
    last_result_version = 0

    try:
        while True:
            last_result_version, frame_result = result_store.get_latest(last_result_version, timeout_s=0.1)
            if frame_result is None:
                if result_store.closed and (stop_event.is_set() or frame_store.closed):
                    break
                continue

            if previous_frame_time is not None:
                fps_history.append(1.0 / max(frame_result.frame_time - previous_frame_time, 1e-6))
            previous_frame_time = frame_result.frame_time
            fps = sum(fps_history) / len(fps_history) if fps_history else 0.0

            rendered_frame, render_ms = render_processed_frame(
                frame_result,
                render_cache,
                fps=fps,
            )

            display_started_at = time.perf_counter()
            if display:
                cv2.imshow("Ball Tracker", rendered_frame)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    stop_event.set()
                    break
            frame_result.stage_timings.display_ms = (time.perf_counter() - display_started_at) * 1000.0
            frame_result.stage_timings.render_ms = render_ms
    finally:
        stop_event.set()
        frame_store.close()
        result_store.close()
        capture_thread.join(timeout=1.0)
        inference_thread.join(timeout=1.0)
        if display:
            cv2.destroyAllWindows()


def main() -> None:
    from ultralytics import YOLO

    parser = argparse.ArgumentParser(description="Real-time single-ball tracker")
    parser.add_argument(
        "--mode",
        choices=(GAME_MODE_TARGET, GAME_MODE_JUGGLE),
        default=GAME_MODE_TARGET,
        help="Gameplay mode to run",
    )
    parser.add_argument("--source", default="0", help="Webcam index or video file / stream URL")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--benchmark", action="store_true", help="Run a replay benchmark without display")
    parser.add_argument("--benchmark-output", help="Optional JSON file path for benchmark metrics")
    parser.add_argument("--max-frames", type=int, help="Optional processing cap for live runs or benchmarks")
    parser.add_argument("--no-display", action="store_true", help="Disable the OpenCV preview window")
    parser.add_argument("--pose-model", default=POSE_MODEL_PATH, help="Pose model path for juggle mode")
    parser.add_argument(
        "--pose-backend",
        choices=POSE_BACKEND_CHOICES,
        default=POSE_BACKEND_AUTO,
        help="Lower-body pose backend for juggle mode",
    )
    parser.add_argument(
        "--pose-imgsz",
        type=int,
        default=POSE_IMG_SIZE,
        help="Pose inference image size for juggle mode",
    )
    parser.add_argument(
        "--pose-conf",
        type=float,
        default=POSE_CONF_THRESHOLD,
        help="Pose confidence threshold for juggle mode",
    )
    parser.add_argument(
        "--juggle-lookahead-frames",
        type=int,
        default=JUGGLE_LOOKAHEAD_FRAMES,
        help="Fixed lookahead used to confirm juggle reversal candidates",
    )
    parser.add_argument(
        "--juggle-prominence-radius-fraction",
        type=float,
        default=JUGGLE_PROMINENCE_RADIUS_FRACTION,
        help="Minimum apex prominence as a fraction of ball radius",
    )
    parser.add_argument(
        "--juggle-proof-threshold",
        type=float,
        default=JUGGLE_COUNT_THRESHOLD,
        help="Minimum body-part proof score required to count a juggle",
    )
    parser.add_argument(
        "--juggle-ground-margin-radius-fraction",
        type=float,
        default=JUGGLE_GROUND_MARGIN_RADIUS_FRACTION,
        help="Ground band size as a fraction of ball radius",
    )
    args = parser.parse_args()

    model = YOLO(MODEL_PATH)
    predict_kwargs, device_name = _build_predict_kwargs(args.width, args.height)
    pose_model = None
    pose_predict_kwargs: Optional[dict[str, Any]] = None
    pose_runtime: Optional[PoseRuntimeContext] = None
    if args.mode == GAME_MODE_JUGGLE:
        if args.pose_backend in {POSE_BACKEND_AUTO, "yolo"}:
            pose_model = YOLO(args.pose_model)
            pose_predict_kwargs = _build_pose_predict_kwargs(
                predict_kwargs["device"],
                args.pose_imgsz,
                args.pose_conf,
            )
        pose_runtime = create_pose_runtime(
            args.pose_backend,
            yolo_model=pose_model,
            yolo_predict_kwargs=pose_predict_kwargs,
        )
    _warmup_detector(model, predict_kwargs, args.width, args.height)
    if pose_model is not None and pose_predict_kwargs is not None:
        _warmup_detector(pose_model, pose_predict_kwargs, args.width, args.height)

    gamma_lut = build_gamma_lut()
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    rng = np.random.default_rng()
    render_cache = RenderCache()
    if args.mode == GAME_MODE_TARGET:
        render_cache.prime(
            target_radius_for_frame((args.height, args.width)),
            tuple((points, 1.0) for points in (1, 2, 3, 4, 5)),
        )

    source = parse_source(args.source)
    cap = cv2.VideoCapture(source)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    if not cap.isOpened():
        print(f"ERROR: Could not open source '{args.source}'")
        return

    print(f"Tracking started on device: {device_name} ({args.mode} mode)")

    try:
        if args.benchmark:
            run_benchmark(
                cap,
                source_label=str(args.source),
                game_mode=args.mode,
                model=model,
                predict_kwargs=predict_kwargs,
                pose_runtime=pose_runtime,
                gamma_lut=gamma_lut,
                clahe=clahe,
                rng=rng,
                render_cache=render_cache,
                juggle_count_threshold=args.juggle_proof_threshold,
                juggle_lookahead_frames=args.juggle_lookahead_frames,
                juggle_prominence_radius_fraction=args.juggle_prominence_radius_fraction,
                juggle_ground_margin_radius_fraction=args.juggle_ground_margin_radius_fraction,
                max_frames=args.max_frames,
                benchmark_output=args.benchmark_output,
            )
        else:
            run_live_tracker(
                cap,
                source_label=str(args.source),
                game_mode=args.mode,
                model=model,
                predict_kwargs=predict_kwargs,
                pose_runtime=pose_runtime,
                gamma_lut=gamma_lut,
                clahe=clahe,
                rng=rng,
                render_cache=render_cache,
                juggle_count_threshold=args.juggle_proof_threshold,
                juggle_lookahead_frames=args.juggle_lookahead_frames,
                juggle_prominence_radius_fraction=args.juggle_prominence_radius_fraction,
                juggle_ground_margin_radius_fraction=args.juggle_ground_margin_radius_fraction,
                max_frames=args.max_frames,
                display=not args.no_display,
            )
    finally:
        close_pose_runtime(pose_runtime)
        cap.release()


if __name__ == "__main__":
    main()
