from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

from .resolve import ResolveAdapter, ResolveUnavailable
from .ingest import scan_source
from .semantic import index_media, search
from .store import IndexStore
from .synthcut import SynthCutClipBridge, SynthCutBridgeError
from .transcript import index_transcripts, search_transcripts, transcript_moments
from .videohighlighter import VideoHighlighterAdapter
from .workflow import (
    default_remainder_timeline_name,
    default_timeline_name,
    find_moments,
    unselected_moments,
)


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _json_dump(value) -> None:
    print(json.dumps(value, indent=2, ensure_ascii=False))


def _moment_dict(moment) -> dict:
    payload = {
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
    if isinstance(moment.metadata.get("transcript"), str):
        payload["transcript"] = moment.metadata["transcript"]
    return payload


def _timecode(seconds: float) -> str:
    value = max(0.0, float(seconds))
    hours = int(value // 3600)
    minutes = int((value % 3600) // 60)
    secs = value % 60
    return f"{hours:02d}:{minutes:02d}:{secs:05.2f}"


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
            adapter = ResolveAdapter(root)
            resolve = adapter.connect()
            checks["resolve"] = f"{resolve.GetProductName()} {resolve.GetVersionString()}"
            project_manager = resolve.GetProjectManager()
            project = project_manager.GetCurrentProject() if project_manager else None
            if project is None:
                checks["resolve_project_frame_rates"] = "ERROR: No current Resolve project is open"
            else:
                adapter.require_saved_current_project(project_manager, project)
                timeline_rate, playback_rate = adapter.require_matching_project_frame_rates(project)
                checks["resolve_project_frame_rates"] = (
                    f"timeline={timeline_rate:g} playback={playback_rate:g} (matched)"
                )
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


def cmd_scan(args: argparse.Namespace) -> int:
    _json_dump(scan_source(args.source, _repo_root(), gap_hours=args.gap_hours))
    return 0


def cmd_project_status(args: argparse.Namespace) -> int:
    root = Path(args.project_root).expanduser().resolve()
    with IndexStore.for_project(root) as store:
        _json_dump(
            {
                "project_root": str(root),
                "exists": root.exists(),
                "assets": store.asset_count(),
                "visual_samples": store.visual_sample_count(),
                "transcripts": store.transcript_count(),
                "index_path": str(store.path),
            }
        )
    return 0


def cmd_resolve_scaffold(args: argparse.Namespace) -> int:
    result = ResolveAdapter(_repo_root()).scaffold_project(
        project_name=args.project_name,
        project_root=Path(args.project_root),
        source=Path(args.source),
        timeline_fps=args.timeline_fps,
    )
    _json_dump(result)
    return 0


def cmd_search(args: argparse.Namespace) -> int:
    with IndexStore.for_project(args.project_root) as store, SynthCutClipBridge(_repo_root()) as bridge:
        hits = search(
            args.query,
            store,
            bridge,
            limit=args.limit,
            per_asset_limit=args.per_asset_limit,
            min_score=args.min_score,
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


def cmd_transcribe(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).expanduser().resolve()
    source = Path(args.source).expanduser().resolve()
    with IndexStore.for_project(project_root) as store, SynthCutClipBridge(_repo_root()) as bridge:
        if store.asset_count() == 0:
            raise RuntimeError("No indexed footage. Run clip-resolved index before transcription.")
        updated = index_transcripts(
            source,
            store,
            bridge,
            language=args.language,
            model=args.model,
            force=args.force,
            progress=lambda msg: print(msg, file=sys.stderr),
        )
        _json_dump(
            {
                "project_root": str(project_root),
                "transcripts_updated": updated,
                "transcripts_in_store": store.transcript_count(),
            }
        )
    return 0


def cmd_transcript_search(args: argparse.Namespace) -> int:
    with IndexStore.for_project(args.project_root) as store:
        hits = search_transcripts(args.query, store, limit=args.limit)
        _json_dump(
            [
                {
                    "asset_id": hit.asset_id,
                    "source_path": str(hit.source_path),
                    "start": hit.start,
                    "end": hit.end,
                    "text": hit.text,
                    "score": hit.score,
                }
                for hit in hits
            ]
        )
    return 0


def cmd_transcript_selects(args: argparse.Namespace) -> int:
    with IndexStore.for_project(args.project_root) as store:
        moments, assets = transcript_moments(
            args.query,
            store,
            limit=args.limit,
            pre_handle=args.pre_handle,
            post_handle=args.post_handle,
            minimum_duration=args.minimum_duration,
        )
        if not moments:
            print("No matching transcript moments found; Resolve was not changed.", file=sys.stderr)
            return 2
        timeline_name = args.timeline_name or default_timeline_name(args.query)
        result = _create_selects_with_remainder(
            timeline_name=timeline_name,
            moments=moments,
            assets=assets,
            project_root=Path(args.project_root),
            query=args.query,
            create_remainder=not args.no_remainder,
            remainder_name=args.remainder_timeline_name,
        )
        result["query"] = args.query
        result["moments"] = len(moments)
        _json_dump(result)
    return 0


def cmd_transcript_moments(args: argparse.Namespace) -> int:
    with IndexStore.for_project(args.project_root) as store:
        moments, _assets = transcript_moments(
            args.query,
            store,
            limit=args.limit,
            pre_handle=args.pre_handle,
            post_handle=args.post_handle,
            minimum_duration=args.minimum_duration,
        )
        _json_dump([_moment_dict(moment) for moment in moments])
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
            min_score=args.min_score,
            pre_handle=args.pre_handle,
            post_handle=args.post_handle,
            minimum_duration=args.minimum_duration,
        )
        return store, bridge, moments, assets
    except Exception:
        bridge.close()
        store.close()
        raise


def _create_selects_with_remainder(
    *,
    timeline_name: str,
    moments,
    assets,
    project_root: Path,
    query: str,
    create_remainder: bool,
    remainder_name: str | None,
) -> dict:
    adapter = ResolveAdapter(_repo_root())
    result = adapter.create_selects_timeline(
        timeline_name, moments, assets, project_root=project_root
    )
    result.update(
        {
            "remainder_timeline": None,
            "remainder_ranges_requested": 0,
            "remainder_ranges_appended": 0,
            "coverage_complete": False,
        }
    )
    if not create_remainder:
        return result

    remainder = unselected_moments(moments, assets, query=query)
    if remainder:
        requested_name = remainder_name or default_remainder_timeline_name(timeline_name)
        remainder_result = adapter.create_selects_timeline(
            requested_name, remainder, assets, project_root=project_root
        )
        result.update(
            {
                "remainder_timeline": remainder_result["timeline"],
                "remainder_ranges_requested": remainder_result["ranges_requested"],
                "remainder_ranges_appended": remainder_result["ranges_appended"],
                "coverage_complete": (
                    remainder_result["ranges_requested"]
                    == remainder_result["ranges_appended"]
                ),
                "snapshot": remainder_result.get("snapshot") or result.get("snapshot"),
                "snapshot_exported": bool(remainder_result.get("snapshot_exported")),
            }
        )
    else:
        result["coverage_complete"] = True
    return result


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
        result = _create_selects_with_remainder(
            timeline_name=timeline_name,
            moments=moments,
            assets=assets,
            project_root=Path(args.project_root),
            query=args.query,
            create_remainder=not args.no_remainder,
            remainder_name=args.remainder_timeline_name,
        )
        result["query"] = args.query
        result["moments"] = len(moments)
        _json_dump(result)
    finally:
        bridge.close()
        store.close()
    return 0


def cmd_session(args: argparse.Namespace) -> int:
    """Keep the footage brain warm for a simple search-first editing session."""
    project_root = Path(args.project_root).expanduser().resolve()
    with IndexStore.for_project(project_root) as store, SynthCutClipBridge(_repo_root()) as bridge:
        if args.source:
            index_media(
                Path(args.source).expanduser().resolve(),
                store,
                bridge,
                interval=args.interval,
                force=args.force,
                progress=lambda msg: print(msg, file=sys.stderr),
            )
        if store.asset_count() == 0:
            raise RuntimeError("No indexed footage. Pass --source on the first session run.")

        resolve_adapter = ResolveAdapter(_repo_root())
        resolve = resolve_adapter.connect()
        project_manager = resolve.GetProjectManager()
        project = project_manager.GetCurrentProject() if project_manager else None
        if project is None:
            raise ResolveUnavailable("No current Resolve project is open")
        resolve_adapter.require_matching_project_frame_rates(project)

        builder = VideoHighlighterAdapter(_repo_root())
        print(
            f"Connected to Resolve project: {project.GetName()}\n"
            f"Indexed footage: {store.asset_count()} clips · {store.visual_sample_count()} visual samples\n"
            "Type any visual search. Enter q to quit."
        )

        while True:
            try:
                query = input("\nSearch footage> ").strip()
            except EOFError:
                print()
                break
            if query.lower() in {"q", "quit", "exit"}:
                break
            if not query:
                continue

            moments, assets = find_moments(
                query,
                store,
                bridge,
                builder,
                search_limit=args.limit,
                per_asset_limit=args.per_asset_limit,
                min_score=args.min_score,
                pre_handle=args.pre_handle,
                post_handle=args.post_handle,
                minimum_duration=args.minimum_duration,
            )
            if not moments:
                print("No sufficiently relevant moments found. Try different wording or a lower --min-score.")
                continue

            print(f"\n{len(moments)} handled moment{'s' if len(moments) != 1 else ''}:")
            for index, moment in enumerate(moments, start=1):
                print(
                    f"  {index}. {moment.source_path.name}  "
                    f"{_timecode(moment.handled_start or 0.0)}–{_timecode(moment.handled_end or 0.0)}  "
                    f"score {moment.score:.3f}"
                )

            default_name = default_timeline_name(query)
            try:
                choice = input(
                    f"Create '{default_name}' in Resolve? [Y/n or type another timeline name] "
                ).strip()
            except EOFError:
                print()
                break
            if choice.lower() in {"n", "no"}:
                continue
            timeline_name = default_name if choice.lower() in {"", "y", "yes"} else choice
            result = _create_selects_with_remainder(
                timeline_name=timeline_name,
                moments=moments,
                assets=assets,
                project_root=project_root,
                query=query,
                create_remainder=True,
                remainder_name=None,
            )
            print(
                f"Created {result['timeline']} — "
                f"{result['ranges_appended']} source range{'s' if result['ranges_appended'] != 1 else ''}; "
                f"created {result['remainder_timeline']} with "
                f"{result['remainder_ranges_appended']} remaining range"
                f"{'s' if result['remainder_ranges_appended'] != 1 else ''}."
            )

    return 0


def _add_query_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--project-root", required=True, help="Project root containing .clip-resolved index state")
    parser.add_argument("query", help="Arbitrary semantic footage query")
    parser.add_argument("--limit", type=int, default=80, help="Maximum semantic frame hits considered globally")
    parser.add_argument("--per-asset-limit", type=int, default=30, help="Maximum frame hits retained per source asset")
    parser.add_argument(
        "--min-score",
        type=float,
        default=None,
        help="Minimum CLIP cosine relevance (search returns raw ranked hits when omitted)",
    )


def _add_moment_args(parser: argparse.ArgumentParser) -> None:
    _add_query_args(parser)
    parser.set_defaults(min_score=0.22)
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

    scan = sub.add_parser("scan", help="Read-only media scan with temporal shoot grouping")
    scan.add_argument("--source", required=True)
    scan.add_argument("--gap-hours", type=float, default=3.0)
    scan.set_defaults(func=cmd_scan)

    status = sub.add_parser("status", help="Report durable project index state")
    status.add_argument("--project-root", required=True)
    status.set_defaults(func=cmd_project_status)

    scaffold = sub.add_parser("resolve-scaffold", help="Create/load a Resolve project and import originals")
    scaffold.add_argument("--project-root", required=True)
    scaffold.add_argument("--project-name", required=True)
    scaffold.add_argument("--source", required=True)
    scaffold.add_argument("--timeline-fps", type=float, default=30.0)
    scaffold.set_defaults(func=cmd_resolve_scaffold)

    index = sub.add_parser("index", help="Build/update the persistent visual index")
    index.add_argument("--project-root", required=True)
    index.add_argument("--source", required=True, help="Folder or source video to index")
    index.add_argument("--interval", type=float, default=2.0, help="Frame sampling interval in seconds")
    index.add_argument("--force", action="store_true", help="Re-index unchanged assets")
    index.set_defaults(func=cmd_index)

    search_parser = sub.add_parser("search", help="Search the existing visual index")
    _add_query_args(search_parser)
    search_parser.set_defaults(func=cmd_search)

    transcribe = sub.add_parser("transcribe", help="Build/update timed transcripts using SynthCut Whisper")
    transcribe.add_argument("--project-root", required=True)
    transcribe.add_argument("--source", required=True, help="Indexed footage folder or source video")
    transcribe.add_argument("--language", default="auto")
    transcribe.add_argument("--model", default="base.en")
    transcribe.add_argument("--force", action="store_true")
    transcribe.set_defaults(func=cmd_transcribe)

    transcript_search = sub.add_parser("transcript-search", help="Search existing timed transcripts")
    transcript_search.add_argument("--project-root", required=True)
    transcript_search.add_argument("query")
    transcript_search.add_argument("--limit", type=int, default=50)
    transcript_search.set_defaults(func=cmd_transcript_search)

    transcript_selects = sub.add_parser(
        "transcript-selects",
        help="Create a Resolve SELECTS timeline from spoken-word matches",
    )
    transcript_selects.add_argument("--project-root", required=True)
    transcript_selects.add_argument("query")
    transcript_selects.add_argument("--limit", type=int, default=50)
    transcript_selects.add_argument("--timeline-name")
    transcript_selects.add_argument("--pre-handle", type=float, default=1.0)
    transcript_selects.add_argument("--post-handle", type=float, default=1.5)
    transcript_selects.add_argument("--minimum-duration", type=float, default=4.0)
    transcript_selects.add_argument("--remainder-timeline-name")
    transcript_selects.add_argument(
        "--no-remainder",
        action="store_true",
        help="Do not create the exact NOT SELECTED complement timeline",
    )
    transcript_selects.set_defaults(func=cmd_transcript_selects)

    transcript_moment_parser = sub.add_parser(
        "transcript-moments",
        help="Turn a spoken-word query into handled editorial moments",
    )
    transcript_moment_parser.add_argument("--project-root", required=True)
    transcript_moment_parser.add_argument("query")
    transcript_moment_parser.add_argument("--limit", type=int, default=50)
    transcript_moment_parser.add_argument("--pre-handle", type=float, default=1.0)
    transcript_moment_parser.add_argument("--post-handle", type=float, default=1.5)
    transcript_moment_parser.add_argument("--minimum-duration", type=float, default=4.0)
    transcript_moment_parser.set_defaults(func=cmd_transcript_moments)

    moments = sub.add_parser("moments", help="Turn a semantic query into handled editorial moments")
    _add_moment_args(moments)
    moments.set_defaults(func=cmd_moments)

    selects = sub.add_parser("selects", help="Create a Resolve SELECTS timeline from a semantic query")
    _add_moment_args(selects)
    selects.add_argument("--timeline-name", help="Override the generated '<QUERY> SELECTS' name")
    selects.add_argument("--remainder-timeline-name")
    selects.add_argument(
        "--no-remainder",
        action="store_true",
        help="Do not create the exact NOT SELECTED complement timeline",
    )
    selects.set_defaults(func=cmd_selects)

    session = sub.add_parser(
        "session",
        help="Run a persistent search-and-SELECTS loop against the open Resolve project",
    )
    session.add_argument("--project-root", required=True)
    session.add_argument("--source", help="Footage folder to index/update before searching")
    session.add_argument("--interval", type=float, default=2.0, help="Frame sampling interval in seconds")
    session.add_argument("--force", action="store_true", help="Re-index unchanged assets")
    session.add_argument("--limit", type=int, default=80)
    session.add_argument("--per-asset-limit", type=int, default=30)
    session.add_argument("--min-score", type=float, default=0.22)
    session.add_argument("--pre-handle", type=float, default=2.0)
    session.add_argument("--post-handle", type=float, default=3.0)
    session.add_argument("--minimum-duration", type=float, default=6.0)
    session.set_defaults(func=cmd_session)

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
