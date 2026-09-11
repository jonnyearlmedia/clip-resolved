# Resolve Project Flow

## Verified Resolve project model

DaVinci Resolve does **not** treat a `.drp` like a live Premiere-style project file.

The live working project exists inside Resolve's Project Library. A `.drp` is an exported/importable project snapshot. Importing a `.drp` copies that project into the selected Project Library; subsequent edits happen to the library copy, not the original `.drp` on disk.

clip resolved must not pretend otherwise.

## Project folder remains the canonical media package

When the user confirms a shoot group, clip resolved immediately creates the final movable project folder and verified-offloads the footage into it.

Example:

```text
Carabao/
├── Media/
│   └── Osmo/
│       ├── DJI_0041.MP4
│       ├── DJI_0042.MP4
│       └── ...
├── Assets/
├── Project/
│   └── Carabao.drp
└── .clip-resolved/
    ├── manifests/
    ├── index/
    └── analysis/
```

There is only one authoritative source-media copy after ingest: the verified files under `Carabao/Media/...`.

Resolve and clip resolved both reference those exact files.

## Live Resolve project creation is real API functionality

The current Resolve scripting API exposes the operations required for this workflow, and the `samuelgursky/davinci-resolve-mcp` project tracks/live-tests them.

Relevant operations include:

- `ProjectManager.CreateProject(projectName, mediaLocationPath=None)`
- `ProjectManager.SaveProject()`
- `ProjectManager.ExportProject(projectName, filePath, withStillsAndLUTs=True)`
- `MediaPool.AddSubFolder(folder, name)`
- `MediaStorage.AddItemListToMediaPool(...)`
- `MediaPool.CreateEmptyTimeline(name)`
- `MediaPool.AppendToTimeline([{mediaPoolItem, startFrame, endFrame, ...}])`
- `MediaPool.RelinkClips(...)` / related relink APIs
- `ProjectManager.ArchiveProject(...)`

Use the existing Resolve MCP wrapper/guard code rather than reimplementing this API layer.

## What group confirmation should create

Once a group is confirmed and named/classified:

1. Create the final project folder on disk.
2. Create the live Resolve project in the user's normal Resolve Project Library.
3. Create a minimal Media Pool scaffold:

```text
ORIGINALS/
└── OSMO/

SELECTS/

EDITS/
```

4. Verified-offload source files into `Media/Osmo/`.
5. Import the **verified destination files** from `Media/Osmo/` into the Resolve `ORIGINALS/OSMO` bin.
6. All subsequent AI analysis references those same source files.
7. AI-generated selects timelines are created inside the `SELECTS` bin and contain source ranges referencing the originals, not newly rendered MP4s.
8. Do not automatically create a final edit timeline until the delivery format/aspect ratio/frame-rate requirement is known.

## Portable `.drp` copy

`Project/Carabao.drp` is a portable project snapshot, not the live project database.

clip resolved should export/update this snapshot:

- after initial project scaffolding
- after clip resolved makes material automated changes to bins/selects/timelines
- when the user explicitly asks to sync/package/share

A future background snapshot policy may additionally keep it fresh while the project is being manually edited in Resolve, but this needs testing before being promised.

## Moving the normal project folder

If the whole `Carabao/` folder is moved, all relative relationships inside the folder remain the same, but Resolve may still have absolute source paths from the old root.

clip resolved should detect the moved project using its manifest and automatically relink Resolve Media Pool items to the corresponding paths under the new project root.

Example:

```text
old root:
/Users/jonny/Active Projects/Client/Carabao/

new root:
/Volumes/T7/Carabao/
```

The media itself is not recopied. Only Resolve's path references are updated.

## Sending to another Resolve editor

For a formal handoff, use Resolve's real archive mechanism:

`ArchiveProject(projectName, filePath, isArchiveSrcMedia=True, isArchiveRenderCache=False, isArchiveProxyMedia=<choice>)`

This creates a Resolve project archive (`.dra`) containing the project and selected media assets.

Default clip resolved packaging policy should be:

- source media: yes
- render cache: no
- proxies: optional

The normal working folder remains the everyday project package; `.dra` is the explicit Resolve-to-Resolve handoff/archive format.

## Current next stage

With ingest + project creation + portability now defined, the next workflow stage is:

**turning analyzed raw Osmo footage into useful handled source ranges and automatically assembling those ranges into category SELECTS timelines.**

That moment-extraction logic must be designed from existing OSS implementations and tested workflows, not invented from scratch.