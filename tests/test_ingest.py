from datetime import datetime, timezone
from pathlib import Path
from types import SimpleNamespace

from clip_resolved import ingest


def test_scan_groups_temporal_sessions_and_accounts_for_every_video(tmp_path, monkeypatch):
    names = [
        "DJI_20260101233000_0001_D.MP4",
        "DJI_20260102001500_0002_D.MP4",
        "DJI_20260102110000_0003_D.MP4",
    ]
    for name in names:
        (tmp_path / name).write_bytes(b"fixture")
    (tmp_path / "DJI_20260101233000_0001_D.SRT").write_text("sidecar")

    times = {
        names[0]: datetime(2026, 1, 1, 23, 30, tzinfo=timezone.utc),
        names[1]: datetime(2026, 1, 2, 0, 15, tzinfo=timezone.utc),
        names[2]: datetime(2026, 1, 2, 11, 0, tzinfo=timezone.utc),
    }

    def fake_probe(path, _stat):
        return times[path.name], 10.0, 59.94, 3840, 2160, True

    monkeypatch.setattr(ingest, "_probe_video", fake_probe)
    result = ingest.scan_source(tmp_path, Path(__file__).parents[1], gap_hours=3)

    assert result["video_count"] == 3
    assert len(result["groups"]) == 2
    assert result["groups"][0]["video_count"] == 2
    assert result["groups"][0]["file_count"] == 3
    assert result["groups"][1]["video_count"] == 1
    accounted = [
        file["path"]
        for group in result["groups"]
        for file in group["files"]
        if file["kind"] == "video"
    ]
    assert sorted(accounted) == sorted(str(tmp_path / name) for name in names)
    assert len(accounted) == len(set(accounted))


def test_scan_mic_card_creates_audio_session_without_camera_video(tmp_path, monkeypatch):
    names = ["DJI_01_20260926_110000.WAV", "DJI_01_20260926_111500.WAV"]
    for name in names:
        (tmp_path / name).write_bytes(b"audio-fixture")

    times = {
        names[0]: datetime(2026, 9, 26, 18, 0, tzinfo=timezone.utc),
        names[1]: datetime(2026, 9, 26, 18, 15, tzinfo=timezone.utc),
    }

    def fake_probe(path, _stat):
        return times[path.name], 600.0

    monkeypatch.setattr(ingest, "_probe_audio", fake_probe)
    result = ingest.scan_source(tmp_path, Path(__file__).parents[1], gap_hours=3)

    assert result["video_count"] == 0
    assert result["audio_count"] == 2
    assert len(result["groups"]) == 1
    assert result["groups"][0]["source_kind"] == "Audio"
    assert result["groups"][0]["audio_count"] == 2
    assert result["groups"][0]["video_count"] == 0
    assert all(item["kind"] == "audio" for item in result["groups"][0]["files"])


def test_ffprobe_retries_a_transient_external_media_read(monkeypatch, tmp_path):
    video = tmp_path / "DJI_0001.MP4"
    video.write_bytes(b"fixture")
    calls = 0
    payload = {
        "streams": [
            {
                "codec_type": "video",
                "duration": "10.0",
                "avg_frame_rate": "60000/1001",
                "width": 3840,
                "height": 2160,
                "tags": {},
            }
        ],
        "format": {"duration": "10.0", "tags": {}},
    }

    def fake_run(*_args, **_kwargs):
        nonlocal calls
        calls += 1
        if calls == 1:
            return SimpleNamespace(returncode=1, stdout="", stderr="temporary I/O error")
        return SimpleNamespace(returncode=0, stdout=__import__("json").dumps(payload), stderr="")

    monkeypatch.setattr(ingest.subprocess, "run", fake_run)
    monkeypatch.setattr(ingest.time, "sleep", lambda _seconds: None)

    result = ingest._probe_video(video, video.stat())

    assert calls == 2
    assert result[1] == 10.0
    assert result[3:5] == (3840, 2160)


def test_scan_reports_unreadable_video_without_crashing_or_silently_omitting_it(tmp_path, monkeypatch):
    readable = tmp_path / "DJI_0001.MP4"
    unreadable = tmp_path / "DJI_0002.MP4"
    readable.write_bytes(b"good")
    unreadable.write_bytes(b"bad")

    def fake_probe(path, _stat):
        if path == unreadable:
            raise ingest.MediaProbeError("ffprobe could not read this file after 2 attempts: I/O error")
        return datetime(2026, 9, 29, tzinfo=timezone.utc), 10.0, 59.94, 3840, 2160, True

    monkeypatch.setattr(ingest, "_probe_video", fake_probe)

    result = ingest.scan_source(tmp_path, Path(__file__).parents[1])

    assert result["video_count"] == 2
    assert sum(group["video_count"] for group in result["groups"]) == 1
    assert result["scan_issues"] == [
        {
            "path": str(unreadable),
            "relative_path": unreadable.name,
            "kind": "video",
            "reason": "ffprobe could not read this file after 2 attempts: I/O error",
        }
    ]
