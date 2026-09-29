from pathlib import Path

from clip_resolved.models import MediaAsset
from clip_resolved.store import IndexStore
from clip_resolved.transcript import exact_range_moments, search_transcripts, transcript_context, transcript_moments


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


def test_transcript_context_preserves_source_identity_and_exact_cue_times(tmp_path: Path):
    source = tmp_path / "DJI_0001.WAV"
    source.write_bytes(b"audio")
    with IndexStore(tmp_path / "index.sqlite3") as store:
        item = _asset(source)
        store.upsert_asset(item)
        store.put_transcript(
            item.id,
            {
                "cues": [
                    {"start": 1.25, "end": 3.5, "text": "This gallery is a gathering place."},
                    {"start": 7.0, "end": 9.0, "text": "Ray makes the space feel alive."},
                ],
                "words": [],
            },
        )

        context = transcript_context(store)

    assert context["transcript_file_count"] == 1
    assert context["cue_count"] == 2
    assert context["truncated"] is False
    assert context["files"][0]["source_path"] == str(source)
    assert context["files"][0]["cues"][0] == {
        "start": 1.25,
        "end": 3.5,
        "text": "This gallery is a gathering place.",
    }


def test_transcript_context_reports_truncation_without_partial_quotes(tmp_path: Path):
    source = tmp_path / "DJI_0001.WAV"
    source.write_bytes(b"audio")
    with IndexStore(tmp_path / "index.sqlite3") as store:
        item = _asset(source)
        store.upsert_asset(item)
        store.put_transcript(
            item.id,
            {"cues": [{"start": 0.0, "end": 1.0, "text": "long narration"}], "words": []},
        )
        context = transcript_context(store, max_characters=4)

    assert context["truncated"] is True
    assert context["cue_count"] == 0
    assert context["files"] == []


def test_exact_range_moments_validate_and_preserve_requested_source_range(tmp_path: Path):
    source = tmp_path / "DJI_0047.WAV"
    source.write_bytes(b"audio")
    with IndexStore(tmp_path / "index.sqlite3") as store:
        item = _asset(source)
        store.upsert_asset(item)
        moments, assets = exact_range_moments(
            [{"source_path": str(source), "start": 2.5, "end": 12.0, "transcript": "Clean take"}],
            store,
            query="MAGGIE NARRATION SELECTS",
        )

    assert list(assets) == [item.id]
    assert moments[0].handled_start == 2.5
    assert moments[0].handled_end == 12.0
    assert moments[0].metadata["transcript"] == "Clean take"
