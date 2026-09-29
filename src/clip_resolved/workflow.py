from __future__ import annotations

import math
import re
import tempfile
from dataclasses import dataclass
from pathlib import Path

from .models import MediaAsset, Moment
from .ranges import apply_handles, merge_overlapping_handled
from .semantic import hits_by_asset, search
from .store import IndexStore
from .synthcut import SynthCutClipBridge
from .videohighlighter import VideoHighlighterAdapter
from .vision_verify import extract_frame, verify_candidates


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


GENERAL_CANDIDATE_SELECTS: tuple[SelectsCategory, ...] = (
    SelectsCategory("VEHICLES SELECTS", "cars vehicles trucks parked or driving"),
    SelectsCategory("ANIMALS PETS SELECTS", "animals pets dogs cats"),
    SelectsCategory("CHILDREN KIDS SELECTS", "children kids playing"),
    SelectsCategory("OUTDOOR NATURE SELECTS", "outdoor nature trees park greenery"),
    SelectsCategory("TEXT SIGNAGE CLOSE UPS SELECTS", "text sign lettering close up"),
    SelectsCategory("HANDS DETAIL WORK SELECTS", "hands close up detail work craft"),
    SelectsCategory("GROUP SHOTS SELECTS", "group of people standing or sitting together"),
    SelectsCategory("SINGLE PERSON PORTRAIT SELECTS", "single person portrait close up"),
    SelectsCategory("MUSIC PERFORMANCE SELECTS", "music performance instrument playing on stage"),
    SelectsCategory("ARTS CRAFTS SELECTS", "handmade art craft product on display"),
)


@dataclass(frozen=True)
class CategoryEvidence:
    """Real-footage support for one candidate category, before any decision."""

    category: SelectsCategory
    distinct_assets: int
    average_top_score: float


def _evaluate_category_evidence(
    category: SelectsCategory,
    store: IndexStore,
    bridge: SynthCutClipBridge,
    *,
    min_score: float,
    search_limit: int,
    per_asset_limit: int,
) -> CategoryEvidence:
    hits = search(
        category.query,
        store,
        bridge,
        limit=search_limit,
        per_asset_limit=per_asset_limit,
        min_score=min_score,
    )
    grouped = hits_by_asset(hits)
    if not grouped:
        return CategoryEvidence(category, distinct_assets=0, average_top_score=0.0)
    top_scores = [max(hit.score for hit in asset_hits) for asset_hits in grouped.values()]
    return CategoryEvidence(
        category,
        distinct_assets=len(grouped),
        average_top_score=sum(top_scores) / len(top_scores),
    )


def propose_categories(
    store: IndexStore,
    bridge: SynthCutClipBridge,
    *,
    base_profile: tuple[SelectsCategory, ...] | None = None,
    candidate_pool: tuple[SelectsCategory, ...] | None = None,
    min_assets: int = 3,
    min_score: float = 0.27,
    search_limit: int = 80,
    per_asset_limit: int = 30,
) -> tuple[list[SelectsCategory], dict[str, list[str]]]:
    """Replace blind fixed-profile output with footage-evidence category proposal.

    `base_profile` (typically from `selects_profile(name)`) supplies the
    priors for this shoot type, but every prior still has to clear a real
    evidence bar against the project's actual index — a restaurant project
    with zero sake-bottle hits will not get a SAKE BOTTLES SELECTS timeline.
    Every fixed profile plus `candidate_pool` (default: GENERAL_CANDIDATE_SELECTS)
    is also evaluated, so categories the seed profile never anticipated can
    still surface when the footage actually supports them.

    Returns the accepted categories, most-evidenced first, plus a diagnostic
    dict naming which seed priors were dropped for lack of evidence and which
    accepted categories were not part of the seed profile at all.
    """
    seeds: dict[str, SelectsCategory] = {}
    for pool in (
        base_profile or (),
        RESTAURANT_SELECTS_PROFILE,
        COMMUNITY_STORY_SELECTS_PROFILE,
        EVENT_SELECTS_PROFILE,
        candidate_pool or GENERAL_CANDIDATE_SELECTS,
    ):
        for category in pool:
            seeds.setdefault(category.query, category)

    prior_queries = {category.query for category in (base_profile or ())}

    evidence = [
        _evaluate_category_evidence(
            category,
            store,
            bridge,
            min_score=min_score,
            search_limit=search_limit,
            per_asset_limit=per_asset_limit,
        )
        for category in seeds.values()
    ]

    accepted = [item for item in evidence if item.distinct_assets >= max(1, min_assets)]
    accepted.sort(key=lambda item: (item.distinct_assets, item.average_top_score), reverse=True)

    dropped = [
        item.category.timeline_name
        for item in evidence
        if item.distinct_assets < max(1, min_assets) and item.category.query in prior_queries
    ]
    discovered = [
        item.category.timeline_name
        for item in accepted
        if item.category.query not in prior_queries
    ]

    return [item.category for item in accepted], {"dropped": dropped, "discovered": discovered}


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


def visual_asset_map(assets) -> dict[str, MediaAsset]:
    """Keep camera/video assets separate from recorder-only audio coverage."""
    return {
        asset.id: asset
        for asset in assets
        if asset.width > 0 and asset.height > 0 and asset.fps > 0
    }


def unselected_moments(
    selected: list[Moment],
    assets: dict[str, MediaAsset],
    *,
    query: str,
    audio_fps: float | None = None,
) -> list[Moment]:
    """Return the exact source-frame complement of handled SELECTS ranges."""
    def frame_rate(asset: MediaAsset) -> float:
        if asset.fps > 0:
            return asset.fps
        if asset.has_audio and asset.width <= 0 and asset.height <= 0:
            return float(audio_fps or 0.0)
        return 0.0

    selected_frames: dict[str, list[tuple[int, int]]] = {}
    for moment in selected:
        asset = assets.get(moment.asset_id)
        if asset is None:
            continue
        fps = frame_rate(asset)
        if fps <= 0:
            continue
        start_seconds = moment.handled_start if moment.handled_start is not None else moment.detected_start
        end_seconds = moment.handled_end if moment.handled_end is not None else moment.detected_end
        start = max(0, int(math.floor(start_seconds * fps)))
        end = max(start + 1, int(math.ceil(end_seconds * fps)))
        total = max(1, int(math.ceil(asset.duration * fps)))
        selected_frames.setdefault(asset.id, []).append((min(start, total), min(end, total)))

    remainder: list[Moment] = []
    for asset in sorted(
        assets.values(),
        key=lambda item: (item.capture_time if item.capture_time is not None else math.inf, str(item.path)),
    ):
        fps = frame_rate(asset)
        if fps <= 0:
            continue
        total = max(1, int(math.ceil(asset.duration * fps)))
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
            start_seconds = start / fps
            end_seconds = end / fps
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
    # A visual SELECTS pair covers the complete indexed camera set, even when
    # this query matches only a subset. Recorder WAVs have their own narration
    # and transcript coverage and must never leak into a B-roll remainder.
    assets = visual_asset_map(store.iter_assets())

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


def vision_verify_moments(
    category_name: str,
    category_query: str,
    moments: list[Moment],
    assets: dict[str, MediaAsset],
    *,
    top_k: int = 10,
) -> tuple[list[Moment], dict]:
    """Let Claude actually look at the strongest CLIP candidates for a category
    and judge real relevance, instead of trusting a raw similarity score.

    CLIP-only similarity search is fast but can't reason -- it was proven on
    real client footage (Andaan Gallery, 2026-09-29) to accept category
    "matches" that a person would immediately reject. This adds Claude as a
    real second-pass judge on the shortlist: the top `top_k` moments by score
    are rendered to real frames and reviewed; only ones Claude confirms are
    kept, so a category is either evidence-backed AND actually verified, or it
    stays empty rather than getting padded with weak CLIP-only guesses.

    Degrades to returning `moments` completely unchanged (with an explanatory
    report) if Claude isn't available, isn't authenticated, or the call fails
    for any reason -- this can never crash smart-selects or block Resolve
    creation on a missing/broken Claude Code install.
    """
    if not moments:
        return moments, {"verified": 0, "kept": 0, "dropped": 0, "verify_available": False}

    shortlist = sorted(moments, key=lambda m: m.score, reverse=True)[:top_k]

    with tempfile.TemporaryDirectory(prefix="clip-resolved-verify-") as tmp:
        frame_paths: list[Path] = []
        frame_indices: list[int] = []
        for position, moment in enumerate(shortlist):
            asset = assets.get(moment.asset_id)
            if asset is None:
                continue
            start = moment.handled_start if moment.handled_start is not None else moment.detected_start
            end = moment.handled_end if moment.handled_end is not None else moment.detected_end
            midpoint = start + max(0.0, (end - start)) / 2.0
            frame_path = Path(tmp) / f"{position}.jpg"
            try:
                extract_frame(asset.path, midpoint, frame_path)
            except RuntimeError:
                continue
            frame_paths.append(frame_path)
            frame_indices.append(position)

        if not frame_paths:
            return moments, {"verified": 0, "kept": len(moments), "dropped": 0, "verify_available": False}

        verdicts = verify_candidates(category_name, category_query, frame_paths)

    if not verdicts:
        return moments, {"verified": 0, "kept": len(moments), "dropped": 0, "verify_available": False}

    shortlist_ids = {id(m) for m in shortlist}
    kept: list[Moment] = []
    dropped = 0
    for local_index, position in enumerate(frame_indices):
        moment = shortlist[position]
        verdict = verdicts.get(local_index)
        if verdict is None:
            # This specific candidate's verdict didn't come back cleanly --
            # keep it rather than silently discard real CLIP evidence.
            kept.append(moment)
            continue
        if verdict.relevant:
            moment.metadata["vision_verify_reason"] = verdict.reason
            kept.append(moment)
        else:
            dropped += 1

    # Anything below the shortlist was never sent to Claude. It must NOT be
    # silently re-added -- that would defeat the entire point of vision-verify
    # (confirmed on real Andaan footage: PRODUCT FOOD SELECTS had Claude
    # reject all 10 of its strongest candidates, yet the category still kept
    # 26 clips total because the unreviewed remainder slipped back in
    # unconditionally). An unreviewed candidate is neither confirmed nor
    # rejected; only Claude-confirmed candidates count as verified evidence.
    # Raise --verify-top-k to review more of the shortlist instead.
    unreviewed = sum(1 for m in moments if id(m) not in shortlist_ids)

    return kept, {
        "verified": len(verdicts),
        "kept": len(kept),
        "dropped": dropped,
        "unreviewed_excluded": unreviewed,
        "verify_available": True,
    }
