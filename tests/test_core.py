from pathlib import Path
from types import SimpleNamespace

from clip_resolved.models import MediaAsset, Moment, VisualSample
from clip_resolved.ffprobe import probe
from clip_resolved.semantic import sample_times, search
from clip_resolved.store import IndexStore
from clip_resolved.transcript import index_transcripts
from clip_resolved.cli import _timecode
from clip_resolved.workflow import (
    COMMUNITY_STORY_SELECTS_PROFILE,
    EVENT_SELECTS_PROFILE,
    RESTAURANT_SELECTS_PROFILE,
    SelectsCategory,
    all_source_moments,
    default_remainder_timeline_name,
    default_timeline_name,
    propose_categories,
    selects_profile,
    unselected_moments,
    visual_asset_map,
)


def test_selects_pair_reopens_requested_timeline(monkeypatch, tmp_path):
    from clip_resolved import cli

    class FakeAdapter:
        def __init__(self):
            self.created = []
            self.activated = []

        def create_selects_timeline(self, name, moments, assets, project_root=None):
            self.created.append(name)
            return {
                "project": "Downtown Shots",
                "timeline": name,
                "ranges_requested": len(moments),
                "ranges_appended": len(moments),
                "snapshot": None,
                "snapshot_exported": False,
            }

        def activate_timeline(self, name):
            self.activated.append(name)
            return {"project": "Downtown Shots", "timeline": name, "opened": True}

    adapter = FakeAdapter()
    monkeypatch.setattr(cli, "ResolveAdapter", lambda _root: adapter)
    monkeypatch.setattr(cli, "unselected_moments", lambda *args, **kwargs: ["remainder"])

    result = cli._create_selects_with_remainder(
        timeline_name="DOWNTOWN STREET SELECTS",
        moments=["selected"],
        assets={},
        project_root=tmp_path,
        query="downtown street",
        create_remainder=True,
        remainder_name=None,
    )

    assert result["remainder_timeline"] == "DOWNTOWN STREET NOT SELECTED"
    assert adapter.activated == ["DOWNTOWN STREET SELECTS"]


def asset(path: Path, *, size: int = 10, mtime_ns: int = 100) -> MediaAsset:
    return MediaAsset(
        id="asset-1",
        path=path,
        duration=20.0,
        fps=60.0,
        width=3840,
        height=2160,
        has_audio=True,
        size=size,
        mtime_ns=mtime_ns,
    )


def test_audio_transcription_registers_recorder_asset_without_inflating_video_count(monkeypatch, tmp_path):
    wav = tmp_path / "MAGGIE.WAV"
    wav.write_bytes(b"audio")
    audio_asset = MediaAsset(
        id="audio-1",
        path=wav,
        duration=12.0,
        fps=0.0,
        width=0,
        height=0,
        has_audio=True,
        size=5,
        mtime_ns=100,
    )

    class FakeBridge:
        def transcribe(self, path, *, language, model):
            assert path == wav
            return {"cues": [{"start": 0, "end": 2, "text": "Welcome to Andaan."}], "words": []}

    monkeypatch.setattr("clip_resolved.transcript.discover_audio_files", lambda _root: [wav])
    monkeypatch.setattr("clip_resolved.transcript.probe", lambda _path: audio_asset)

    with IndexStore(tmp_path / "index.sqlite3") as store:
        assert index_transcripts(tmp_path, store, FakeBridge()) == 1
        assert store.asset_count() == 1
        assert store.video_asset_count() == 0
        assert store.transcript_count() == 1


def test_probe_accepts_audio_only_media(monkeypatch, tmp_path):
    wav = tmp_path / "MAGGIE.WAV"
    wav.write_bytes(b"audio")
    payload = {
        "streams": [{"codec_type": "audio", "duration": "12.5"}],
        "format": {"duration": "12.5", "tags": {}},
    }
    monkeypatch.setattr(
        "clip_resolved.ffprobe.subprocess.run",
        lambda *args, **kwargs: SimpleNamespace(stdout=__import__("json").dumps(payload)),
    )

    result = probe(wav)

    assert result.duration == 12.5
    assert result.has_audio is True
    assert result.fps == 0
    assert result.width == 0
    assert result.height == 0


def test_sample_times_avoid_eof():
    times = sample_times(10.0, interval=2.0)
    assert times[0] >= 0
    assert times[-1] < 10.0
    assert times == sorted(times)


def test_timeline_name_from_arbitrary_query():
    assert default_timeline_name("all the luxury cars") == "ALL THE LUXURY CARS SELECTS"
    assert default_timeline_name("chef / food close-ups!") == "CHEF FOOD CLOSE UPS SELECTS"
    assert default_remainder_timeline_name("FOOD SHOTS SELECTS") == "FOOD SHOTS NOT SELECTED"


def test_restaurant_profile_restores_original_category_package():
    assert selects_profile("restaurant") == RESTAURANT_SELECTS_PROFILE


def test_shoot_profiles_are_distinct_and_ordered():
    assert selects_profile("community story") == COMMUNITY_STORY_SELECTS_PROFILE
    assert selects_profile("baby shower") == EVENT_SELECTS_PROFILE
    assert COMMUNITY_STORY_SELECTS_PROFILE[0].timeline_name == "INTERVIEW SETUPS SELECTS"
    assert EVENT_SELECTS_PROFILE[0].timeline_name == "CEREMONY KEY MOMENTS SELECTS"
    assert [category.timeline_name for category in RESTAURANT_SELECTS_PROFILE] == [
        "FOOD SHOTS SELECTS",
        "EXTERIOR STOREFRONT SELECTS",
        "INTERIOR DINING ROOM SELECTS",
        "DRINKS SELECTS",
        "SIGNAGE LOGO SELECTS",
        "JAPANESE FOOD CLOSE UPS SELECTS",
        "SAKE BOTTLES SELECTS",
    ]


def test_global_remainder_uses_union_of_all_category_ranges(tmp_path: Path):
    item = asset(tmp_path / "DJI_0001.MP4")
    category_ranges = [
        Moment(
            asset_id=item.id,
            source_path=item.path,
            detected_start=2,
            detected_end=6,
            handled_start=2,
            handled_end=6,
            score=0.5,
            query="food",
        ),
        Moment(
            asset_id=item.id,
            source_path=item.path,
            detected_start=4,
            detected_end=10,
            handled_start=4,
            handled_end=10,
            score=0.4,
            query="drinks",
        ),
    ]

    remainder = unselected_moments(category_ranges, {item.id: item}, query="restaurant package")
    assert [
        (moment.metadata["source_start_frame"], moment.metadata["source_end_frame"])
        for moment in remainder
    ] == [(0, 120), (600, 1200)]


def test_all_source_stringout_contains_each_original_once_in_path_order(tmp_path: Path):
    first = asset(tmp_path / "DJI_0002.MP4")
    second = MediaAsset(
        **{**first.__dict__, "id": "asset-2", "path": tmp_path / "DJI_0001.MP4", "duration": 5.0}
    )

    moments = all_source_moments({first.id: first, second.id: second})

    assert [moment.source_path.name for moment in moments] == ["DJI_0001.MP4", "DJI_0002.MP4"]
    assert [moment.metadata["source_start_frame"] for moment in moments] == [0, 0]
    assert [moment.metadata["source_end_frame"] for moment in moments] == [300, 1200]


def test_visual_asset_set_excludes_recorder_audio_from_broll_remainder(tmp_path: Path):
    video = asset(tmp_path / "DJI_0001.MP4")
    narration = MediaAsset(
        id="audio-1",
        path=tmp_path / "DJI_47.WAV",
        duration=210.0,
        fps=0.0,
        width=0,
        height=0,
        has_audio=True,
        size=10,
        mtime_ns=100,
    )

    result = visual_asset_map([video, narration])

    assert set(result) == {video.id}
    assert all(item.width > 0 and item.height > 0 for item in result.values())


def test_event_stringout_uses_capture_time_across_camera_names(tmp_path: Path):
    osmo = asset(tmp_path / "DJI_9999.MP4")
    osmo = MediaAsset(**{**osmo.__dict__, "capture_time": 200.0})
    phone = MediaAsset(
        **{
            **osmo.__dict__,
            "id": "asset-phone",
            "path": tmp_path / "IMG_0001.MOV",
            "capture_time": 100.0,
        }
    )

    moments = all_source_moments({osmo.id: osmo, phone.id: phone})

    assert [moment.source_path.name for moment in moments] == ["IMG_0001.MOV", "DJI_9999.MP4"]


def test_unselected_moments_are_exact_source_frame_complement(tmp_path: Path):
    first = asset(tmp_path / "DJI_0001.MP4")
    second = MediaAsset(
        **{
            **first.__dict__,
            "id": "asset-2",
            "path": tmp_path / "DJI_0002.MP4",
            "duration": 5.0,
        }
    )
    selected = [
        Moment(
            asset_id=first.id,
            source_path=first.path,
            detected_start=2.1,
            detected_end=4.2,
            handled_start=2.1,
            handled_end=4.2,
            score=0.5,
            query="food",
        )
    ]

    remainder = unselected_moments(
        selected,
        {first.id: first, second.id: second},
        query="food",
    )
    frame_ranges = [
        (
            moment.asset_id,
            moment.metadata["source_start_frame"],
            moment.metadata["source_end_frame"],
        )
        for moment in remainder
    ]

    assert frame_ranges == [
        ("asset-1", 0, 126),
        ("asset-1", 252, 1200),
        ("asset-2", 0, 300),
    ]
    selected_frames = 252 - 126
    remainder_frames = sum(end - start for _, start, end in frame_ranges)
    assert selected_frames + remainder_frames == 1200 + 300


def test_timecode_is_editor_readable():
    assert _timecode(0) == "00:00:00.00"
    assert _timecode(65.25) == "00:01:05.25"


def test_changed_source_invalidates_visual_index(tmp_path: Path):
    db = tmp_path / "index.sqlite3"
    source = tmp_path / "DJI_0001.MP4"
    source.write_bytes(b"x")

    with IndexStore(db) as store:
        first = asset(source)
        store.upsert_asset(first)
        store.replace_visual_samples(
            first.id,
            [VisualSample(asset_id=first.id, time=1.0, embedding=(0.1, 0.2))],
        )
        assert store.visual_index_is_current(first)

        changed = asset(source, size=11, mtime_ns=200)
        store.upsert_asset(changed)
        assert not store.visual_index_is_current(changed)


class FakeTextBridge:
    def embed_text(self, query: str):
        return (1.0, 0.0)


def test_search_can_filter_weak_hits_without_discarding_raw_index(tmp_path: Path):
    source = tmp_path / "DJI_0001.MP4"
    source.write_bytes(b"x")
    with IndexStore(tmp_path / "index.sqlite3") as store:
        item = asset(source)
        store.upsert_asset(item)
        store.replace_visual_samples(
            item.id,
            [
                VisualSample(asset_id=item.id, time=1.0, embedding=(0.30, 0.95)),
                VisualSample(asset_id=item.id, time=3.0, embedding=(0.18, 0.98)),
            ],
        )

        raw = search("anything", store, FakeTextBridge())
        filtered = search("anything", store, FakeTextBridge(), min_score=0.22)

        assert [hit.time for hit in raw] == [1.0, 3.0]
        assert [hit.time for hit in filtered] == [1.0]


class FakeQueryAwareBridge:
    """Unlike FakeTextBridge, gives different queries different embeddings so
    evidence-gating logic can be proven to actually discriminate categories."""

    def __init__(self, mapping: dict[str, tuple[float, float]], default: tuple[float, float] = (0.0, 0.0)):
        self.mapping = mapping
        self.default = default

    def embed_text(self, query: str):
        return self.mapping.get(query, self.default)


def test_propose_categories_gates_seed_profile_on_real_evidence(tmp_path: Path):
    with IndexStore(tmp_path / "index.sqlite3") as store:
        first = asset(tmp_path / "DJI_0001.MP4")
        second = MediaAsset(**{**first.__dict__, "id": "asset-2", "path": tmp_path / "DJI_0002.MP4"})
        store.upsert_asset(first)
        store.upsert_asset(second)
        # Both clips contain frames that visually match "market stalls" but
        # nothing anywhere in this project matches "sake bottles".
        store.replace_visual_samples(
            first.id, [VisualSample(asset_id=first.id, time=1.0, embedding=(1.0, 0.0))]
        )
        store.replace_visual_samples(
            second.id, [VisualSample(asset_id=second.id, time=1.0, embedding=(1.0, 0.0))]
        )

        base_profile = (
            SelectsCategory("SAKE BOTTLES SELECTS", "sake bottles"),
            SelectsCategory("MARKET STALLS SELECTS", "market stalls"),
        )
        bridge = FakeQueryAwareBridge(
            {
                "sake bottles": (0.0, 1.0),
                "market stalls": (1.0, 0.0),
            }
        )

        accepted, report = propose_categories(
            store,
            bridge,
            base_profile=base_profile,
            candidate_pool=(),
            min_assets=2,
            min_score=0.5,
        )

    accepted_names = {category.timeline_name for category in accepted}
    assert "MARKET STALLS SELECTS" in accepted_names
    assert "SAKE BOTTLES SELECTS" not in accepted_names
    assert report["dropped"] == ["SAKE BOTTLES SELECTS"]


def test_propose_categories_can_discover_categories_outside_the_seed_profile(tmp_path: Path):
    with IndexStore(tmp_path / "index.sqlite3") as store:
        first = asset(tmp_path / "DJI_0001.MP4")
        second = MediaAsset(**{**first.__dict__, "id": "asset-2", "path": tmp_path / "DJI_0002.MP4"})
        store.upsert_asset(first)
        store.upsert_asset(second)
        store.replace_visual_samples(
            first.id, [VisualSample(asset_id=first.id, time=1.0, embedding=(0.0, 1.0))]
        )
        store.replace_visual_samples(
            second.id, [VisualSample(asset_id=second.id, time=1.0, embedding=(0.0, 1.0))]
        )

        # Empty seed profile: nothing about "restaurant" is relevant here, but
        # a general-vocabulary candidate is strongly supported by both clips.
        bridge = FakeQueryAwareBridge(
            {"cars vehicles trucks parked or driving": (0.0, 1.0)}
        )

        accepted, report = propose_categories(
            store,
            bridge,
            base_profile=(),
            min_assets=2,
            min_score=0.5,
        )

    assert "VEHICLES SELECTS" in report["discovered"]
    assert any(category.timeline_name == "VEHICLES SELECTS" for category in accepted)


def test_iter_assets_returns_complete_source_set(tmp_path: Path):
    with IndexStore(tmp_path / "index.sqlite3") as store:
        first = asset(tmp_path / "DJI_0001.MP4")
        second = MediaAsset(**{**first.__dict__, "id": "asset-2", "path": tmp_path / "DJI_0002.MP4"})
        store.upsert_asset(second)
        store.upsert_asset(first)

        assert [item.id for item in store.iter_assets()] == ["asset-1", "asset-2"]


def test_transfer_asset_moves_visual_index_and_transcript_without_reembedding(tmp_path: Path):
    source_path = tmp_path / "source" / "DJI_0001.MP4"
    destination_path = tmp_path / "destination" / "DJI_0001.MP4"
    source_path.parent.mkdir()
    destination_path.parent.mkdir()
    source_path.write_bytes(b"camera-media")
    source_path.replace(destination_path)

    original = asset(source_path, size=len(b"camera-media"), mtime_ns=destination_path.stat().st_mtime_ns)
    source_db = tmp_path / "source.sqlite3"
    destination_db = tmp_path / "destination.sqlite3"
    with IndexStore(source_db) as source_store, IndexStore(destination_db) as destination_store:
        source_store.upsert_asset(original)
        source_store.replace_visual_samples(
            original.id,
            [VisualSample(asset_id=original.id, time=1.5, embedding=(0.1, 0.2))],
        )
        source_store.put_transcript(original.id, {"segments": [{"text": "hello"}]})

        moved = source_store.transfer_asset_to(
            destination_store,
            source_path,
            destination_path,
        )

        assert moved is not None
        assert moved.path == destination_path.resolve()
        assert source_store.asset_count() == 0
        assert destination_store.asset_count() == 1
        assert destination_store.visual_sample_count() == 1
        assert destination_store.get_transcript(moved.id)["segments"][0]["text"] == "hello"
