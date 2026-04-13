from common import ballr_utils


def test_open_video_capture_prefers_directshow_for_windows_camera_indices(monkeypatch):
    attempts = []

    class FakeCapture:
        def __init__(self, source, api_preference):
            attempts.append((source, api_preference))
            self._opened = api_preference == ballr_utils.cv2.CAP_DSHOW

        def isOpened(self):
            return self._opened

        def release(self):
            return None

    monkeypatch.setattr(ballr_utils.platform, "system", lambda: "Windows")
    monkeypatch.setattr(ballr_utils.cv2, "VideoCapture", FakeCapture)

    capture, backend_name = ballr_utils.open_video_capture(1)

    assert capture.isOpened()
    assert backend_name == ballr_utils.CAMERA_BACKEND_DSHOW
    assert attempts == [(1, ballr_utils.cv2.CAP_DSHOW)]


def test_open_video_capture_falls_back_to_msmf_when_directshow_fails(monkeypatch):
    attempts = []

    class FakeCapture:
        def __init__(self, source, api_preference):
            attempts.append((source, api_preference))
            self._opened = api_preference == ballr_utils.cv2.CAP_MSMF

        def isOpened(self):
            return self._opened

        def release(self):
            return None

    monkeypatch.setattr(ballr_utils.platform, "system", lambda: "Windows")
    monkeypatch.setattr(ballr_utils.cv2, "VideoCapture", FakeCapture)

    capture, backend_name = ballr_utils.open_video_capture(1)

    assert capture.isOpened()
    assert backend_name == ballr_utils.CAMERA_BACKEND_MSMF
    assert attempts == [
        (1, ballr_utils.cv2.CAP_DSHOW),
        (1, ballr_utils.cv2.CAP_MSMF),
    ]
