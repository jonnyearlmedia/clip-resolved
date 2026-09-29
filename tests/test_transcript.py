from pathlib import Path

from clip_resolved.models import MediaAsset
from clip_resolved.store import IndexStore
from clip_resolved.transcript import (
    exact_range_moments,
    index_transcripts,
    list_speakers,
    search_transcripts,
    speaker_moments,
    transcript_context,
    transcript_moments,
)


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


class _FakeTranscribeBridge:
    def transcribe(self, path, *, language, model):
        return {
            "cues": [
                {"start": 0.0, "end": 2.0, "text": "Hello there"},
                {"start": 3.0, "end": 5.0, "text": "Nice to meet you"},
            ],
            "words": [],
        }


def _fake_diarize(video_path: str, cues: list[dict]) -> list[dict]:
    labels = ["Person 1", "Person 2"]
    for i, cue in enumerate(cues):
        cue["speaker_label"] = labels[i % len(labels)]
    return cues


def test_index_transcripts_diarize_true_tags_cues_with_speaker_labels(tmp_path: Path):
    source = tmp_path / "DJI_0001.MP4"
    source.write_bytes(b"video")
    with IndexStore(tmp_path / "index.sqlite3") as store:
        item = _asset(source)
        store.upsert_asset(item)

        index_transcripts(
            tmp_path,
            store,
            _FakeTranscribeBridge(),
            diarize=True,
            diarize_fn=_fake_diarize,
        )

        payload = store.get_transcript(item.id)
        assert [cue["speaker_label"] for cue in payload["cues"]] == ["Person 1", "Person 2"]


def test_index_transcripts_diarize_false_never_calls_diarize_fn(tmp_path: Path):
    source = tmp_path / "DJI_0001.MP4"
    source.write_bytes(b"video")
    calls: list[str] = []

    def tracking_diarize(video_path: str, cues: list[dict]) -> list[dict]:
        calls.append(video_path)
        return cues

    with IndexStore(tmp_path / "index.sqlite3") as store:
        item = _asset(source)
        store.upsert_asset(item)

        index_transcripts(
            tmp_path,
            store,
            _FakeTranscribeBridge(),
            diarize=False,
            diarize_fn=tracking_diarize,
        )

        payload = store.get_transcript(item.id)
        assert calls == []
        assert "speaker_label" not in payload["cues"][0]


def test_index_transcripts_diarize_failure_degrades_to_plain_transcript(tmp_path: Path):
    source = tmp_path / "DJI_0001.MP4"
    source.write_bytes(b"video")
    messages: list[str] = []

    def broken_diarize(video_path: str, cues: list[dict]) -> list[dict]:
        raise RuntimeError("no GPU / model unavailable")

    with IndexStore(tmp_path / "index.sqlite3") as store:
        item = _asset(source)
        store.upsert_asset(item)

        count = index_transcripts(
            tmp_path,
            store,
            _FakeTranscribeBridge(),
            diarize=True,
            diarize_fn=broken_diarize,
            progress=messages.append,
        )

        payload = store.get_transcript(item.id)

    assert count == 1
    assert len(payload["cues"]) == 2
    assert "speaker_label" not in payload["cues"][0]
    assert any("diarization failed" in message for message in messages)


def test_list_speakers_and_speaker_moments_group_by_diarized_label(tmp_path: Path):
    source_a = tmp_path / "DJI_0001.MP4"
    source_b = tmp_path / "DJI_0002.MP4"
    source_a.write_bytes(b"video")
    source_b.write_bytes(b"video")
    with IndexStore(tmp_path / "index.sqlite3") as store:
        asset_a = MediaAsset(
            id="a", path=source_a, duration=30.0, fps=60.0, width=3840, height=2160,
            has_audio=True, size=10, mtime_ns=1,
        )
        asset_b = MediaAsset(
            id="b", path=source_b, duration=30.0, fps=60.0, width=3840, height=2160,
            has_audio=True, size=10, mtime_ns=1,
        )
        store.upsert_asset(asset_a)
        store.upsert_asset(asset_b)
        store.put_transcript(
            asset_a.id,
            {
                "cues": [
                    {"start": 1.0, "end": 3.0, "text": "I run the kitchen", "speaker_label": "Person 1"},
                    {"start": 5.0, "end": 7.0, "text": "and I do the front", "speaker_label": "Person 2"},
                    {"start": 9.0, "end": 10.0, "text": "unclear", "speaker_label": "Unknown"},
                ],
                "words": [],
            },
        )
        store.put_transcript(
            asset_b.id,
            {
                "cues": [
                    {"start": 2.0, "end": 4.0, "text": "more from person one", "speaker_label": "Person 1"},
                ],
                "words": [],
            },
        )

        speakers = list_speakers(store)
        assert speakers == ["Person 1", "Person 2"]

        moments, assets = speaker_moments("Person 1", store, pre_handle=0, post_handle=0, minimum_duration=0)

    assert list(assets) == [asset_a.id, asset_b.id]
    assert len(moments) == 2
    assert {moment.source_path for moment in moments} == {source_a, source_b}
    assert all(moment.metadata["speaker_label"] == "Person 1" for moment in moments)
