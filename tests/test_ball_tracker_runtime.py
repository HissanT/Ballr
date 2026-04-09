import numpy as np

from ball_tracker import (
    BenchmarkAccumulator,
    LatestValueStore,
    PipelineCounters,
    ProcessedFrame,
    StageTimings,
    TargetState,
)


def test_latest_value_store_returns_newest_item_and_counts_drop():
    store = LatestValueStore[int]()

    store.put(1)
    store.put(2)

    version, item = store.get_latest(0, timeout_s=0.0)

    assert version > 0
    assert item == 2
    assert store.dropped_count == 1


def test_benchmark_accumulator_summarizes_stage_timings_and_tracking_metrics():
    accumulator = BenchmarkAccumulator(wall_started_at=10.0, wall_finished_at=11.0)
    frame = ProcessedFrame(
        frame_index=1,
        frame=np.zeros((480, 640, 3), dtype=np.uint8),
        frame_time=10.5,
        stage_timings=StageTimings(
            capture_ms=4.0,
            preprocess_ms=3.0,
            inference_ms=9.0,
            candidate_ms=1.0,
            tracking_ms=2.0,
            render_ms=5.0,
            display_ms=0.5,
            pipeline_ms=24.5,
        ),
        track=None,
        target=TargetState(center=np.array((320.0, 300.0), dtype=np.float32), radius=40, score=5),
        score_effects=[],
        candidates_count=2,
        primary_candidate_confidence=0.91,
        counters=PipelineCounters(
            total_frames=10,
            matched_frames=8,
            held_frames=1,
            active_frames=9,
            hit_frames=2,
            pose_live_frames=0,
            pose_stale_frames=0,
        ),
    )
    accumulator.add(frame)

    summary = accumulator.summary(
        source="clip.mp4",
        frame_size=(640, 480),
        queue_drops={"capture_to_inference": 3, "inference_to_render": 1},
    )

    assert summary["frames_processed"] == 1
    assert summary["avg_fps"] == 1.0
    assert summary["stage_timings_ms"]["inference"]["avg"] == 9.0
    assert summary["tracking_metrics"]["detection_rate_pct"] == 80.0
    assert summary["tracking_metrics"]["avg_candidates_per_frame"] == 2.0
    assert summary["tracking_metrics"]["avg_primary_confidence"] == 0.91
    assert summary["tracking_metrics"]["pose_live_rate_pct"] == 0.0
    assert summary["tracking_metrics"]["pose_stale_rate_pct"] == 0.0
    assert summary["queue_drops"] == {"capture_to_inference": 3, "inference_to_render": 1}
    assert summary["mode"] == "target"
    assert summary["target_metrics"] == {"score": 5}


def test_benchmark_accumulator_includes_juggle_metrics():
    accumulator = BenchmarkAccumulator(wall_started_at=4.0, wall_finished_at=5.0)
    frame = ProcessedFrame(
        frame_index=3,
        frame=np.zeros((480, 640, 3), dtype=np.uint8),
        frame_time=4.5,
        stage_timings=StageTimings(
            capture_ms=4.0,
            preprocess_ms=3.0,
            inference_ms=8.0,
            candidate_ms=1.0,
            tracking_ms=2.0,
            render_ms=5.0,
            display_ms=0.5,
            pipeline_ms=23.5,
        ),
        track=None,
        target=None,
        score_effects=[],
        candidates_count=1,
        primary_candidate_confidence=0.88,
        counters=PipelineCounters(
            total_frames=20,
            matched_frames=16,
            held_frames=2,
            active_frames=18,
            hit_frames=6,
            pose_live_frames=14,
            pose_stale_frames=2,
        ),
        game_mode="juggle",
        current_score=4,
        best_score=9,
        status_label="Ready",
        total_score_events=11,
        drop_resets=2,
        loss_resets=1,
        warmup_seconds=2.1,
        body_part_counts={"L ankle": 6, "Head": 5},
        ground_suppressed_events=3,
        contact_candidates=15,
    )
    accumulator.add(frame)

    summary = accumulator.summary(source="clip.mp4", frame_size=(640, 480), mode="juggle")

    assert summary["mode"] == "juggle"
    assert summary["juggle_metrics"]["current_streak"] == 4
    assert summary["juggle_metrics"]["best_streak"] == 9
    assert summary["juggle_metrics"]["juggles_scored"] == 11
    assert summary["juggle_metrics"]["drop_resets"] == 2
    assert summary["juggle_metrics"]["loss_resets"] == 1
    assert summary["juggle_metrics"]["warmup_seconds"] == 2.1
    assert summary["juggle_metrics"]["pose_live_rate_pct"] == 70.0
    assert summary["juggle_metrics"]["pose_stale_rate_pct"] == 10.0
    assert summary["juggle_metrics"]["contact_candidates"] == 15
    assert summary["juggle_metrics"]["ground_suppressed_events"] == 3
    assert summary["juggle_metrics"]["body_part_counts"] == {"L ankle": 6, "Head": 5}
