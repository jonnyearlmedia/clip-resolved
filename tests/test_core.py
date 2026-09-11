from pathlib import Path

from clip_resolved.models import MediaAsset, VisualSample
from clip_resolved.semantic import sample_times
from clip_resolved.store import IndexStore
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
