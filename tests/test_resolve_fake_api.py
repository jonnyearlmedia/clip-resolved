from pathlib import Path

from clip_resolved.models import MediaAsset, Moment
from clip_resolved.resolve import ResolveAdapter, ResolveUnavailable
from clip_resolved.sources import register_source


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

    def GetTrackCount(self, media_type):
        return 1 if media_type in {"video", "audio"} else 0

    def GetItemListInTrack(self, media_type, track):
        return []


class FakeMediaPool:
    def __init__(self):
        self.root = FakeFolder("root")
        self.current = self.root
        self.appended = []
        self.synced = None
        self.multicam = None
        self.owner_project = None  # set by FakeProject; mirrors real Resolve auto-registration

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
        timeline = FakeTimeline(name)
        if self.owner_project is not None:
            self.owner_project.timelines.append(timeline)
            self.owner_project.current_timeline = timeline
        return timeline

    def AppendToTimeline(self, clip_infos):
        self.appended.extend(clip_infos)
        return [object() for _ in clip_infos]

    def AutoSyncAudio(self, items, settings):
        self.synced = (items, settings)
        return True

    def CreateMulticamClip(self, items, options):
        self.multicam = (items, options)
        return [FakeItem("multicam://created")]


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
        media_pool.owner_project = self
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

    def SetSetting(self, name, value):
        self.settings[name] = value
        return True

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

    def ExportProject(self, name, path, with_stills_and_luts):
        return True


class FakeResolve:
    AUDIO_SYNC_WAVEFORM = 1
    AUDIO_SYNC_CHANNEL_AUTOMATIC = 0
    MULTICAM_ANGLE_SYNC_AUDIO = 1
    MULTICAM_ANGLE_SYNC_TIMECODE = 2
    MULTICAM_AUDIO_ALL = 3
    MULTICAM_ANGLE_NAME_FILE = 4
    MULTICAM_DETECT_NONE = 0

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


def test_selects_appends_audio_only_range_using_project_timebase():
    resolve = FakeResolve()
    adapter = ResolveAdapter()
    adapter._resolve = resolve
    audio = MediaAsset(
        id="audio",
        path=Path("/source/DJI_0047.WAV"),
        duration=240.0,
        fps=0.0,
        width=0,
        height=0,
        has_audio=True,
        size=1,
        mtime_ns=1,
    )
    moment = Moment(
        asset_id=audio.id,
        source_path=audio.path,
        detected_start=156.72,
        detected_end=200.44,
        handled_start=156.72,
        handled_end=200.44,
        score=1.0,
        query="MAGGIE NARRATION SELECTS",
    )

    result = adapter.create_selects_timeline(
        "MAGGIE NARRATION SELECTS",
        [moment],
        {audio.id: audio},
    )

    assert resolve.media_pool.appended == [
        {
            "mediaPoolItem": resolve.media_pool.appended[0]["mediaPoolItem"],
            "startFrame": 4701,
            "endFrame": 6014,
            "mediaType": 2,
        }
    ]
    assert result["timeline_fps"] == 30.0


def test_selects_reuses_same_named_empty_timeline_after_interrupted_append():
    resolve = FakeResolve()
    existing = FakeTimeline("MAGGIE NARRATION SELECTS")
    resolve.project.timelines = [existing]
    adapter = ResolveAdapter()
    adapter._resolve = resolve
    audio = MediaAsset(
        id="audio",
        path=Path("/source/DJI_0047.WAV"),
        duration=240.0,
        fps=0.0,
        width=0,
        height=0,
        has_audio=True,
        size=1,
        mtime_ns=1,
    )
    moment = Moment(
        asset_id=audio.id,
        source_path=audio.path,
        detected_start=156.72,
        detected_end=200.44,
        handled_start=156.72,
        handled_end=200.44,
        score=1.0,
        query="MAGGIE NARRATION SELECTS",
    )

    result = adapter.create_selects_timeline(
        "MAGGIE NARRATION SELECTS",
        [moment],
        {audio.id: audio},
    )

    assert result["timeline"] == "MAGGIE NARRATION SELECTS"
    assert resolve.project.current_timeline is existing


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


def test_registered_sources_drive_waveform_sync_and_multicam(tmp_path):
    project_root = tmp_path / "Project"
    osmo = tmp_path / "Osmo"
    phone = tmp_path / "Phone"
    osmo.mkdir()
    phone.mkdir()
    osmo_video = osmo / "DJI_0001.MP4"
    osmo_audio = osmo / "DJI_0001.WAV"
    phone_video = phone / "IMG_0001.MOV"
    for path in (osmo_video, osmo_audio, phone_video):
        path.write_bytes(b"fixture")
    register_source(project_root, osmo, label="OSMO")
    register_source(project_root, phone, label="IPHONE")

    resolve = FakeResolve()
    resolve.media_pool.root.clips.extend(
        [FakeItem(str(osmo_video)), FakeItem(str(osmo_audio)), FakeItem(str(phone_video))]
    )
    adapter = ResolveAdapter()
    adapter._resolve = resolve

    sync = adapter.auto_sync_audio(project_root)
    multicam = adapter.create_multicam(
        project_root,
        name="EVENT MULTICAM",
        sync_mode="audio",
    )

    assert sync["synced"] is True
    assert sync["videos"] == 2
    assert sync["audio_files"] == 1
    assert resolve.media_pool.synced[1]["retainEmbeddedAudio"] is True
    assert multicam["camera_sources"] == ["IPHONE", "OSMO"]
    assert multicam["multicam_clips_created"] == 1
    assert resolve.media_pool.multicam[1]["splitAtGaps"] is True


def test_scaffold_project_adds_later_registered_recorder_without_duplicating_camera(tmp_path):
    """Camera ingests and scaffolds Resolve first; the Mic Mini is registered and
    the project re-scaffolded afterward. This must update the same project (no
    second project gets created) and must not re-import the camera clips already
    in the Media Pool, while still adding the recorder's audio into its own bin.

    This is fake-API evidence for the exact sequence Jonny asked about, not a
    live-Resolve proof: no real Resolve/DJI Mic run has happened (SCENARIO_LEDGER
    S07/S25 stay NOT TESTED/PARTIAL for that).
    """
    project_root = tmp_path / "Project"
    camera_dir = tmp_path / "Osmo"
    camera_dir.mkdir()
    camera_video = camera_dir / "DJI_0001.MP4"
    camera_video.write_bytes(b"fixture")
    register_source(project_root, camera_dir, label="OSMO", kind="camera")

    resolve = FakeResolve()
    adapter = ResolveAdapter()
    adapter._resolve = resolve

    first_run = adapter.scaffold_project(
        project_name="Quick Test",
        project_root=project_root,
        source=camera_dir,
    )

    footage_root = next(
        folder for folder in resolve.media_pool.root.children if folder.name == "01 FOOTAGE"
    )
    osmo_folder = next(folder for folder in footage_root.children if folder.name == "OSMO")
    assert {clip.path for clip in osmo_folder.clips} == {str(camera_video)}
    assert first_run["imported"] == 1
    assert len(resolve.project_manager.GetProjectListInCurrentFolder()) == 1
    first_project = resolve.project_manager.GetCurrentProject()

    # Mic Mini arrives later and is registered as its own audio-only source.
    mic_dir = tmp_path / "MicMini"
    mic_dir.mkdir()
    mic_audio = mic_dir / "MIC_0001.WAV"
    mic_audio.write_bytes(b"fixture")
    register_source(project_root, mic_dir, label="MIC MINI", kind="audio")

    second_run = adapter.scaffold_project(
        project_name="Quick Test",
        project_root=project_root,
        source=camera_dir,
    )

    # Same project, not a second one.
    assert resolve.project_manager.GetCurrentProject() is first_project
    assert len(resolve.project_manager.GetProjectListInCurrentFolder()) == 1

    # Camera clip was not re-imported/duplicated.
    osmo_folder_again = next(
        folder for folder in footage_root.children if folder.name == "OSMO"
    )
    assert osmo_folder_again is osmo_folder
    assert [clip.path for clip in osmo_folder.clips] == [str(camera_video)]

    # The recorder's audio was added into its own labeled bin.
    audio_root = next(
        folder for folder in resolve.media_pool.root.children if folder.name == "02 AUDIO"
    )
    mic_folder = next(folder for folder in audio_root.children if folder.name == "MIC MINI")
    assert {clip.path for clip in mic_folder.clips} == {str(mic_audio)}

    # Only the new recorder file was imported on the second run.
    assert second_run["imported"] == 1


def test_scaffold_project_creates_obvious_main_edit_and_assets_bins_once(tmp_path):
    """Jonny's real complaint (2026-09-29) about the Andaan project: the main
    edit timeline ended up mixed into the SELECTS bin with a dozen
    auto-generated category timelines, so it was unclear which one to edit
    in, and there was no assets/music bin in Resolve at all. Every scaffolded
    project must always get an unambiguous main edit timeline in EDITS and a
    real ASSETS bin, and re-running scaffold must not create a duplicate.
    """
    project_root = tmp_path / "Project"
    camera_dir = tmp_path / "Osmo"
    camera_dir.mkdir()
    (camera_dir / "DJI_0001.MP4").write_bytes(b"fixture")
    register_source(project_root, camera_dir, label="OSMO", kind="camera")

    resolve = FakeResolve()
    adapter = ResolveAdapter()
    adapter._resolve = resolve

    adapter.scaffold_project(
        project_name="Quick Test",
        project_root=project_root,
        source=camera_dir,
    )

    timelines_root = next(
        folder for folder in resolve.media_pool.root.children if folder.name == "00 TIMELINES"
    )
    edits_folder = next(folder for folder in timelines_root.children if folder.name == "EDITS")
    assets_root = next(
        folder for folder in resolve.media_pool.root.children if folder.name == "03 ASSETS"
    )
    assert {folder.name for folder in assets_root.children} == {"MUSIC", "GRAPHICS"}

    main_edits = [t for t in resolve.project.timelines if t.GetName() == "QUICK TEST MAIN EDIT"]
    assert len(main_edits) == 1
    assert edits_folder is not None

    # Re-scaffolding (e.g. a later source arriving) must not create a second one.
    adapter.scaffold_project(
        project_name="Quick Test",
        project_root=project_root,
        source=camera_dir,
    )
    main_edits_after = [t for t in resolve.project.timelines if t.GetName() == "QUICK TEST MAIN EDIT"]
    assert len(main_edits_after) == 1
