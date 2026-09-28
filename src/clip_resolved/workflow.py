from __future__ import annotations

import math
import re
from pathlib import Path

from .models import MediaAsset, Moment
from .ranges import apply_handles, merge_overlapping_handled
from .semantic import hits_by_asset, search
from .store import IndexStore
from .synthcut import SynthCutClipBridge
from .videohighlighter import VideoHighlighterAdapter


def default_timeline_name(query: str) -> str:
    words = re.sub(r"[^A-Za-z0-9]+", " ", query).strip().upper()
    words = re.sub(r"\s+", " ", words)
    return f"{words or 'QUERY'} SELECTS"


def default_remainder_timeline_name(selects_name: str) -> str:
    base = re.sub(r"\s+SELECTS$", "", selects_name.strip(), flags=re.IGNORECASE)
    return f"{base or 'QUERY'} NOT SELECTED"


def unselected_moments(
    selected: list[Moment],
    assets: dict[str, MediaAsset],
    *,
    query: str,
) -> list[Moment]:
    """Return the exact source-frame complement of handled SELECTS ranges."""
    selected_frames: dict[str, list[tuple[int, int]]] = {}
    for moment in selected:
        asset = assets.get(moment.asset_id)
        if asset is None or asset.fps <= 0:
            continue
        start_seconds = moment.handled_start if moment.handled_start is not None else moment.detected_start
        end_seconds = moment.handled_end if moment.handled_end is not None else moment.detected_end
        start = max(0, int(math.floor(start_seconds * asset.fps)))
        end = max(start + 1, int(math.ceil(end_seconds * asset.fps)))
        total = max(1, int(math.ceil(asset.duration * asset.fps)))
        selected_frames.setdefault(asset.id, []).append((min(start, total), min(end, total)))

    remainder: list[Moment] = []
    for asset in sorted(assets.values(), key=lambda item: str(item.path)):
        if asset.fps <= 0:
            continue
        total = max(1, int(math.ceil(asset.duration * asset.fps)))
        merged: list[list[int]] = []
        for start, end in sorted(selected_frames.get(asset.id, [])):
            if start >= end:
                continue
            if merged and start <= merged[-1][1]:
                merged[-1][1] = max(merged[-1][1], end)
            else:
                merged.append([start, end])

        cursor = 0
        gaps: list[tuple[int, int]] = []
        for start, end in merged:
            if cursor < start:
                gaps.append((cursor, start))
            cursor = max(cursor, end)
        if cursor < total:
            gaps.append((cursor, total))

        for start, end in gaps:
            start_seconds = start / asset.fps
            end_seconds = end / asset.fps
            remainder.append(
                Moment(
                    asset_id=asset.id,
                    source_path=asset.path,
                    detected_start=start_seconds,
                    detected_end=end_seconds,
                    handled_start=start_seconds,
                    handled_end=end_seconds,
                    score=0.0,
                    query=f"{query} — not selected",
                    labels={"not selected"},
                    provenance=["exact source-frame complement"],
                    metadata={
                        "source_start_frame": start,
                        "source_end_frame": end,
                        "complement_of": query,
                    },
                )
            )
    return remainder


def find_moments(
    query: str,
    store: IndexStore,
    bridge: SynthCutClipBridge,
    region_builder: VideoHighlighterAdapter,
    *,
    search_limit: int = 80,
    per_asset_limit: int = 30,
    min_score: float = 0.22,
    pre_handle: float = 2.0,
    post_handle: float = 3.0,
    minimum_duration: float = 6.0,
) -> tuple[list[Moment], dict[str, MediaAsset]]:
    hits = search(
        query,
        store,
        bridge,
        limit=search_limit,
        per_asset_limit=per_asset_limit,
        min_score=min_score,
    )
    grouped = hits_by_asset(hits)
    moments: list[Moment] = []
    # Resolve imports the complete indexed source set, even when this query only
    # matches a subset. Query results remain source ranges into those originals.
    assets = {asset.id: asset for asset in store.iter_assets()}

    for asset_id, asset_hits in grouped.items():
        asset = store.get_asset(asset_id)
        if asset is None:
            continue
        detected = region_builder.semantic_regions(asset, asset_hits, query)
        moments.extend(
            apply_handles(
                moment,
                asset.duration,
                pre=pre_handle,
                post=post_handle,
                minimum=minimum_duration,
            )
            for moment in detected
        )

    # SELECTS/stringout convention: preserve source chronology. Score remains on
    # each moment so a later UI can sort/rank without losing editorial order.
    return merge_overlapping_handled(moments), assets
