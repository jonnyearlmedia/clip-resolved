from datetime import datetime, timezone
from pathlib import Path

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
