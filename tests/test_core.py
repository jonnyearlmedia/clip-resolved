from pathlib import Path

from clip_resolved.models import MediaAsset, Moment, VisualSample
from clip_resolved.semantic import sample_times, search
from clip_resolved.store import IndexStore
from clip_resolved.cli import _timecode
from clip_resolved.workflow import (
    COMMUNITY_STORY_SELECTS_PROFILE,
    EVENT_SELECTS_PROFILE,
    RESTAURANT_SELECTS_PROFILE,
    all_source_moments,
    default_remainder_timeline_name,
    default_timeline_name,
    selects_profile,
    unselected_moments,
)


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


def test_iter_assets_returns_complete_source_set(tmp_path: Path):
    with IndexStore(tmp_path / "index.sqlite3") as store:
        first = asset(tmp_path / "DJI_0001.MP4")
        second = MediaAsset(**{**first.__dict__, "id": "asset-2", "path": tmp_path / "DJI_0002.MP4"})
        store.upsert_asset(second)
        store.upsert_asset(first)

        assert [item.id for item in store.iter_assets()] == ["asset-1", "asset-2"]
