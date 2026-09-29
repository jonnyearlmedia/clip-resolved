from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

_CLAUDE_BINARY_CANDIDATES = ("/opt/homebrew/bin/claude", "/usr/local/bin/claude")

_VERIFY_SCHEMA = json.dumps(
    {
        "type": "object",
        "properties": {
            "verdicts": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "index": {"type": "integer"},
                        "relevant": {"type": "boolean"},
                        "reason": {"type": "string"},
                    },
                    "required": ["index", "relevant", "reason"],
                    "additionalProperties": False,
                },
            }
        },
        "required": ["verdicts"],
        "additionalProperties": False,
    }
)

_SYSTEM_PROMPT = (
    "You are a precise footage-review assistant judging candidate video frames for a "
    "specific editorial category. For each numbered image, look at it and decide whether "
    "it genuinely shows the described category -- real visual judgment, not a guess. If a "
    "frame is ambiguous, borderline, or you are not confident, mark it not relevant and say "
    "why in one short sentence. Never claim to see something the image does not show."
)


@dataclass(frozen=True)
class VerifyResult:
    relevant: bool
    reason: str


def claude_binary() -> str | None:
    """Locate the local Claude Code CLI, same install the app's chat service uses."""
    for candidate in _CLAUDE_BINARY_CANDIDATES:
        if Path(candidate).exists():
            return candidate
    return None


def extract_frame(video_path: Path, time: float, out_path: Path) -> None:
    """Extract one real JPEG frame at `time` seconds into `out_path`."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-y",
            "-ss",
            f"{max(0.0, time):.3f}",
            "-i",
            str(video_path),
            "-vframes",
            "1",
            "-q:v",
            "3",
            str(out_path),
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0 or not out_path.exists():
        raise RuntimeError(
            proc.stderr.strip() or f"ffmpeg could not extract a frame from {video_path} at {time:.2f}s"
        )


def verify_candidates(
    category_name: str,
    category_query: str,
    frame_paths: list[Path],
    *,
    model: str = "sonnet",
    effort: str = "low",
    timeout: float = 180.0,
    run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
) -> dict[int, VerifyResult]:
    """Ask Claude to actually look at real extracted frames and judge category fit.

    One batched call covers every frame in `frame_paths` (indices match the
    list order). Returns a dict keyed by index; a MISSING index (including
    every index, on any failure) must be treated by the caller as
    "unverified" and handled by falling back to the existing CLIP-only
    behavior -- this function degrades to an empty dict rather than raising,
    so it can never crash `smart-selects` or block Resolve creation because
    Claude isn't installed, isn't logged in, times out, or returns something
    unparseable.
    """
    if not frame_paths:
        return {}
    binary = claude_binary()
    if binary is None:
        return {}

    prompt = "\n".join(f"{index}. {path}" for index, path in enumerate(frame_paths))
    system_prompt = (
        f"{_SYSTEM_PROMPT}\n\nCategory: {category_name}\nWhat this category means: {category_query}"
    )

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
                _VERIFY_SCHEMA,
                "--system-prompt",
                system_prompt,
            ],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}

    if proc.returncode != 0:
        return {}

    try:
        envelope = json.loads(proc.stdout)
        verdicts = envelope["structured_output"]["verdicts"]
    except Exception:
        return {}

    results: dict[int, VerifyResult] = {}
    for item in verdicts:
        try:
            index = int(item["index"])
            results[index] = VerifyResult(relevant=bool(item["relevant"]), reason=str(item.get("reason", "")))
        except Exception:
            continue
    return results
