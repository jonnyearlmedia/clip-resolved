from __future__ import annotations

import importlib
import math
import os
import sys
from pathlib import Path
from typing import Iterable

from .models import MediaAsset, Moment
from .ffprobe import discover_audio_files, discover_video_files
from .sources import ProjectSource, load_sources, source_for_path


class ResolveUnavailable(RuntimeError):
    pass


class ResolveAdapter:
    """Small clip-resolved layer over the pinned Resolve MCP connection helper.

    The upstream repository owns platform detection / DaVinciResolveScript setup.
    This class only owns clip-resolved-specific bin and SELECTS behavior.
    """

    def __init__(self, repo_root: Path | None = None) -> None:
        self.repo_root = repo_root or Path(__file__).resolve().parents[2]
        self.upstream_root = self.repo_root / "external" / "davinci-resolve-mcp"
        self._resolve = None

    def connect(self):
        if self._resolve is not None:
            return self._resolve
        if not self.upstream_root.exists():
            raise ResolveUnavailable(
                f"Resolve MCP checkout missing at {self.upstream_root}. "
                "Run scripts/bootstrap_upstreams.sh first."
            )
        root = str(self.upstream_root)
        if root not in sys.path:
            sys.path.insert(0, root)
        module = importlib.import_module("src.utils.resolve_connection")
        # The upstream helper exposes platform-aware path discovery separately
        # from initialize_resolve(). Apply it in-process so users do not need to
        # maintain Resolve scripting variables in their shell profile.
        if not module.set_default_environment_variables():
            raise ResolveUnavailable("Could not configure DaVinci Resolve scripting paths")
        self._resolve = module.initialize_resolve()
        if self._resolve is None:
            raise ResolveUnavailable(
                "Could not connect to DaVinci Resolve Studio. Start Resolve and ensure scripting is available."
            )
        return self._resolve

    @staticmethod
    def _frame_rate(value) -> float | None:
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    @classmethod
    def project_frame_rates(cls, project) -> tuple[float | None, float | None]:
        """Return the project's timeline and playback rates as reported by Resolve."""
        return (
            cls._frame_rate(project.GetSetting("timelineFrameRate")),
            cls._frame_rate(project.GetSetting("timelinePlaybackFrameRate")),
        )

    @classmethod
    def require_matching_project_frame_rates(cls, project) -> tuple[float, float]:
        """Stop before editing when Resolve would play timelines at the wrong speed.

        Resolve's scripting API can read timelinePlaybackFrameRate but, in current
        Studio releases, refuses to write it. The only reliable repair is the
        Project Settings UI, so surface that exact action instead of continuing.
        """
        timeline_rate, playback_rate = cls.project_frame_rates(project)
        if timeline_rate is None or playback_rate is None:
            raise RuntimeError("Resolve did not report the project timeline/playback frame rates")
        if not math.isclose(timeline_rate, playback_rate, rel_tol=0.0, abs_tol=0.001):
            raise RuntimeError(
                "Resolve project frame-rate mismatch: "
                f"timeline is {timeline_rate:g} fps but playback is {playback_rate:g} fps. "
                "In Project Settings > Master Settings, set Playback frame rate "
                f"to {timeline_rate:g}, save, then retry."
            )
        return timeline_rate, playback_rate

    @staticmethod
    def _folder_by_name(parent, name: str):
        for child in parent.GetSubFolderList() or []:
            if child.GetName() == name:
                return child
        return None

    @classmethod
    def _ensure_folder_path(cls, media_pool, names: Iterable[str]):
        folder = media_pool.GetRootFolder()
        for name in names:
            child = cls._folder_by_name(folder, name)
            if child is None:
                child = media_pool.AddSubFolder(folder, name)
            if child is None:
                raise RuntimeError(f"Resolve failed to create Media Pool folder: {name}")
            folder = child
        return folder

    @staticmethod
    def _iter_clips(folder):
        stack = [folder]
        while stack:
            current = stack.pop()
            for clip in current.GetClipList() or []:
                yield clip
            children = list(current.GetSubFolderList() or [])
            stack.extend(reversed(children))

    @classmethod
    def _find_item_by_path(cls, media_pool, source_path: Path):
        wanted = os.path.normcase(os.path.realpath(str(source_path)))
        for item in cls._iter_clips(media_pool.GetRootFolder()):
            try:
                value = item.GetClipProperty("File Path") or item.GetClipProperty("FilePath")
            except Exception:
                continue
            if not value:
                continue
            if os.path.normcase(os.path.realpath(str(value))) == wanted:
                return item
        return None

    @classmethod
    def _items_by_path(cls, media_pool) -> dict[str, object]:
        """Read the Media Pool once; Resolve IPC is too slow for an O(n²) lookup loop."""
        result: dict[str, object] = {}
        for item in cls._iter_clips(media_pool.GetRootFolder()):
            try:
                value = item.GetClipProperty("File Path") or item.GetClipProperty("FilePath")
            except Exception:
                continue
            if value:
                result[os.path.normcase(os.path.realpath(str(value)))] = item
        return result

    @staticmethod
    def _unique_timeline_name(project, base: str) -> str:
        names = set()
        for index in range(1, int(project.GetTimelineCount() or 0) + 1):
            timeline = project.GetTimelineByIndex(index)
            if timeline:
                names.add(timeline.GetName())
        if base not in names:
            return base
        counter = 2
        while f"{base} {counter}" in names:
            counter += 1
        return f"{base} {counter}"

    @classmethod
    def _source_folder(cls, media_pool, source: ProjectSource, media_kind: str):
        root_name = "02 AUDIO" if media_kind == "audio" else "01 FOOTAGE"
        return cls._ensure_folder_path(media_pool, [root_name, source.label])

    @staticmethod
    def _timelines(project) -> list:
        return [
            timeline
            for index in range(1, int(project.GetTimelineCount() or 0) + 1)
            if (timeline := project.GetTimelineByIndex(index)) is not None
        ]

    def timeline_state(self) -> dict:
        resolve = self.connect()
        manager = resolve.GetProjectManager()
        project = manager.GetCurrentProject() if manager else None
        if project is None:
            raise ResolveUnavailable("No current Resolve project is open")
        self.require_saved_current_project(manager, project)
        current = project.GetCurrentTimeline()
        return {
            "project": project.GetName(),
            "timelines": [timeline.GetName() for timeline in self._timelines(project)],
            "current_timeline": current.GetName() if current else None,
        }

    def activate_timeline(self, timeline_name: str) -> dict:
        resolve = self.connect()
        manager = resolve.GetProjectManager()
        project = manager.GetCurrentProject() if manager else None
        if project is None:
            raise ResolveUnavailable("No current Resolve project is open")
        self.require_saved_current_project(manager, project)
        timeline = next(
            (item for item in self._timelines(project) if item.GetName() == timeline_name),
            None,
        )
        if timeline is None:
            raise RuntimeError(f"Resolve timeline not found: {timeline_name}")
        if project.SetCurrentTimeline(timeline) is False:
            raise RuntimeError(f"Resolve could not open timeline: {timeline_name}")
        return {"project": project.GetName(), "timeline": timeline.GetName(), "opened": True}

    def _registered_media_items(self, project_root: Path):
        resolve = self.connect()
        manager = resolve.GetProjectManager()
        project = manager.GetCurrentProject() if manager else None
        if project is None:
            raise ResolveUnavailable("No current Resolve project is open")
        self.require_saved_current_project(manager, project)
        media_pool = project.GetMediaPool()
        existing = self._items_by_path(media_pool)
        videos: list[tuple[ProjectSource, object]] = []
        audios: list[tuple[ProjectSource, object]] = []
        missing: list[str] = []
        for source in load_sources(project_root):
            if source.kind == "camera":
                for path in discover_video_files(source.root):
                    item = existing.get(os.path.normcase(os.path.realpath(str(path))))
                    if item is None:
                        missing.append(str(path))
                    else:
                        videos.append((source, item))
            for path in discover_audio_files(source.root):
                item = existing.get(os.path.normcase(os.path.realpath(str(path))))
                if item is None:
                    missing.append(str(path))
                else:
                    audios.append((source, item))
        if missing:
            sample = ", ".join(Path(path).name for path in missing[:3])
            raise RuntimeError(
                f"{len(missing)} registered source file(s) are not in the Resolve Media Pool "
                f"({sample}). Run Prepare Resolve first."
            )
        return resolve, manager, project, media_pool, videos, audios

    def auto_sync_audio(
        self,
        project_root: Path,
        *,
        retain_embedded_audio: bool = True,
    ) -> dict:
        resolve, manager, project, media_pool, videos, audios = self._registered_media_items(
            project_root.expanduser().resolve()
        )
        if not videos or not audios:
            raise RuntimeError(
                "Waveform sync needs at least one imported video and one imported audio file."
            )
        settings = {
            "syncMode": resolve.AUDIO_SYNC_WAVEFORM,
            "channelNumber": resolve.AUDIO_SYNC_CHANNEL_AUTOMATIC,
            "retainEmbeddedAudio": retain_embedded_audio,
            "retainVideoMetadata": True,
        }
        items = [item for _source, item in videos] + [item for _source, item in audios]
        if media_pool.AutoSyncAudio(items, settings) is False:
            raise RuntimeError(
                "Resolve could not waveform-sync the registered camera and external-audio files. "
                "No successful sync was reported."
            )
        if manager.SaveProject() is False:
            raise RuntimeError("Resolve synced audio but SaveProject() failed")
        return {
            "project": project.GetName(),
            "sync_mode": "waveform",
            "videos": len(videos),
            "audio_files": len(audios),
            "retain_embedded_audio": retain_embedded_audio,
            "synced": True,
        }

    def create_multicam(
        self,
        project_root: Path,
        *,
        name: str,
        sync_mode: str = "audio",
    ) -> dict:
        resolve, manager, project, media_pool, videos, _audios = self._registered_media_items(
            project_root.expanduser().resolve()
        )
        source_labels = {source.label for source, _item in videos}
        if len(source_labels) < 2:
            raise RuntimeError(
                "Multicam needs video from at least two registered camera sources. "
                "Add each camera to this project first."
            )
        if sync_mode not in {"audio", "timecode"}:
            raise ValueError("Multicam sync mode must be audio or timecode")
        media_pool.SetCurrentFolder(
            self._ensure_folder_path(media_pool, ["01 FOOTAGE", "MULTICAM"])
        )
        options = {
            "name": name,
            "angleSyncMode": (
                resolve.MULTICAM_ANGLE_SYNC_AUDIO
                if sync_mode == "audio"
                else resolve.MULTICAM_ANGLE_SYNC_TIMECODE
            ),
            "multicamAudioMode": resolve.MULTICAM_AUDIO_ALL,
            "angleNameMode": resolve.MULTICAM_ANGLE_NAME_FILE,
            "splitAtGaps": sync_mode == "audio",
            "useFullClipExtents": True,
            "createBinForSourceClips": True,
            "detectSameCameraClipsMode": resolve.MULTICAM_DETECT_NONE,
        }
        created = media_pool.CreateMulticamClip(
            [item for _source, item in videos],
            options,
        ) or []
        if not created:
            raise RuntimeError(
                f"Resolve created no multicam clips using {sync_mode} sync. "
                "The source clips may not overlap or may not share usable sync evidence."
            )
        if manager.SaveProject() is False:
            raise RuntimeError("Resolve created multicam media but SaveProject() failed")
        return {
            "project": project.GetName(),
            "name": name,
            "sync_mode": sync_mode,
            "camera_sources": sorted(source_labels),
            "source_clips": len(videos),
            "multicam_clips_created": len(created),
            "created": True,
        }

    @classmethod
    def _project_has_media(cls, project) -> bool:
        try:
            return any(cls._iter_clips(project.GetMediaPool().GetRootFolder()))
        except Exception:
            return True

    @classmethod
    def require_saved_current_project(cls, project_manager, project) -> None:
        name = project.GetName()
        saved_names = set(project_manager.GetProjectListInCurrentFolder() or [])
        if name not in saved_names:
            raise ResolveUnavailable(
                f"Resolve is on the unsaved project '{name}'. Open the intended saved project "
                "in Resolve's Project Manager, then retry. Clip Resolved did not change it."
            )

    @staticmethod
    def _source_frame_range(moment: Moment, asset: MediaAsset) -> tuple[int, int]:
        explicit_start = moment.metadata.get("source_start_frame")
        explicit_end = moment.metadata.get("source_end_frame")
        if isinstance(explicit_start, int) and isinstance(explicit_end, int):
            if explicit_start < 0 or explicit_end <= explicit_start:
                raise ValueError(
                    f"invalid explicit source frame range for {asset.path}: "
                    f"{explicit_start}–{explicit_end}"
                )
            return explicit_start, explicit_end
        if moment.handled_start is None or moment.handled_end is None:
            raise ValueError("moment requires handled_start/handled_end before Resolve placement")
        fps = asset.fps
        if fps <= 0:
            raise ValueError(f"invalid source fps for {asset.path}: {fps}")
        start = max(0, int(math.floor(moment.handled_start * fps)))
        # Resolve MCP's Studio 21 live readback proves endFrame is exclusive.
        end_exclusive = max(start + 1, int(math.ceil(moment.handled_end * fps)))
        return start, end_exclusive

    def create_selects_timeline(
        self,
        timeline_name: str,
        moments: list[Moment],
        assets: dict[str, MediaAsset],
        project_root: Path | None = None,
    ) -> dict:
        resolve = self.connect()
        project_manager = resolve.GetProjectManager()
        project = project_manager.GetCurrentProject() if project_manager else None
        if project is None:
            raise ResolveUnavailable("No current Resolve project is open")
        self.require_saved_current_project(project_manager, project)
        self.require_matching_project_frame_rates(project)
        media_pool = project.GetMediaPool()
        media_storage = resolve.GetMediaStorage()

        fallback_footage_folder = self._ensure_folder_path(media_pool, ["01 FOOTAGE", "OSMO"])
        selects_folder = self._ensure_folder_path(media_pool, ["00 TIMELINES", "SELECTS"])
        self._ensure_folder_path(media_pool, ["00 TIMELINES", "EDITS"])

        items: dict[str, object] = {}
        existing_items = self._items_by_path(media_pool)
        for asset_id, asset in assets.items():
            key = os.path.normcase(os.path.realpath(str(asset.path)))
            item = existing_items.get(key)
            if item is None:
                source = source_for_path(project_root, asset.path) if project_root else None
                destination = (
                    self._source_folder(media_pool, source, "camera")
                    if source is not None
                    else fallback_footage_folder
                )
                media_pool.SetCurrentFolder(destination)
                imported = media_storage.AddItemListToMediaPool([str(asset.path)]) or []
                item = imported[0] if imported else self._find_item_by_path(media_pool, asset.path)
            if item is None:
                raise RuntimeError(f"Resolve could not import/find source media: {asset.path}")
            items[asset_id] = item
            existing_items[key] = item

        media_pool.SetCurrentFolder(selects_folder)
        actual_name = self._unique_timeline_name(project, timeline_name)
        timeline = media_pool.CreateEmptyTimeline(actual_name)
        if timeline is None:
            raise RuntimeError(f"Resolve failed to create timeline: {actual_name}")
        project.SetCurrentTimeline(timeline)

        clip_infos = []
        for moment in moments:
            asset = assets[moment.asset_id]
            start_frame, end_frame = self._source_frame_range(moment, asset)
            clip_infos.append(
                {
                    "mediaPoolItem": items[moment.asset_id],
                    "startFrame": start_frame,
                    "endFrame": end_frame,
                }
            )

        appended = media_pool.AppendToTimeline(clip_infos) or []
        if len(appended) != len(clip_infos):
            raise RuntimeError(
                f"Resolve appended {len(appended)} of {len(clip_infos)} requested source ranges"
            )
        if project_manager.SaveProject() is False:
            raise RuntimeError("Resolve created the SELECTS timeline but SaveProject() failed")

        snapshot = None
        snapshot_exported = None
        if project_root is not None:
            project_root = project_root.expanduser().resolve()
            snapshot_path = project_root / "Project" / f"{project.GetName()}.drp"
            snapshot_path.parent.mkdir(parents=True, exist_ok=True)
            snapshot = str(snapshot_path)
            snapshot_exported = bool(
                project_manager.ExportProject(project.GetName(), snapshot, True)
            )

        return {
            "project": project.GetName(),
            "timeline": actual_name,
            "ranges_requested": len(clip_infos),
            "ranges_appended": len(appended),
            "snapshot": snapshot,
            "snapshot_exported": snapshot_exported,
        }

    def ensure_project(self, name: str, media_location: Path):
        resolve = self.connect()
        manager = resolve.GetProjectManager()
        if manager is None:
            raise ResolveUnavailable("Resolve project manager is unavailable")
        current = manager.GetCurrentProject()
        if current is not None and current.GetName() == name:
            return current
        saved_names = set(manager.GetProjectListInCurrentFolder() or [])
        if current is not None:
            current_name = current.GetName()
            current_is_saved = current_name in saved_names
            current_is_empty = (
                int(current.GetTimelineCount() or 0) == 0
                and not self._project_has_media(current)
            )
            if current_is_saved:
                if manager.SaveProject() is False:
                    raise RuntimeError(f"Resolve could not save the current project: {current_name}")
            elif not current_is_empty:
                raise ResolveUnavailable(
                    f"Resolve is on unsaved project '{current_name}' with content. "
                    "Save or close it in Resolve before preparing another project."
                )
        project = manager.LoadProject(name) if name in saved_names else None
        if name in saved_names and project is None:
            raise ResolveUnavailable(
                f"Resolve could not switch to saved project '{name}'. Open it in the "
                "Project Manager, then retry; no new project was created."
            )
        if project is None:
            try:
                project = manager.CreateProject(name, str(media_location))
            except TypeError:
                project = manager.CreateProject(name)
        if project is None:
            raise RuntimeError(f"Resolve could not create or load project: {name}")
        return project

    def scaffold_project(
        self,
        *,
        project_name: str,
        project_root: Path,
        source: Path,
        timeline_fps: float = 30.0,
    ) -> dict:
        project_root = project_root.expanduser().resolve()
        source = source.expanduser().resolve()
        for relative in ("Media", "Assets", "Project", ".clip-resolved/manifests", ".clip-resolved/analysis"):
            (project_root / relative).mkdir(parents=True, exist_ok=True)

        project = self.ensure_project(project_name, project_root)
        manager = self.connect().GetProjectManager()
        media_pool = project.GetMediaPool()
        media_storage = self.connect().GetMediaStorage()
        sources = load_sources(project_root)
        if not sources:
            sources = [ProjectSource(label="OSMO", path=str(source), kind="camera")]
        self._ensure_folder_path(media_pool, ["00 TIMELINES", "SELECTS"])
        self._ensure_folder_path(media_pool, ["00 TIMELINES", "EDITS"])

        if int(project.GetTimelineCount() or 0) == 0:
            project.SetSetting("timelineFrameRate", str(timeline_fps))

        imported = 0
        existing_items = self._items_by_path(media_pool)
        video_paths: list[Path] = []
        audio_paths: list[Path] = []
        for registered in sources:
            source_root = registered.root
            if registered.kind == "camera":
                camera_paths = discover_video_files(source_root)
                video_paths.extend(camera_paths)
                footage_folder = self._source_folder(media_pool, registered, "camera")
                for path in camera_paths:
                    key = os.path.normcase(os.path.realpath(str(path)))
                    if key in existing_items:
                        continue
                    media_pool.SetCurrentFolder(footage_folder)
                    result = media_storage.AddItemListToMediaPool([str(path)]) or []
                    if not result:
                        raise RuntimeError(f"Resolve could not import source media: {path}")
                    existing_items[key] = result[0]
                    imported += 1

            source_audio = discover_audio_files(source_root)
            audio_paths.extend(source_audio)
            if source_audio:
                audio_folder = self._source_folder(media_pool, registered, "audio")
                for path in source_audio:
                    key = os.path.normcase(os.path.realpath(str(path)))
                    if key in existing_items:
                        continue
                    media_pool.SetCurrentFolder(audio_folder)
                    result = media_storage.AddItemListToMediaPool([str(path)]) or []
                    if not result:
                        raise RuntimeError(f"Resolve could not import source audio: {path}")
                    existing_items[key] = result[0]
                    imported += 1

        if manager.SaveProject() is False:
            raise RuntimeError("Resolve project scaffold was created but SaveProject() failed")

        snapshot = project_root / "Project" / f"{project_name}.drp"
        exported = manager.ExportProject(project_name, str(snapshot), True)
        timeline_rate, playback_rate = self.project_frame_rates(project)
        return {
            "project": project.GetName(),
            "project_root": str(project_root),
            "source": str(source),
            "sources": [
                {"label": item.label, "path": item.path, "kind": item.kind}
                for item in sources
            ],
            "source_files": len(video_paths),
            "audio_files": len(audio_paths),
            "imported": imported,
            "snapshot": str(snapshot),
            "snapshot_exported": bool(exported),
            "timeline_fps": timeline_rate,
            "playback_fps": playback_rate,
            "frame_rates_match": (
                timeline_rate is not None
                and playback_rate is not None
                and math.isclose(timeline_rate, playback_rate, rel_tol=0.0, abs_tol=0.001)
            ),
        }
