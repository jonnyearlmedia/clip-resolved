from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .models import MediaAsset, Moment
from .ranges import apply_handles, merge_overlapping_handled
from .store import IndexStore
from .synthcut import SynthCutClipBridge


_NON_SPEECH = re.compile(r"^\s*\[[A-Z_ ]+\]\s*$", re.IGNORECASE)


@dataclass(frozen=True)
class TranscriptHit:
    asset_id: str
    source_path: Path
    start: float
    end: float
    text: str
    score: float


def index_transcripts(
    source: str | Path,
    store: IndexStore,
    bridge: SynthCutClipBridge,
    *,
    language: str = "auto",
    model: str = "base.en",
    force: bool = False,
    progress: Callable[[str], None] = print,
) -> int:
    root = Path(source).expanduser().resolve()
    count = 0
    for asset in store.iter_assets():
        try:
            asset.path.relative_to(root)
        except ValueError:
            if asset.path != root:
                continue
        if not asset.has_audio:
            progress(f"skip no audio: {asset.path.name}")
            continue
        if not force and store.get_transcript(asset.id) is not None:
            progress(f"skip transcribed: {asset.path.name}")
            continue
        progress(f"transcribing {asset.path.name}")
        payload = bridge.transcribe(asset.path, language=language, model=model)
        payload["cues"] = [
            cue for cue in payload.get("cues", [])
            if str(cue.get("text") or "").strip() and not _NON_SPEECH.match(str(cue.get("text") or ""))
        ]
        payload["words"] = [
            word for word in payload.get("words", [])
            if str(word.get("text") or "").strip() and not _NON_SPEECH.match(str(word.get("text") or ""))
        ]
        payload["model"] = model
        payload["language"] = language
        store.put_transcript(asset.id, payload)
        count += 1
    return count


def _tokens(value: str) -> list[str]:
    return re.findall(r"[a-z0-9']+", value.lower())


def search_transcripts(query: str, store: IndexStore, *, limit: int = 50) -> list[TranscriptHit]:
    phrase = " ".join(_tokens(query))
    wanted = set(_tokens(query))
    if not wanted:
        return []
    hits: list[TranscriptHit] = []
    for asset, payload in store.iter_transcripts():
        for segment in payload.get("cues", []):
            text = str(segment.get("text") or "").strip()
            normalized = " ".join(_tokens(text))
            present = set(_tokens(text))
            overlap = len(wanted & present) / len(wanted)
            phrase_bonus = 1.0 if phrase and phrase in normalized else 0.0
            score = overlap + phrase_bonus
            if score <= 0:
                continue
            hits.append(
                TranscriptHit(
                    asset_id=asset.id,
                    source_path=asset.path,
                    start=float(segment.get("start") or 0.0),
                    end=float(segment.get("end") or 0.0),
                    text=text,
                    score=score,
                )
            )
    hits.sort(key=lambda hit: (-hit.score, str(hit.source_path), hit.start))
    return hits[: max(1, limit)]


def transcript_moments(
    query: str,
    store: IndexStore,
    *,
    limit: int = 50,
    pre_handle: float = 1.0,
    post_handle: float = 1.5,
    minimum_duration: float = 4.0,
) -> tuple[list[Moment], dict[str, MediaAsset]]:
    hits = search_transcripts(query, store, limit=limit)
    assets = {asset.id: asset for asset in store.iter_assets()}
    moments = []
    for hit in hits:
        asset = assets.get(hit.asset_id)
        if asset is None:
            continue
        moment = Moment(
            asset_id=asset.id,
            source_path=asset.path,
            detected_start=hit.start,
            detected_end=max(hit.end, hit.start + 0.1),
            score=hit.score,
            query=query,
            labels={"transcript", query},
            provenance=["Relo-video/SynthCut:whisper/transcribe.ts"],
            metadata={"transcript": hit.text},
        )
        moments.append(
            apply_handles(
                moment,
                asset.duration,
                pre=pre_handle,
                post=post_handle,
                minimum=minimum_duration,
            )
        )
    return merge_overlapping_handled(moments), assets
