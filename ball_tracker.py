import argparse
import time
from collections import deque
from pathlib import Path
from typing import Optional

import cv2
import numpy as np

from ball_tracker_audio import TARGET_SOUND_PATH, play_score_sound as _play_score_sound
from ball_tracker_rendering import (
    PIL_LANCZOS,
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
    TARGET_PHASE_IDLE,
    TARGET_PHASE_SCORING,
    TARGET_RADIUS_RATIO,
    TARGET_RESPAWN_DISTANCE_MULTIPLIER,
    TARGET_SCORE_ANIMATION_SECONDS,
    TARGET_SPAWN_ATTEMPTS,
    TargetPhase,
    TargetState,
    advance_target_state,
    begin_target_scoring,
    can_score_with_track,
    clamp_unit,
    has_live_track,
    spawn_target,
    target_animation_progress,
    target_hit,
    target_radius_for_frame,
    target_spawn_bounds,
)
from ball_tracker_tracking import (
    CANDIDATE_CONF_THRESHOLD,
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


def play_score_sound(sound_path: Path = TARGET_SOUND_PATH) -> None:
    _play_score_sound(sound_path, winsound_module=winsound)


def main() -> None:
    from ultralytics import YOLO

    parser = argparse.ArgumentParser(description="Real-time single-ball tracker")
    parser.add_argument("--source", default="0", help="Webcam index or DroidCam URL")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    args = parser.parse_args()

    model = YOLO(MODEL_PATH)
    gamma_lut = build_gamma_lut()
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    rng = np.random.default_rng()

    source = parse_source(args.source)
    cap = cv2.VideoCapture(source)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

    if not cap.isOpened():
        print(f"ERROR: Could not open source '{args.source}'")
        return

    cv2.namedWindow("Ball Tracker", cv2.WINDOW_NORMAL)

    fps_history: deque = deque(maxlen=10)
    prev_time = time.time()
    total_frames = 0
    matched_frames = 0
    held_frames = 0
    active_frames = 0
    track: Optional[BallTrack] = None
    target: Optional[TargetState] = None
    next_track_id = 1

    print("Tracking started - press 'q' to quit")

    while True:
        ret, frame = cap.read()
        if not ret:
            print("ERROR: Failed to grab frame")
            break

        frame_time = time.time()
        frame = mirror_frame(frame)
        total_frames += 1

        enhanced = preprocess_frame(frame, gamma_lut, clahe)
        results = model.predict(
            enhanced,
            conf=CANDIDATE_CONF_THRESHOLD,
            iou=IOU_THRESHOLD,
            classes=[SPORTS_BALL_CLASS_ID],
            max_det=MAX_DETECTIONS,
            imgsz=max(args.width, args.height),
            verbose=False,
        )

        candidates = extract_candidates(results)
        primary_candidate = choose_primary_candidate(candidates, track)
        is_confirmed_detection = primary_candidate is not None

        if primary_candidate is not None:
            track, next_track_id = update_track(track, primary_candidate, next_track_id)
            matched_frames += 1
        else:
            track = advance_track(track)
            if track is not None:
                held_frames += 1

        if target is None:
            target_radius = target_radius_for_frame(frame.shape)
            target = TargetState(
                center=spawn_target(frame.shape[:2], target_radius, rng=rng),
                radius=target_radius,
            )
        else:
            target = advance_target_state(target, frame_time, frame.shape[:2], rng=rng, ball_track=track)

        if target_hit(track, target):
            target = begin_target_scoring(target, frame_time)
            play_score_sound()

        if track is not None:
            active_frames += 1
            draw_track(frame, track)

        draw_target(frame, target, frame_time)
        draw_label_right(frame, f"Score: {target.score}", 8, 24)

        fps_history.append(1.0 / max(frame_time - prev_time, 1e-6))
        prev_time = frame_time
        fps = sum(fps_history) / len(fps_history)

        draw_label(frame, f"FPS: {fps:.1f}", 8, 24)
        match_rate = (matched_frames / total_frames * 100) if total_frames > 0 else 0.0
        hold_rate = (held_frames / total_frames * 100) if total_frames > 0 else 0.0
        lock_rate = (active_frames / total_frames * 100) if total_frames > 0 else 0.0
        draw_label(frame, f"Det: {match_rate:.1f}%", 8, 52)
        draw_label(frame, f"Hold: {hold_rate:.1f}%", 8, 80)
        draw_label(frame, f"Lock: {lock_rate:.1f}%", 8, 108)
        draw_label(frame, f"Cands: {len(candidates)}", 8, 136)
        if is_confirmed_detection and primary_candidate is not None:
            draw_label(frame, f"Conf: {primary_candidate.confidence:.2f}", 8, 164)

        cv2.imshow("Ball Tracker", frame)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
