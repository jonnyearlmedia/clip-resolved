from pathlib import Path

from clip_resolved.models import MediaAsset, VisualSample
from clip_resolved.semantic import sample_times, search
from clip_resolved.store import IndexStore
from clip_resolved.cli import _timecode
from clip_resolved.workflow import default_timeline_name


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
