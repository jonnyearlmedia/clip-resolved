from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

from .resolve import ResolveAdapter, ResolveUnavailable
from .ingest import scan_source
from .ranges import merge_overlapping_handled
from .semantic import index_media, search
from .sources import load_sources, register_source
from .store import IndexStore
from .synthcut import SynthCutClipBridge, SynthCutBridgeError
from .transcript import (
    exact_range_moments,
    index_transcripts,
    list_speakers,
    search_transcripts,
    speaker_moments,
    transcript_context,
    transcript_moments,
)
from .videohighlighter import VideoHighlighterAdapter
from .workflow import (
    all_source_moments,
    default_remainder_timeline_name,
    default_timeline_name,
    find_moments,
    propose_categories,
    selects_profile,
    unselected_moments,
    vision_verify_moments,
    visual_asset_map,
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
    registered = register_source(
        project_root,
        source,
        label=args.source_label,
        kind=args.source_kind,
    )
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
                "source": {
                    "label": registered.label,
                    "path": registered.path,
                    "kind": registered.kind,
                },
            }
        )
    return 0


def cmd_register_source(args: argparse.Namespace) -> int:
    source = register_source(
        args.project_root,
        args.source,
        label=args.source_label,
        kind=args.source_kind,
    )
    _json_dump(
        {
            "project_root": str(Path(args.project_root).expanduser().resolve()),
            "source": {"label": source.label, "path": source.path, "kind": source.kind},
            "sources": [
                {"label": item.label, "path": item.path, "kind": item.kind}
                for item in load_sources(args.project_root)
            ],
        }
    )
    return 0


def cmd_relocate_indexed_assets(args: argparse.Namespace) -> int:
    source_project = Path(args.source_project_root).expanduser().resolve()
    destination_project = Path(args.destination_project_root).expanduser().resolve()
    if source_project == destination_project:
        raise ValueError("Source and destination projects must be different")
    payload = json.loads(Path(args.mapping_file).expanduser().resolve().read_text())
    moves = payload.get("moves", [])
    if not isinstance(moves, list) or not moves:
        raise ValueError("Move manifest contains no media mappings")

    transferred = 0
    missing_from_index: list[str] = []
    with IndexStore.for_project(source_project) as source_store, IndexStore.for_project(destination_project) as destination_store:
        for item in moves:
            if item.get("is_video") is False:
                continue
            source = Path(str(item["source"])).expanduser().resolve()
            destination = Path(str(item["destination"])).expanduser().resolve()
            if not destination.is_file():
                raise ValueError(f"Moved media is missing: {destination}")
            moved = source_store.transfer_asset_to(destination_store, source, destination)
            if moved is None:
                missing_from_index.append(str(source))
            else:
                transferred += 1
        _json_dump(
            {
                "transferred": transferred,
                "missing_from_index": missing_from_index,
                "source_assets": source_store.asset_count(),
                "source_visual_samples": source_store.visual_sample_count(),
                "destination_assets": destination_store.asset_count(),
                "destination_visual_samples": destination_store.visual_sample_count(),
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
                # The UI's clip count is camera footage. Audio-only assets may
                # also live in this index for timed narration transcripts.
                "assets": store.video_asset_count(),
                "visual_samples": store.visual_sample_count(),
                "transcripts": store.transcript_count(),
                "index_path": str(store.path),
            }
        )
    return 0


def cmd_resolve_scaffold(args: argparse.Namespace) -> int:
    register_source(
        args.project_root,
        args.source,
        label=args.source_label,
        kind="camera",
    )
    result = ResolveAdapter(_repo_root()).scaffold_project(
        project_name=args.project_name,
        project_root=Path(args.project_root),
        source=Path(args.source),
        timeline_fps=args.timeline_fps,
    )
    _json_dump(result)
    return 0


def cmd_resolve_timelines(args: argparse.Namespace) -> int:
    _json_dump(ResolveAdapter(_repo_root()).timeline_state())
    return 0


def cmd_open_timeline(args: argparse.Namespace) -> int:
    _json_dump(ResolveAdapter(_repo_root()).activate_timeline(args.timeline_name))
    return 0


def cmd_sync_audio(args: argparse.Namespace) -> int:
    _json_dump(
        ResolveAdapter(_repo_root()).auto_sync_audio(
            Path(args.project_root),
            retain_embedded_audio=not args.replace_embedded_audio,
        )
    )
    return 0


def cmd_create_multicam(args: argparse.Namespace) -> int:
    _json_dump(
        ResolveAdapter(_repo_root()).create_multicam(
            Path(args.project_root),
            name=args.name,
            sync_mode=args.sync_mode,
        )
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
        updated = index_transcripts(
            source,
            store,
            bridge,
            language=args.language,
            model=args.model,
            force=args.force,
            diarize=args.diarize,
            progress=lambda msg: print(msg, file=sys.stderr),
        )
        _json_dump(
            {
                "project_root": str(project_root),
                "transcripts_updated": updated,
                "transcripts_in_store": store.transcript_count(),
                "diarized": args.diarize,
            }
        )
    return 0


def cmd_speakers(args: argparse.Namespace) -> int:
    with IndexStore.for_project(args.project_root) as store:
        _json_dump({"speakers": list_speakers(store)})
    return 0


def cmd_speaker_selects(args: argparse.Namespace) -> int:
    with IndexStore.for_project(args.project_root) as store:
        moments, assets = speaker_moments(
            args.speaker_label,
            store,
            pre_handle=args.pre_handle,
            post_handle=args.post_handle,
            minimum_duration=args.minimum_duration,
        )
        if not moments:
            print(
                f"No transcript cues found for speaker {args.speaker_label!r}; "
                "Resolve was not changed.",
                file=sys.stderr,
            )
            return 2
        timeline_name = args.timeline_name or f"{args.speaker_label.upper()} SELECTS"
        result = _create_selects_with_remainder(
            timeline_name=timeline_name,
            moments=moments,
            assets=assets,
            project_root=Path(args.project_root),
            query=f"speaker: {args.speaker_label}",
            create_remainder=not args.no_remainder,
            remainder_name=args.remainder_timeline_name,
        )
        result["speaker_label"] = args.speaker_label
        result["moments"] = len(moments)
        _json_dump(result)
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


def cmd_transcript_context(args: argparse.Namespace) -> int:
    with IndexStore.for_project(args.project_root) as store:
        _json_dump(transcript_context(store, max_characters=args.max_characters))
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


def cmd_exact_range_selects(args: argparse.Namespace) -> int:
    project_root = Path(args.project_root).expanduser().resolve()
    payload = json.loads(Path(args.ranges_file).expanduser().resolve().read_text())
    ranges = payload.get("ranges", [])
    with IndexStore.for_project(project_root) as store:
        moments, assets = exact_range_moments(ranges, store, query=args.timeline_name)
        result = _create_selects_with_remainder(
            timeline_name=args.timeline_name,
            moments=moments,
            assets=assets,
            project_root=project_root,
            query=args.timeline_name,
            create_remainder=not args.no_remainder,
            remainder_name=args.remainder_timeline_name,
        )
        result["query"] = args.timeline_name
        result["moments"] = len(moments)
        _json_dump(result)
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

    remainder = unselected_moments(
        moments,
        assets,
        query=query,
        audio_fps=result.get("timeline_fps"),
    )
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
        # Creating the complement makes it current in Resolve. Return the user
        # to the timeline they explicitly asked for after both timelines exist.
        adapter.activate_timeline(result["timeline"])
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


def cmd_smart_selects(args: argparse.Namespace) -> int:
    """Build a shoot-aware category package plus one exact global complement."""
    project_root = Path(args.project_root).expanduser().resolve()
    base_categories = selects_profile(args.profile)
    category_results: list[dict] = []
    all_selected = []

    with IndexStore.for_project(project_root) as store, SynthCutClipBridge(_repo_root()) as bridge:
        if store.video_asset_count() == 0:
            raise RuntimeError("No indexed footage. Run clip-resolved index first.")

        evidence_report: dict[str, list[str]] | None = None
        if args.adaptive:
            categories, evidence_report = propose_categories(
                store,
                bridge,
                base_profile=base_categories,
                min_assets=args.min_category_assets,
                min_score=args.min_score,
                search_limit=args.limit,
                per_asset_limit=args.per_asset_limit,
            )
            if args.dry_run and not args.vision_verify:
                _json_dump(
                    {
                        "profile": args.profile,
                        "proposed_categories": [
                            {"name": c.timeline_name, "query": c.query} for c in categories
                        ],
                        "dropped_priors": evidence_report["dropped"],
                        "discovered_categories": evidence_report["discovered"],
                    }
                )
                return 0
        else:
            categories = list(base_categories)

        builder = VideoHighlighterAdapter(_repo_root())
        assets = visual_asset_map(store.iter_assets())
        adapter = ResolveAdapter(_repo_root())
        planned_categories = []

        # Finish all semantic planning before the first Resolve mutation. This
        # keeps an empty/overly strict profile from leaving a partial package.
        verify_reports: dict[str, dict] = {}
        for category in categories:
            # With vision-verify on, Claude does the real relevance judgment, so
            # candidate gathering deliberately casts a wider net than the
            # stricter unverified min-score -- otherwise the tightened default
            # can exclude real candidates before Claude ever sees them.
            candidate_min_score = args.candidate_min_score if args.vision_verify else args.min_score
            moments, _ = find_moments(
                category.query,
                store,
                bridge,
                builder,
                search_limit=args.limit,
                per_asset_limit=args.per_asset_limit,
                min_score=candidate_min_score,
                pre_handle=args.pre_handle,
                post_handle=args.post_handle,
                minimum_duration=args.minimum_duration,
            )
            if args.vision_verify:
                moments, report = vision_verify_moments(
                    category.timeline_name,
                    category.query,
                    moments,
                    assets,
                    top_k=args.verify_top_k,
                )
                verify_reports[category.timeline_name] = report
            planned_categories.append((category, moments))
            all_selected.extend(moments)

        if args.dry_run:
            _json_dump(
                {
                    "profile": args.profile,
                    "adaptive": args.adaptive,
                    "vision_verify": args.vision_verify,
                    "categories": [
                        {
                            "name": category.timeline_name,
                            "query": category.query,
                            "moments": len(moments),
                            "vision_verify": verify_reports.get(category.timeline_name),
                        }
                        for category, moments in planned_categories
                    ],
                }
            )
            return 0

        if not all_selected:
            print("No category moments found; Resolve was not changed.", file=sys.stderr)
            return 2

        stringout_result = adapter.create_selects_timeline(
            args.stringout_timeline_name,
            all_source_moments(assets),
            assets,
            project_root=project_root,
        )

        all_broll = merge_overlapping_handled(all_selected)
        all_broll_result = adapter.create_selects_timeline(
            args.all_broll_timeline_name,
            all_broll,
            assets,
            project_root=project_root,
        )

        latest_snapshot = all_broll_result.get("snapshot") or stringout_result.get("snapshot")
        for category, moments in planned_categories:
            if not moments:
                category_results.append(
                    {
                        "name": category.timeline_name,
                        "query": category.query,
                        "timeline": None,
                        "moments": 0,
                        "ranges_requested": 0,
                        "ranges_appended": 0,
                    }
                )
                continue

            result = adapter.create_selects_timeline(
                category.timeline_name,
                moments,
                assets,
                project_root=project_root,
            )
            latest_snapshot = result.get("snapshot") or latest_snapshot
            category_results.append(
                {
                    "name": category.timeline_name,
                    "query": category.query,
                    "timeline": result["timeline"],
                    "moments": len(moments),
                    "ranges_requested": result["ranges_requested"],
                    "ranges_appended": result["ranges_appended"],
                }
            )

        remainder = unselected_moments(
            all_selected,
            assets,
            query=f"{args.profile} smart selects package",
        )
        remainder_result = None
        if remainder:
            remainder_result = adapter.create_selects_timeline(
                args.remainder_timeline_name,
                remainder,
                assets,
                project_root=project_root,
            )
            latest_snapshot = remainder_result.get("snapshot") or latest_snapshot

        created = [item for item in category_results if item["timeline"] is not None]
        every_append_succeeded = (
            stringout_result["ranges_requested"] == stringout_result["ranges_appended"]
            and all_broll_result["ranges_requested"] == all_broll_result["ranges_appended"]
            and all(item["ranges_requested"] == item["ranges_appended"] for item in created)
            and (
                remainder_result is None
                or remainder_result["ranges_requested"] == remainder_result["ranges_appended"]
            )
        )
        _json_dump(
            {
                "project": stringout_result["project"],
                "profile": args.profile,
                "categories": category_results,
                "category_timelines_created": len(created),
                "selected_ranges": sum(item["ranges_appended"] for item in created),
                "all_broll_timeline": all_broll_result["timeline"],
                "all_broll_ranges_requested": all_broll_result["ranges_requested"],
                "all_broll_ranges_appended": all_broll_result["ranges_appended"],
                "stringout_timeline": stringout_result["timeline"],
                "stringout_ranges_requested": stringout_result["ranges_requested"],
                "stringout_ranges_appended": stringout_result["ranges_appended"],
                "remainder_timeline": remainder_result["timeline"] if remainder_result else None,
                "remainder_ranges_requested": remainder_result["ranges_requested"] if remainder_result else 0,
                "remainder_ranges_appended": remainder_result["ranges_appended"] if remainder_result else 0,
                "indexed_assets": len(assets),
                "coverage_complete": every_append_succeeded,
                "snapshot": latest_snapshot,
                "adaptive": args.adaptive,
                "dropped_priors": evidence_report["dropped"] if evidence_report else [],
                "discovered_categories": evidence_report["discovered"] if evidence_report else [],
                "vision_verify": args.vision_verify,
                "vision_verify_reports": verify_reports,
            }
        )
    return 0


def cmd_raw_stringout(args: argparse.Namespace) -> int:
    """Create one complete source-linked timeline for delivery/review."""
    project_root = Path(args.project_root).expanduser().resolve()
    with IndexStore.for_project(project_root) as store:
        assets = visual_asset_map(store.iter_assets())
        if not assets:
            raise RuntimeError("No indexed footage. Run clip-resolved index first.")
        result = ResolveAdapter(_repo_root()).create_selects_timeline(
            args.timeline_name,
            all_source_moments(assets),
            assets,
            project_root=project_root,
        )
        result.update(
            {
                "indexed_assets": len(assets),
                "complete_source_coverage": result["ranges_appended"] == len(assets),
            }
        )
        _json_dump(result)
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

    register = sub.add_parser(
        "register-source",
        help="Add or update a camera/audio source in a project's durable source manifest",
    )
    register.add_argument("--project-root", required=True)
    register.add_argument("--source", required=True)
    register.add_argument("--source-label")
    register.add_argument("--source-kind", choices=["camera", "audio"], default="camera")
    register.set_defaults(func=cmd_register_source)

    relocate = sub.add_parser(
        "relocate-indexed-assets",
        help="Transfer existing visual/transcript index rows after media moves between projects",
    )
    relocate.add_argument("--source-project-root", required=True)
    relocate.add_argument("--destination-project-root", required=True)
    relocate.add_argument("--mapping-file", required=True)
    relocate.set_defaults(func=cmd_relocate_indexed_assets)

    scaffold = sub.add_parser("resolve-scaffold", help="Create/load a Resolve project and import originals")
    scaffold.add_argument("--project-root", required=True)
    scaffold.add_argument("--project-name", required=True)
    scaffold.add_argument("--source", required=True)
    scaffold.add_argument("--source-label")
    scaffold.add_argument("--timeline-fps", type=float, default=30.0)
    scaffold.set_defaults(func=cmd_resolve_scaffold)

    resolve_timelines = sub.add_parser(
        "resolve-timelines",
        help="List timelines in the currently open saved Resolve project",
    )
    resolve_timelines.set_defaults(func=cmd_resolve_timelines)

    open_timeline = sub.add_parser(
        "open-timeline",
        help="Switch Resolve to an existing timeline by exact name",
    )
    open_timeline.add_argument("--timeline-name", required=True)
    open_timeline.set_defaults(func=cmd_open_timeline)

    sync_audio = sub.add_parser(
        "sync-audio",
        help="Waveform-sync registered external audio to imported camera clips in Resolve 21.1+",
    )
    sync_audio.add_argument("--project-root", required=True)
    sync_audio.add_argument(
        "--replace-embedded-audio",
        action="store_true",
        help="Discard embedded camera audio after sync instead of retaining it",
    )
    sync_audio.set_defaults(func=cmd_sync_audio)

    multicam = sub.add_parser(
        "create-multicam",
        help="Create Resolve multicam media from all registered camera sources",
    )
    multicam.add_argument("--project-root", required=True)
    multicam.add_argument("--name", required=True)
    multicam.add_argument("--sync-mode", choices=["audio", "timecode"], default="audio")
    multicam.set_defaults(func=cmd_create_multicam)

    index = sub.add_parser("index", help="Build/update the persistent visual index")
    index.add_argument("--project-root", required=True)
    index.add_argument("--source", required=True, help="Folder or source video to index")
    index.add_argument("--source-label")
    index.add_argument("--source-kind", choices=["camera"], default="camera")
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
    transcribe.add_argument(
        "--diarize",
        action="store_true",
        help=(
            "Also run local speaker diarization (Aseiel/VideoHighlighter: "
            "Resemblyzer + clustering, no HuggingFace token) and tag each "
            "transcript cue with a speaker label"
        ),
    )
    transcribe.set_defaults(func=cmd_transcribe)

    transcript_search = sub.add_parser("transcript-search", help="Search existing timed transcripts")
    transcript_search.add_argument("--project-root", required=True)
    transcript_search.add_argument("query")
    transcript_search.add_argument("--limit", type=int, default=50)
    transcript_search.set_defaults(func=cmd_transcript_search)

    transcript_context_parser = sub.add_parser(
        "transcript-context",
        help="Return a bounded source-identified transcript corpus for project chat",
    )
    transcript_context_parser.add_argument("--project-root", required=True)
    transcript_context_parser.add_argument("--max-characters", type=int, default=40_000)
    transcript_context_parser.set_defaults(func=cmd_transcript_context)

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

    speakers_parser = sub.add_parser(
        "speakers",
        help="List distinct diarized speaker labels found in stored transcripts",
    )
    speakers_parser.add_argument("--project-root", required=True)
    speakers_parser.set_defaults(func=cmd_speakers)

    speaker_selects = sub.add_parser(
        "speaker-selects",
        help="Create a Resolve SELECTS timeline from one diarized speaker's cues",
    )
    speaker_selects.add_argument("--project-root", required=True)
    speaker_selects.add_argument("speaker_label", help='e.g. "Person 1", from `speakers`')
    speaker_selects.add_argument("--timeline-name")
    speaker_selects.add_argument("--pre-handle", type=float, default=1.0)
    speaker_selects.add_argument("--post-handle", type=float, default=1.5)
    speaker_selects.add_argument("--minimum-duration", type=float, default=4.0)
    speaker_selects.add_argument("--remainder-timeline-name")
    speaker_selects.add_argument(
        "--no-remainder",
        action="store_true",
        help="Do not create the exact NOT SELECTED complement timeline",
    )
    speaker_selects.set_defaults(func=cmd_speaker_selects)

    exact_ranges = sub.add_parser(
        "exact-range-selects",
        help="Create a source-linked Resolve timeline from validated exact ranges",
    )
    exact_ranges.add_argument("--project-root", required=True)
    exact_ranges.add_argument("--ranges-file", required=True)
    exact_ranges.add_argument("--timeline-name", required=True)
    exact_ranges.add_argument("--remainder-timeline-name")
    exact_ranges.add_argument("--no-remainder", action="store_true")
    exact_ranges.set_defaults(func=cmd_exact_range_selects)

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

    smart_selects = sub.add_parser(
        "smart-selects",
        help="Create a shoot-aware category SELECTS package and one global NOT SELECTED review timeline",
    )
    smart_selects.add_argument("--project-root", required=True)
    smart_selects.add_argument(
        "--profile",
        default="restaurant",
        choices=["restaurant", "community-story", "event"],
    )
    smart_selects.add_argument("--limit", type=int, default=80)
    smart_selects.add_argument("--per-asset-limit", type=int, default=30)
    smart_selects.add_argument(
        "--min-score",
        type=float,
        default=0.27,
        help=(
            "Minimum match strength for both category evidence and individual clip "
            "selection. 0.22 (the general point-search default) was proven too loose "
            "for package-quality selects on two real projects (OSAKA, Andaan Gallery) "
            "-- it accepted nearly every candidate category regardless of real fit."
        ),
    )
    smart_selects.add_argument("--pre-handle", type=float, default=2.0)
    smart_selects.add_argument("--post-handle", type=float, default=3.0)
    smart_selects.add_argument("--minimum-duration", type=float, default=6.0)
    smart_selects.add_argument(
        "--all-broll-timeline-name",
        default="ALL B-ROLL SELECTS",
        help="Name for the merged union of every populated category",
    )
    smart_selects.add_argument(
        "--stringout-timeline-name",
        default="00 ALL RAW FOOTAGE STRINGOUT",
        help="Name for the chronological full-length source timeline",
    )
    smart_selects.add_argument(
        "--remainder-timeline-name",
        default="ALL FOOTAGE NOT SELECTED REVIEW",
        help="Name for the exact complement of the union of every category",
    )
    smart_selects.add_argument(
        "--adaptive",
        action="store_true",
        help=(
            "Gate the --profile category list on real footage evidence instead of "
            "using it unconditionally, and allow evidence-backed categories from "
            "other profiles or the general vocabulary to be proposed as well"
        ),
    )
    smart_selects.add_argument(
        "--min-category-assets",
        type=int,
        default=3,
        help="With --adaptive, minimum distinct clips a category must appear in to be kept/proposed",
    )
    smart_selects.add_argument(
        "--dry-run",
        action="store_true",
        help="With --adaptive and/or --vision-verify, print the planned package and exit without touching Resolve",
    )
    smart_selects.add_argument(
        "--vision-verify",
        action="store_true",
        help=(
            "Have Claude actually look at the strongest CLIP candidate frames per category "
            "and judge real relevance, dropping ones it rejects, instead of trusting the raw "
            "similarity score alone. Uses the local Claude Code install (no separate API key), "
            "costs real time/usage per category, and is opt-in for that reason."
        ),
    )
    smart_selects.add_argument(
        "--verify-top-k",
        type=int,
        default=10,
        help="With --vision-verify, how many top-scoring candidates per category Claude reviews",
    )
    smart_selects.add_argument(
        "--candidate-min-score",
        type=float,
        default=0.20,
        help=(
            "With --vision-verify, the looser match strength used to gather the candidate "
            "shortlist Claude reviews (real evidence: at the stricter --min-score default, "
            "categories can return zero candidates before Claude ever gets to look -- an "
            "empty category is more honest than a wrong one, but it isn't a fix either. Claude "
            "does the real filtering here, so this casts a wider net on purpose). Ignored "
            "without --vision-verify."
        ),
    )
    smart_selects.set_defaults(func=cmd_smart_selects)

    raw_stringout = sub.add_parser(
        "raw-stringout",
        help="Create one chronological full-length timeline containing every indexed original once",
    )
    raw_stringout.add_argument("--project-root", required=True)
    raw_stringout.add_argument("--timeline-name", default="00 ALL RAW FOOTAGE STRINGOUT")
    raw_stringout.set_defaults(func=cmd_raw_stringout)

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
