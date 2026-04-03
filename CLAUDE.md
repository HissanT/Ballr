# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ballr** is a gamified soccer training app being built in stages. The current stage is a standalone **real-time ball tracking program** — not a full app yet.

## Current Stage: Ball Tracking Program

Goal: Live real-time soccer ball detection and tracking using a webcam (including DroidCam phone-as-webcam), with a visual overlay (outline) drawn around the detected ball.

### Tech Stack
- Python
- YOLO (latest streamlined models, e.g. YOLOv8/YOLOv11 via `ultralytics`) with pretrained COCO weights (`sports ball` class)
- OpenCV for video capture and overlay rendering
- DroidCam as the webcam source (accessed like a standard webcam or IP camera)

### Key Constraints
- Use pretrained weights first; custom dataset fine-tuning comes later
- Keep it simple — no unnecessary complexity for features not yet required
- DroidCam integration: connect via USB (shows as a standard webcam index) or Wi-Fi (use IP stream URL like `http://<phone-ip>:4747/video`)

## Running the Program

```bash
# Install dependencies
pip install ultralytics opencv-python

# Run tracker (once implemented)
python ball_tracker.py
```

## Architecture

Single-script design for now (`ball_tracker.py`):
1. Open video stream (webcam index or DroidCam IP URL)
2. Run YOLO inference per frame, filtering for `sports ball` class
3. Draw bounding box / outline overlay on detected ball
4. Display live feed with `cv2.imshow`

## Roadmap (Do Not Implement Yet)
- Custom dataset collection and fine-tuning
- Full gamified app UI
- Performance metrics / training analytics
