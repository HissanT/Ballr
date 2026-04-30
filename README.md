# Ballr

Ballr is a real-time soccer-ball tracking and juggling workflow repo. The Python files are grouped into plain folders by purpose and are run directly as modules.

## Layout

- `common/`: shared path helpers and utility functions.
- `runtime/`: live tracking, pose, rendering, target mode, and audio/runtime support.
- `juggling/`: juggling runtime logic plus the juggle dataset, review, export, and classifier training files.
- `data_tools/`: dataset capture, preparation, and review tooling.
- `model_tools/`: detector training and CoreML export code.
- `frontend_ballr/`: iOS frontend code.
- `assets/`: runtime images, score audio, and combo soundtrack clips.
- `models/`: detector and pose weights used by the app and training scripts.
- `training/`: datasets, prepared dataset variants, imported external datasets, and future training runs.
- `tests/`: regression tests for runtime logic and dataset tooling.

## Common Commands

- `python -m runtime.ball_tracker`: run the live tracker with the canonical detector in `models/`.
- `python -m data_tools.collect_data`: collect new labeled samples into `training/dataset`.
- `python -m data_tools.review_queue dataset --root training/dataset --output-root training/dataset_cleaned`: review a dataset copy.
- `python -m data_tools.dataset_tools prepare-v4`: rebuild the prepared v4 datasets under `training/`.
- `python -m data_tools.eval_tools stats --root training/dataset_prepared_v5_eval --split val`: report label counts, empty labels, and sqrt-area ball-size bins.
- `python -m data_tools.eval_tools score-labels --root training/dataset_prepared_v5_eval --predictions-root training/predictions/ballr_v5 --split val`: score recall by ball-size bin and false positives per minute.
- `python -m data_tools.eval_tools split-heldout --source-root training/dataset_prepared_v5_all --output-root training/dataset_prepared_v5_eval`: create a deterministic held-out validation split instead of validating on train.
- `python -m data_tools.augment_tools --source-root training/dataset_prepared_v5_eval --output-root training/dataset_prepared_v5_eval_aug`: build mild train-only ball-specific augmentations; validation is copied unchanged.
- `python -m data_tools.eval_tools build-temporal --source-root training/dataset_prepared_v5_eval --output-root training/dataset_prepared_v6_temporal_768`: compose temporal grayscale triplet images for `ballr_v6_temporal_768`.
- `python -m model_tools.train --preset v4-tune`: train on `training/dataset_prepared_v4_tune_cleaned`.
- `python -m model_tools.export_mlpackage --overwrite`: export the detector to `models/coreml/<checkpoint>.mlpackage` on macOS or Linux.

## Notes

- `data.yaml` at repo root points at `training/dataset` as a convenience entrypoint.
- The canonical runtime detector checkpoint is `models/ballr_v5_cleaned_final.pt`.
- `dataset_tools.build_label_viewer(root)` writes `label_overlay_viewer.html` into the target dataset root.
- Keep `ballr_v5_cleaned_final` at `imgsz=768` as the production control until a fixed held-out eval shows a replacement improves small-ball recall without materially increasing empty-video false positives.
- Ball-specific offline augmentation is intentionally mild: light blur, light motion blur, light noise/JPEG compression, and a gentle zoom-out that updates labels to make the ball smaller. Apply it to train only, never validation.
- Run the grouped modules from the repo root with `python -m ...` so imports resolve cleanly.

## CoreML Export

- The CoreML export path is `python -m model_tools.export_mlpackage`.
- Ultralytics/CoreML export is blocked on Windows, so run the exporter on macOS or Linux.
- The exporter writes two artifacts into `models/coreml/`:
  - `<name>.mlpackage`: the detector package.
  - `<name>.json`: sidecar metadata for frontend integration, including input size, thresholds, and Vision preprocessing notes.
- The metadata assumes Vision should use `scaleFit`, preserve orientation, and map detections back from the letterboxed model canvas to preview coordinates.
- Exported metadata includes `input.temporal_mode`. The current production value is `single_rgb`; temporal experiments should use `temporal_gray_3` while keeping `input.shape` as `[1, 3, imgsz, imgsz]`.
