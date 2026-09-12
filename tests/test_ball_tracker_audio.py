from ball_tracker import app as ball_tracker
from ball_tracker import ball_tracker_audio


class FakeWinsound:
    SND_ASYNC = 1
    SND_FILENAME = 2
    SND_NODEFAULT = 4

    def __init__(self) -> None:
        self.calls: list[tuple[str | None, int]] = []

    def PlaySound(self, sound_path: str | None, flags: int) -> None:
        self.calls.append((sound_path, flags))


def test_play_score_sound_uses_winsound(monkeypatch):
    fake_winsound = FakeWinsound()

    monkeypatch.setattr(ball_tracker, "winsound", fake_winsound)

    ball_tracker.play_score_sound(ball_tracker.TARGET_SOUND_PATH)

    assert fake_winsound.calls == [
        (None, 0),
        (
            str(ball_tracker.TARGET_SOUND_PATH),
            fake_winsound.SND_ASYNC | fake_winsound.SND_FILENAME | fake_winsound.SND_NODEFAULT,
        ),
    ]


def test_play_score_sound_restarts_clip_on_repeat(monkeypatch):
    fake_winsound = FakeWinsound()

    monkeypatch.setattr(ball_tracker, "winsound", fake_winsound)

    ball_tracker.play_score_sound(ball_tracker.TARGET_SOUND_PATH)
    ball_tracker.play_score_sound(ball_tracker.TARGET_SOUND_PATH)

    assert fake_winsound.calls == [
        (None, 0),
        (
            str(ball_tracker.TARGET_SOUND_PATH),
            fake_winsound.SND_ASYNC | fake_winsound.SND_FILENAME | fake_winsound.SND_NODEFAULT,
        ),
        (None, 0),
        (
            str(ball_tracker.TARGET_SOUND_PATH),
            fake_winsound.SND_ASYNC | fake_winsound.SND_FILENAME | fake_winsound.SND_NODEFAULT,
        ),
    ]


def test_play_target_score_sound_ignores_combo_streak(monkeypatch):
    observed_paths: list[object] = []

    monkeypatch.setattr(ball_tracker, "play_score_sound", lambda sound_path=ball_tracker.TARGET_SOUND_PATH: observed_paths.append(sound_path))

    ball_tracker.play_target_score_sound(12)

    assert observed_paths == [ball_tracker.TARGET_SOUND_PATH]


def test_combo_sound_path_loops_back_to_one():
    soundtrack_dir = ball_tracker_audio.COMBO_SOUNDTRACK_DIR
    assert soundtrack_dir.exists()
    assert ball_tracker_audio.combo_sound_path_for_streak(1, soundtrack_dir=soundtrack_dir) == (
        soundtrack_dir / "1.wav"
    )
    assert ball_tracker_audio.combo_sound_path_for_streak(10, soundtrack_dir=soundtrack_dir) == (
        soundtrack_dir / "10.wav"
    )
    assert ball_tracker_audio.combo_sound_path_for_streak(11, soundtrack_dir=soundtrack_dir) == (
        soundtrack_dir / "1.wav"
    )
    assert ball_tracker_audio.combo_sound_path_for_streak(23, soundtrack_dir=soundtrack_dir) == (
        soundtrack_dir / "3.wav"
    )


def test_play_combo_sound_uses_looped_soundtrack_selection(monkeypatch):
    fake_winsound = FakeWinsound()
    soundtrack_dir = ball_tracker_audio.COMBO_SOUNDTRACK_DIR
    assert soundtrack_dir.exists()

    monkeypatch.setattr(ball_tracker, "winsound", fake_winsound)

    ball_tracker.play_combo_sound(12, soundtrack_dir=soundtrack_dir)

    assert fake_winsound.calls == [
        (None, 0),
        (
            str(soundtrack_dir / "2.wav"),
            fake_winsound.SND_ASYNC | fake_winsound.SND_FILENAME | fake_winsound.SND_NODEFAULT,
        ),
    ]
