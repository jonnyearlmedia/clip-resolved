from __future__ import annotations

import importlib
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from .models import MediaAsset, Moment
from .ffprobe import discover_audio_files, probe
from .ranges import apply_handles, merge_overlapping_handled
from .store import IndexStore
from .synthcut import SynthCutClipBridge


_NON_SPEECH = re.compile(r"^\s*\[[A-Z_ ]+\]\s*$", re.IGNORECASE)


def _default_diarize(
    video_path: str,
    cues: list[dict],
    *,
    progress: Callable[[str], None],
) -> list[dict]:
    """Run the vendored VideoHighlighter speaker diarization in-place.

    Loaded lazily and the same way videohighlighter.py loads auto_segments:
    the pinned checkout is added to sys.path rather than reproducing its
    Resemblyzer/clustering pipeline here. No HuggingFace token or gated
    model is required.
    """
    upstream_root = Path(__file__).resolve().parents[2] / "external" / "VideoHighlighter"
    if not upstream_root.exists():
        raise RuntimeError(
            f"VideoHighlighter checkout missing at {upstream_root}. "
            "Run scripts/bootstrap_upstreams.sh first."
        )
    root = str(upstream_root)
    if root not in sys.path:
        sys.path.insert(0, root)
    module = importlib.import_module("modules.speaker_utils")
    return module.enrich_segments_with_speakers(
        video_path=video_path,
        whisper_segments=cues,
        log_fn=progress,
    )


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
    diarize: bool = False,
    diarize_fn: Callable[[str, list[dict]], list[dict]] | None = None,
    progress: Callable[[str], None] = print,
) -> int:
    root = Path(source).expanduser().resolve()
    # External recorders are registered project sources but do not have visual
    # frames, so the visual index intentionally skips them. Register their
    # lightweight ffprobe metadata here before walking transcript candidates.
    # This lets narration arrive before or after camera media without pretending
    # an audio file is a visually indexed clip.
    for path in discover_audio_files(root):
        store.upsert_asset(probe(path))
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
        if diarize and payload["cues"]:
            try:
                if diarize_fn is not None:
                    payload["cues"] = diarize_fn(str(asset.path), payload["cues"])
                else:
                    payload["cues"] = _default_diarize(
                        str(asset.path), payload["cues"], progress=progress
                    )
            except Exception as exc:  # noqa: BLE001 - diarization is best-effort
                progress(
                    f"diarization failed for {asset.path.name}: {exc}; "
                    "keeping plain transcript"
                )
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


def transcript_context(store: IndexStore, *, max_characters: int = 40_000) -> dict:
    """Return a bounded, source-identified transcript corpus for project chat.

    This is deliberately not a semantic search. It gives the assistant the
    complete spoken record when the corpus is small enough, so requests such as
    "what story does she tell?" can be answered before the user knows which
    words to search for.
    """
    remaining = max(1, int(max_characters))
    files: list[dict] = []
    cue_count = 0
    truncated = False
    for asset, payload in store.iter_transcripts():
        cues: list[dict] = []
        for segment in payload.get("cues", []):
            text = str(segment.get("text") or "").strip()
            if not text:
                continue
            if len(text) > remaining:
                truncated = True
                break
            cues.append(
                {
                    "start": float(segment.get("start") or 0.0),
                    "end": float(segment.get("end") or 0.0),
                    "text": text,
                }
            )
            cue_count += 1
            remaining -= len(text)
        if cues:
            files.append(
                {
                    "source_path": str(asset.path),
                    "duration": asset.duration,
                    "cues": cues,
                }
            )
        if truncated:
            break
    return {
        "files": files,
        "cue_count": cue_count,
        "transcript_file_count": store.transcript_count(),
        "truncated": truncated,
    }


def exact_range_moments(ranges: list[dict], store: IndexStore, *, query: str) -> tuple[list[Moment], dict[str, MediaAsset]]:
    """Validate assistant-proposed source ranges against the local index."""
    moments: list[Moment] = []
    assets: dict[str, MediaAsset] = {}
    for item in ranges:
        source_path = Path(str(item.get("source_path") or "")).expanduser().resolve()
        asset = store.get_asset_by_path(source_path)
        if asset is None:
            raise ValueError(f"Proposed source is not indexed: {source_path}")
        start = max(0.0, float(item.get("start") or 0.0))
        end = min(asset.duration, float(item.get("end") or 0.0))
        if end <= start:
            raise ValueError(f"Invalid proposed range for {source_path.name}: {start:g}-{end:g}")
        assets[asset.id] = asset
        moments.append(
            Moment(
                asset_id=asset.id,
                source_path=asset.path,
                detected_start=start,
                detected_end=end,
                handled_start=start,
                handled_end=end,
                score=1.0,
                query=query,
                labels={"assistant-proposed", "exact-source-range"},
                provenance=["Clip Resolved transcript intelligence"],
                metadata={"transcript": str(item.get("transcript") or "").strip()},
            )
        )
    if not moments:
        raise ValueError("No exact source ranges were proposed")
    moments.sort(key=lambda moment: (str(moment.source_path), moment.handled_start or 0.0))
    return moments, assets


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


def list_speakers(store: IndexStore) -> list[str]:
    """Return distinct diarized speaker labels present in stored transcripts.

    Empty until transcripts have been built with diarize=True. Cues that
    diarization could not attribute to a speaker carry no usable label and
    are excluded here rather than surfaced as a fake "Unknown" category.
    """
    labels: set[str] = set()
    for _asset, payload in store.iter_transcripts():
        for segment in payload.get("cues", []):
            label = str(segment.get("speaker_label") or "").strip()
            if label and label.lower() != "unknown":
                labels.add(label)
    return sorted(labels)


def speaker_moments(
    speaker_label: str,
    store: IndexStore,
    *,
    pre_handle: float = 1.0,
    post_handle: float = 1.5,
    minimum_duration: float = 4.0,
) -> tuple[list[Moment], dict[str, MediaAsset]]:
    """Turn cues diarization attributed to one speaker into handled moments."""
    assets = {asset.id: asset for asset in store.iter_assets()}
    moments: list[Moment] = []
    for asset, payload in store.iter_transcripts():
        if asset.id not in assets:
            continue
        for segment in payload.get("cues", []):
            label = str(segment.get("speaker_label") or "").strip()
            if label != speaker_label:
                continue
            text = str(segment.get("text") or "").strip()
            start = float(segment.get("start") or 0.0)
            end = max(float(segment.get("end") or 0.0), start + 0.1)
            moment = Moment(
                asset_id=asset.id,
                source_path=asset.path,
                detected_start=start,
                detected_end=end,
                score=1.0,
                query=f"speaker: {speaker_label}",
                labels={"speaker", speaker_label},
                provenance=["Aseiel/VideoHighlighter:modules/speaker_utils.py"],
                metadata={"transcript": text, "speaker_label": speaker_label},
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
