import json
import subprocess
from pathlib import Path

from clip_resolved.category_discovery import discover_categories, sample_frame_points
from clip_resolved.models import MediaAsset
from clip_resolved.workflow import SelectsCategory


def _asset(path: Path, *, asset_id: str, duration: float = 20.0, capture_time: float | None = None) -> MediaAsset:
    return MediaAsset(
        id=asset_id,
        path=path,
        duration=duration,
        fps=30.0,
        width=1920,
        height=1080,
        has_audio=True,
        size=10,
        mtime_ns=100,
        capture_time=capture_time,
    )


# --- sample_frame_points: pure sampling logic, no subprocess ---


def test_sample_frame_points_spreads_across_all_assets_not_just_the_first(tmp_path):
    assets = {
        f"a{i}": _asset(tmp_path / f"clip{i}.mp4", asset_id=f"a{i}", capture_time=float(i))
        for i in range(10)
    }
    points = sample_frame_points(assets, sample_size=5)
    asset_ids = {a.id for a, _ in points}
    # Should not just be the first 5 by capture_time -- should span the range.
    assert len(points) <= 5
    assert min(int(i[1:]) for i in asset_ids) < 5
    assert max(int(i[1:]) for i in asset_ids) >= 5


def test_sample_frame_points_respects_sample_size_cap():
    points = sample_frame_points({}, sample_size=10)
    assert points == []


def test_sample_frame_points_skips_zero_duration_assets(tmp_path):
    assets = {"a": _asset(tmp_path / "clip.mp4", asset_id="a", duration=0.0)}
    assert sample_frame_points(assets, sample_size=10) == []


# --- discover_categories: stubbed subprocess, no real Claude calls in CI ---


def test_discover_categories_returns_empty_with_no_assets():
    categories, report = discover_categories({})
    assert categories == []
    assert report["discovery_available"] is False


def test_discover_categories_returns_empty_when_claude_missing(tmp_path, monkeypatch):
    monkeypatch.setattr("clip_resolved.category_discovery.claude_binary", lambda: None)
    assets = {"a": _asset(tmp_path / "clip.mp4", asset_id="a")}
    categories, report = discover_categories(assets)
    assert categories == []
    assert report["discovery_available"] is False


def test_discover_categories_degrades_on_subprocess_error(tmp_path, monkeypatch):
    monkeypatch.setattr("clip_resolved.category_discovery.claude_binary", lambda: "/usr/bin/claude")
    monkeypatch.setattr(
        "clip_resolved.category_discovery.extract_frame",
        lambda video, time, out: out.write_bytes(b"fake"),
    )

    def raising_run(*args, **kwargs):
        raise OSError("no such process")

    assets = {"a": _asset(tmp_path / "clip.mp4", asset_id="a")}
    categories, report = discover_categories(assets, run=raising_run)
    assert categories == []
    assert report["discovery_available"] is False


def test_discover_categories_degrades_on_malformed_output(tmp_path, monkeypatch):
    monkeypatch.setattr("clip_resolved.category_discovery.claude_binary", lambda: "/usr/bin/claude")
    monkeypatch.setattr(
        "clip_resolved.category_discovery.extract_frame",
        lambda video, time, out: out.write_bytes(b"fake"),
    )

    def bad_json_run(*args, **kwargs):
        return subprocess.CompletedProcess(args, returncode=0, stdout="not json", stderr="")

    assets = {"a": _asset(tmp_path / "clip.mp4", asset_id="a")}
    categories, report = discover_categories(assets, run=bad_json_run)
    assert categories == []
    assert report["discovery_available"] is False


def test_discover_categories_parses_real_response_shape_and_dedupes(tmp_path, monkeypatch):
    """Same envelope shape confirmed live for verify_candidates: top-level
    'structured_output' -> the schema's array key -> list of objects."""
    monkeypatch.setattr("clip_resolved.category_discovery.claude_binary", lambda: "/usr/bin/claude")
    monkeypatch.setattr(
        "clip_resolved.category_discovery.extract_frame",
        lambda video, time, out: out.write_bytes(b"fake"),
    )
    envelope = {
        "structured_output": {
            "categories": [
                {"name": "INSTALLATION WORK SELECTS", "query": "person installing or arranging an art piece"},
                {"name": "SCULPTURE DISPLAY SELECTS", "query": "sculpture on a pedestal in a gallery"},
                {"name": "INSTALLATION WORK SELECTS", "query": "duplicate name, should be dropped"},
                {"name": "", "query": "empty name, should be dropped"},
            ]
        }
    }
    captured = {}

    def fake_run(args, *, input, capture_output, text, timeout):
        captured["args"] = args
        captured["input"] = input
        return subprocess.CompletedProcess(args, returncode=0, stdout=json.dumps(envelope), stderr="")

    assets = {
        f"a{i}": _asset(tmp_path / f"clip{i}.mp4", asset_id=f"a{i}", capture_time=float(i))
        for i in range(3)
    }
    categories, report = discover_categories(assets, sample_size=6, run=fake_run)

    assert categories == [
        SelectsCategory("INSTALLATION WORK SELECTS", "person installing or arranging an art piece"),
        SelectsCategory("SCULPTURE DISPLAY SELECTS", "sculpture on a pedestal in a gallery"),
    ]
    assert report["discovery_available"] is True
    assert report["frames_sampled"] > 0
    assert report["assets_sampled"] > 0
    assert "--allowedTools" in captured["args"]
    assert "Read" in captured["args"]
    assert "--tools" not in captured["args"]  # would block image reading
