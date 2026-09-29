import json
import subprocess
from pathlib import Path

import pytest

from clip_resolved.models import MediaAsset, Moment
from clip_resolved.vision_verify import VerifyResult, extract_frame, verify_candidates
from clip_resolved import workflow


def _asset(path: Path, *, asset_id: str = "asset-1") -> MediaAsset:
    return MediaAsset(
        id=asset_id,
        path=path,
        duration=20.0,
        fps=30.0,
        width=1920,
        height=1080,
        has_audio=True,
        size=10,
        mtime_ns=100,
    )


def _moment(item: MediaAsset, *, start: float, end: float, score: float) -> Moment:
    return Moment(
        asset_id=item.id,
        source_path=item.path,
        detected_start=start,
        detected_end=end,
        handled_start=start,
        handled_end=end,
        score=score,
        query="process action",
    )


# --- extract_frame: real ffmpeg, no network/model dependency ---


def test_extract_frame_writes_a_real_jpeg(tmp_path):
    video = tmp_path / "fixture.mp4"
    proc = subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=1:size=64x64:rate=5",
            str(video),
        ],
        capture_output=True,
        text=True,
    )
    assert proc.returncode == 0, proc.stderr

    out = tmp_path / "frame.jpg"
    extract_frame(video, 0.2, out)
    assert out.exists()
    assert out.stat().st_size > 0


def test_extract_frame_raises_on_missing_source(tmp_path):
    with pytest.raises(RuntimeError):
        extract_frame(tmp_path / "does-not-exist.mp4", 0.0, tmp_path / "out.jpg")


# --- verify_candidates: stubbed subprocess, no real Claude calls in CI ---


def test_verify_candidates_returns_empty_without_frames():
    assert verify_candidates("CAT", "query", []) == {}


def test_verify_candidates_returns_empty_when_claude_missing(tmp_path, monkeypatch):
    monkeypatch.setattr("clip_resolved.vision_verify.claude_binary", lambda: None)
    assert verify_candidates("CAT", "query", [tmp_path / "a.jpg"]) == {}


def test_verify_candidates_degrades_on_subprocess_error(tmp_path, monkeypatch):
    monkeypatch.setattr("clip_resolved.vision_verify.claude_binary", lambda: "/usr/bin/claude")

    def raising_run(*args, **kwargs):
        raise OSError("no such process")

    result = verify_candidates("CAT", "query", [tmp_path / "a.jpg"], run=raising_run)
    assert result == {}


def test_verify_candidates_degrades_on_nonzero_exit(tmp_path, monkeypatch):
    monkeypatch.setattr("clip_resolved.vision_verify.claude_binary", lambda: "/usr/bin/claude")

    def failing_run(*args, **kwargs):
        return subprocess.CompletedProcess(args, returncode=1, stdout="", stderr="not logged in")

    result = verify_candidates("CAT", "query", [tmp_path / "a.jpg"], run=failing_run)
    assert result == {}


def test_verify_candidates_degrades_on_malformed_output(tmp_path, monkeypatch):
    monkeypatch.setattr("clip_resolved.vision_verify.claude_binary", lambda: "/usr/bin/claude")

    def bad_json_run(*args, **kwargs):
        return subprocess.CompletedProcess(args, returncode=0, stdout="not json", stderr="")

    result = verify_candidates("CAT", "query", [tmp_path / "a.jpg"], run=bad_json_run)
    assert result == {}


def test_verify_candidates_parses_real_observed_response_shape(tmp_path, monkeypatch):
    """Shape confirmed live against the actual claude CLI (2026-09-29):
    top-level 'structured_output' -> 'verdicts' -> [{index, relevant, reason}]."""
    monkeypatch.setattr("clip_resolved.vision_verify.claude_binary", lambda: "/usr/bin/claude")
    envelope = {
        "structured_output": {
            "verdicts": [
                {"index": 0, "relevant": True, "reason": "Shows a vendor at a market stall."},
                {"index": 1, "relevant": False, "reason": "No sake bottles visible."},
            ]
        }
    }
    captured = {}

    def fake_run(args, *, input, capture_output, text, timeout):
        captured["args"] = args
        captured["input"] = input
        return subprocess.CompletedProcess(args, returncode=0, stdout=json.dumps(envelope), stderr="")

    frames = [tmp_path / "0.jpg", tmp_path / "1.jpg"]
    result = verify_candidates("SAKE BOTTLES SELECTS", "sake bottles", frames, run=fake_run)

    assert result == {
        0: VerifyResult(relevant=True, reason="Shows a vendor at a market stall."),
        1: VerifyResult(relevant=False, reason="No sake bottles visible."),
    }
    # Prompt via stdin (matches the app's existing Claude CLI invocation pattern), not argv.
    assert captured["input"] == f"0. {frames[0]}\n1. {frames[1]}"
    assert "--allowedTools" in captured["args"]
    assert "Read" in captured["args"]
    assert "--tools" not in captured["args"]  # would block image reading


# --- vision_verify_moments: the workflow.py orchestration ---


def test_vision_verify_moments_drops_rejected_and_keeps_confirmed(tmp_path, monkeypatch):
    item = _asset(tmp_path / "clip.mp4")
    assets = {item.id: item}
    strong = _moment(item, start=0, end=4, score=0.9)
    weak = _moment(item, start=10, end=14, score=0.8)

    monkeypatch.setattr(workflow, "extract_frame", lambda *a, **k: None)
    monkeypatch.setattr(
        workflow,
        "verify_candidates",
        lambda *a, **k: {
            0: VerifyResult(relevant=True, reason="really shows it"),
            1: VerifyResult(relevant=False, reason="does not show it"),
        },
    )

    kept, report = workflow.vision_verify_moments(
        "PROCESS ACTION SELECTS", "process action", [strong, weak], assets, top_k=10
    )

    assert kept == [strong]
    assert report["verified"] == 2
    assert report["dropped"] == 1
    assert report["verify_available"] is True


def test_vision_verify_moments_only_reviews_top_k_and_keeps_the_rest_unverified(tmp_path, monkeypatch):
    item = _asset(tmp_path / "clip.mp4")
    assets = {item.id: item}
    top = _moment(item, start=0, end=4, score=0.9)
    tail = _moment(item, start=10, end=14, score=0.1)

    monkeypatch.setattr(workflow, "extract_frame", lambda *a, **k: None)
    monkeypatch.setattr(
        workflow,
        "verify_candidates",
        lambda *a, **k: {0: VerifyResult(relevant=True, reason="confirmed")},
    )

    kept, report = workflow.vision_verify_moments(
        "CAT", "query", [top, tail], assets, top_k=1
    )

    assert top in kept
    assert tail in kept  # never sent to Claude, so kept unverified rather than dropped
    assert report["verified"] == 1


def test_vision_verify_moments_degrades_to_unchanged_when_claude_unavailable(tmp_path, monkeypatch):
    item = _asset(tmp_path / "clip.mp4")
    assets = {item.id: item}
    moments = [_moment(item, start=0, end=4, score=0.9)]

    monkeypatch.setattr(workflow, "extract_frame", lambda *a, **k: None)
    monkeypatch.setattr(workflow, "verify_candidates", lambda *a, **k: {})

    kept, report = workflow.vision_verify_moments("CAT", "query", moments, assets)

    assert kept == moments
    assert report["verify_available"] is False


def test_vision_verify_moments_handles_empty_input():
    kept, report = workflow.vision_verify_moments("CAT", "query", [], {})
    assert kept == []
    assert report["verify_available"] is False
