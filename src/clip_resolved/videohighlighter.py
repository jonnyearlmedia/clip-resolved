from __future__ import annotations

import importlib
import math
import sys
from pathlib import Path

import numpy as np

from .models import MediaAsset, Moment, SearchHit


class VideoHighlighterAdapter:
    """Loads and calls the pinned VideoHighlighter implementation in-place."""

    def __init__(self, repo_root: Path | None = None) -> None:
        self.repo_root = repo_root or Path(__file__).resolve().parents[2]
        self.upstream_root = self.repo_root / "external" / "VideoHighlighter"
        self._module = None

    def _auto_segments(self):
        if self._module is not None:
            return self._module
        if not self.upstream_root.exists():
            raise RuntimeError(
                f"VideoHighlighter checkout missing at {self.upstream_root}. "
                "Run scripts/bootstrap_upstreams.sh first."
            )
        root = str(self.upstream_root)
        if root not in sys.path:
            sys.path.insert(0, root)
        self._module = importlib.import_module("modules.auto_segments")
        return self._module

    def semantic_regions(
        self,
        asset: MediaAsset,
        hits: list[SearchHit],
        query: str,
        *,
        min_duration: float = 1.5,
        max_duration: float = 30.0,
        merge_gap: float = 1.5,
    ) -> list[Moment]:
        """Turn timestamped semantic hits into editor-facing candidate regions.

        This deliberately reuses VideoHighlighter's own region primitives instead
        of reproducing its clustering/merge/constrain algorithm here. Semantic
        hits are presented to the upstream engine as per-second detections; this
        gives us its mature point-clustering behavior while keeping the semantic
        source (SynthCut CLIP) replaceable.
        """
        if not hits:
            return []
        upstream = self._auto_segments()
        score = np.zeros(max(2, int(math.ceil(asset.duration)) + 2), dtype=float)
        detections: dict[int, list[str]] = {}

        # CLIP similarities are ranking values rather than calibrated probabilities.
        # We only send the already-ranked hit set to the region builder and preserve
        # the raw scores for later real-footage tuning.
        min_hit_score = min(hit.score for hit in hits)
        for hit in hits:
            sec = max(0, min(len(score) - 1, int(round(hit.time))))
            # Keep scores positive because VideoHighlighter excludes zero-score regions.
            shifted = max(1e-6, hit.score - min_hit_score + 1e-3)
            score[sec] = max(score[sec], shifted)
            detections.setdefault(sec, []).append(query)

        regions = upstream._regions_from_objects(detections, [], score)
        regions = upstream.merge_regions(regions, gap_tolerance=merge_gap)
        regions = upstream.constrain_regions(
            regions,
            score,
            asset.duration,
            min_dur=min_duration,
            max_dur=max_duration,
        )

        moments: list[Moment] = []
        for region in regions:
            overlapping = [h for h in hits if region.start <= h.time <= region.end]
            raw_score = max((h.score for h in overlapping), default=0.0)
            moments.append(
                Moment(
                    asset_id=asset.id,
                    source_path=asset.path,
                    detected_start=max(0.0, float(region.start)),
                    detected_end=min(asset.duration, float(region.end)),
                    score=raw_score,
                    query=query,
                    labels={query},
                    provenance=list(region.sources),
                    metadata={
                        "upstream": "Aseiel/VideoHighlighter:modules/auto_segments.py",
                        "sample_hits": len(overlapping),
                    },
                )
            )
        moments.sort(key=lambda m: (m.source_path.as_posix(), m.detected_start))
        return moments
