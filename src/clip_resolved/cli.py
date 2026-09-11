from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

from .resolve import ResolveAdapter, ResolveUnavailable
from .semantic import index_media, search
from .store import IndexStore
from .synthcut import SynthCutClipBridge, SynthCutBridgeError
from .videohighlighter import VideoHighlighterAdapter
from .workflow import default_timeline_name, find_moments


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _json_dump(value) -> None:
    print(json.dumps(value, indent=2, ensure_ascii=False))


def _moment_dict(moment) -> dict:
    return {
        "asset_id": moment.asset_id,
        "source_path": str(moment.source_path),
        "query": moment.query,
        "score": moment.score,
        "detected_start": moment.detected_start,
        "detected_end": moment.detected_end,
        "handled_start": moment.handled_start,
        "handled_end": moment.handled_end,
        "labels": sorted(moment.labels),
        "provenance": moment.provenance,
        "metadata": moment.metadata,
    }


def cmd_doctor(args: argparse.Namespace) -> int:
    root = _repo_root()
    checks = {}
    for executable in ("git", "python3", "node", "npm", "ffmpeg", "ffprobe"):
        checks[executable] = shutil.which(executable)
    checks["SynthCut"] = str(root / "external" / "SynthCut") if (root / "external" / "SynthCut").exists() else None
    checks["VideoHighlighter"] = str(root / "external" / "VideoHighlighter") if (root / "external" / "VideoHighlighter").exists() else None
    checks["davinci-resolve-mcp"] = str(root / "external" / "davinci-resolve-mcp") if (root / "external" / "davinci-resolve-mcp").exists() else None

    if args.deep and checks["SynthCut"]:
        try:
            with SynthCutClipBridge(root) as bridge:
                checks["synthcut_clip_model"] = bridge.ensure_available()
        except Exception as exc:
            checks["synthcut_clip_model"] = f"ERROR: {exc}"

    if args.resolve and checks["davinci-resolve-mcp"]:
        try:
            resolve = ResolveAdapter(root).connect()
            checks["resolve"] = f"{resolve.GetProductName()} {resolve.GetVersionString()}"
        except Exception as exc:
            checks["resolve"] = f"ERROR: {exc}"

    _json_dump(checks)
    failed = [name for name, value in checks.items() if value is None or (isinstance(value, str) and value.startswith("ERROR:"))]
    return 1 if failed else 0


def cmd_index(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).expanduser().resolve()
    source = Path(args.source).expanduser().resolve()
    with IndexStore.for_project(project_root) as store, SynthCutClipBridge(_repo_root()) as bridge:
        assets = index_media(
            source,
            store,
            bridge,
            interval=args.interval,
            force=args.force,
            progress=lambda msg: print(msg, file=sys.stderr),
        )
        _json_dump(
            {
                "project_root": str(project_root),
                "assets_seen": len(assets),
                "assets_in_store": store.asset_count(),
                "visual_samples": store.visual_sample_count(),
            }
        )
    return 0


def cmd_search(args: argparse.Namespace) -> int:
    with IndexStore.for_project(args.project_root) as store, SynthCutClipBridge(_repo_root()) as bridge:
        hits = search(
            args.query,
            store,
            bridge,
            limit=args.limit,
            per_asset_limit=args.per_asset_limit,
        )
        _json_dump(
            [
                {
                    "asset_id": hit.asset_id,
                    "source_path": str(hit.source_path),
                    "time": hit.time,
                    "score": hit.score,
                }
                for hit in hits
            ]
        )
    return 0


def _moments_for_args(args: argparse.Namespace):
    store = IndexStore.for_project(args.project_root)
    bridge = SynthCutClipBridge(_repo_root())
    bridge.start()
    builder = VideoHighlighterAdapter(_repo_root())
    try:
        moments, assets = find_moments(
            args.query,
            store,
            bridge,
            builder,
            search_limit=args.limit,
            per_asset_limit=args.per_asset_limit,
            pre_handle=args.pre_handle,
            post_handle=args.post_handle,
            minimum_duration=args.minimum_duration,
        )
        return store, bridge, moments, assets
    except Exception:
        bridge.close()
        store.close()
        raise


def cmd_moments(args: argparse.Namespace) -> int:
    store, bridge, moments, _assets = _moments_for_args(args)
    try:
        _json_dump([_moment_dict(m) for m in moments])
    finally:
        bridge.close()
        store.close()
    return 0


def cmd_selects(args: argparse.Namespace) -> int:
    store, bridge, moments, assets = _moments_for_args(args)
    try:
        if not moments:
            print("No candidate moments found; Resolve was not changed.", file=sys.stderr)
            return 2
        timeline_name = args.timeline_name or default_timeline_name(args.query)
        result = ResolveAdapter(_repo_root()).create_selects_timeline(timeline_name, moments, assets)
        result["query"] = args.query
        result["moments"] = len(moments)
        _json_dump(result)
    finally:
        bridge.close()
        store.close()
    return 0


def _add_query_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project-root", required=True, help="Project root containing .clip-resolved index state")
    parser.add_argument("query", help="Arbitrary semantic footage query")
    parser.add_argument("--limit", type=int, default=80, help="Maximum semantic frame hits considered globally")
    parser.add_argument("--per-asset-limit", type=int, default=30, help="Maximum frame hits retained per source asset")


def _add_moment_args(parser: argparse.ArgumentParser) -> None:
    _add_query_args(parser)
    parser.add_argument("--pre-handle", type=float, default=2.0)
    parser.add_argument("--post-handle", type=float, default=3.0)
    parser.add_argument("--minimum-duration", type=float, default=6.0)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="clip-resolved")
    sub = parser.add_subparsers(dest="command", required=True)

    doctor = sub.add_parser("doctor", help="Check local dependencies and optional live integrations")
    doctor.add_argument("--deep", action="store_true", help="Load/download the SynthCut CLIP model")
    doctor.add_argument("--resolve", action="store_true", help="Attempt a live Resolve connection")
    doctor.set_defaults(func=cmd_doctor)

    index = sub.add_parser("index", help="Build/update the persistent visual index")
    index.add_argument("--project-root", required=True)
    index.add_argument("--source", required=True, help="Folder or source video to index")
    index.add_argument("--interval", type=float, default=2.0, help="Frame sampling interval in seconds")
    index.add_argument("--force", action="store_true", help="Re-index unchanged assets")
    index.set_defaults(func=cmd_index)

    search_parser = sub.add_parser("search", help="Search the existing visual index")
    _add_query_args(search_parser)
    search_parser.set_defaults(func=cmd_search)

    moments = sub.add_parser("moments", help="Turn a semantic query into handled editorial moments")
    _add_moment_args(moments)
    moments.set_defaults(func=cmd_moments)

    selects = sub.add_parser("selects", help="Create a Resolve SELECTS timeline from a semantic query")
    _add_moment_args(selects)
    selects.add_argument("--timeline-name", help="Override the generated '<QUERY> SELECTS' name")
    selects.set_defaults(func=cmd_selects)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except (SynthCutBridgeError, ResolveUnavailable, RuntimeError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
