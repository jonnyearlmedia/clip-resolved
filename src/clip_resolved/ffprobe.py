from __future__ import annotations

import hashlib
import json
import subprocess
from datetime import datetime
from fractions import Fraction
from pathlib import Path

from .models import MediaAsset


def _rate(value: str | None) -> float:
    if not value or value in {"0/0", "N/A"}:
        return 0.0
    try:
        return float(Fraction(value))
    except (ValueError, ZeroDivisionError):
        try:
            return float(value)
        except (TypeError, ValueError):
            return 0.0


def _asset_id(path: Path) -> str:
    # Stable for the current vertical slice while a source remains at one path.
    # Verified ingest hashes can replace this later without coupling callers to
    # size/mtime, which are freshness signals rather than identity.
    payload = str(path.resolve()).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()[:24]


def _capture_timestamp(payload: dict, stat) -> float:
    candidates = [payload.get("format", {}).get("tags", {}).get("creation_time")]
    candidates.extend(
        stream.get("tags", {}).get("creation_time")
        for stream in payload.get("streams", [])
    )
    for candidate in candidates:
        if not candidate:
            continue
        try:
            return datetime.fromisoformat(str(candidate).replace("Z", "+00:00")).timestamp()
        except ValueError:
            continue
    return float(getattr(stat, "st_birthtime", stat.st_mtime))


def probe(path: str | Path) -> MediaAsset:
    source = Path(path).expanduser().resolve()
    stat = source.stat()
    proc = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(source),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(proc.stdout)
    streams = payload.get("streams", [])
    videos = [s for s in streams if s.get("codec_type") == "video"]
    audios = [s for s in streams if s.get("codec_type") == "audio"]
    if not videos:
        raise ValueError(f"no video stream: {source}")

    video = videos[0]
    duration = 0.0
    for candidate in (
        video.get("duration"),
        payload.get("format", {}).get("duration"),
    ):
        if candidate not in (None, "N/A"):
            try:
                duration = float(candidate)
                break
            except (TypeError, ValueError):
                pass

    fps = _rate(video.get("avg_frame_rate")) or _rate(video.get("r_frame_rate"))
    width = int(video.get("width") or 0)
    height = int(video.get("height") or 0)

    return MediaAsset(
        id=_asset_id(source),
        path=source,
        duration=max(0.0, duration),
        fps=max(0.0, fps),
        width=width,
        height=height,
        has_audio=bool(audios),
        size=stat.st_size,
        mtime_ns=stat.st_mtime_ns,
        capture_time=_capture_timestamp(payload, stat),
    )


def discover_video_files(root: str | Path) -> list[Path]:
    base = Path(root).expanduser().resolve()
    suffixes = {".mp4", ".mov", ".mxf", ".m4v", ".insv"}
    if base.is_file():
        return [base] if base.suffix.lower() in suffixes else []
    return sorted(
        p.resolve()
        for p in base.rglob("*")
        if p.is_file() and p.suffix.lower() in suffixes
    )


def discover_audio_files(root: str | Path) -> list[Path]:
    base = Path(root).expanduser().resolve()
    suffixes = {".wav", ".m4a", ".mp3", ".aif", ".aiff", ".flac"}
    if base.is_file():
        return [base] if base.suffix.lower() in suffixes else []
    return sorted(
        p.resolve()
        for p in base.rglob("*")
        if p.is_file() and p.suffix.lower() in suffixes
    )
