# Implementation Handoff

## First rule

Read root `AGENTS.md` before changing implementation.

This repository is no longer documentation-only. A real first vertical slice exists under `src/clip_resolved/`.

## Reuse rule

This is a personal tool. Implementation originality is irrelevant.

If upstream OSS works, use the actual code. Copy whole files/directories, vendor/fork the repo, or run directly from a pinned checkout — whichever is simplest and most reliable.

Do not rewrite a working subsystem just to make it look native to clip resolved.

Keep upstream license/attribution files when code is copied. That is compliance housekeeping, not an architectural reason to rebuild anything.

## What exists now

```text
local source folder
  -> ffprobe metadata
  -> SynthCut actual CLIP embedImage()
  -> persistent SQLite visual index
  -> SynthCut actual CLIP embedText()
  -> arbitrary semantic timestamp hits
  -> VideoHighlighter actual auto_segments region functions
  -> handled editorial ranges
  -> Resolve MCP actual connection helper
  -> DaVinci Resolve Media Pool
  -> AppendToTimeline exact source ranges
  -> SELECTS timeline
```

Detected moments are source ranges. They are not rendered into replacement MP4s.

## Pull the exact upstream code

Run:

```bash
bash scripts/bootstrap_upstreams.sh
```

This clones the exact commits already researched into `external/` and installs SynthCut dependencies.

Pins live in `upstreams.lock.json`:

- `Relo-video/SynthCut` @ `96b1ca0e8b9935cc0d9561a3bc020f29bf9e88a0`
- `Aseiel/VideoHighlighter` @ `063e16416531679b98e39c7729c219e7ada362d9`
- `samuelgursky/davinci-resolve-mcp` @ `f4cd0f90d11431278ef5a24474ddad9d4e483251`

These are working code dependencies, not reference material.

If it becomes easier later to copy/vendor more of an upstream repo directly into this repository, do it instead of recreating it.

## Current code map

### `bridges/synthcut_clip_bridge.ts`

Dynamically imports the pinned SynthCut file:

`packages/core/src/media/clip.ts`

It directly calls upstream:

- `ensureClip()`
- `embedImage(path, time)`
- `embedText(query)`

### `src/clip_resolved/synthcut.py`

Keeps the SynthCut bridge process alive and sends JSON-lines requests.

### `src/clip_resolved/ffprobe.py`

Uses ffprobe for source metadata and media discovery.

### `src/clip_resolved/store.py`

SQLite project intelligence state:

- source assets
- source freshness
- persistent visual embeddings
- reserved transcript storage

### `src/clip_resolved/semantic.py`

Indexes original source frames using SynthCut embeddings and searches the saved corpus with arbitrary later text queries.

Ordinary new queries do not re-embed the video.

### `src/clip_resolved/videohighlighter.py`

Loads the pinned VideoHighlighter checkout and directly calls `modules/auto_segments.py` for region creation/merge/duration constraints.

The current adapter feeds semantic timestamp hits into that existing region engine. Tune or replace that adapter from real footage, but do not recreate VideoHighlighter's working region algorithms from scratch.

### `src/clip_resolved/ranges.py`

Adds provisional editor handles:

- 2 sec before
- 3 sec after
- 6 sec minimum handled duration

These values are intentionally provisional until tested on Jonny's footage.

### `src/clip_resolved/resolve.py`

Uses the pinned Resolve MCP repo's actual `src.utils.resolve_connection.initialize_resolve()` helper.

Then it:

- ensures `01 FOOTAGE / OSMO`
- ensures `00 TIMELINES / SELECTS`
- finds imported media by real file path
- imports missing original media
- creates a SELECTS timeline
- converts source seconds to frames
- calls `MediaPool.AppendToTimeline(...)`
- saves the current project

The source-frame end convention must be checked live on Jonny's installed Resolve build before treating frame boundaries as locked.

### `src/clip_resolved/cli.py`

Current commands:

```bash
clip-resolved doctor
clip-resolved doctor --deep
clip-resolved doctor --resolve

clip-resolved index \
  --project-root "/path/to/Test Project" \
  --source "/path/to/Test Project/Media/Osmo"

clip-resolved search \
  --project-root "/path/to/Test Project" \
  "food shots"

clip-resolved moments \
  --project-root "/path/to/Test Project" \
  "all the luxury cars"

clip-resolved selects \
  --project-root "/path/to/Test Project" \
  "all the luxury cars"
```

`selects` changes the currently open Resolve project.

## First local run on Jonny's Mac

1. Clone this repo.
2. Run `bash scripts/bootstrap_upstreams.sh`.
3. Run `source .venv/bin/activate`.
4. Run `clip-resolved doctor --deep`.
5. Use a normal working folder containing representative Osmo footage.
6. Run `clip-resolved index ...`.
7. Try arbitrary `clip-resolved search ...` queries.
8. Run `clip-resolved moments ...` and inspect timestamps.
9. Open Resolve Studio with a disposable test project.
10. Run `clip-resolved doctor --resolve`.
11. Run `clip-resolved selects ...`.
12. Confirm the generated timeline references the original source media and the expected source ranges.

## Mandatory benchmark queries

At minimum:

- `food shots`
- `exterior storefront`
- `people`
- an unplanned post-index query such as `all the luxury cars`

The unplanned query matters because Wideframe-style behavior is the actual target: analyze once, then ask new questions later.

## What is implemented but not yet live-tested here

This environment cannot run Jonny's local Resolve instance or his real Osmo footage, so Claude Code/Codex must verify:

- SynthCut bridge on his installed Node/macOS setup
- first CLIP model download/cache
- semantic retrieval quality
- best frame sampling interval
- VideoHighlighter grouping quality from semantic hits
- Resolve source-frame off-by-one behavior
- Resolve Media Pool `File Path` lookup behavior
- throughput/RAM while Resolve is also open on M2 Pro 16 GB

Do not add more architecture before running these tests unless something is genuinely blocked.

## Next coding order after first footage test

1. Fix actual failures in the current vertical slice.
2. Pull in more VideoHighlighter code directly where it improves results: `shot_type.py`, `clip_quality.py`, scene/change signals.
3. Pull in SynthCut/Whisper transcript code directly and persist timestamped transcripts.
4. Combine visual + transcript evidence for interview separation and richer queries.
5. Add the minimal Resolve-side search/selects UI.
6. Integrate the already-researched ingest repos after the footage-brain -> Resolve path is proven.

## Do not do these

- do not write another CLIP implementation
- do not write another scene detector
- do not write another Whisper implementation
- do not write another Resolve connection framework
- do not render select ranges into separate MP4s
- do not force fixed FOOD/PEOPLE/etc categories as the only way to query footage
- do not start over because the upstream code style is different from ours
