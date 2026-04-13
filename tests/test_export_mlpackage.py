import shutil
from pathlib import Path

import pytest

from export_mlpackage import (
    build_export_metadata,
    move_exported_package,
    require_supported_platform,
    write_metadata,
)


def test_require_supported_platform_rejects_windows():
    with pytest.raises(SystemExit, match="not supported on Windows"):
        require_supported_platform("Windows")


def test_build_export_metadata_includes_frontend_and_runtime_defaults():
    metadata = build_export_metadata(
        weights_path=Path("models/ballr_v4_tune_cleaned.pt"),
        package_path=Path("models/coreml/ballr_v4_tune_cleaned.mlpackage"),
        imgsz=768,
        nms_enabled=True,
        int8_enabled=False,
    )

    assert metadata["format"] == "coreml"
    assert metadata["task"] == "object_detection"
    assert metadata["input"]["shape"] == [1, 3, 768, 768]
    assert metadata["output"]["includes_nms"] is True
    assert metadata["frontend_notes"]["vision_crop_and_scale"] == "scaleFit"
    assert metadata["ballr_runtime_defaults"]["ball_class_id"] == 0


def test_move_exported_package_moves_directory_to_requested_destination(monkeypatch):
    source_path = Path("raw_export.mlpackage")
    destination_path = Path("models/coreml/ballr.mlpackage")
    moved = []
    mkdir_calls = []

    monkeypatch.setattr(Path, "mkdir", lambda self, parents=False, exist_ok=False: mkdir_calls.append(self))
    monkeypatch.setattr(Path, "exists", lambda self: False)
    monkeypatch.setattr(shutil, "move", lambda src, dst: moved.append((src, dst)))

    moved_path = move_exported_package(source_path, destination_path, overwrite=False)

    assert moved_path == destination_path.resolve()
    assert moved == [(str(source_path.resolve()), str(destination_path.resolve()))]
    assert mkdir_calls == [destination_path.resolve().parent]


def test_write_metadata_refuses_to_overwrite_without_flag(monkeypatch):
    metadata_path = Path("models/coreml/ballr.json")
    writes = []

    monkeypatch.setattr(Path, "mkdir", lambda self, parents=False, exist_ok=False: None)
    monkeypatch.setattr(Path, "write_text", lambda self, data, encoding=None: writes.append((self, data, encoding)))
    monkeypatch.setattr(Path, "exists", lambda self: not not writes)

    write_metadata(metadata_path, {"a": 1}, overwrite=False)

    with pytest.raises(SystemExit, match="Refusing to overwrite existing metadata"):
        write_metadata(metadata_path, {"a": 2}, overwrite=False)
