from __future__ import annotations

import math
from collections import defaultdict
from pathlib import Path
from typing import Callable, Iterable

import numpy as np

from .ffprobe import discover_video_files, probe
from .models import MediaAsset, SearchHit, VisualSample
from .store import IndexStore
from .synthcut import SynthCutClipBridge


def sample_times(duration: float, interval: float = 2.0) -> list[float]:
    """Return source-safe frame sample times without landing exactly on EOF."""
    if duration <= 0:
        return [0.0]
    interval = max(0.25, float(interval))
    end = max(0.0, duration - 0.05)
    if end <= 0.25:
        return [end / 2.0]
    first = min(0.5, end / 2.0)
    count = max(1, int(math.floor((end - first) / interval)) + 1)
    times = [min(end, first + i * interval) for i in range(count)]
    if end - times[-1] > interval * 0.6:
        times.append(end)
    return sorted(set(round(t, 3) for t in times))


def index_media(
    source: str | Path,
    store: IndexStore,
    bridge: SynthCutClipBridge,
    *,
    interval: float = 2.0,
    force: bool = False,
    progress: Callable[[str], None] = print,
) -> list[MediaAsset]:
    if not bridge.ensure_available():
        raise RuntimeError("SynthCut CLIP model is unavailable")

    assets: list[MediaAsset] = []
    for path in discover_video_files(source):
        asset = probe(path)
        store.upsert_asset(asset)
        assets.append(asset)
        if not force and store.visual_index_is_current(asset):
            progress(f"skip indexed: {path.name}")
            continue

        samples: list[VisualSample] = []
        times = sample_times(asset.duration, interval=interval)
        progress(f"indexing {path.name}: {len(times)} frame samples")
        for i, t in enumerate(times, start=1):
            embedding = bridge.embed_image(asset.path, t)
            if embedding is not None:
                samples.append(VisualSample(asset_id=asset.id, time=t, embedding=embedding))
            if i == len(times) or i % 20 == 0:
                progress(f"  {i}/{len(times)}")
        if not samples:
            raise RuntimeError(f"SynthCut produced no semantic samples for {asset.path}")
        store.replace_visual_samples(asset.id, samples)
    return assets


def search(
    query: str,
    store: IndexStore,
    bridge: SynthCutClipBridge,
    *,
    limit: int = 80,
    per_asset_limit: int = 30,
) -> list[SearchHit]:
    query_embedding = bridge.embed_text(query)
    if query_embedding is None:
        raise RuntimeError("SynthCut could not embed the text query")
    q = np.asarray(query_embedding, dtype=np.float32)

    by_asset: dict[str, list[SearchHit]] = defaultdict(list)
    for asset, sample in store.iter_visual_samples():
        e = np.asarray(sample.embedding, dtype=np.float32)
        if e.shape != q.shape:
            continue
        # SynthCut normalizes CLIP embeddings, so dot product is cosine similarity.
        score = float(np.dot(q, e))
        by_asset[asset.id].append(
            SearchHit(asset_id=asset.id, source_path=asset.path, time=sample.time, score=score)
        )

    candidates: list[SearchHit] = []
    for hits in by_asset.values():
        hits.sort(key=lambda h: h.score, reverse=True)
        candidates.extend(hits[: max(1, per_asset_limit)])

    candidates.sort(key=lambda h: h.score, reverse=True)
    return candidates[: max(1, limit)]


def hits_by_asset(hits: Iterable[SearchHit]) -> dict[str, list[SearchHit]]:
    grouped: dict[str, list[SearchHit]] = defaultdict(list)
    for hit in hits:
        grouped[hit.asset_id].append(hit)
    for group in grouped.values():
        group.sort(key=lambda h: h.time)
    return dict(grouped)
