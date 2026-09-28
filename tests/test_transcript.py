from pathlib import Path

from clip_resolved.models import MediaAsset
from clip_resolved.store import IndexStore
from clip_resolved.transcript import search_transcripts, transcript_moments


def _asset(path: Path, *, size: int = 10, mtime_ns: int = 1) -> MediaAsset:
    return MediaAsset(
        id="spoken-1",
        path=path,
        duration=30.0,
        fps=60.0,
        width=3840,
        height=2160,
        has_audio=True,
        size=size,
        mtime_ns=mtime_ns,
    )


def test_transcript_search_and_handled_moments(tmp_path: Path):
    source = tmp_path / "DJI_0001.MP4"
    source.write_bytes(b"video")
    with IndexStore(tmp_path / "index.sqlite3") as store:
        item = _asset(source)
        store.upsert_asset(item)
        store.put_transcript(
            item.id,
            {
                "cues": [
                    {"start": 4.0, "end": 6.0, "text": "Welcome to Osaka Marketplace"},
                    {"start": 12.0, "end": 14.0, "text": "Try the fresh noodles"},
                ],
                "words": [],
            },
        )

        hits = search_transcripts("Osaka Marketplace", store)
        assert [(hit.start, hit.text) for hit in hits] == [(4.0, "Welcome to Osaka Marketplace")]

        moments, assets = transcript_moments("fresh noodles", store, pre_handle=2, post_handle=3, minimum_duration=6)
        assert list(assets) == [item.id]
        assert len(moments) == 1
        assert moments[0].handled_start == 10.0
        assert moments[0].handled_end == 17.0


def test_changed_source_invalidates_transcript(tmp_path: Path):
    source = tmp_path / "DJI_0001.MP4"
    source.write_bytes(b"video")
    with IndexStore(tmp_path / "index.sqlite3") as store:
        item = _asset(source)
        store.upsert_asset(item)
        store.put_transcript(item.id, {"cues": [], "words": []})
        assert store.transcript_count() == 1

        store.upsert_asset(_asset(source, size=99, mtime_ns=2))
        assert store.transcript_count() == 0
