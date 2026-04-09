from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

import numpy as np

from ball_tracker_pose import PoseFrame
from ball_tracker_tracking import BallTrack, is_track_live

JUGGLE_WARMUP_SECONDS = 0.5
JUGGLE_HISTORY_SECONDS = 1.5
JUGGLE_MIN_CONFIRMED_FRAMES = 2

JUGGLE_CONTACT_WINDOW_SECONDS = 0.20
JUGGLE_RISE_CONFIRM_SECONDS = 0.25
JUGGLE_LOSS_RESET_SECONDS = 0.45
JUGGLE_GROUND_DWELL_SECONDS = 0.18

JUGGLE_CONTACT_SCORE_WEIGHT = 0.45
JUGGLE_TRAJECTORY_SCORE_WEIGHT = 0.35
JUGGLE_CLEARANCE_SCORE_WEIGHT = 0.20
JUGGLE_SCORE_THRESHOLD = 0.70

JUGGLE_CLEARANCE_RISE_RADIUS_MULTIPLIER = 1.5
DESCENDING_ON = 1.5
DESCENDING_OFF = 0.5
RISING_ON = -1.5
RISING_OFF = -0.5

JUGGLE_GROUND_MARGIN_RADIUS_MULTIPLIER = 0.65
JUGGLE_GROUND_MARGIN_MIN = 8.0
JUGGLE_KNEE_ZONE_MARGIN_RADIUS_MULTIPLIER = 0.25
JUGGLE_KNEE_ZONE_MARGIN_MIN = 4.0


class JugglePhase(str, Enum):
    WARMUP = "Warmup"
    READY = "Ready"
    CONTACT_WINDOW = "ContactWindow"
    RISE_WINDOW = "RiseWindow"
    DROP_PENDING = "DropPending"
    LOST = "Lost"


@dataclass(frozen=True)
class JuggleSample:
    timestamp: float
    center: np.ndarray
    radius: float


@dataclass
class PendingContact:
    started_at: float
    contact_y: float
    origin_y: float
    landmark_name: str
    landmark_display_name: str
    landmark_distance: float
    landmark_confidence: float
    contact_score: float = JUGGLE_CONTACT_SCORE_WEIGHT
    trajectory_score: float = 0.0
    clearance_score: float = 0.0

    @property
    def total_score(self) -> float:
        return self.contact_score + self.trajectory_score + self.clearance_score


@dataclass
class JuggleState:
    history: deque[JuggleSample] = field(default_factory=deque)
    phase: JugglePhase = JugglePhase.WARMUP
    current_streak: int = 0
    best_streak: int = 0
    total_juggles: int = 0
    drop_resets: int = 0
    loss_resets: int = 0
    warmup_started_at: Optional[float] = None
    armed_at: Optional[float] = None
    last_live_track_at: Optional[float] = None
    loss_started_at: Optional[float] = None
    pending_contact: Optional[PendingContact] = None
    drop_started_at: Optional[float] = None
    awaiting_rearm: bool = False
    rearm_ready: bool = False
    last_count_at: Optional[float] = None
    ground_blocked_active: bool = False
    status_label: str = JugglePhase.WARMUP.value
    body_part_counts: dict[str, int] = field(default_factory=dict)
    ground_suppressed_events: int = 0
    contact_candidates: int = 0
    pose_live_frames: int = 0
    pose_stale_frames: int = 0
    descending_active: bool = False
    rising_active: bool = False

    @property
    def armed(self) -> bool:
        return self.armed_at is not None

    @property
    def warmup_seconds(self) -> float:
        if self.warmup_started_at is None or self.armed_at is None:
            return 0.0
        return max(0.0, self.armed_at - self.warmup_started_at)


def has_live_juggle_track(track: Optional[BallTrack]) -> bool:
    return is_track_live(track, min_confirmed_frames=JUGGLE_MIN_CONFIRMED_FRAMES)


def update_juggle_state(
    state: Optional[JuggleState],
    track: Optional[BallTrack],
    pose_frame: Optional[PoseFrame],
    timestamp: float,
    frame_size: tuple[int, int],
) -> tuple[JuggleState, bool]:
    del frame_size
    state = state or JuggleState()
    live_track = has_live_juggle_track(track)
    pose_frame = pose_frame or PoseFrame()

    if pose_frame.live:
        state.pose_live_frames += 1
    elif pose_frame.stale:
        state.pose_stale_frames += 1

    if live_track:
        assert track is not None
        _append_live_sample(state, track, timestamp)
        state.last_live_track_at = timestamp
        state.loss_started_at = None
    else:
        _handle_tracking_loss(state, timestamp)
        _update_status(state)
        return state, False

    if not state.armed:
        _advance_warmup(state, pose_frame, timestamp)
        _update_status(state)
        return state, False

    if state.phase == JugglePhase.LOST:
        state.phase = JugglePhase.READY

    scored = False
    effective_radius = _effective_radius(state, track.radius)
    current_y = float(track.center[1])
    vertical_speed = float(track.velocity[1])
    descending, rising = _update_vertical_motion_state(state, vertical_speed)

    knee_line_y = pose_frame.knee_line_y
    ground_y = pose_frame.ground_y
    lower_body_zone = _is_lower_body_zone(current_y, knee_line_y, effective_radius)
    ground_band_overlap = _is_ground_overlap(current_y, ground_y, effective_radius)
    contact_candidate = (
        pose_frame.nearest_contact
        if pose_frame.nearest_contact is not None and pose_frame.nearest_contact.is_valid
        else None
    )

    if state.awaiting_rearm and not state.rearm_ready and not lower_body_zone:
        state.rearm_ready = True
    if state.awaiting_rearm and state.rearm_ready and (descending or lower_body_zone):
        state.awaiting_rearm = False
        state.rearm_ready = False
        if state.pending_contact is None and not ground_band_overlap:
            state.phase = JugglePhase.READY

    if (
        pose_frame.live
        and not state.awaiting_rearm
        and state.pending_contact is None
        and contact_candidate is not None
        and lower_body_zone
        and descending
        and not ground_band_overlap
    ):
        state.contact_candidates += 1
        state.pending_contact = PendingContact(
            started_at=timestamp,
            contact_y=current_y,
            origin_y=_recent_origin_y(state, default=current_y),
            landmark_name=contact_candidate.name,
            landmark_display_name=contact_candidate.display_name,
            landmark_distance=contact_candidate.distance,
            landmark_confidence=contact_candidate.confidence,
        )
        state.phase = JugglePhase.CONTACT_WINDOW
        state.drop_started_at = None

    if state.pending_contact is not None:
        scored = _advance_pending_contact(
            state,
            timestamp,
            current_y,
            knee_line_y,
            effective_radius,
            rising=rising,
        )

    if ground_band_overlap:
        if state.drop_started_at is None:
            state.drop_started_at = timestamp
        if rising and not state.ground_blocked_active and state.pending_contact is None:
            state.ground_suppressed_events += 1
            state.ground_blocked_active = True
        if not scored and state.pending_contact is None:
            state.phase = JugglePhase.DROP_PENDING
        if (
            not scored
            and timestamp - state.drop_started_at >= JUGGLE_GROUND_DWELL_SECONDS
            and state.pending_contact is None
        ):
            _reset_streak(state, "drop")
            state.phase = JugglePhase.DROP_PENDING
    else:
        state.drop_started_at = None
        state.ground_blocked_active = False
        if (
            state.pending_contact is None
            and not state.awaiting_rearm
            and state.phase == JugglePhase.DROP_PENDING
        ):
            state.phase = JugglePhase.READY

    if (
        state.pending_contact is None
        and not state.awaiting_rearm
        and state.phase == JugglePhase.RISE_WINDOW
        and state.last_count_at is not None
        and timestamp - state.last_count_at > JUGGLE_RISE_CONFIRM_SECONDS
    ):
        state.phase = JugglePhase.READY

    _update_status(state)
    return state, scored


def _append_live_sample(state: JuggleState, track: BallTrack, timestamp: float) -> None:
    state.history.append(
        JuggleSample(
            timestamp=timestamp,
            center=track.center.copy(),
            radius=float(track.radius),
        )
    )
    cutoff = timestamp - JUGGLE_HISTORY_SECONDS
    while state.history and state.history[0].timestamp < cutoff:
        state.history.popleft()


def _advance_warmup(state: JuggleState, pose_frame: PoseFrame, timestamp: float) -> None:
    if not pose_frame.live:
        state.warmup_started_at = None
        state.phase = JugglePhase.WARMUP
        return

    if state.warmup_started_at is None:
        state.warmup_started_at = timestamp

    if timestamp - state.warmup_started_at >= JUGGLE_WARMUP_SECONDS:
        state.armed_at = timestamp
        state.phase = JugglePhase.READY


def _handle_tracking_loss(state: JuggleState, timestamp: float) -> None:
    state.descending_active = False
    state.rising_active = False
    if state.loss_started_at is None:
        state.loss_started_at = timestamp

    protected_rise = (
        state.phase == JugglePhase.RISE_WINDOW
        and state.last_count_at is not None
        and timestamp - state.last_count_at <= JUGGLE_LOSS_RESET_SECONDS
    )
    if protected_rise:
        return

    if state.armed and timestamp - state.loss_started_at >= JUGGLE_LOSS_RESET_SECONDS:
        _reset_streak(state, "loss")
        state.phase = JugglePhase.LOST


def _advance_pending_contact(
    state: JuggleState,
    timestamp: float,
    current_y: float,
    knee_line_y: Optional[float],
    effective_radius: float,
    *,
    rising: bool,
) -> bool:
    pending = state.pending_contact
    if pending is None:
        return False

    if rising:
        pending.trajectory_score = JUGGLE_TRAJECTORY_SCORE_WEIGHT
        clearance_rise = max(
            effective_radius * JUGGLE_CLEARANCE_RISE_RADIUS_MULTIPLIER,
            8.0,
        )
        if (
            knee_line_y is not None and current_y <= knee_line_y
        ) or (pending.contact_y - current_y >= clearance_rise):
            pending.clearance_score = JUGGLE_CLEARANCE_SCORE_WEIGHT

        state.phase = JugglePhase.RISE_WINDOW
        if pending.total_score >= JUGGLE_SCORE_THRESHOLD:
            state.current_streak += 1
            state.best_streak = max(state.best_streak, state.current_streak)
            state.total_juggles += 1
            state.body_part_counts[pending.landmark_display_name] = (
                state.body_part_counts.get(pending.landmark_display_name, 0) + 1
            )
            state.pending_contact = None
            state.awaiting_rearm = True
            state.rearm_ready = False
            state.last_count_at = timestamp
            return True

    if timestamp - pending.started_at > JUGGLE_CONTACT_WINDOW_SECONDS:
        state.pending_contact = None
        if not state.awaiting_rearm and state.phase == JugglePhase.CONTACT_WINDOW:
            state.phase = JugglePhase.READY
    return False


def _recent_origin_y(state: JuggleState, *, default: float) -> float:
    if not state.history:
        return default
    recent = [
        float(sample.center[1])
        for sample in state.history
        if state.history[-1].timestamp - sample.timestamp <= 0.6
    ]
    if not recent:
        return default
    return float(min(recent))


def _effective_radius(state: JuggleState, fallback_radius: float) -> float:
    if not state.history:
        return fallback_radius
    radii = np.array([sample.radius for sample in state.history], dtype=np.float32)
    if not len(radii):
        return fallback_radius
    return float(np.median(radii))


def _is_lower_body_zone(current_y: float, knee_line_y: Optional[float], radius: float) -> bool:
    if knee_line_y is None:
        return False
    margin = max(radius * JUGGLE_KNEE_ZONE_MARGIN_RADIUS_MULTIPLIER, JUGGLE_KNEE_ZONE_MARGIN_MIN)
    return current_y >= knee_line_y - margin


def _is_ground_overlap(current_y: float, ground_y: Optional[float], radius: float) -> bool:
    if ground_y is None:
        return False
    margin = max(radius * JUGGLE_GROUND_MARGIN_RADIUS_MULTIPLIER, JUGGLE_GROUND_MARGIN_MIN)
    return current_y + radius >= ground_y - margin


def _reset_streak(state: JuggleState, reason: str) -> None:
    if reason == "drop":
        state.drop_resets += 1
    else:
        state.loss_resets += 1
    state.current_streak = 0
    state.pending_contact = None
    state.awaiting_rearm = False
    state.rearm_ready = False
    state.last_count_at = None
    state.descending_active = False
    state.rising_active = False


def _update_vertical_motion_state(state: JuggleState, vertical_speed: float) -> tuple[bool, bool]:
    if state.descending_active:
        if vertical_speed <= DESCENDING_OFF:
            state.descending_active = False
    elif vertical_speed >= DESCENDING_ON:
        state.descending_active = True
        state.rising_active = False

    if state.rising_active:
        if vertical_speed >= RISING_OFF:
            state.rising_active = False
    elif vertical_speed <= RISING_ON:
        state.rising_active = True
        state.descending_active = False

    return state.descending_active, state.rising_active


def _update_status(state: JuggleState) -> None:
    state.status_label = state.phase.value
