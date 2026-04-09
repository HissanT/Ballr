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

from ball_tracker_audio import TARGET_SOUND_PATH, play_score_sound as _play_score_sound
from ball_tracker_juggling import JuggleState, update_juggle_state
from ball_tracker_pose import (
    POSE_CONF_THRESHOLD,
    POSE_IMG_SIZE,
    POSE_MODEL_PATH,
    PoseFrame,
    PoseState,
    update_pose_state,
)
from ball_tracker_rendering import (
    PIL_LANCZOS,
    RenderCache,
    TARGET_BADGE_CORE_RADIUS,
    TARGET_BADGE_FILL_RADIUS,
    TARGET_BADGE_OUTER_RADIUS,
    TARGET_IDLE_BADGE_CORE_COLOR,
    TARGET_IDLE_BADGE_FILL_COLOR,
    TARGET_IDLE_BADGE_RIM_COLOR,
    TARGET_IDLE_DASH_COLOR,
    TARGET_IDLE_DASH_COUNT,
    TARGET_IDLE_DASH_SWEEP_DEGREES,
    TARGET_IDLE_STAR_COLOR,
    TARGET_REFERENCE_BACKGROUND_RGB,
    TARGET_REFERENCE_COLLISION_RADIUS,
    TARGET_REFERENCE_HEIGHT,
    TARGET_REFERENCE_IDLE_CENTER,
    TARGET_REFERENCE_ORBIT_RADIUS,
    TARGET_REFERENCE_ORBIT_THICKNESS,
    TARGET_REFERENCE_SCORED_CENTER,
    TARGET_REFERENCE_WIDTH,
    TARGET_RENDER_OVERSAMPLE,
    TARGET_SCORED_BADGE_CORE_COLOR,
    TARGET_SCORED_BADGE_FILL_COLOR,
    TARGET_SCORED_BADGE_RIM_COLOR,
    TARGET_SCORED_NODE_COLOR,
    TARGET_SCORED_NODE_COUNT,
    TARGET_SCORED_NODE_RADIUS,
    TARGET_SCORED_RING_COLOR,
    TARGET_SCORED_STAR_COLOR,
    TARGET_STAR_INNER_RADIUS,
    TARGET_STAR_OUTER_RADIUS,
    composite_sprite,
    draw_arc_with_round_caps,
    draw_circle,
    draw_label,
    draw_label_right,
    draw_pose_overlay,
    draw_scored_target_effects,
    draw_target,
    draw_track,
    lerp_color,
    lerp_point,
    mirror_frame,
    polar_point,
    render_target_reference_rgb,
    render_target_reference_rgba,
    render_target_sprite,
    smoothstep,
    star_points,
    with_alpha,
)
from ball_tracker_targets import (
    TARGET_BALL_CLEARANCE,
    TARGET_IDLE_PULSE_PERIOD_SECONDS,
    TARGET_IDLE_PULSE_SCALE,
    TARGET_LOWER_Y_FRACTION,
    TARGET_MAX_RADIUS,
    TARGET_MIN_RADIUS,
    TARGET_RADIUS_RATIO,
    TARGET_RESPAWN_DISTANCE_MULTIPLIER,
    TARGET_SCORE_BURST_SECONDS,
    TARGET_SCORE_EFFECT_SECONDS,
    TARGET_SCORE_POPUP_DELAY_SECONDS,
    TARGET_SCORE_POPUP_SECONDS,
    TARGET_SCORE_VALUE,
    TARGET_SPAWN_ATTEMPTS,
    ScoredTargetEffect,
    TargetState,
    clamp_unit,
    score_target,
    scored_target_effect_burst_progress,
    scored_target_effect_elapsed,
    scored_target_effect_is_active,
    scored_target_effect_popup_progress,
    spawn_target,
    target_hit,
    target_radius_for_frame,
    target_spawn_bounds,
)
from ball_tracker_tracking import (
    CANDIDATE_CONF_THRESHOLD,
    BallMotionState,
    CENTER_SMOOTHING,
    INIT_CONF_THRESHOLD,
    IOU_THRESHOLD,
    MAX_DETECTIONS,
    MAX_MISSES,
    MODEL_PATH,
    MOTION_DECAY,
    RADIUS_SMOOTHING,
    REACQUIRE_CONF_THRESHOLD,
    SPORTS_BALL_CLASS_ID,
    VELOCITY_SMOOTHING,
    BallTrack,
    DetectionCandidate,
    advance_track,
    choose_primary_candidate,
    extract_candidates,
    predict_track,
    predicted_center,
    score_candidate,
    track_gate_radius,
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
    target: Optional[TargetState] = None
    score_effects: list[ScoredTargetEffect] = field(default_factory=list)
    juggle: Optional[JuggleState] = None
    pose: Optional[PoseState] = None
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
    current_score: int = 0
    best_score: int = 0
    status_label: str = ""
    total_score_events: int = 0
    drop_resets: int = 0
    loss_resets: int = 0
    warmup_seconds: float = 0.0
    pose_frame: Optional[PoseFrame] = None
    body_part_counts: dict[str, int] = field(default_factory=dict)
    ground_suppressed_events: int = 0
    contact_candidates: int = 0


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
                "score": (
                    self.final_frame.current_score
                    if self.final_frame.current_score
                    else (
                        self.final_frame.target.score
                        if self.final_frame.target is not None
                        else 0
                    )
                ),
            }
        if self.final_frame is not None and mode == GAME_MODE_JUGGLE:
            summary["juggle_metrics"] = {
                "current_streak": self.final_frame.current_score,
                "best_streak": self.final_frame.best_score,
                "juggles_scored": self.final_frame.total_score_events,
                "drop_resets": self.final_frame.drop_resets,
                "loss_resets": self.final_frame.loss_resets,
                "warmup_seconds": round(self.final_frame.warmup_seconds, 3),
                "pose_live_rate_pct": round(_rate(counters.pose_live_frames, counters.total_frames), 3),
                "pose_stale_rate_pct": round(_rate(counters.pose_stale_frames, counters.total_frames), 3),
                "contact_candidates": self.final_frame.contact_candidates,
                "ground_suppressed_events": self.final_frame.ground_suppressed_events,
                "body_part_counts": self.final_frame.body_part_counts,
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
        "max_det": 4,
    }


def _warmup_detector(model, predict_kwargs: dict[str, Any], width: int, height: int) -> None:
    warmup_frame = np.zeros((height, width, 3), dtype=np.uint8)
    model.predict(warmup_frame, **predict_kwargs)


def process_capture_packet(
    packet: CapturePacket,
    state: TrackerRuntimeState,
    model,
    predict_kwargs: dict[str, Any],
    pose_model,
    pose_predict_kwargs: Optional[dict[str, Any]],
    gamma_lut: np.ndarray,
    clahe: cv2.CLAHE,
    rng: np.random.Generator,
    render_cache: RenderCache,
    *,
    game_mode: str = GAME_MODE_TARGET,
    on_score: Optional[Callable[[], None]] = None,
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
    pose_results = None
    if game_mode == GAME_MODE_JUGGLE and pose_model is not None and pose_predict_kwargs is not None:
        pose_results = pose_model.predict(packet.frame, **pose_predict_kwargs)
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

    target: Optional[TargetState] = state.target
    score_effects: list[ScoredTargetEffect] = []
    juggle_state = state.juggle
    pose_state = state.pose
    pose_frame: Optional[PoseFrame] = None
    current_score = 0
    best_score = 0
    status_label = game_mode.title()
    total_score_events = counters.hit_frames
    drop_resets = 0
    loss_resets = 0
    warmup_seconds = 0.0
    body_part_counts: dict[str, int] = {}
    ground_suppressed_events = 0
    contact_candidates = 0

    if game_mode == GAME_MODE_TARGET:
        score_effects = [
            effect for effect in state.score_effects if scored_target_effect_is_active(effect, frame_time)
        ]
        if target is None:
            target_radius = target_radius_for_frame(packet.frame.shape)
            render_cache.prime(target_radius, (TARGET_SCORE_VALUE,))
            target = TargetState(
                center=spawn_target(packet.frame.shape[:2], target_radius, rng=rng),
                radius=target_radius,
            )

        if target_hit(track, target):
            target, scored_effect = score_target(
                target,
                frame_time,
                packet.frame.shape[:2],
                rng=rng,
                ball_track=track,
            )
            score_effects.append(scored_effect)
            counters.hit_frames += 1
            if on_score is not None:
                on_score()

        current_score = target.score
        best_score = target.score
        status_label = "Target"
        total_score_events = counters.hit_frames
    elif game_mode == GAME_MODE_JUGGLE:
        target = None
        score_effects = []
        pose_state, pose_frame = update_pose_state(
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
        juggle_state, juggle_scored = update_juggle_state(
            state.juggle,
            track,
            pose_frame,
            frame_time,
            packet.frame.shape[:2],
        )
        if juggle_scored:
            counters.hit_frames += 1

        current_score = juggle_state.current_streak
        best_score = juggle_state.best_streak
        status_label = juggle_state.status_label
        total_score_events = juggle_state.total_juggles
        drop_resets = juggle_state.drop_resets
        loss_resets = juggle_state.loss_resets
        warmup_seconds = juggle_state.warmup_seconds
        body_part_counts = dict(juggle_state.body_part_counts)
        ground_suppressed_events = juggle_state.ground_suppressed_events
        contact_candidates = juggle_state.contact_candidates
    else:
        raise ValueError(f"Unsupported game mode: {game_mode}")

    if track is not None:
        counters.active_frames += 1

    stage_timings.tracking_ms = (time.perf_counter() - tracking_started_at) * 1000.0
    stage_timings.pipeline_ms = (time.perf_counter() - packet.capture_started_at) * 1000.0

    updated_state = TrackerRuntimeState(
        track=track,
        motion=motion,
        target=target,
        score_effects=score_effects,
        juggle=juggle_state,
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
        target=target,
        score_effects=score_effects,
        candidates_count=len(candidates),
        primary_candidate_confidence=(
            float(primary_candidate.confidence) if primary_candidate is not None else None
        ),
        counters=_copy_counters(counters),
        game_mode=game_mode,
        current_score=current_score,
        best_score=best_score,
        status_label=status_label,
        total_score_events=total_score_events,
        drop_resets=drop_resets,
        loss_resets=loss_resets,
        warmup_seconds=warmup_seconds,
        pose_frame=pose_frame,
        body_part_counts=body_part_counts,
        ground_suppressed_events=ground_suppressed_events,
        contact_candidates=contact_candidates,
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

    if frame_result.game_mode == GAME_MODE_TARGET and frame_result.target is not None:
        draw_target(frame, frame_result.target, frame_result.frame_time, render_cache=render_cache)
        draw_scored_target_effects(
            frame,
            frame_result.score_effects,
            frame_result.frame_time,
            render_cache=render_cache,
        )
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
        draw_label_right(
            frame,
            f"Status: {frame_result.status_label}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 2,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
        pose_source = "None"
        if frame_result.pose_frame is not None and frame_result.pose_frame.available:
            pose_source = "Live" if frame_result.pose_frame.live else "Held"
        draw_label_right(
            frame,
            f"Pose: {pose_source}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 3,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
        )
        contact_label = "None"
        if frame_result.pose_frame is not None and frame_result.pose_frame.nearest_contact is not None:
            contact_label = frame_result.pose_frame.nearest_contact.display_name
        draw_label_right(
            frame,
            f"Contact: {contact_label}",
            8,
            HUD_BASELINE_Y + HUD_LINE_HEIGHT * 4,
            font_scale=HUD_FONT_SCALE,
            thickness=HUD_FONT_THICKNESS,
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

    render_ms = (time.perf_counter() - render_started_at) * 1000.0
    return frame, render_ms


def run_benchmark(
    cap: cv2.VideoCapture,
    *,
    source_label: str,
    game_mode: str,
    model,
    predict_kwargs: dict[str, Any],
    pose_model,
    pose_predict_kwargs: Optional[dict[str, Any]],
    gamma_lut: np.ndarray,
    clahe: cv2.CLAHE,
    rng: np.random.Generator,
    render_cache: RenderCache,
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
            pose_model,
            pose_predict_kwargs,
            gamma_lut,
            clahe,
            rng,
            render_cache,
            game_mode=game_mode,
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
    pose_model,
    pose_predict_kwargs: Optional[dict[str, Any]],
    gamma_lut: np.ndarray,
    clahe: cv2.CLAHE,
    rng: np.random.Generator,
    render_cache: RenderCache,
    on_score: Optional[Callable[[], None]],
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
                pose_model,
                pose_predict_kwargs,
                gamma_lut,
                clahe,
                rng,
                render_cache,
                game_mode=game_mode,
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
    pose_model,
    pose_predict_kwargs: Optional[dict[str, Any]],
    gamma_lut: np.ndarray,
    clahe: cv2.CLAHE,
    rng: np.random.Generator,
    render_cache: RenderCache,
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
            "pose_model": pose_model,
            "pose_predict_kwargs": pose_predict_kwargs,
            "gamma_lut": gamma_lut,
            "clahe": clahe,
            "rng": rng,
            "render_cache": render_cache,
            "on_score": play_score_sound if game_mode == GAME_MODE_TARGET else None,
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
    args = parser.parse_args()

    model = YOLO(MODEL_PATH)
    predict_kwargs, device_name = _build_predict_kwargs(args.width, args.height)
    pose_model = None
    pose_predict_kwargs: Optional[dict[str, Any]] = None
    if args.mode == GAME_MODE_JUGGLE:
        pose_model = YOLO(args.pose_model)
        pose_predict_kwargs = _build_pose_predict_kwargs(
            predict_kwargs["device"],
            args.pose_imgsz,
            args.pose_conf,
        )
    _warmup_detector(model, predict_kwargs, args.width, args.height)
    if pose_model is not None and pose_predict_kwargs is not None:
        _warmup_detector(pose_model, pose_predict_kwargs, args.width, args.height)

    gamma_lut = build_gamma_lut()
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    rng = np.random.default_rng()
    render_cache = RenderCache()
    if args.mode == GAME_MODE_TARGET:
        render_cache.prime(target_radius_for_frame((args.height, args.width)), (TARGET_SCORE_VALUE,))

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
                pose_model=pose_model,
                pose_predict_kwargs=pose_predict_kwargs,
                gamma_lut=gamma_lut,
                clahe=clahe,
                rng=rng,
                render_cache=render_cache,
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
                pose_model=pose_model,
                pose_predict_kwargs=pose_predict_kwargs,
                gamma_lut=gamma_lut,
                clahe=clahe,
                rng=rng,
                render_cache=render_cache,
                max_frames=args.max_frames,
                display=not args.no_display,
            )
    finally:
        cap.release()


if __name__ == "__main__":
    main()
