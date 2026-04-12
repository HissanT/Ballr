from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

import numpy as np

from ball_tracker_rendering import (
    RenderCache,
    draw_label_right,
    draw_scored_target_effects,
    draw_target,
)
from ball_tracker_targets import (
    ScoredTargetEffect,
    TARGET_COMBO_POPUP_SCALE,
    TargetState,
    combo_multiplier_for_streak,
    expire_target,
    next_combo_threshold_for_streak,
    score_target,
    scored_target_effect_is_active,
    spawn_initial_target,
    target_base_points,
    target_fade_alpha,
    target_has_expired,
    target_hit,
    target_radius_for_frame,
)
from ball_tracker_tracking import BallTrack

HUD_BASELINE_Y = 22
HUD_LINE_HEIGHT = 22
HUD_FONT_SCALE = 0.45
HUD_FONT_THICKNESS = 1
HUD_RIGHT_MARGIN = 8
TARGET_POPUP_DESTINATION_X_OFFSET = 104.0
TARGET_POPUP_DESTINATION_Y = 40.0
COMBO_POPUP_DESTINATION_X = 104.0
COMBO_POPUP_DESTINATION_Y = 40.0


@dataclass
class TargetModeState:
    target: Optional[TargetState] = None
    score_effects: list[ScoredTargetEffect] = field(default_factory=list)
    combo_effects: list[ScoredTargetEffect] = field(default_factory=list)
    score: int = 0
    hit_streak: int = 0


@dataclass(frozen=True)
class TargetModeFrame:
    target: TargetState
    score_effects: list[ScoredTargetEffect]
    combo_effects: list[ScoredTargetEffect]
    score: int
    hit_streak: int
    combo_multiplier: int
    next_combo_threshold: int
    target_fade_alpha: float


def step_target_mode(
    state: TargetModeState,
    track: Optional[BallTrack],
    frame_size: tuple[int, int],
    timestamp: float,
    rng: np.random.Generator,
    render_cache: RenderCache,
) -> tuple[TargetModeState, TargetModeFrame, bool]:
    score_effects = [
        effect for effect in state.score_effects if scored_target_effect_is_active(effect, timestamp)
    ]
    combo_effects = [
        effect for effect in state.combo_effects if scored_target_effect_is_active(effect, timestamp)
    ]
    score = state.score
    hit_streak = state.hit_streak
    target = state.target
    did_score = False

    if target is None:
        target = spawn_initial_target(
            frame_size,
            target_radius_for_frame(frame_size),
            timestamp,
            rng=rng,
            ball_track=track,
        )
        render_cache.prime(target.radius, tuple((points, 1.0) for points in range(1, 6)))

    if target_has_expired(target, timestamp):
        miss_result = expire_target(
            target,
            timestamp,
            frame_size,
            rng=rng,
            ball_track=track,
        )
        target = miss_result.target
        score_effects.append(miss_result.effect)
        score = max(score - miss_result.penalty_points, 0)
        hit_streak = 0
        render_cache.prime(target.radius, ((miss_result.effect.points, miss_result.effect.popup_scale),))
    elif target_hit(track, target):
        base_points = target_base_points(target, timestamp)
        hit_result = score_target(
            target,
            timestamp,
            frame_size,
            base_points=base_points,
            combo_multiplier=combo_multiplier_for_streak(hit_streak),
            rng=rng,
            ball_track=track,
        )
        target = hit_result.target
        score_effects.append(hit_result.effect)
        combo_effects.append(
            ScoredTargetEffect(
                center=hit_result.effect.center.copy(),
                radius=hit_result.effect.radius,
                points=1,
                started_at=timestamp,
                show_burst=False,
                popup_scale=TARGET_COMBO_POPUP_SCALE,
            )
        )
        score += hit_result.awarded_points
        hit_streak += 1
        render_cache.prime(
            target.radius,
            (
                (hit_result.awarded_points, hit_result.effect.popup_scale),
                (1, TARGET_COMBO_POPUP_SCALE),
            ),
        )
        did_score = True

    mode_state = TargetModeState(
        target=target,
        score_effects=score_effects,
        combo_effects=combo_effects,
        score=score,
        hit_streak=hit_streak,
    )
    mode_frame = TargetModeFrame(
        target=target,
        score_effects=score_effects,
        combo_effects=combo_effects,
        score=score,
        hit_streak=hit_streak,
        combo_multiplier=combo_multiplier_for_streak(hit_streak),
        next_combo_threshold=next_combo_threshold_for_streak(hit_streak),
        target_fade_alpha=target_fade_alpha(target, timestamp),
    )
    return mode_state, mode_frame, did_score


def _score_popup_destination(frame: np.ndarray) -> np.ndarray:
    return np.array(
        (frame.shape[1] - TARGET_POPUP_DESTINATION_X_OFFSET, TARGET_POPUP_DESTINATION_Y),
        dtype=np.float32,
    )


def _combo_popup_destination() -> np.ndarray:
    return np.array(
        (COMBO_POPUP_DESTINATION_X, COMBO_POPUP_DESTINATION_Y),
        dtype=np.float32,
    )


def draw_target_mode(
    frame: np.ndarray,
    mode_frame: TargetModeFrame,
    timestamp: float,
    *,
    render_cache: RenderCache,
) -> None:
    draw_target(
        frame,
        mode_frame.target,
        timestamp,
        render_cache=render_cache,
        alpha=mode_frame.target_fade_alpha,
    )
    draw_scored_target_effects(
        frame,
        mode_frame.score_effects,
        timestamp,
        render_cache=render_cache,
        popup_destination=_score_popup_destination(frame),
    )
    draw_scored_target_effects(
        frame,
        mode_frame.combo_effects,
        timestamp,
        render_cache=render_cache,
        popup_destination=_combo_popup_destination(),
    )
    draw_label_right(
        frame,
        f"Score: {mode_frame.score}",
        HUD_RIGHT_MARGIN,
        HUD_BASELINE_Y,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )

    if mode_frame.hit_streak <= 0:
        return

    draw_label_right(
        frame,
        f"Combo: {mode_frame.hit_streak}/{mode_frame.next_combo_threshold}",
        HUD_RIGHT_MARGIN,
        HUD_BASELINE_Y + HUD_LINE_HEIGHT,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
    draw_label_right(
        frame,
        f"x{mode_frame.combo_multiplier}",
        HUD_RIGHT_MARGIN,
        HUD_BASELINE_Y + HUD_LINE_HEIGHT * 2,
        font_scale=HUD_FONT_SCALE,
        thickness=HUD_FONT_THICKNESS,
    )
