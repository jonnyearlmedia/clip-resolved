from pathlib import Path

from clip_resolved.models import MediaAsset, Moment
from clip_resolved.resolve import ResolveAdapter, ResolveUnavailable


class FakeFolder:
    def __init__(self, name):
        self.name = name
        self.children = []
        self.clips = []

    def GetName(self):
        return self.name

    def GetSubFolderList(self):
        return self.children

    def GetClipList(self):
        return self.clips


class FakeItem:
    def __init__(self, path):
        self.path = path

    def GetClipProperty(self, name):
        return self.path if name in {"File Path", "FilePath"} else None


class FakeTimeline:
    def __init__(self, name):
        self.name = name

    def GetName(self):
        return self.name


class FakeMediaPool:
    def __init__(self):
        self.root = FakeFolder("root")
        self.current = self.root
        self.appended = []

    def GetRootFolder(self):
        return self.root

    def AddSubFolder(self, parent, name):
        folder = FakeFolder(name)
        parent.children.append(folder)
        return folder

    def SetCurrentFolder(self, folder):
        self.current = folder
        return True

    def CreateEmptyTimeline(self, name):
        return FakeTimeline(name)

    def AppendToTimeline(self, clip_infos):
        self.appended.extend(clip_infos)
        return [object() for _ in clip_infos]


class FakeMediaStorage:
    def __init__(self, media_pool):
        self.media_pool = media_pool

    def AddItemListToMediaPool(self, paths):
        items = [FakeItem(path) for path in paths]
        self.media_pool.current.clips.extend(items)
        return items


class FakeProject:
    def __init__(self, media_pool, timeline_rate="30", playback_rate="30"):
        self.media_pool = media_pool
        self.current_timeline = None
        self.timelines = []
        self.settings = {
            "timelineFrameRate": timeline_rate,
            "timelinePlaybackFrameRate": playback_rate,
        }

    def GetName(self):
        return "Quick Test"

    def GetMediaPool(self):
        return self.media_pool

    def GetSetting(self, name):
        return self.settings.get(name)

    def GetTimelineCount(self):
        return len(self.timelines)

    def GetTimelineByIndex(self, index):
        return self.timelines[index - 1]

    def GetCurrentTimeline(self):
        return self.current_timeline

    def SetCurrentTimeline(self, timeline):
        self.current_timeline = timeline
        return True


class FakeProjectManager:
    def __init__(self, project):
        self.project = project

    def GetCurrentProject(self):
        return self.project

    def SaveProject(self):
        return True

    def GetProjectListInCurrentFolder(self):
        return [self.project.GetName()]


class FakeResolve:
    def __init__(self):
        self.media_pool = FakeMediaPool()
        self.project = FakeProject(self.media_pool)
        self.project_manager = FakeProjectManager(self.project)
        self.media_storage = FakeMediaStorage(self.media_pool)

    def GetProjectManager(self):
        return self.project_manager

    def GetMediaStorage(self):
        return self.media_storage


def _asset(asset_id, path):
    return MediaAsset(
        id=asset_id,
        path=Path(path),
        duration=20.0,
        fps=50.0,
        width=3840,
        height=2160,
        has_audio=True,
        size=1,
        mtime_ns=1,
    )


def test_selects_scaffolds_exact_bins_and_imports_all_indexed_originals():
    resolve = FakeResolve()
    adapter = ResolveAdapter()
    adapter._resolve = resolve
    first = _asset("a", "/source/DJI_0001.MP4")
    second = _asset("b", "/source/DJI_0002.MP4")
    moment = Moment(
        asset_id=first.id,
        source_path=first.path,
        detected_start=4.0,
        detected_end=6.0,
        handled_start=2.0,
        handled_end=9.0,
        score=0.4,
        query="food shots",
    )

    result = adapter.create_selects_timeline(
        "FOOD SHOTS SELECTS",
        [moment],
        {first.id: first, second.id: second},
    )

    root = resolve.media_pool.root
    timelines = next(folder for folder in root.children if folder.name == "00 TIMELINES")
    footage = next(folder for folder in root.children if folder.name == "01 FOOTAGE")
    osmo = next(folder for folder in footage.children if folder.name == "OSMO")

    assert {folder.name for folder in timelines.children} == {"SELECTS", "EDITS"}
    assert {item.path for item in osmo.clips} == {str(first.path), str(second.path)}
    assert len(resolve.media_pool.appended) == 1
    assert resolve.media_pool.appended[0]["mediaPoolItem"].path == str(first.path)
    assert resolve.media_pool.appended[0]["startFrame"] == 100
    assert resolve.media_pool.appended[0]["endFrame"] == 450
    assert result["timeline"] == "FOOD SHOTS SELECTS"
    assert result["ranges_appended"] == 1


def test_selects_refuses_mismatched_project_playback_rate_before_mutating_resolve():
    resolve = FakeResolve()
    resolve.project.settings["timelinePlaybackFrameRate"] = "24"
    adapter = ResolveAdapter()
    adapter._resolve = resolve
    asset = _asset("a", "/source/DJI_0001.MP4")
    moment = Moment(
        asset_id=asset.id,
        source_path=asset.path,
        detected_start=4.0,
        detected_end=6.0,
        handled_start=2.0,
        handled_end=9.0,
        score=0.4,
        query="food shots",
    )

    try:
        adapter.create_selects_timeline("FOOD SHOTS SELECTS", [moment], {asset.id: asset})
    except RuntimeError as exc:
        assert "timeline is 30 fps but playback is 24 fps" in str(exc)
        assert "Project Settings > Master Settings" in str(exc)
    else:
        raise AssertionError("mismatched playback rate should stop timeline creation")

    assert resolve.media_pool.root.children == []
    assert resolve.media_pool.appended == []


def test_selects_refuses_unsaved_current_project_before_mutating_resolve():
    resolve = FakeResolve()
    resolve.project_manager.GetProjectListInCurrentFolder = lambda: []
    adapter = ResolveAdapter()
    adapter._resolve = resolve
    item = _asset("a", "/source/DJI_0001.MP4")
    moment = Moment(
        asset_id=item.id,
        source_path=item.path,
        detected_start=4.0,
        detected_end=6.0,
        handled_start=2.0,
        handled_end=9.0,
        score=0.4,
        query="food shots",
    )

    try:
        adapter.create_selects_timeline("FOOD SHOTS SELECTS", [moment], {item.id: item})
    except ResolveUnavailable as exc:
        assert "unsaved project" in str(exc)
    else:
        raise AssertionError("an unsaved current project should stop timeline creation")

    assert resolve.media_pool.root.children == []
    assert resolve.media_pool.appended == []


def test_existing_named_timeline_can_be_listed_and_opened_without_duplication():
    resolve = FakeResolve()
    food = FakeTimeline("FOOD SHOTS SELECTS")
    drinks = FakeTimeline("DRINKS SELECTS")
    resolve.project.timelines = [food, drinks]
    resolve.project.current_timeline = drinks
    adapter = ResolveAdapter()
    adapter._resolve = resolve

    state = adapter.timeline_state()
    result = adapter.activate_timeline("FOOD SHOTS SELECTS")

    assert state == {
        "project": "Quick Test",
        "timelines": ["FOOD SHOTS SELECTS", "DRINKS SELECTS"],
        "current_timeline": "DRINKS SELECTS",
    }
    assert result == {
        "project": "Quick Test",
        "timeline": "FOOD SHOTS SELECTS",
        "opened": True,
    }
    assert resolve.project.current_timeline is food
    assert len(resolve.project.timelines) == 2
