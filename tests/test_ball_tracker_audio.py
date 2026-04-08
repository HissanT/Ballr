import ball_tracker


class FakeWinsound:
    SND_ASYNC = 1
    SND_FILENAME = 2
    SND_NODEFAULT = 4

    def __init__(self) -> None:
        self.calls: list[tuple[str, int]] = []

    def PlaySound(self, sound_path: str, flags: int) -> None:
        self.calls.append((sound_path, flags))


def test_play_score_sound_uses_winsound(monkeypatch):
    fake_winsound = FakeWinsound()

    monkeypatch.setattr(ball_tracker, "winsound", fake_winsound)

    ball_tracker.play_score_sound(ball_tracker.TARGET_SOUND_PATH)

    assert fake_winsound.calls == [
        (
            str(ball_tracker.TARGET_SOUND_PATH),
            fake_winsound.SND_ASYNC | fake_winsound.SND_FILENAME | fake_winsound.SND_NODEFAULT,
        )
    ]
