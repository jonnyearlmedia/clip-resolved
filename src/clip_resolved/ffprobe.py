from __future__ import annotations

import hashlib
import json
import subprocess
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


def _asset_id(path: Path, size: int, mtime_ns: int) -> str:
    # Vertical-slice identity. The final canonical project manifest can replace
    # this with verified ingest hashes without changing callers.
    payload = f"{path.resolve()}\0{size}\0{mtime_ns}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()[:24]


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
        id=_asset_id(source, stat.st_size, stat.st_mtime_ns),
        path=source,
        duration=max(0.0, duration),
        fps=max(0.0, fps),
        width=width,
        height=height,
        has_audio=bool(audios),
        size=stat.st_size,
        mtime_ns=stat.st_mtime_ns,
    )


def discover_video_files(root: str | Path) -> list[Path]:
    base = Path(root).expanduser().resolve()
    if base.is_file():
        return [base]
    suffixes = {".mp4", ".mov", ".mxf", ".m4v"}
    return sorted(
        p.resolve()
        for p in base.rglob("*")
        if p.is_file() and p.suffix.lower() in suffixes
    )
