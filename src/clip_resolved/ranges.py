from __future__ import annotations

from dataclasses import replace

from .models import Moment


def handled_bounds(
    start: float,
    end: float,
    source_duration: float,
    *,
    pre: float = 2.0,
    post: float = 3.0,
    minimum: float = 6.0,
) -> tuple[float, float]:
    """Expand a detected moment into a comfortable source range.

    Detection boundaries and editorial handles are intentionally separate.
    The result is always clamped to the source media and expanded toward the
    requested minimum duration when the source contains enough material.
    """
    duration = max(0.0, float(source_duration))
    if duration == 0:
        return 0.0, 0.0

    detected_start = min(max(0.0, float(start)), duration)
    detected_end = min(max(detected_start, float(end)), duration)
    out_start = max(0.0, detected_start - max(0.0, float(pre)))
    out_end = min(duration, detected_end + max(0.0, float(post)))

    target = min(duration, max(0.0, float(minimum)))
    deficit = target - (out_end - out_start)
    if deficit > 0:
        left_room = out_start
        right_room = duration - out_end
        left_add = min(left_room, deficit / 2.0)
        out_start -= left_add
        deficit -= left_add
        right_add = min(right_room, deficit)
        out_end += right_add
        deficit -= right_add
        if deficit > 0:
            left_add = min(out_start, deficit)
            out_start -= left_add

    return round(out_start, 6), round(out_end, 6)


def apply_handles(
    moment: Moment,
    source_duration: float,
    *,
    pre: float = 2.0,
    post: float = 3.0,
    minimum: float = 6.0,
) -> Moment:
    start, end = handled_bounds(
        moment.detected_start,
        moment.detected_end,
        source_duration,
        pre=pre,
        post=post,
        minimum=minimum,
    )
    return replace(moment, handled_start=start, handled_end=end)
