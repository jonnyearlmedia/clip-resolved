from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path
from typing import Callable

from .models import MediaAsset
from .vision_verify import claude_binary, extract_frame
from .workflow import SelectsCategory

_DISCOVER_SCHEMA = json.dumps(
    {
        "type": "object",
        "properties": {
            "categories": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "query": {"type": "string"},
                    },
                    "required": ["name", "query"],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["categories"],
        "additionalProperties": False,
    }
)

_SYSTEM_PROMPT = (
    "These are real frames sampled from a video shoot that needs organizing for editing. "
    "Look at what is actually in them and propose the natural groupings a video editor would "
    "want to pull footage into: recurring locations, activities, recurring subjects, useful "
    "b-roll groupings. Do not propose generic single-object labels for individual images, and "
    "do not propose a category just because a shoot of this general type would typically have "
    "it -- only propose one you can actually see real evidence for across these frames. Do not "
    "invent people's names or claim identity without evidence. Keep the list reasonable, "
    "roughly 5 to 10 categories, not dozens.\n\n"
    "For each category return:\n"
    "- name: a short ALL-CAPS name ending in \"SELECTS\", suitable as a Resolve timeline name "
    "(e.g. \"INSTALLATION WORK SELECTS\")\n"
    "- query: one plain-language visual sentence describing the category, usable as a search "
    "phrase (e.g. \"person installing or arranging an art piece\")"
)


def sample_frame_points(
    assets: dict[str, MediaAsset],
    *,
    sample_size: int = 24,
) -> list[tuple[MediaAsset, float]]:
    """Pick a fair cross-section of (asset, time) points across the whole project.

    Spreads across assets first (sorted by capture time, falling back to path,
    so the sample is not just "the first N clips indexed"), then across each
    sampled asset's duration, rather than clustering everything in a few clips.
    """
    ordered = sorted(
        (a for a in assets.values() if a.duration > 0),
        key=lambda a: (a.capture_time if a.capture_time is not None else float("inf"), str(a.path)),
    )
    if not ordered or sample_size <= 0:
        return []

    per_asset = max(1, min(3, sample_size // max(1, len(ordered))))
    max_assets = max(1, sample_size // per_asset)

    if len(ordered) > max_assets:
        step = len(ordered) / max_assets
        chosen = [ordered[int(i * step)] for i in range(max_assets)]
    else:
        chosen = ordered

    points: list[tuple[MediaAsset, float]] = []
    for asset in chosen:
        if per_asset == 1:
            offsets = [0.5]
        else:
            offsets = [i / (per_asset - 1) for i in range(per_asset)]
        for offset in offsets:
            if len(points) >= sample_size:
                break
            time = min(max(asset.duration * offset, 0.0), max(0.0, asset.duration - 0.05))
            points.append((asset, time))
        if len(points) >= sample_size:
            break
    return points[:sample_size]


def discover_categories(
    assets: dict[str, MediaAsset],
    *,
    sample_size: int = 24,
    model: str = "sonnet",
    effort: str = "low",
    timeout: float = 240.0,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> tuple[list[SelectsCategory], dict]:
    """Have Claude invent editorial categories from real sampled footage frames,
    instead of picking from a human-written fixed profile menu.

    Degrades to `([], report)` with `discovery_available: False` on any
    failure (Claude missing/not signed in/timeout/bad output) or when there
    is nothing to sample -- never raises, so it can never block `smart-selects`.
    """
    points = sample_frame_points(assets, sample_size=sample_size)
    if not points:
        return [], {
            "frames_sampled": 0,
            "assets_sampled": 0,
            "discovery_available": False,
            "reason": "no indexed assets with a known duration to sample",
        }

    binary = claude_binary()
    if binary is None:
        return [], {
            "frames_sampled": 0,
            "assets_sampled": len({a.id for a, _ in points}),
            "discovery_available": False,
            "reason": "Claude Code CLI not found",
        }

    with tempfile.TemporaryDirectory(prefix="clip-resolved-discover-") as tmp:
        frame_paths: list[Path] = []
        for index, (asset, time) in enumerate(points):
            frame_path = Path(tmp) / f"{index}.jpg"
            try:
                extract_frame(asset.path, time, frame_path)
            except RuntimeError:
                continue
            frame_paths.append(frame_path)

        if not frame_paths:
            return [], {
                "frames_sampled": 0,
                "assets_sampled": len({a.id for a, _ in points}),
                "discovery_available": False,
                "reason": "ffmpeg could not extract any sample frame",
            }

        prompt = "\n".join(f"{index}. {path}" for index, path in enumerate(frame_paths))

        try:
            proc = run(
                [
                    binary,
                    "-p",
                    "--allowedTools",
                    "Read",
                    "--permission-mode",
                    "dontAsk",
                    "--permission-prompts",
                    "none",
                    "--no-session-persistence",
                    "--model",
                    model,
                    "--effort",
                    effort,
                    "--output-format",
                    "json",
                    "--json-schema",
                    _DISCOVER_SCHEMA,
                    "--system-prompt",
                    _SYSTEM_PROMPT,
                ],
                input=prompt,
                capture_output=True,
                text=True,
                timeout=timeout,
            )
        except (OSError, subprocess.TimeoutExpired):
            return [], {
                "frames_sampled": len(frame_paths),
                "assets_sampled": len({a.id for a, _ in points}),
                "discovery_available": False,
                "reason": "Claude Code CLI call failed or timed out",
            }

    if proc.returncode != 0:
        return [], {
            "frames_sampled": len(frame_paths),
            "assets_sampled": len({a.id for a, _ in points}),
            "discovery_available": False,
            "reason": (proc.stderr or "").strip()[:400] or "Claude Code CLI returned a non-zero exit",
        }

    try:
        envelope = json.loads(proc.stdout)
        raw_categories = envelope["structured_output"]["categories"]
    except Exception:
        return [], {
            "frames_sampled": len(frame_paths),
            "assets_sampled": len({a.id for a, _ in points}),
            "discovery_available": False,
            "reason": "Claude Code CLI returned unparseable output",
        }

    categories: list[SelectsCategory] = []
    seen_names: set[str] = set()
    for item in raw_categories:
        try:
            name = str(item["name"]).strip()
            query = str(item["query"]).strip()
        except Exception:
            continue
        if not name or not query or name in seen_names:
            continue
        seen_names.add(name)
        categories.append(SelectsCategory(name, query))

    return categories, {
        "frames_sampled": len(frame_paths),
        "assets_sampled": len({a.id for a, _ in points}),
        "discovery_available": True,
    }
