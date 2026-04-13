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
- `python -m model_tools.train --preset v4-tune`: train on `training/dataset_prepared_v4_tune_cleaned`.
- `python -m model_tools.export_mlpackage --overwrite`: export the detector to `models/coreml/<checkpoint>.mlpackage` on macOS or Linux.

## Notes

- `data.yaml` at repo root points at `training/dataset` as a convenience entrypoint.
- The canonical runtime detector checkpoint is `models/ballr_v4_tune_cleaned.pt`.
- `dataset_tools.build_label_viewer(root)` writes `label_overlay_viewer.html` into the target dataset root.
- Run the grouped modules from the repo root with `python -m ...` so imports resolve cleanly.

## CoreML Export

- The CoreML export path is `python -m model_tools.export_mlpackage`.
- Ultralytics/CoreML export is blocked on Windows, so run the exporter on macOS or Linux.
- The exporter writes two artifacts into `models/coreml/`:
  - `<name>.mlpackage`: the detector package.
  - `<name>.json`: sidecar metadata for frontend integration, including input size, thresholds, and Vision preprocessing notes.
- The metadata assumes Vision should use `scaleFit`, preserve orientation, and map detections back from the letterboxed model canvas to preview coordinates.
