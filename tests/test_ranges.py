from pathlib import Path

from clip_resolved.models import Moment
from clip_resolved.ranges import apply_handles, handled_bounds


def test_normal_handles():
    assert handled_bounds(37.2, 44.1, 120.0) == (35.2, 47.1)


def test_handles_clamp_to_start_and_meet_minimum():
    start, end = handled_bounds(0.4, 1.2, 20.0, pre=2, post=1, minimum=6)
    assert start == 0.0
    assert end == 6.0


def test_handles_clamp_to_end_and_meet_minimum():
    start, end = handled_bounds(18.8, 19.5, 20.0, pre=1, post=3, minimum=6)
    assert end == 20.0
    assert start == 14.0


def test_source_shorter_than_minimum_returns_whole_source():
    assert handled_bounds(1.0, 1.5, 4.0, minimum=6) == (0.0, 4.0)


def test_apply_handles_preserves_detection():
    moment = Moment(
        asset_id="a",
        source_path=Path("/tmp/a.mp4"),
        detected_start=10.0,
        detected_end=12.0,
        score=0.5,
        query="food",
    )
    handled = apply_handles(moment, 60.0)
    assert handled.detected_start == 10.0
    assert handled.detected_end == 12.0
    assert handled.handled_start == 8.0
    assert handled.handled_end == 15.0
