import numpy as np

from ball_tracker.ball_tracker_rendering import RenderCache
from ball_tracker.ball_tracker_targets import (
    ScoredTargetEffect,
    TARGET_SCORE_POPUP_DELAY_SECONDS,
    TARGET_SCORE_VALUE,
)


def test_render_cache_reuses_idle_sprite_for_same_quantized_phase():
    cache = RenderCache()
    cache.prime(40, ((TARGET_SCORE_VALUE, 1.0),))

    first = cache.get_idle_sprite(40, 0.10)
    second = cache.get_idle_sprite(40, 0.10)

    assert first.sprite is second.sprite
    assert first.anchor == second.anchor


def test_render_cache_reuses_popup_sprite_for_same_effect_time():
    cache = RenderCache()
    effect = ScoredTargetEffect(
        center=np.array((320.0, 300.0), dtype=np.float32),
        radius=40,
        points=TARGET_SCORE_VALUE * 2,
        started_at=5.0,
    )

    first = cache.get_popup_sprite(effect, effect.started_at + TARGET_SCORE_POPUP_DELAY_SECONDS + 0.15)
    second = cache.get_popup_sprite(effect, effect.started_at + TARGET_SCORE_POPUP_DELAY_SECONDS + 0.15)

    assert first is not None
    assert second is not None
    assert first[0].sprite is second[0].sprite
    assert first[0].anchor == second[0].anchor
    assert first[1] == second[1]
