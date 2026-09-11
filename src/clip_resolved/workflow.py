from __future__ import annotations

import re
from pathlib import Path

from .models import MediaAsset, Moment
from .ranges import apply_handles
from .semantic import hits_by_asset, search
from .store import IndexStore
from .synthcut import SynthCutClipBridge
from .videohighlighter import VideoHighlighterAdapter


def default_timeline_name(query: str) -> str:
    words = re.sub(r"[^A-Za-z0-9]+", " ", query).strip().upper()
    words = re.sub(r"\s+", " ", words)
    return f"{words or 'QUERY'} SELECTS"


def find_moments(
    query: str,
    store: IndexStore,
    bridge: SynthCutClipBridge,
    region_builder: VideoHighlighterAdapter,
    *,
    search_limit: int = 80,
    per_asset_limit: int = 30,
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
    )
    grouped = hits_by_asset(hits)
    moments: list[Moment] = []
    assets: dict[str, MediaAsset] = {}

    for asset_id, asset_hits in grouped.items():
        asset = store.get_asset(asset_id)
        if asset is None:
            continue
        assets[asset_id] = asset
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
    moments.sort(key=lambda m: (str(m.source_path), m.handled_start or 0.0))
    return moments, assets
