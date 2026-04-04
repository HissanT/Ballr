import argparse
import time
from collections import deque

import cv2
import numpy as np
from ultralytics import YOLO

SPORTS_BALL_CLASS_ID = 0
CONF_THRESHOLD = 0.45
IOU_THRESHOLD = 0.35
MODEL_PATH = "runs/train/ballr_v3/weights/best.pt"


def build_gamma_lut(gamma: float = 1.2) -> np.ndarray:
    table = np.array(
        [(i / 255.0) ** (1.0 / gamma) * 255 for i in range(256)], dtype=np.uint8
    )
    return table


def preprocess_frame(frame: np.ndarray, gamma_lut: np.ndarray, clahe: cv2.CLAHE) -> np.ndarray:
    # CLAHE on luminance channel to normalise uneven lighting / shadows
    lab = cv2.cvtColor(frame, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    l = clahe.apply(l)
    lab = cv2.merge((l, a, b))
    enhanced = cv2.cvtColor(lab, cv2.COLOR_LAB2BGR)

    # Gamma boost only when frame is dim (e.g. indoor / evening)
    if enhanced.mean() < 100:
        enhanced = cv2.LUT(enhanced, gamma_lut)

    return enhanced


def parse_source(arg: str):
    if arg.isdigit():
        return int(arg)
    return arg  # DroidCam Wi-Fi URL or any stream URL


def draw_label(frame: np.ndarray, text: str, x: int, y: int) -> None:
    (tw, th), baseline = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2)
    y = max(y, th + baseline)
    cv2.rectangle(frame, (x, y - th - baseline), (x + tw, y + baseline), (0, 0, 0), -1)
    cv2.putText(frame, text, (x, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 2)


def main() -> None:
    parser = argparse.ArgumentParser(description="Real-time soccer ball tracker")
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
    detected_frames = 0

    print("Tracking started — press 'q' to quit")

    while True:
        ret, frame = cap.read()
        if not ret:
            print("ERROR: Failed to grab frame")
            break

        total_frames += 1
        enhanced = preprocess_frame(frame, gamma_lut, clahe)

        results = model.track(
            enhanced,
            persist=True,
            conf=CONF_THRESHOLD,
            iou=IOU_THRESHOLD,
            classes=[SPORTS_BALL_CLASS_ID],
            tracker="bytetrack.yaml",
            verbose=False,
        )

        # Draw detections on the original (unprocessed) frame
        if results and results[0].boxes is not None and len(results[0].boxes):
            detected_frames += 1
            boxes = results[0].boxes
            for box in boxes:
                x1, y1, x2, y2 = map(int, box.xyxy[0].tolist())
                track_id = int(box.id[0]) if box.id is not None else None

                cx = (x1 + x2) // 2
                cy = (y1 + y2) // 2
                radius = max((x2 - x1), (y2 - y1)) // 2
                cv2.circle(frame, (cx, cy), radius, (0, 255, 0), 2)

                label = f"Ball #{track_id}" if track_id is not None else "Ball"
                draw_label(frame, label, cx - radius, y1)

        # FPS overlay
        now = time.time()
        fps_history.append(1.0 / max(now - prev_time, 1e-6))
        prev_time = now
        fps = sum(fps_history) / len(fps_history)
        draw_label(frame, f"FPS: {fps:.1f}", 8, 24)
        det_rate = (detected_frames / total_frames * 100) if total_frames > 0 else 0
        draw_label(frame, f"Det: {det_rate:.1f}%", 8, 52)

        cv2.imshow("Ball Tracker", frame)
        if cv2.waitKey(1) & 0xFF == ord("q"):
            break

    cap.release()
    cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
