from __future__ import annotations

import argparse
import time
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLO

from ball_tracker_juggle_dataset import JuggleCandidateRecord, load_manifest, manifest_path, save_manifest
from ball_tracker_juggling import (
    FEATURE_NAMES,
    JUGGLE_LOOKAHEAD_FRAMES,
    JUGGLE_LOOKBACK_FRAMES,
    JUGGLE_WINDOW_FRAMES,
    load_juggle_event_classifier,
    update_juggle_state,
)
from ball_tracker_pose import POSE_CONF_THRESHOLD, POSE_IMG_SIZE, POSE_MODEL_PATH, PoseState, update_pose_state
from ball_tracker_rendering import mirror_frame
from ball_tracker_tracking import (
    CANDIDATE_CONF_THRESHOLD,
    IOU_THRESHOLD,
    MAX_DETECTIONS,
    MODEL_PATH,
    SPORTS_BALL_CLASS_ID,
    BallMotionState,
    BallTrack,
    advance_track,
    choose_primary_candidate,
    extract_candidates,
    predict_track,
    update_track,
)
from ballr_utils import build_gamma_lut, ensure_dir, parse_source, preprocess_frame


def _select_device():
    try:
        import torch
    except ImportError:
        return "cpu"
    return 0 if torch.cuda.is_available() else "cpu"


def _save_clip(path: Path, frames: list[np.ndarray], fps: float) -> None:
    if not frames:
        raise ValueError("Cannot save an empty candidate clip")
    height, width = frames[0].shape[:2]
    writer = cv2.VideoWriter(
        str(path),
        cv2.VideoWriter_fourcc(*"mp4v"),
        fps,
        (width, height),
    )
    try:
        for frame in frames:
            writer.write(frame)
    finally:
        writer.release()


def _candidate_frames(
    frame_cache: dict[int, np.ndarray],
    event_frame_index: int,
) -> list[np.ndarray] | None:
    frames: list[np.ndarray] = []
    for frame_index in range(
        event_frame_index - JUGGLE_LOOKBACK_FRAMES,
        event_frame_index + JUGGLE_LOOKAHEAD_FRAMES + 1,
    ):
        frame = frame_cache.get(frame_index)
        if frame is None:
            return None
        frames.append(frame)
    if len(frames) != JUGGLE_WINDOW_FRAMES:
        return None
    return frames


def main() -> None:
    parser = argparse.ArgumentParser(description="Export classified juggle reversal candidates")
    parser.add_argument("--source", default="0", help="Webcam index or video file / stream URL")
    parser.add_argument("--output", default="dataset/juggle_candidates", help="Export root directory")
    parser.add_argument("--session", help="Optional session name")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--max-frames", type=int, help="Optional processing cap")
    parser.add_argument("--pose-model", default=POSE_MODEL_PATH, help="Pose model path")
    parser.add_argument("--pose-imgsz", type=int, default=POSE_IMG_SIZE)
    parser.add_argument("--pose-conf", type=float, default=POSE_CONF_THRESHOLD)
    parser.add_argument("--event-model", help="Optional trained event classifier checkpoint")
    args = parser.parse_args()

    session_name = args.session or time.strftime("%Y%m%d_%H%M%S")
    output_root = Path(args.output) / session_name
    clips_dir = ensure_dir(output_root / "clips")
    features_dir = ensure_dir(output_root / "features")
    manifest = load_manifest(manifest_path(output_root))

    device = _select_device()
    ball_model = YOLO(MODEL_PATH)
    pose_model = YOLO(args.pose_model)
    event_classifier = load_juggle_event_classifier(args.event_model, device="cpu" if device == "cpu" else str(device))

    gamma_lut = build_gamma_lut()
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    source = parse_source(args.source)
    cap = cv2.VideoCapture(source)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    if not cap.isOpened():
        raise SystemExit(f"Could not open source '{args.source}'")

    track: BallTrack | None = None
    motion: BallMotionState | None = None
    pose_state = PoseState()
    juggle_state = None
    next_track_id = 1
    frame_cache: dict[int, np.ndarray] = {}
    exported = 0
    frame_index = 0

    try:
        while True:
            if args.max_frames is not None and frame_index >= args.max_frames:
                break
            ret, frame = cap.read()
            if not ret:
                break

            frame_index += 1
            timestamp = frame_index / 30.0
            frame = mirror_frame(frame)
            frame_cache[frame_index] = frame.copy()
            while len(frame_cache) > JUGGLE_WINDOW_FRAMES + 12:
                oldest = min(frame_cache)
                del frame_cache[oldest]

            enhanced = preprocess_frame(frame, gamma_lut, clahe)
            results = ball_model.predict(
                enhanced,
                conf=CANDIDATE_CONF_THRESHOLD,
                iou=IOU_THRESHOLD,
                classes=[SPORTS_BALL_CLASS_ID],
                max_det=MAX_DETECTIONS,
                imgsz=max(args.width, args.height),
                verbose=False,
                device=device,
            )
            pose_results = pose_model.predict(
                frame,
                conf=args.pose_conf,
                imgsz=args.pose_imgsz,
                classes=[0],
                verbose=False,
                device=device,
            )

            track, motion = predict_track(track, motion, timestamp)
            candidates = extract_candidates(results)
            primary_candidate = choose_primary_candidate(candidates, track)
            if primary_candidate is not None:
                track, motion, next_track_id = update_track(
                    track,
                    motion,
                    primary_candidate,
                    next_track_id,
                    timestamp,
                )
            else:
                track, motion = advance_track(track, motion)

            pose_state, pose_frame = update_pose_state(
                pose_state,
                pose_results,
                track,
                frame.shape[:2],
                timestamp,
            )
            juggle_state, event = update_juggle_state(
                juggle_state,
                track,
                pose_frame,
                timestamp,
                frame.shape[:2],
                frame_index=frame_index,
                classifier=event_classifier,
            )
            if event is None:
                continue

            clip_frames = _candidate_frames(frame_cache, event.event_frame_index)
            if clip_frames is None:
                continue

            candidate_id = f"{session_name}_{event.event_frame_index:06d}"
            clip_path = clips_dir / f"{candidate_id}.mp4"
            features_path = features_dir / f"{candidate_id}.npz"
            _save_clip(clip_path, clip_frames, fps=30.0)
            np.savez_compressed(
                features_path,
                feature_window=event.feature_window.astype(np.float32),
                feature_names=np.array(FEATURE_NAMES),
                probabilities=np.array(
                    [event.probabilities[event_class] for event_class in sorted(event.probabilities)],
                    dtype=np.float32,
                ),
            )
            manifest.append(
                JuggleCandidateRecord(
                    candidate_id=candidate_id,
                    session_name=session_name,
                    source=str(args.source),
                    event_frame_index=event.event_frame_index,
                    event_time=event.event_time,
                    clip_relpath=str(clip_path.relative_to(output_root)),
                    features_relpath=str(features_path.relative_to(output_root)),
                    predicted_class=event.event_class.value,
                    predicted_confidence=event.confidence,
                    probabilities=dict(event.probabilities),
                )
            )
            exported += 1
    finally:
        cap.release()

    save_manifest(manifest_path(output_root), manifest)
    print(f"Exported {exported} juggle candidates to '{output_root}'.")


if __name__ == "__main__":
    main()
