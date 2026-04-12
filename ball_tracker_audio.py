import threading
from pathlib import Path
from typing import Any

TARGET_SOUND_PATH = Path(__file__).with_name("target_scored_sound_effect.wav")
COMBO_SOUNDTRACK_DIR = Path(__file__).with_name("soundtracks")
COMBO_SOUND_COUNT = 10
_PLAYBACK_LOCK = threading.Lock()

def combo_sound_path_for_streak(
    hit_streak: int,
    soundtrack_dir: Path = COMBO_SOUNDTRACK_DIR,
) -> Path:
    combo_index = ((max(hit_streak, 1) - 1) % COMBO_SOUND_COUNT) + 1
    soundtrack_path = soundtrack_dir / f"{combo_index}.wav"
    if soundtrack_path.exists():
        return soundtrack_path
    return TARGET_SOUND_PATH


def play_score_sound(sound_path: Path = TARGET_SOUND_PATH, winsound_module: Any = None) -> None:
    if winsound_module is None or not sound_path.exists():
        return

    flags = (
        winsound_module.SND_ASYNC
        | winsound_module.SND_FILENAME
        | winsound_module.SND_NODEFAULT
    )
    with _PLAYBACK_LOCK:
        # Force a restart so rapid repeat hits do not get dropped while a prior cue is still active.
        winsound_module.PlaySound(None, 0)
        winsound_module.PlaySound(str(sound_path), flags)


def play_combo_sound(hit_streak: int, winsound_module: Any = None) -> None:
    play_score_sound(combo_sound_path_for_streak(hit_streak), winsound_module=winsound_module)
