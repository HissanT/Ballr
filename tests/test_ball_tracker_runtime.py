import numpy as np

from ball_tracker.app import (
    BenchmarkAccumulator,
    GAME_MODE_PRECISION_TARGET,
    LatestValueStore,
    PipelineCounters,
    ProcessedFrame,
    StageTimings,
    TargetState,
)
from ball_tracker.ball_tracker_precision_target import PrecisionImpact, PrecisionTargetFrame, WallCalibration


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
        target=TargetState(center=np.array((320.0, 300.0), dtype=np.float32), radius=40, spawned_at=0.0),
        score_effects=[],
        candidates_count=2,
        primary_candidate_confidence=0.91,
        counters=PipelineCounters(
            total_frames=10,
            matched_frames=8,
            held_frames=1,
            active_frames=9,
            hit_frames=2,
        ),
        current_score=5,
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
    assert summary["queue_drops"] == {"capture_to_inference": 3, "inference_to_render": 1}
    assert summary["mode"] == "target"
    assert summary["target_metrics"] == {"score": 5}


def test_benchmark_accumulator_summarizes_juggle_metrics():
    accumulator = BenchmarkAccumulator(wall_started_at=5.0, wall_finished_at=7.0)
    frame = ProcessedFrame(
        frame_index=1,
        frame=np.zeros((480, 640, 3), dtype=np.uint8),
        frame_time=6.0,
        stage_timings=StageTimings(
            capture_ms=4.0,
            preprocess_ms=3.0,
            inference_ms=12.0,
            candidate_ms=1.0,
            tracking_ms=3.0,
            render_ms=5.0,
            display_ms=0.5,
            pipeline_ms=28.5,
        ),
        track=None,
        target=None,
        score_effects=[],
        candidates_count=1,
        primary_candidate_confidence=0.88,
        counters=PipelineCounters(
            total_frames=10,
            matched_frames=8,
            held_frames=1,
            active_frames=9,
            hit_frames=2,
            pose_live_frames=7,
            pose_stale_frames=2,
        ),
        game_mode="juggle",
        current_score=2,
        best_score=3,
        total_score_events=2,
        status_label="Ready",
        body_part_counts={"Foot": 1, "Knee": 1},
        ground_suppressed_events=1,
        contact_candidates=4,
    )
    accumulator.add(frame)

    summary = accumulator.summary(source="clip.mp4", frame_size=(640, 480), mode="juggle")

    assert summary["mode"] == "juggle"
    assert summary["tracking_metrics"]["pose_live_frames"] == 7
    assert summary["juggle_metrics"]["current_streak"] == 2
    assert summary["juggle_metrics"]["best_streak"] == 3
    assert summary["juggle_metrics"]["ground_suppressed_events"] == 1
    assert summary["juggle_metrics"]["body_part_counts"] == {"Foot": 1, "Knee": 1}


def test_benchmark_accumulator_summarizes_precision_target_metrics():
    accumulator = BenchmarkAccumulator(wall_started_at=3.0, wall_finished_at=4.0)
    frame = ProcessedFrame(
        frame_index=1,
        frame=np.zeros((480, 640, 3), dtype=np.uint8),
        frame_time=3.5,
        stage_timings=StageTimings(
            capture_ms=4.0,
            preprocess_ms=3.0,
            inference_ms=10.0,
            candidate_ms=1.0,
            tracking_ms=2.0,
            render_ms=5.0,
            display_ms=0.5,
            pipeline_ms=25.5,
        ),
        track=None,
        target=None,
        score_effects=[],
        candidates_count=1,
        primary_candidate_confidence=0.9,
        counters=PipelineCounters(
            total_frames=10,
            matched_frames=8,
            held_frames=1,
            active_frames=9,
            hit_frames=1,
        ),
        game_mode=GAME_MODE_PRECISION_TARGET,
        current_score=5,
        total_score_events=1,
        status_label="Hit scored: 5",
        precision_target=PrecisionTargetFrame(
            phase="live_precision_target",
            score=5,
            status_text="Hit scored: 5",
            ball_spec_label="Size 5",
            focal_length_px=2400.0,
            bullseye_center=np.array((500.0, 400.0), dtype=np.float32),
            wall_calibration=WallCalibration(
                wall_distance_m=5.0,
                impact_pixel_diameter_px=105.6,
                impact_frame_time=2.0,
                confidence=0.95,
            ),
            current_depth=None,
            current_relative_depth_m=4.0,
            zero_reference_depth_m=1.0,
            last_impact=PrecisionImpact(
                center=np.array((540.0, 420.0), dtype=np.float32),
                radial_distance_cm=9.317,
                dx_cm=8.333,
                dy_cm=4.167,
                score=5,
                frame_time=3.2,
            ),
            last_score=5,
        ),
    )
    accumulator.add(frame)

    summary = accumulator.summary(
        source="clip.mp4",
        frame_size=(640, 480),
        mode=GAME_MODE_PRECISION_TARGET,
    )

    assert summary["mode"] == GAME_MODE_PRECISION_TARGET
    assert summary["precision_target_metrics"]["score"] == 5
    assert summary["precision_target_metrics"]["impacts"] == 1
    assert summary["precision_target_metrics"]["wall_distance_m"] == 5.0
    assert summary["precision_target_metrics"]["last_score"] == 5
