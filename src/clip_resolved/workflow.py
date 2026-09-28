from __future__ import annotations

import math
import re
from dataclasses import dataclass
from pathlib import Path

from .models import MediaAsset, Moment
from .ranges import apply_handles, merge_overlapping_handled
from .semantic import hits_by_asset, search
from .store import IndexStore
from .synthcut import SynthCutClipBridge
from .videohighlighter import VideoHighlighterAdapter


@dataclass(frozen=True)
class SelectsCategory:
    timeline_name: str
    query: str


RESTAURANT_SELECTS_PROFILE: tuple[SelectsCategory, ...] = (
    SelectsCategory("FOOD SHOTS SELECTS", "food dishes plated meals"),
    SelectsCategory("EXTERIOR STOREFRONT SELECTS", "restaurant exterior storefront entrance"),
    SelectsCategory("INTERIOR DINING ROOM SELECTS", "restaurant interior dining room"),
    SelectsCategory("DRINKS SELECTS", "drinks beverages cocktails"),
    SelectsCategory("SIGNAGE LOGO SELECTS", "restaurant sign signage logo"),
    SelectsCategory("JAPANESE FOOD CLOSE UPS SELECTS", "Japanese food close up detail"),
    SelectsCategory("SAKE BOTTLES SELECTS", "sake bottles"),
)

COMMUNITY_STORY_SELECTS_PROFILE: tuple[SelectsCategory, ...] = (
    SelectsCategory("INTERVIEW SETUPS SELECTS", "interview subject talking to camera seated portrait"),
    SelectsCategory("PEOPLE COMMUNITY SELECTS", "people community customers staff candid interaction"),
    SelectsCategory("PROCESS ACTION SELECTS", "person working making preparing serving process action"),
    SelectsCategory("PRODUCT FOOD SELECTS", "food product merchandise close up hero shot"),
    SelectsCategory("EXTERIOR LOCATION SELECTS", "business exterior storefront entrance establishing shot"),
    SelectsCategory("INTERIOR ATMOSPHERE SELECTS", "business interior workspace atmosphere wide shot"),
    SelectsCategory("DETAILS CUTAWAYS SELECTS", "detail close up hands tools texture sign cutaway"),
)

EVENT_SELECTS_PROFILE: tuple[SelectsCategory, ...] = (
    SelectsCategory("CEREMONY KEY MOMENTS SELECTS", "ceremony celebration presentation important moment"),
    SelectsCategory("SPEECHES TOASTS SELECTS", "person giving speech toast holding microphone"),
    SelectsCategory("FAMILY REACTIONS SELECTS", "family friends smiling laughing emotional reaction"),
    SelectsCategory("GROUPS PORTRAITS SELECTS", "group photo family portrait people posing"),
    SelectsCategory("CANDID MOMENTS SELECTS", "candid people talking laughing celebration"),
    SelectsCategory("DETAILS DECOR GIFTS SELECTS", "event decorations table details gifts invitations"),
    SelectsCategory("FOOD CAKE SELECTS", "party food cake dessert close up"),
    SelectsCategory("VENUE ESTABLISHING SELECTS", "event venue exterior interior wide establishing shot"),
)


def selects_profile(name: str) -> tuple[SelectsCategory, ...]:
    """Return a shoot-aware query recipe without limiting later arbitrary search."""
    normalized = re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")
    if normalized in {"restaurant", "restaurant-food", "food"}:
        return RESTAURANT_SELECTS_PROFILE
    if normalized in {"community-story", "community", "interview", "restaurant-story"}:
        return COMMUNITY_STORY_SELECTS_PROFILE
    if normalized in {"event", "family-event", "baby-shower", "celebration"}:
        return EVENT_SELECTS_PROFILE
    raise ValueError(
        f"Unknown SELECTS profile: {name}. "
        "Available profiles: restaurant, community-story, event"
    )


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
    for asset in sorted(
        assets.values(),
        key=lambda item: (item.capture_time if item.capture_time is not None else math.inf, str(item.path)),
    ):
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


def all_source_moments(assets: dict[str, MediaAsset]) -> list[Moment]:
    """Return every indexed original in source order, full length, exactly once."""
    moments: list[Moment] = []
    for asset in sorted(
        assets.values(),
        key=lambda item: (item.capture_time if item.capture_time is not None else math.inf, str(item.path)),
    ):
        if asset.fps <= 0:
            continue
        total_frames = max(1, int(math.ceil(asset.duration * asset.fps)))
        moments.append(
            Moment(
                asset_id=asset.id,
                source_path=asset.path,
                detected_start=0.0,
                detected_end=asset.duration,
                handled_start=0.0,
                handled_end=asset.duration,
                score=1.0,
                query="all raw footage",
                labels={"all raw footage", "stringout"},
                provenance=["complete indexed original"],
                metadata={
                    "source_start_frame": 0,
                    "source_end_frame": total_frames,
                },
            )
        )
    return moments


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
