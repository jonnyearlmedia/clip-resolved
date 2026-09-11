from pathlib import Path

from clip_resolved.models import MediaAsset, Moment
from clip_resolved.resolve import ResolveAdapter


def test_60fps_handled_seconds_convert_to_inclusive_source_frames():
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
    assert end == 2825
    assert end - start + 1 == 714
