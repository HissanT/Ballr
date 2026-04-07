from pathlib import Path
from typing import Any

TARGET_SOUND_PATH = Path(__file__).with_name("target_scored_sound_effect.wav")


def play_score_sound(sound_path: Path = TARGET_SOUND_PATH, winsound_module: Any = None) -> None:
    if winsound_module is None or not sound_path.exists():
        return

    winsound_module.PlaySound(
        str(sound_path),
        winsound_module.SND_ASYNC
        | winsound_module.SND_FILENAME
        | winsound_module.SND_NODEFAULT,
    )
