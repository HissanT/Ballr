import math
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from typing import Optional

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from .ball_tracker_pose import PoseFrame
from .ball_tracker_targets import (
    TARGET_IDLE_PULSE_PERIOD_SECONDS,
    TARGET_IDLE_PULSE_SCALE,
    TARGET_SCORE_BURST_SECONDS,
    TARGET_SCORE_EFFECT_SECONDS,
    TARGET_SCORE_POPUP_DELAY_SECONDS,
    TARGET_SCORE_POPUP_SECONDS,
    ScoredTargetEffect,
    TargetState,
    clamp_unit,
    scored_target_effect_burst_progress,
    scored_target_effect_elapsed,
    scored_target_effect_popup_progress,
)
from .ball_tracker_tracking import BallTrack

TARGET_REFERENCE_WIDTH = 216
TARGET_REFERENCE_HEIGHT = 202
TARGET_REFERENCE_IDLE_CENTER = (107.5, 94.5)
TARGET_REFERENCE_SCORED_CENTER = (111.5, 96.5)
TARGET_REFERENCE_COLLISION_RADIUS = 84.0
TARGET_REFERENCE_ORBIT_RADIUS = 79.0
TARGET_REFERENCE_ORBIT_THICKNESS = 6.0
TARGET_IDLE_DASH_COUNT = 21
TARGET_IDLE_DASH_SWEEP_DEGREES = 7.5
TARGET_SCORED_NODE_COUNT = 8
TARGET_SCORED_NODE_RADIUS = 5.0
TARGET_BADGE_OUTER_RADIUS = 59.0
TARGET_BADGE_FILL_RADIUS = 53.0
TARGET_BADGE_CORE_RADIUS = 31.0
TARGET_STAR_OUTER_RADIUS = 18.0
TARGET_STAR_INNER_RADIUS = 7.5
TARGET_RENDER_OVERSAMPLE = 4
TARGET_REFERENCE_BACKGROUND_RGB = (38, 38, 36)

TARGET_IDLE_DASH_COLOR = (173, 223, 204)
TARGET_IDLE_BADGE_RIM_COLOR = (75, 156, 120)
TARGET_IDLE_BADGE_FILL_COLOR = (229, 245, 239)
TARGET_IDLE_BADGE_CORE_COLOR = (75, 156, 120)
TARGET_IDLE_STAR_COLOR = (183, 216, 201)

TARGET_SCORED_RING_COLOR = (122, 200, 167)
TARGET_SCORED_NODE_COLOR = (228, 163, 69)
TARGET_SCORED_BADGE_RIM_COLOR = (75, 156, 120)
TARGET_SCORED_BADGE_FILL_COLOR = (173, 223, 204)
TARGET_SCORED_BADGE_CORE_COLOR = (50, 109, 88)
TARGET_SCORED_STAR_COLOR = (245, 248, 247)

PIL_LANCZOS = Image.Resampling.LANCZOS if hasattr(Image, "Resampling") else Image.LANCZOS
TARGET_SCORE_BURST_EXPAND_SCALE = 1.35
TARGET_SCORE_POPUP_RISE_MULTIPLIER = 1.15
TARGET_SCORE_POPUP_FONT_SCALE = 1.25
TARGET_SCORE_POPUP_FONT_MIN_SIZE = 36
TARGET_SCORE_POPUP_FONT_MAX_SIZE = 72
TARGET_SCORE_POPUP_OUTLINE_ALPHA = 96
TARGET_IDLE_CACHE_PHASES = 24
TARGET_SCORE_BURST_CACHE_FRAMES = 14
TARGET_SCORE_POPUP_CACHE_FRAMES = 24
TARGET_SCORE_POPUP_FONT_PATHS = (
    Path(r"C:\Windows\Fonts\LEMONMILK-Bold.otf"),
    Path(r"C:\Windows\Fonts\LEMONMILK-Bold.ttf"),
    Path(r"C:\Windows\Fonts\LEMONMILK.otf"),
    Path(r"C:\Windows\Fonts\LEMONMILK.ttf"),
    Path.home() / "Downloads" / "LEMONMILK-Bold.otf",
    Path.home() / "Downloads" / "LEMONMILK-Bold.ttf",
    Path.home() / "Desktop" / "LEMONMILK-Bold.otf",
    Path.home() / "Desktop" / "LEMONMILK-Bold.ttf",
    Path.home() / "Documents" / "LEMONMILK-Bold.otf",
    Path.home() / "Documents" / "LEMONMILK-Bold.ttf",
    Path(r"C:\Windows\Fonts\arialbd.ttf"),
)


def mirror_frame(frame: np.ndarray) -> np.ndarray:
    return cv2.flip(frame, 1)


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    if edge0 == edge1:
        return 1.0 if value >= edge1 else 0.0

    t = clamp_unit((value - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def lerp_color(start: tuple[int, int, int], end: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = clamp_unit(t)
    return tuple(
        int(round(start[index] + (end[index] - start[index]) * t))
        for index in range(3)
    )


def with_alpha(color: tuple[int, int, int], alpha: float) -> tuple[int, int, int, int]:
    return color + (int(round(255 * clamp_unit(alpha))),)


def lerp_point(
    start: tuple[float, float],
    end: tuple[float, float],
    t: float,
) -> tuple[float, float]:
    t = clamp_unit(t)
    return (
        start[0] + (end[0] - start[0]) * t,
        start[1] + (end[1] - start[1]) * t,
    )


def polar_point(center: tuple[float, float], radius: float, angle_degrees: float) -> tuple[float, float]:
    angle_radians = math.radians(angle_degrees)
    return (
        center[0] + math.cos(angle_radians) * radius,
        center[1] + math.sin(angle_radians) * radius,
    )


def star_points(
    center: tuple[float, float],
    outer_radius: float,
    inner_radius: float,
    rotation_degrees: float = -90.0,
) -> list[tuple[float, float]]:
    points: list[tuple[float, float]] = []
    for index in range(10):
        radius = outer_radius if index % 2 == 0 else inner_radius
        angle = rotation_degrees + index * 36.0
        points.append(polar_point(center, radius, angle))
    return points


def draw_circle(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    radius: float,
    *,
    fill: Optional[tuple[int, int, int, int]] = None,
    outline: Optional[tuple[int, int, int, int]] = None,
    width: int = 1,
) -> None:
    bbox = (
        center[0] - radius,
        center[1] - radius,
        center[0] + radius,
        center[1] + radius,
    )
    draw.ellipse(bbox, fill=fill, outline=outline, width=width)


def draw_arc_with_round_caps(
    draw: ImageDraw.ImageDraw,
    center: tuple[float, float],
    radius: float,
    start_degrees: float,
    end_degrees: float,
    width: float,
    fill: tuple[int, int, int, int],
    rounded: bool = True,
) -> None:
    bbox = (
        center[0] - radius,
        center[1] - radius,
        center[0] + radius,
        center[1] + radius,
    )
    pixel_width = max(int(round(width)), 1)
    draw.arc(bbox, start=start_degrees, end=end_degrees, fill=fill, width=pixel_width)

    if not rounded:
        return

    cap_radius = pixel_width / 2.0
    for angle in (start_degrees, end_degrees):
        cap_center = polar_point(center, radius, angle)
        draw_circle(draw, cap_center, cap_radius, fill=fill)


def composite_sprite(
    frame: np.ndarray,
    sprite_rgba: np.ndarray,
    anchor: tuple[float, float],
    center: np.ndarray,
) -> None:
    sprite_h, sprite_w = sprite_rgba.shape[:2]
    x0 = int(round(float(center[0]) - anchor[0]))
    y0 = int(round(float(center[1]) - anchor[1]))
    x1 = x0 + sprite_w
    y1 = y0 + sprite_h

    clip_x0 = max(x0, 0)
    clip_y0 = max(y0, 0)
    clip_x1 = min(x1, frame.shape[1])
    clip_y1 = min(y1, frame.shape[0])
    if clip_x0 >= clip_x1 or clip_y0 >= clip_y1:
        return

    sprite_x0 = clip_x0 - x0
    sprite_y0 = clip_y0 - y0
    sprite_x1 = sprite_x0 + (clip_x1 - clip_x0)
    sprite_y1 = sprite_y0 + (clip_y1 - clip_y0)

    sprite_roi = sprite_rgba[sprite_y0:sprite_y1, sprite_x0:sprite_x1]
    sprite_alpha = sprite_roi[:, :, 3:4].astype(np.float32) / 255.0
    if not np.any(sprite_alpha):
        return

    sprite_bgr = sprite_roi[:, :, :3][:, :, ::-1].astype(np.float32)
    frame_roi = frame[clip_y0:clip_y1, clip_x0:clip_x1].astype(np.float32)
    frame[clip_y0:clip_y1, clip_x0:clip_x1] = np.clip(
        sprite_bgr * sprite_alpha + frame_roi * (1.0 - sprite_alpha),
        0.0,
        255.0,
    ).astype(np.uint8)


def resize_reference_sprite(
    reference_sprite: np.ndarray,
    reference_center: tuple[float, float],
    scale: float,
) -> tuple[np.ndarray, tuple[float, float]]:
    scaled_width = max(int(round(reference_sprite.shape[1] * scale)), 1)
    scaled_height = max(int(round(reference_sprite.shape[0] * scale)), 1)
    sprite = cv2.resize(reference_sprite, (scaled_width, scaled_height), interpolation=cv2.INTER_LINEAR)
    anchor = (reference_center[0] * scale, reference_center[1] * scale)
    return sprite, anchor


@dataclass(frozen=True)
class CachedSprite:
    sprite: np.ndarray
    anchor: tuple[float, float]


@dataclass
class RenderAtlas:
    radius: int
    idle_sprites: list[CachedSprite]
    burst_sprites: list[CachedSprite]
    popup_sprites: dict[tuple[int, int], list[CachedSprite]]


class RenderCache:
    def __init__(self) -> None:
        self._atlases: dict[int, RenderAtlas] = {}

    def prime(self, radius: int, popup_specs: tuple[tuple[int, float], ...] = ()) -> None:
        self._get_atlas(radius, popup_specs)

    def get_idle_sprite(self, radius: int, timestamp: float) -> CachedSprite:
        atlas = self._get_atlas(radius)
        phase = (timestamp % TARGET_IDLE_PULSE_PERIOD_SECONDS) / TARGET_IDLE_PULSE_PERIOD_SECONDS
        return atlas.idle_sprites[_quantize_progress_index(phase, len(atlas.idle_sprites))]

    def get_burst_sprite(self, effect: ScoredTargetEffect, timestamp: float) -> Optional[CachedSprite]:
        if not effect.show_burst:
            return None

        elapsed = scored_target_effect_elapsed(effect, timestamp)
        if elapsed >= TARGET_SCORE_BURST_SECONDS:
            return None

        atlas = self._get_atlas(effect.radius)
        progress = scored_target_effect_burst_progress(effect, timestamp)
        return atlas.burst_sprites[_quantize_progress_index(progress, len(atlas.burst_sprites))]

    def get_popup_sprite(self, effect: ScoredTargetEffect, timestamp: float) -> Optional[tuple[CachedSprite, float]]:
        elapsed = scored_target_effect_elapsed(effect, timestamp)
        if elapsed < TARGET_SCORE_POPUP_DELAY_SECONDS or elapsed >= TARGET_SCORE_EFFECT_SECONDS:
            return None

        popup_key = _popup_sprite_key(effect.points, effect.popup_scale)
        atlas = self._get_atlas(effect.radius, ((effect.points, effect.popup_scale),))
        progress = scored_target_effect_popup_progress(effect, timestamp)
        sprite = atlas.popup_sprites[popup_key][
            _quantize_progress_index(progress, len(atlas.popup_sprites[popup_key]))
        ]
        return sprite, smoothstep(0.0, 1.0, progress)

    def _get_atlas(
        self,
        radius: int,
        popup_specs: tuple[tuple[int, float], ...] = (),
    ) -> RenderAtlas:
        atlas = self._atlases.get(radius)
        if atlas is None:
            atlas = self._build_atlas(radius)
            self._atlases[radius] = atlas

        missing_popup_specs = tuple(
            spec for spec in popup_specs if _popup_sprite_key(spec[0], spec[1]) not in atlas.popup_sprites
        )
        if missing_popup_specs:
            for points, popup_scale in missing_popup_specs:
                atlas.popup_sprites[_popup_sprite_key(points, popup_scale)] = _build_popup_sprite_frames(
                    points,
                    radius,
                    popup_scale=popup_scale,
                )

        return atlas

    def _build_atlas(self, radius: int) -> RenderAtlas:
        idle_scale = radius / TARGET_REFERENCE_COLLISION_RADIUS
        idle_sprites = []
        for index in range(TARGET_IDLE_CACHE_PHASES):
            phase = index / max(TARGET_IDLE_CACHE_PHASES, 1)
            idle_pulse = math.sin(2.0 * math.pi * phase)
            reference_sprite = render_target_reference_rgba(0.0, idle_pulse=idle_pulse)
            sprite, anchor = resize_reference_sprite(reference_sprite, TARGET_REFERENCE_IDLE_CENTER, idle_scale)
            idle_sprites.append(CachedSprite(sprite=sprite, anchor=anchor))

        scored_reference_sprite = render_target_reference_rgba(1.0, idle_pulse=0.0)
        burst_sprites = []
        for index in range(TARGET_SCORE_BURST_CACHE_FRAMES):
            progress = _progress_for_index(index, TARGET_SCORE_BURST_CACHE_FRAMES)
            eased_progress = smoothstep(0.0, 1.0, progress)
            scale = idle_scale * (1.0 + (TARGET_SCORE_BURST_EXPAND_SCALE - 1.0) * eased_progress)
            sprite, anchor = resize_reference_sprite(
                scored_reference_sprite,
                TARGET_REFERENCE_SCORED_CENTER,
                scale,
            )
            burst_sprites.append(
                CachedSprite(
                    sprite=apply_sprite_alpha(sprite, 1.0 - eased_progress),
                    anchor=anchor,
                )
            )

        return RenderAtlas(
            radius=radius,
            idle_sprites=idle_sprites,
            burst_sprites=burst_sprites,
            popup_sprites={},
        )


def _progress_for_index(index: int, frame_count: int) -> float:
    if frame_count <= 1:
        return 1.0
    return index / (frame_count - 1)


def _quantize_progress_index(progress: float, frame_count: int) -> int:
    if frame_count <= 1:
        return 0
    return int(np.clip(round(clamp_unit(progress) * (frame_count - 1)), 0, frame_count - 1))


def _popup_sprite_key(points: int, popup_scale: float) -> tuple[int, int]:
    return points, int(round(popup_scale * 1000.0))


def _build_popup_sprite_frames(points: int, radius: int, *, popup_scale: float = 1.0) -> list[CachedSprite]:
    popup_frames = []
    for index in range(TARGET_SCORE_POPUP_CACHE_FRAMES):
        progress = _progress_for_index(index, TARGET_SCORE_POPUP_CACHE_FRAMES)
        eased_progress = smoothstep(0.0, 1.0, progress)
        sprite, anchor = render_score_popup_text_sprite(
            points,
            radius,
            1.0 - eased_progress,
            popup_scale=popup_scale,
        )
        popup_frames.append(CachedSprite(sprite=sprite, anchor=anchor))
    return popup_frames


def apply_sprite_alpha(sprite_rgba: np.ndarray, alpha: float) -> np.ndarray:
    alpha = clamp_unit(alpha)
    if alpha >= 0.999:
        return sprite_rgba

    sprite = sprite_rgba.copy()
    sprite[:, :, 3] = np.clip(sprite[:, :, 3].astype(np.float32) * alpha, 0.0, 255.0).astype(np.uint8)
    return sprite


@lru_cache(maxsize=32)
def load_score_popup_font(font_size: int) -> ImageFont.ImageFont | ImageFont.FreeTypeFont:
    for font_path in TARGET_SCORE_POPUP_FONT_PATHS:
        if not font_path.exists():
            continue
        try:
            return ImageFont.truetype(str(font_path), font_size)
        except OSError:
            continue

    return ImageFont.load_default()


def render_score_popup_text_sprite(
    points: int,
    radius: int,
    alpha: float,
    *,
    popup_scale: float = 1.0,
) -> tuple[np.ndarray, tuple[float, float]]:
    font_size = int(
        round(
            np.clip(
                radius * TARGET_SCORE_POPUP_FONT_SCALE * popup_scale,
                TARGET_SCORE_POPUP_FONT_MIN_SIZE,
                TARGET_SCORE_POPUP_FONT_MAX_SIZE,
            )
        )
    )
    stroke_width = max(1, font_size // 18)
    font = load_score_popup_font(font_size)
    text = f"{points:+d}"

    measure_canvas = Image.new("RGBA", (1, 1), (0, 0, 0, 0))
    measure_draw = ImageDraw.Draw(measure_canvas)
    bbox = measure_draw.textbbox((0, 0), text, font=font, stroke_width=stroke_width)
    padding = stroke_width + 4
    width = max(bbox[2] - bbox[0] + padding * 2, 1)
    height = max(bbox[3] - bbox[1] + padding * 2, 1)
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    origin = (padding - bbox[0], padding - bbox[1])
    text_alpha = int(round(255 * clamp_unit(alpha)))
    outline_alpha = int(round(TARGET_SCORE_POPUP_OUTLINE_ALPHA * clamp_unit(alpha)))
    draw.text(
        origin,
        text,
        font=font,
        fill=(255, 255, 255, text_alpha),
        stroke_width=stroke_width,
        stroke_fill=(0, 0, 0, outline_alpha),
    )
    sprite = np.array(canvas, dtype=np.uint8)
    anchor = (sprite.shape[1] / 2.0, sprite.shape[0] / 2.0)
    return sprite, anchor


def render_target_reference_rgba(scoring_progress: float, idle_pulse: float = 0.0) -> np.ndarray:
    progress = clamp_unit(scoring_progress)
    pulse_scale = 1.0 + (1.0 - progress) * TARGET_IDLE_PULSE_SCALE * idle_pulse
    scale = TARGET_RENDER_OVERSAMPLE

    canvas = Image.new(
        "RGBA",
        (TARGET_REFERENCE_WIDTH * scale, TARGET_REFERENCE_HEIGHT * scale),
        (0, 0, 0, 0),
    )
    draw = ImageDraw.Draw(canvas)

    center = tuple(
        component * scale
        for component in lerp_point(TARGET_REFERENCE_IDLE_CENTER, TARGET_REFERENCE_SCORED_CENTER, progress)
    )
    orbit_radius = TARGET_REFERENCE_ORBIT_RADIUS * pulse_scale * scale
    orbit_width = TARGET_REFERENCE_ORBIT_THICKNESS * scale
    badge_outer_radius = TARGET_BADGE_OUTER_RADIUS * pulse_scale * scale
    badge_fill_radius = TARGET_BADGE_FILL_RADIUS * pulse_scale * scale
    badge_core_radius = TARGET_BADGE_CORE_RADIUS * pulse_scale * scale
    star_outer_radius = TARGET_STAR_OUTER_RADIUS * pulse_scale * scale
    star_inner_radius = TARGET_STAR_INNER_RADIUS * pulse_scale * scale

    idle_dash_alpha = 1.0 - progress
    if idle_dash_alpha > 0.0:
        idle_dash_color = with_alpha(TARGET_IDLE_DASH_COLOR, idle_dash_alpha)
        for dash_index in range(TARGET_IDLE_DASH_COUNT):
            angle = -90.0 + dash_index * (360.0 / TARGET_IDLE_DASH_COUNT)
            start = angle - TARGET_IDLE_DASH_SWEEP_DEGREES / 2.0
            end = angle + TARGET_IDLE_DASH_SWEEP_DEGREES / 2.0
            draw_arc_with_round_caps(
                draw,
                center,
                orbit_radius,
                start,
                end,
                orbit_width,
                idle_dash_color,
                rounded=False,
            )

    if progress > 0.0:
        scored_ring_color = with_alpha(TARGET_SCORED_RING_COLOR, smoothstep(0.0, 0.35, progress))
        if progress >= 0.999:
            draw_circle(
                draw,
                center,
                orbit_radius,
                outline=scored_ring_color,
                width=max(int(round(orbit_width)), 1),
            )
        else:
            draw_arc_with_round_caps(
                draw,
                center,
                orbit_radius,
                -90.0,
                -90.0 + 360.0 * progress,
                orbit_width,
                scored_ring_color,
            )

        node_alpha = smoothstep(0.45, 0.85, progress)
        if node_alpha > 0.0:
            node_radius = TARGET_SCORED_NODE_RADIUS * scale * (0.82 + 0.18 * node_alpha)
            node_color = with_alpha(TARGET_SCORED_NODE_COLOR, node_alpha)
            for node_index in range(TARGET_SCORED_NODE_COUNT):
                angle = -90.0 + node_index * (360.0 / TARGET_SCORED_NODE_COUNT)
                node_center = polar_point(center, orbit_radius, angle)
                draw_circle(draw, node_center, node_radius, fill=node_color)

    badge_rim_color = with_alpha(
        lerp_color(TARGET_IDLE_BADGE_RIM_COLOR, TARGET_SCORED_BADGE_RIM_COLOR, progress),
        1.0,
    )
    badge_fill_color = with_alpha(
        lerp_color(TARGET_IDLE_BADGE_FILL_COLOR, TARGET_SCORED_BADGE_FILL_COLOR, progress),
        1.0,
    )
    badge_core_color = with_alpha(
        lerp_color(TARGET_IDLE_BADGE_CORE_COLOR, TARGET_SCORED_BADGE_CORE_COLOR, progress),
        1.0,
    )
    star_color = with_alpha(
        lerp_color(TARGET_IDLE_STAR_COLOR, TARGET_SCORED_STAR_COLOR, progress),
        1.0,
    )

    draw_circle(draw, center, badge_outer_radius, fill=badge_rim_color)
    draw_circle(draw, center, badge_fill_radius, fill=badge_fill_color)
    draw_circle(draw, center, badge_core_radius, fill=badge_core_color)

    glow_strength = math.sin(progress * math.pi)
    if glow_strength > 0.0:
        glow_layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        glow_draw = ImageDraw.Draw(glow_layer)
        glow_points = star_points(center, star_outer_radius * 1.08, star_inner_radius * 1.08)
        glow_draw.polygon(glow_points, fill=with_alpha(TARGET_SCORED_STAR_COLOR, glow_strength * 0.18))
        glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(radius=3.0 * scale * glow_strength))
        canvas = Image.alpha_composite(canvas, glow_layer)
        draw = ImageDraw.Draw(canvas)

    draw.polygon(star_points(center, star_outer_radius, star_inner_radius), fill=star_color)

    return np.array(
        canvas.resize((TARGET_REFERENCE_WIDTH, TARGET_REFERENCE_HEIGHT), PIL_LANCZOS),
        dtype=np.uint8,
    )


def render_target_reference_rgb(scoring_progress: float, idle_pulse: float = 0.0) -> np.ndarray:
    background = np.full(
        (TARGET_REFERENCE_HEIGHT, TARGET_REFERENCE_WIDTH, 3),
        TARGET_REFERENCE_BACKGROUND_RGB,
        dtype=np.uint8,
    )
    sprite = render_target_reference_rgba(scoring_progress, idle_pulse=idle_pulse)
    alpha = sprite[:, :, 3:4].astype(np.float32) / 255.0
    background[:] = np.clip(
        sprite[:, :, :3].astype(np.float32) * alpha + background.astype(np.float32) * (1.0 - alpha),
        0.0,
        255.0,
    ).astype(np.uint8)
    return background


def render_target_sprite(target: TargetState, timestamp: float) -> tuple[np.ndarray, tuple[float, float]]:
    idle_pulse = math.sin((2.0 * math.pi * timestamp) / TARGET_IDLE_PULSE_PERIOD_SECONDS)
    reference_sprite = render_target_reference_rgba(0.0, idle_pulse=idle_pulse)
    scale = target.radius / TARGET_REFERENCE_COLLISION_RADIUS
    return resize_reference_sprite(reference_sprite, TARGET_REFERENCE_IDLE_CENTER, scale)


def render_scored_target_burst_sprite(
    effect: ScoredTargetEffect,
    timestamp: float,
) -> Optional[tuple[np.ndarray, tuple[float, float], np.ndarray]]:
    if not effect.show_burst:
        return None

    elapsed = scored_target_effect_elapsed(effect, timestamp)
    if elapsed >= TARGET_SCORE_BURST_SECONDS:
        return None

    progress = scored_target_effect_burst_progress(effect, timestamp)
    eased_progress = smoothstep(0.0, 1.0, progress)
    scale = (effect.radius / TARGET_REFERENCE_COLLISION_RADIUS) * (
        1.0 + (TARGET_SCORE_BURST_EXPAND_SCALE - 1.0) * eased_progress
    )
    sprite, anchor = resize_reference_sprite(
        render_target_reference_rgba(1.0, idle_pulse=0.0),
        TARGET_REFERENCE_SCORED_CENTER,
        scale,
    )
    return apply_sprite_alpha(sprite, 1.0 - eased_progress), anchor, effect.center


def render_score_popup_sprite(
    effect: ScoredTargetEffect,
    timestamp: float,
    popup_destination: Optional[np.ndarray] = None,
) -> Optional[tuple[np.ndarray, tuple[float, float], np.ndarray]]:
    elapsed = scored_target_effect_elapsed(effect, timestamp)
    if elapsed < TARGET_SCORE_POPUP_DELAY_SECONDS or elapsed >= TARGET_SCORE_EFFECT_SECONDS:
        return None

    progress = scored_target_effect_popup_progress(effect, timestamp)
    eased_progress = smoothstep(0.0, 1.0, progress)
    sprite, anchor = render_score_popup_text_sprite(
        effect.points,
        effect.radius,
        1.0 - eased_progress,
        popup_scale=effect.popup_scale,
    )
    center = popup_center_for_progress(effect, eased_progress, popup_destination)
    return sprite, anchor, center


def popup_center_for_progress(
    effect: ScoredTargetEffect,
    progress: float,
    popup_destination: Optional[np.ndarray] = None,
) -> np.ndarray:
    if popup_destination is None:
        return np.array(
            (
                effect.center[0],
                effect.center[1] - effect.radius * TARGET_SCORE_POPUP_RISE_MULTIPLIER * progress,
            ),
            dtype=np.float32,
        )

    return np.array(
        (
            effect.center[0] + (popup_destination[0] - effect.center[0]) * progress,
            effect.center[1] + (popup_destination[1] - effect.center[1]) * progress,
        ),
        dtype=np.float32,
    )


def draw_label(
    frame: np.ndarray,
    text: str,
    x: int,
    y: int,
    *,
    font_scale: float = 0.6,
    thickness: int = 2,
) -> None:
    thickness = max(int(thickness), 1)
    (tw, th), baseline = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, font_scale, thickness)
    y = max(y, th + baseline)
    cv2.rectangle(frame, (x, y - th - baseline), (x + tw, y + baseline), (0, 0, 0), -1)
    cv2.putText(
        frame,
        text,
        (x, y),
        cv2.FONT_HERSHEY_SIMPLEX,
        font_scale,
        (255, 255, 255),
        thickness,
        lineType=cv2.LINE_AA,
    )


def draw_label_right(
    frame: np.ndarray,
    text: str,
    right_margin: int,
    y: int,
    *,
    font_scale: float = 0.6,
    thickness: int = 2,
) -> None:
    thickness = max(int(thickness), 1)
    (tw, _th), _baseline = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, font_scale, thickness)
    x = max(frame.shape[1] - right_margin - tw, 0)
    draw_label(frame, text, x, y, font_scale=font_scale, thickness=thickness)


def draw_track(frame: np.ndarray, track: BallTrack) -> None:
    frame_h, frame_w = frame.shape[:2]
    cx = int(np.clip(track.center[0], 0, frame_w - 1))
    cy = int(np.clip(track.center[1], 0, frame_h - 1))
    radius = max(int(round(track.radius)), 4)
    color = (255, 225, 160)
    glow_color = (255, 245, 210)
    thickness = 2

    glow_overlay = frame.copy()
    cv2.circle(
        glow_overlay,
        (cx, cy),
        radius + 2,
        glow_color,
        thickness + 2,
        lineType=cv2.LINE_AA,
    )
    cv2.addWeighted(glow_overlay, 0.24, frame, 0.76, 0.0, frame)
    cv2.circle(frame, (cx, cy), radius, color, thickness, lineType=cv2.LINE_AA)

    label = f"Ball #{track.track_id}"
    if track.misses:
        label += f" hold ({track.misses})"
    draw_label(frame, label, max(cx - radius, 0), max(cy - radius - 8, 16))


def draw_pose_overlay(frame: np.ndarray, pose_frame: Optional[PoseFrame]) -> None:
    if pose_frame is None or not pose_frame.available:
        return

    frame_h, frame_w = frame.shape[:2]
    hip_color = (110, 170, 255) if pose_frame.live else (80, 136, 216)
    line_color = (86, 196, 255) if pose_frame.live else (0, 215, 255)
    ground_color = (91, 224, 140) if pose_frame.live else (0, 180, 140)
    point_color = (255, 255, 255) if pose_frame.live else (200, 200, 200)
    thigh_color = (224, 180, 91) if pose_frame.live else (196, 156, 48)

    if pose_frame.box is not None:
        x1, y1, x2, y2 = pose_frame.box
        left = max(int(round(x1)) - 16, 0)
        right = min(int(round(x2)) + 16, frame_w - 1)
    else:
        left = 0
        right = frame_w - 1

    if pose_frame.hip_line_y is not None:
        y = int(np.clip(round(pose_frame.hip_line_y), 0, frame_h - 1))
        cv2.line(frame, (left, y), (right, y), hip_color, 2, lineType=cv2.LINE_AA)
        draw_label(frame, "Hip line", max(left, 8), max(y - 6, 16), font_scale=0.4, thickness=1)

    if pose_frame.knee_line_y is not None:
        y = int(np.clip(round(pose_frame.knee_line_y), 0, frame_h - 1))
        cv2.line(frame, (left, y), (right, y), line_color, 2, lineType=cv2.LINE_AA)
        draw_label(frame, "Knee line", max(left, 8), max(y - 6, 16), font_scale=0.4, thickness=1)

    if pose_frame.ground_y is not None:
        y = int(np.clip(round(pose_frame.ground_y), 0, frame_h - 1))
        cv2.line(frame, (left, y), (right, y), ground_color, 2, lineType=cv2.LINE_AA)
        draw_label(frame, "Ground", max(left, 8), min(y + 18, frame_h - 4), font_scale=0.4, thickness=1)

    nearest_name = pose_frame.nearest_contact.name if pose_frame.nearest_contact is not None else None
    for candidate in pose_frame.contact_candidates:
        if candidate.segment_start is None or candidate.segment_end is None:
            continue
        start = tuple(np.clip(np.round(candidate.segment_start).astype(int), (0, 0), (frame_w - 1, frame_h - 1)))
        end = tuple(np.clip(np.round(candidate.segment_end).astype(int), (0, 0), (frame_w - 1, frame_h - 1)))
        color = (0, 255, 0) if candidate.name == nearest_name else thigh_color
        cv2.line(frame, start, end, color, 2, lineType=cv2.LINE_AA)

    for name, point in pose_frame.keypoints.items():
        px = int(np.clip(round(float(point[0])), 0, frame_w - 1))
        py = int(np.clip(round(float(point[1])), 0, frame_h - 1))
        color = (0, 255, 0) if name == nearest_name else point_color
        cv2.circle(frame, (px, py), 5 if name == nearest_name else 4, color, -1, lineType=cv2.LINE_AA)


def draw_target(
    frame: np.ndarray,
    target: TargetState,
    timestamp: float,
    render_cache: Optional[RenderCache] = None,
    alpha: float = 1.0,
) -> None:
    if render_cache is None:
        sprite, anchor = render_target_sprite(target, timestamp)
    else:
        cached_sprite = render_cache.get_idle_sprite(target.radius, timestamp)
        sprite, anchor = cached_sprite.sprite, cached_sprite.anchor
    if alpha < 0.999:
        sprite = apply_sprite_alpha(sprite, alpha)
    composite_sprite(frame, sprite, anchor, target.center)


def draw_scored_target_effect(
    frame: np.ndarray,
    effect: ScoredTargetEffect,
    timestamp: float,
    render_cache: Optional[RenderCache] = None,
    popup_destination: Optional[np.ndarray] = None,
) -> None:
    if render_cache is None:
        burst = render_scored_target_burst_sprite(effect, timestamp)
        if burst is not None:
            burst_sprite, burst_anchor, burst_center = burst
            composite_sprite(frame, burst_sprite, burst_anchor, burst_center)

        popup = render_score_popup_sprite(effect, timestamp, popup_destination=popup_destination)
        if popup is not None:
            popup_sprite, popup_anchor, popup_center = popup
            composite_sprite(frame, popup_sprite, popup_anchor, popup_center)
        return

    burst_sprite = render_cache.get_burst_sprite(effect, timestamp)
    if burst_sprite is not None:
        composite_sprite(frame, burst_sprite.sprite, burst_sprite.anchor, effect.center)

    popup = render_cache.get_popup_sprite(effect, timestamp)
    if popup is not None:
        popup_sprite, popup_progress = popup
        popup_center = popup_center_for_progress(
            effect,
            popup_progress,
            popup_destination=popup_destination,
        )
        composite_sprite(frame, popup_sprite.sprite, popup_sprite.anchor, popup_center)


def draw_scored_target_effects(
    frame: np.ndarray,
    effects: list[ScoredTargetEffect],
    timestamp: float,
    render_cache: Optional[RenderCache] = None,
    popup_destination: Optional[np.ndarray] = None,
) -> None:
    for effect in effects:
        draw_scored_target_effect(
            frame,
            effect,
            timestamp,
            render_cache=render_cache,
            popup_destination=popup_destination,
        )
