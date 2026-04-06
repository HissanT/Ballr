import argparse
import time
from collections import deque
from dataclasses import dataclass
from typing import Optional

import cv2
import numpy as np
from ultralytics import YOLO

from ballr_utils import build_gamma_lut, parse_source, preprocess_frame

SPORTS_BALL_CLASS_ID = 0
CANDIDATE_CONF_THRESHOLD = 0.25
INIT_CONF_THRESHOLD = 0.40
REACQUIRE_CONF_THRESHOLD = 0.60
IOU_THRESHOLD = 0.35
MAX_DETECTIONS = 8
MAX_MISSES = 4
MOTION_DECAY = 0.82
CENTER_SMOOTHING = 0.65
VELOCITY_SMOOTHING = 0.55
RADIUS_SMOOTHING = 0.60
MODEL_PATH = "runs/train/ballr_v4/weights/best.pt"


@dataclass
class DetectionCandidate:
    x1: int
    y1: int
    x2: int
    y2: int
    center: np.ndarray
    radius: float
    confidence: float


@dataclass
class BallTrack:
    center: np.ndarray
    velocity: np.ndarray
    radius: float
    confidence: float
    track_id: int
    misses: int = 0
    confirmed_frames: int = 0


def predicted_center(track: BallTrack) -> np.ndarray:
    return track.center + track.velocity


def track_gate_radius(track: BallTrack) -> float:
    speed = float(np.linalg.norm(track.velocity))
    base = max(track.radius * 5.0, 55.0)
    return base + speed * 1.5 + track.misses * 25.0


def extract_candidates(results) -> list[DetectionCandidate]:
    if not results or results[0].boxes is None or not len(results[0].boxes):
        return []

    candidates: list[DetectionCandidate] = []
    for box in results[0].boxes:
        x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
        center = np.array(((x1 + x2) / 2.0, (y1 + y2) / 2.0), dtype=np.float32)
        radius = max((x2 - x1), (y2 - y1)) / 2.0
        candidates.append(
            DetectionCandidate(
                x1=x1,
                y1=y1,
                x2=x2,
                y2=y2,
                center=center,
                radius=radius,
                confidence=float(box.conf[0]),
            )
        )

    return candidates


def score_candidate(candidate: DetectionCandidate, track: BallTrack) -> float:
    projected_center = predicted_center(track)
    distance = float(np.linalg.norm(candidate.center - projected_center))
    gate = track_gate_radius(track)
    if distance > gate and candidate.confidence < REACQUIRE_CONF_THRESHOLD:
        return -1.0

    motion_score = max(0.0, 1.0 - distance / max(gate, 1.0))
    size_delta = abs(candidate.radius - track.radius) / max(track.radius, 1.0)
    size_score = max(0.0, 1.0 - size_delta)
    score = candidate.confidence * 0.55 + motion_score * 0.35 + size_score * 0.10

    if distance <= gate * 0.4:
        score += 0.05

    return score


def choose_primary_candidate(
    candidates: list[DetectionCandidate], track: Optional[BallTrack]
) -> Optional[DetectionCandidate]:
    if not candidates:
        return None

    strongest = max(candidates, key=lambda candidate: candidate.confidence)
    if track is None:
        return strongest if strongest.confidence >= INIT_CONF_THRESHOLD else None

    best_candidate = max(candidates, key=lambda candidate: score_candidate(candidate, track))
    best_score = score_candidate(best_candidate, track)
    if best_score >= 0.35:
        return best_candidate

    if track.misses >= 2 and strongest.confidence >= REACQUIRE_CONF_THRESHOLD:
        return strongest

    return None


def update_track(
    track: Optional[BallTrack],
    candidate: DetectionCandidate,
    next_track_id: int,
) -> tuple[BallTrack, int]:
    if track is None:
        return (
            BallTrack(
                center=candidate.center.copy(),
                velocity=np.zeros(2, dtype=np.float32),
                radius=candidate.radius,
                confidence=candidate.confidence,
                track_id=next_track_id,
                confirmed_frames=1,
            ),
            next_track_id + 1,
        )

    projected = predicted_center(track)
    blended_center = projected * (1.0 - CENTER_SMOOTHING) + candidate.center * CENTER_SMOOTHING
    instantaneous_velocity = blended_center - track.center
    blended_velocity = (
        track.velocity * (1.0 - VELOCITY_SMOOTHING)
        + instantaneous_velocity * VELOCITY_SMOOTHING
    )
    blended_radius = track.radius * (1.0 - RADIUS_SMOOTHING) + candidate.radius * RADIUS_SMOOTHING

    return (
        BallTrack(
            center=blended_center,
            velocity=blended_velocity,
            radius=blended_radius,
            confidence=candidate.confidence,
            track_id=track.track_id,
            confirmed_frames=track.confirmed_frames + 1,
        ),
        next_track_id,
    )


def advance_track(track: Optional[BallTrack]) -> Optional[BallTrack]:
    if track is None:
        return None

    misses = track.misses + 1
    if misses > MAX_MISSES:
        return None

    return BallTrack(
        center=track.center + track.velocity,
        velocity=track.velocity * MOTION_DECAY,
        radius=track.radius,
        confidence=max(track.confidence * 0.92, 0.0),
        track_id=track.track_id,
        misses=misses,
        confirmed_frames=track.confirmed_frames,
    )


def draw_label(frame: np.ndarray, text: str, x: int, y: int) -> None:
    (tw, th), baseline = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
    y = max(y, th + baseline)
    cv2.rectangle(frame, (x, y - th - baseline), (x + tw, y + baseline), (0, 0, 0), -1)
    cv2.putText(frame, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)


def draw_track(frame: np.ndarray, track: BallTrack) -> None:
    frame_h, frame_w = frame.shape[:2]
    cx = int(np.clip(track.center[0], 0, frame_w - 1))
    cy = int(np.clip(track.center[1], 0, frame_h - 1))
    radius = max(int(round(track.radius)), 4)
    color = (0, 255, 0) if track.misses == 0 else (0, 215, 255)
    thickness = 2 if track.misses == 0 else 1
    cv2.circle(frame, (cx, cy), radius, color, thickness)

    label = f"Ball #{track.track_id}"
    if track.misses:
        label += f" hold ({track.misses})"
    draw_label(frame, label, max(cx - radius, 0), max(cy - radius - 8, 16))


def main() -> None:
    parser = argparse.ArgumentParser(description="Real-time single-ball tracker")
    parser.add_argument("--source", default="0", help="Webcam index or DroidCam URL")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=480)
    args = parser.parse_args()

    model = YOLO(MODEL_PATH)
    gamma_lut = build_gamma_lut()
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))

    source = parse_source(args.source)
    cap = cv2.VideoCapture(source)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, args.width)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, args.height)
    cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)  # always grab the latest frame


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
    next_track_id = 1

    print("Tracking started - press 'q' to quit")

    while True:
        ret, frame = cap.read()
        if not ret:
            print("ERROR: Failed to grab frame")
            break

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

        if track is not None:
            active_frames += 1
            draw_track(frame, track)

        now = time.time()
        fps_history.append(1.0 / max(now - prev_time, 1e-6))
        prev_time = now
        fps = sum(fps_history) / len(fps_history)
        draw_label(frame, f"FPS: {fps:.1f}", 8, 24)
        match_rate = (matched_frames / total_frames * 100) if total_frames > 0 else 0
        hold_rate = (held_frames / total_frames * 100) if total_frames > 0 else 0
        lock_rate = (active_frames / total_frames * 100) if total_frames > 0 else 0
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
