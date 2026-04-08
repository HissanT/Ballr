import numpy as np

from ball_tracker_rendering import (
    draw_scored_target_effects,
    render_score_popup_sprite,
    render_scored_target_burst_sprite,
)
from ball_tracker_targets import (
    ScoredTargetEffect,
    TARGET_SCORE_BURST_SECONDS,
    TARGET_SCORE_EFFECT_SECONDS,
    TARGET_SCORE_POPUP_DELAY_SECONDS,
    TARGET_SCORE_VALUE,
)


def make_effect(started_at: float = 10.0) -> ScoredTargetEffect:
    return ScoredTargetEffect(
        center=np.array((320.0, 320.0), dtype=np.float32),
        radius=40,
        points=TARGET_SCORE_VALUE,
        started_at=started_at,
    )


def test_render_scored_target_burst_sprite_grows_and_fades():
    effect = make_effect()

    early = render_scored_target_burst_sprite(effect, effect.started_at + 0.05)
    late = render_scored_target_burst_sprite(effect, effect.started_at + 0.30)

    assert early is not None
    assert late is not None

    early_sprite, _early_anchor, _early_center = early
    late_sprite, _late_anchor, _late_center = late

    assert late_sprite.shape[0] > early_sprite.shape[0]
    assert late_sprite.shape[1] > early_sprite.shape[1]
    assert int(late_sprite[:, :, 3].max()) < int(early_sprite[:, :, 3].max())


def test_render_score_popup_sprite_rises_and_fades():
    effect = make_effect()

    early = render_score_popup_sprite(effect, effect.started_at + TARGET_SCORE_POPUP_DELAY_SECONDS + 0.05)
    late = render_score_popup_sprite(effect, effect.started_at + TARGET_SCORE_POPUP_DELAY_SECONDS + 0.60)

    assert early is not None
    assert late is not None

    early_sprite, _early_anchor, early_center = early
    late_sprite, _late_anchor, late_center = late

    assert late_center[1] < early_center[1]
    assert int(late_sprite[:, :, 3].max()) < int(early_sprite[:, :, 3].max())


def test_render_score_popup_sprite_waits_for_popup_delay():
    effect = make_effect()

    popup = render_score_popup_sprite(effect, effect.started_at + TARGET_SCORE_POPUP_DELAY_SECONDS - 0.01)

    assert popup is None


def test_draw_scored_target_effects_ignores_expired_effects():
    frame = np.zeros((480, 640, 3), dtype=np.uint8)
    effect = make_effect()

    draw_scored_target_effects(frame, [effect], effect.started_at + TARGET_SCORE_EFFECT_SECONDS)

    assert not frame.any()
