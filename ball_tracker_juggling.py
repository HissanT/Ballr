from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import Optional

import numpy as np

from ball_tracker_tracking import BallTrack, is_track_live

JUGGLE_WARMUP_SECONDS = 2.0
JUGGLE_HISTORY_SECONDS = 3.0
JUGGLE_MIN_SAMPLES_TO_ARM = 12
JUGGLE_LOW_BAND_PERCENTILE = 82.0
JUGGLE_LOW_BAND_MARGIN_MULTIPLIER = 0.45
JUGGLE_MIN_DESCENT_RADIUS_MULTIPLIER = 1.15
JUGGLE_MIN_DESCENT_PIXELS = 18.0
JUGGLE_MIN_REBOUND_RADIUS_MULTIPLIER = 1.0
JUGGLE_MIN_REBOUND_PIXELS = 20.0
JUGGLE_DIRECTION_SPEED_RADIUS_MULTIPLIER = 7.5
JUGGLE_DIRECTION_SPEED_MIN = 120.0
JUGGLE_RESET_CLEAR_RISE_RADIUS_MULTIPLIER = 0.8
JUGGLE_RESET_CLEAR_RISE_PIXELS = 14.0
JUGGLE_DROP_RESET_SECONDS = 0.55
JUGGLE_LOSS_RESET_SECONDS = 0.45
JUGGLE_GENERAL_LOSS_RESET_SECONDS = 1.20
JUGGLE_STATUS_RESET_SECONDS = 0.8
JUGGLE_MIN_CONFIRMED_FRAMES = 2


@dataclass(frozen=True)
class JuggleSample:
    timestamp: float
    center: np.ndarray
    radius: float


@dataclass
class PendingJuggle:
    contact_at: float
    contact_y: float
    min_rebound_rise: float


@dataclass
class DropPending:
    started_at: float
    contact_y: float
    reason: str
    loss_started_at: Optional[float] = None


@dataclass
class JuggleState:
    history: deque[JuggleSample] = field(default_factory=deque)
    current_streak: int = 0
    best_streak: int = 0
    total_juggles: int = 0
    drop_resets: int = 0
    loss_resets: int = 0
    armed: bool = False
    warmup_started_at: Optional[float] = None
    armed_at: Optional[float] = None
    last_live_track_at: Optional[float] = None
    loss_started_at: Optional[float] = None
    pending_juggle: Optional[PendingJuggle] = None
    drop_pending: Optional[DropPending] = None
    status_label: str = "Warmup"
    last_reset_reason: Optional[str] = None
    last_reset_at: Optional[float] = None

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
    timestamp: float,
    frame_size: tuple[int, int],
) -> tuple[JuggleState, bool]:
    state = state or JuggleState()
    live_track = has_live_juggle_track(track)

    if live_track:
        assert track is not None
        _append_live_sample(state, track, timestamp)
        state.last_live_track_at = timestamp
        state.loss_started_at = None
        if state.drop_pending is not None:
            state.drop_pending.loss_started_at = None

        if not state.armed and _history_is_armed(state):
            state.armed = True
            state.armed_at = timestamp

        if not state.armed:
            _update_status(state, timestamp, live_track=True)
            return state, False

        effective_radius = _effective_radius(state, track.radius)
        low_band_y = _low_band_y(state, frame_size[0])
        down_speed_threshold = max(
            effective_radius * JUGGLE_DIRECTION_SPEED_RADIUS_MULTIPLIER,
            JUGGLE_DIRECTION_SPEED_MIN,
        )

        _start_or_update_drop_pending(
            state,
            timestamp,
            float(track.center[1]),
            effective_radius,
            low_band_y,
            frame_size[0],
            down_speed_threshold,
        )
        _seed_pending_juggle(state, effective_radius, low_band_y, down_speed_threshold)

        scored = _confirm_pending_juggle(state, timestamp, float(track.center[1]))
        _maybe_clear_drop_pending(state, float(track.center[1]), effective_radius)
        _maybe_reset_drop(state, timestamp, float(track.center[1]), effective_radius)
        _update_status(state, timestamp, live_track=True)
        return state, scored

    if state.loss_started_at is None:
        state.loss_started_at = timestamp
    if state.drop_pending is not None and state.drop_pending.loss_started_at is None:
        state.drop_pending.loss_started_at = timestamp

    if state.armed:
        if state.drop_pending is not None:
            loss_started_at = state.drop_pending.loss_started_at or state.loss_started_at or timestamp
            if timestamp - loss_started_at >= JUGGLE_LOSS_RESET_SECONDS:
                _reset_streak(state, "loss", timestamp)
        elif (
            state.current_streak > 0
            and state.loss_started_at is not None
            and timestamp - state.loss_started_at >= JUGGLE_GENERAL_LOSS_RESET_SECONDS
        ):
            _reset_streak(state, "loss", timestamp)

    _update_status(state, timestamp, live_track=False)
    return state, False


def _append_live_sample(state: JuggleState, track: BallTrack, timestamp: float) -> None:
    state.history.append(
        JuggleSample(
            timestamp=timestamp,
            center=track.center.copy(),
            radius=track.radius,
        )
    )
    if state.warmup_started_at is None and state.history:
        state.warmup_started_at = state.history[0].timestamp
    cutoff = timestamp - JUGGLE_HISTORY_SECONDS
    while state.history and state.history[0].timestamp < cutoff:
        state.history.popleft()


def _history_is_armed(state: JuggleState) -> bool:
    if len(state.history) < JUGGLE_MIN_SAMPLES_TO_ARM:
        return False
    return (state.history[-1].timestamp - state.history[0].timestamp) >= JUGGLE_WARMUP_SECONDS


def _effective_radius(state: JuggleState, fallback_radius: float) -> float:
    if not state.history:
        return fallback_radius
    radii = np.array([sample.radius for sample in state.history], dtype=np.float32)
    return float(np.median(radii)) if len(radii) else fallback_radius


def _low_band_y(state: JuggleState, frame_height: int) -> float:
    if not state.history:
        return frame_height * 0.75
    ys = np.array([sample.center[1] for sample in state.history], dtype=np.float32)
    if len(ys) < 4:
        return float(ys.max())
    return float(np.percentile(ys, JUGGLE_LOW_BAND_PERCENTILE))


def _current_vertical_speed(state: JuggleState) -> Optional[float]:
    if len(state.history) < 2:
        return None
    previous = state.history[-2]
    current = state.history[-1]
    dt = max(current.timestamp - previous.timestamp, 1e-6)
    return float((current.center[1] - previous.center[1]) / dt)


def _start_or_update_drop_pending(
    state: JuggleState,
    timestamp: float,
    current_y: float,
    effective_radius: float,
    low_band_y: float,
    frame_height: int,
    down_speed_threshold: float,
) -> None:
    vertical_speed = _current_vertical_speed(state)
    if vertical_speed is None or vertical_speed < down_speed_threshold:
        return

    low_margin = max(effective_radius * JUGGLE_LOW_BAND_MARGIN_MULTIPLIER, 10.0)
    near_bottom = current_y + effective_radius >= frame_height - max(effective_radius * 0.6, 12.0)
    if current_y < low_band_y - low_margin and not near_bottom:
        return

    if state.drop_pending is None:
        state.drop_pending = DropPending(
            started_at=timestamp,
            contact_y=current_y,
            reason="low_descent",
        )
        return

    state.drop_pending.contact_y = max(state.drop_pending.contact_y, current_y)


def _seed_pending_juggle(
    state: JuggleState,
    effective_radius: float,
    low_band_y: float,
    down_speed_threshold: float,
) -> None:
    if len(state.history) < 3:
        return

    oldest, middle, newest = tuple(state.history)[-3:]
    dt1 = max(middle.timestamp - oldest.timestamp, 1e-6)
    dt2 = max(newest.timestamp - middle.timestamp, 1e-6)
    previous_speed = float((middle.center[1] - oldest.center[1]) / dt1)
    current_speed = float((newest.center[1] - middle.center[1]) / dt2)
    contact_y = float(middle.center[1])

    if previous_speed < down_speed_threshold or current_speed > -down_speed_threshold:
        return

    recent_origin_y = min(
        sample.center[1]
        for sample in state.history
        if 0.0 <= middle.timestamp - sample.timestamp <= 0.75
    )
    descent = contact_y - float(recent_origin_y)
    min_descent = max(
        effective_radius * JUGGLE_MIN_DESCENT_RADIUS_MULTIPLIER,
        JUGGLE_MIN_DESCENT_PIXELS,
    )
    low_margin = max(effective_radius * JUGGLE_LOW_BAND_MARGIN_MULTIPLIER, 10.0)
    if contact_y < low_band_y - low_margin or descent < min_descent:
        return

    if state.pending_juggle is not None and abs(middle.timestamp - state.pending_juggle.contact_at) < 0.12:
        return

    state.pending_juggle = PendingJuggle(
        contact_at=middle.timestamp,
        contact_y=contact_y,
        min_rebound_rise=max(
            effective_radius * JUGGLE_MIN_REBOUND_RADIUS_MULTIPLIER,
            JUGGLE_MIN_REBOUND_PIXELS,
        ),
    )

    if state.drop_pending is None:
        state.drop_pending = DropPending(
            started_at=middle.timestamp,
            contact_y=contact_y,
            reason="low_contact",
        )
    else:
        state.drop_pending.contact_y = max(state.drop_pending.contact_y, contact_y)


def _confirm_pending_juggle(state: JuggleState, timestamp: float, current_y: float) -> bool:
    if state.pending_juggle is None:
        return False

    rebound_rise = state.pending_juggle.contact_y - current_y
    if rebound_rise >= state.pending_juggle.min_rebound_rise:
        state.current_streak += 1
        state.best_streak = max(state.best_streak, state.current_streak)
        state.total_juggles += 1
        state.pending_juggle = None
        state.drop_pending = None
        state.last_reset_reason = None
        state.last_reset_at = None
        return True

    if timestamp - state.pending_juggle.contact_at > JUGGLE_DROP_RESET_SECONDS:
        state.pending_juggle = None

    return False


def _maybe_clear_drop_pending(state: JuggleState, current_y: float, effective_radius: float) -> None:
    if state.drop_pending is None:
        return

    clear_rise = max(
        effective_radius * JUGGLE_RESET_CLEAR_RISE_RADIUS_MULTIPLIER,
        JUGGLE_RESET_CLEAR_RISE_PIXELS,
    )
    if current_y <= state.drop_pending.contact_y - clear_rise:
        state.drop_pending = None


def _maybe_reset_drop(
    state: JuggleState,
    timestamp: float,
    current_y: float,
    effective_radius: float,
) -> None:
    if state.drop_pending is None:
        return

    clear_rise = max(
        effective_radius * JUGGLE_RESET_CLEAR_RISE_RADIUS_MULTIPLIER,
        JUGGLE_RESET_CLEAR_RISE_PIXELS,
    )
    if (
        timestamp - state.drop_pending.started_at >= JUGGLE_DROP_RESET_SECONDS
        and current_y > state.drop_pending.contact_y - clear_rise
    ):
        _reset_streak(state, "drop", timestamp)


def _reset_streak(state: JuggleState, reason: str, timestamp: float) -> None:
    if reason == "drop":
        state.drop_resets += 1
    else:
        state.loss_resets += 1

    state.current_streak = 0
    state.pending_juggle = None
    state.drop_pending = None
    state.last_reset_reason = reason
    state.last_reset_at = timestamp


def _update_status(state: JuggleState, timestamp: float, *, live_track: bool) -> None:
    if not state.armed:
        state.status_label = "Warmup"
        return

    if (
        state.last_reset_reason is not None
        and state.last_reset_at is not None
        and timestamp - state.last_reset_at <= JUGGLE_STATUS_RESET_SECONDS
    ):
        state.status_label = "Drop" if state.last_reset_reason == "drop" else "Lost"
        return

    if state.drop_pending is not None:
        state.status_label = "Recover"
        return

    state.status_label = "Armed" if live_track else "Tracking"
