from __future__ import annotations

import importlib
import math
import os
import sys
from pathlib import Path
from typing import Iterable

from .models import MediaAsset, Moment


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
        self._resolve = module.initialize_resolve()
        if self._resolve is None:
            raise ResolveUnavailable(
                "Could not connect to DaVinci Resolve Studio. Start Resolve and ensure scripting is available."
            )
        return self._resolve

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

    @staticmethod
    def _source_frame_range(moment: Moment, asset: MediaAsset) -> tuple[int, int]:
        if moment.handled_start is None or moment.handled_end is None:
            raise ValueError("moment requires handled_start/handled_end before Resolve placement")
        fps = asset.fps
        if fps <= 0:
            raise ValueError(f"invalid source fps for {asset.path}: {fps}")
        start = max(0, int(math.floor(moment.handled_start * fps)))
        # Resolve MCP's live tests use endFrame as the last included source frame.
        end_exclusive = max(start + 1, int(math.ceil(moment.handled_end * fps)))
        end_inclusive = end_exclusive - 1
        return start, end_inclusive

    def create_selects_timeline(
        self,
        timeline_name: str,
        moments: list[Moment],
        assets: dict[str, MediaAsset],
    ) -> dict:
        resolve = self.connect()
        project_manager = resolve.GetProjectManager()
        project = project_manager.GetCurrentProject() if project_manager else None
        if project is None:
            raise ResolveUnavailable("No current Resolve project is open")
        media_pool = project.GetMediaPool()
        media_storage = resolve.GetMediaStorage()

        footage_folder = self._ensure_folder_path(media_pool, ["01 FOOTAGE", "OSMO"])
        selects_folder = self._ensure_folder_path(media_pool, ["00 TIMELINES", "SELECTS"])

        items: dict[str, object] = {}
        for asset_id in {m.asset_id for m in moments}:
            asset = assets[asset_id]
            item = self._find_item_by_path(media_pool, asset.path)
            if item is None:
                media_pool.SetCurrentFolder(footage_folder)
                imported = media_storage.AddItemListToMediaPool([str(asset.path)]) or []
                item = imported[0] if imported else self._find_item_by_path(media_pool, asset.path)
            if item is None:
                raise RuntimeError(f"Resolve could not import/find source media: {asset.path}")
            items[asset_id] = item

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
        if not project_manager.SaveProject():
            raise RuntimeError("Resolve created the SELECTS timeline but SaveProject() failed")

        return {
            "project": project.GetName(),
            "timeline": actual_name,
            "ranges_requested": len(clip_infos),
            "ranges_appended": len(appended),
        }
