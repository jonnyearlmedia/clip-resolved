from __future__ import annotations

import importlib
import json
import subprocess
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


VIDEO_SUFFIXES = {".mp4", ".mov", ".mxf", ".m4v", ".insv"}
AUDIO_SUFFIXES = {".wav", ".m4a", ".mp3", ".aif", ".aiff", ".flac"}
SIDECAR_SUFFIXES = {".srt", ".lrf", ".xml", ".xmp"}


@dataclass(frozen=True)
class ScannedMedia:
    path: str
    relative_path: str
    group_key: str
    kind: str
    size: int
    capture_time: str
    duration: float
    fps: float
    width: int
    height: int
    has_audio: bool


def _formats_module(repo_root: Path):
    """Load KontentManager's actual sidecar/camera-format implementation."""
    backend = repo_root / "external" / "kontentmanager" / "backend"
    if not backend.exists():
        raise RuntimeError("KontentManager checkout missing; run scripts/bootstrap_upstreams.sh")
    value = str(backend)
    if value not in sys.path:
        sys.path.insert(0, value)
    return importlib.import_module("app.services.formats")


def _parse_date(value: str | None) -> datetime | None:
    if not value:
        return None
    normalized = value.strip().replace("Z", "+00:00")
    try:
        result = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if result.tzinfo is None:
        result = result.replace(tzinfo=timezone.utc)
    return result


def _number(value: Any) -> float:
    if value in (None, "", "N/A"):
        return 0.0
    try:
        if isinstance(value, str) and "/" in value:
            numerator, denominator = value.split("/", 1)
            return float(numerator) / float(denominator)
        return float(value)
    except (TypeError, ValueError, ZeroDivisionError):
        return 0.0


def _probe_video(path: Path, stat) -> tuple[datetime, float, float, int, int, bool]:
    proc = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(proc.stdout)
    streams = payload.get("streams", [])
    video = next((stream for stream in streams if stream.get("codec_type") == "video"), {})
    audio = any(stream.get("codec_type") == "audio" for stream in streams)
    format_info = payload.get("format", {})
    capture = (
        _parse_date(video.get("tags", {}).get("creation_time"))
        or _parse_date(format_info.get("tags", {}).get("creation_time"))
        or datetime.fromtimestamp(getattr(stat, "st_birthtime", stat.st_mtime), tz=timezone.utc)
    )
    duration = _number(video.get("duration")) or _number(format_info.get("duration"))
    fps = _number(video.get("avg_frame_rate")) or _number(video.get("r_frame_rate"))
    return (
        capture,
        max(0.0, duration),
        max(0.0, fps),
        int(video.get("width") or 0),
        int(video.get("height") or 0),
        audio,
    )


def _probe_audio(path: Path, stat) -> tuple[datetime, float]:
    proc = subprocess.run(
        [
            "ffprobe",
            "-v",
            "error",
            "-show_streams",
            "-show_format",
            "-of",
            "json",
            str(path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(proc.stdout)
    audio = next(
        (stream for stream in payload.get("streams", []) if stream.get("codec_type") == "audio"),
        {},
    )
    format_info = payload.get("format", {})
    capture = (
        _parse_date(audio.get("tags", {}).get("creation_time"))
        or _parse_date(format_info.get("tags", {}).get("creation_time"))
        or datetime.fromtimestamp(getattr(stat, "st_birthtime", stat.st_mtime), tz=timezone.utc)
    )
    duration = _number(audio.get("duration")) or _number(format_info.get("duration"))
    return capture, max(0.0, duration)


def _temporal_groups(items: list[ScannedMedia], threshold: timedelta) -> list[list[ScannedMedia]]:
    groups: list[list[ScannedMedia]] = []
    previous_end: datetime | None = None
    for item in sorted(items, key=lambda value: value.capture_time):
        capture = _parse_date(item.capture_time) or datetime.fromtimestamp(0, tz=timezone.utc)
        if previous_end is None or capture - previous_end > threshold:
            groups.append([])
        groups[-1].append(item)
        previous_end = max(previous_end or capture, capture + timedelta(seconds=item.duration))
    return groups


def scan_source(source: str | Path, repo_root: Path, *, gap_hours: float = 3.0) -> dict[str, Any]:
    """Read-only card/folder scan with temporal session proposals.

    Session grouping is clip-resolved glue. File recognition and DJI sidecar
    association come from the pinned KontentManager implementation.
    """
    root = Path(source).expanduser().resolve()
    if not root.is_dir():
        raise ValueError(f"source is not a folder: {root}")
    formats = _formats_module(repo_root)
    media: list[ScannedMedia] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.is_symlink() or formats.is_ignored(path):
            continue
        suffix = path.suffix.lower()
        if suffix not in VIDEO_SUFFIXES | AUDIO_SUFFIXES | SIDECAR_SUFFIXES:
            continue
        stat = path.stat()
        if stat.st_size <= 0:
            continue
        relative = str(path.relative_to(root))
        group_key = formats.sidecar_group_key(Path(relative))
        if suffix in VIDEO_SUFFIXES:
            capture, duration, fps, width, height, has_audio = _probe_video(path, stat)
            kind = "video"
        elif suffix in AUDIO_SUFFIXES:
            capture, duration = _probe_audio(path, stat)
            fps = 0.0
            width = height = 0
            has_audio = True
            kind = "audio"
        else:
            capture = datetime.fromtimestamp(getattr(stat, "st_birthtime", stat.st_mtime), tz=timezone.utc)
            duration = fps = 0.0
            width = height = 0
            has_audio = False
            kind = "sidecar"
        media.append(
            ScannedMedia(
                path=str(path),
                relative_path=relative,
                group_key=group_key,
                kind=kind,
                size=stat.st_size,
                capture_time=capture.astimezone().isoformat(),
                duration=duration,
                fps=fps,
                width=width,
                height=height,
                has_audio=has_audio,
            )
        )

    videos = sorted((item for item in media if item.kind == "video"), key=lambda item: item.capture_time)
    audios = sorted((item for item in media if item.kind == "audio"), key=lambda item: item.capture_time)
    threshold = timedelta(hours=max(0.25, gap_hours))
    groups = _temporal_groups(videos, threshold)

    video_keys = {item.group_key for item in videos}
    paired_audio = [item for item in audios if item.group_key in video_keys]
    standalone_audio = [item for item in audios if item.group_key not in video_keys]
    video_group_by_key = {
        item.group_key: index
        for index, group in enumerate(groups)
        for item in group
    }
    for audio in paired_audio:
        groups[video_group_by_key[audio.group_key]].append(audio)
    groups.extend(_temporal_groups(standalone_audio, threshold))

    key_to_group = {
        item.group_key: index
        for index, group in enumerate(groups)
        for item in group
    }
    unassigned_sidecars: list[ScannedMedia] = []
    for sidecar in (item for item in media if item.kind == "sidecar"):
        index = key_to_group.get(sidecar.group_key)
        if index is None:
            unassigned_sidecars.append(sidecar)
        else:
            groups[index].append(sidecar)

    payload_groups = []
    for index, group in enumerate(groups, start=1):
        group.sort(key=lambda item: (item.capture_time, item.relative_path))
        group_videos = [item for item in group if item.kind == "video"]
        group_audio = [item for item in group if item.kind == "audio"]
        primary = group_videos or group_audio
        first = primary[0]
        last = primary[-1]
        group_label = "Shoot" if group_videos else "Audio Session"
        payload_groups.append(
            {
                "id": f"group-{index}",
                "suggested_name": f"{group_label} {index} — {first.capture_time[:10]}",
                "source_kind": "Camera" if group_videos else "Audio",
                "start": first.capture_time,
                "end": last.capture_time,
                "video_count": len(group_videos),
                "audio_count": len(group_audio),
                "file_count": len(group),
                "total_bytes": sum(item.size for item in group),
                "files": [asdict(item) for item in group],
            }
        )

    return {
        "source": str(root),
        "video_count": len(videos),
        "audio_count": len(audios),
        "sidecar_count": sum(item.kind == "sidecar" for item in media),
        "total_bytes": sum(item.size for item in media),
        "groups": payload_groups,
        "unassigned_sidecars": [asdict(item) for item in unassigned_sidecars],
    }
