from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class MediaAsset:
    id: str
    path: Path
    duration: float
    fps: float
    width: int
    height: int
    has_audio: bool
    size: int
    mtime_ns: int


@dataclass(frozen=True)
class VisualSample:
    asset_id: str
    time: float
    embedding: tuple[float, ...]


@dataclass(frozen=True)
class SearchHit:
    asset_id: str
    source_path: Path
    time: float
    score: float


@dataclass
class Moment:
    asset_id: str
    source_path: Path
    detected_start: float
    detected_end: float
    score: float
    query: str
    handled_start: float | None = None
    handled_end: float | None = None
    labels: set[str] = field(default_factory=set)
    provenance: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)

    @property
    def detected_duration(self) -> float:
        return max(0.0, self.detected_end - self.detected_start)

    @property
    def handled_duration(self) -> float | None:
        if self.handled_start is None or self.handled_end is None:
            return None
        return max(0.0, self.handled_end - self.handled_start)
