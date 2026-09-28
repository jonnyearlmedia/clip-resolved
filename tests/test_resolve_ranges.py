from pathlib import Path

from clip_resolved.models import MediaAsset, Moment
from clip_resolved.resolve import ResolveAdapter


def test_60fps_handled_seconds_convert_to_half_open_source_frames():
    asset = MediaAsset(
        id="a",
        path=Path("/tmp/DJI_0001.MP4"),
        duration=120.0,
        fps=60.0,
        width=3840,
        height=2160,
        has_audio=True,
        size=1,
        mtime_ns=1,
    )
    moment = Moment(
        asset_id="a",
        source_path=asset.path,
        detected_start=37.2,
        detected_end=44.1,
        handled_start=35.2,
        handled_end=47.1,
        score=0.8,
        query="food",
    )

    start, end = ResolveAdapter._source_frame_range(moment, asset)

    assert start == 2112
    assert end == 2826
    assert end - start == 714


def test_source_frame_range_honors_exact_complement_metadata():
    asset = MediaAsset(
        id="a",
        path=Path("/tmp/a.mp4"),
        duration=10.0,
        fps=30.0,
        width=1920,
        height=1080,
        has_audio=True,
        size=1,
        mtime_ns=1,
    )
    moment = Moment(
        asset_id="a",
        source_path=asset.path,
        detected_start=1.0,
        detected_end=2.0,
        handled_start=1.0,
        handled_end=2.0,
        score=0.0,
        query="not selected",
        metadata={"source_start_frame": 31, "source_end_frame": 59},
    )

    assert ResolveAdapter._source_frame_range(moment, asset) == (31, 59)
