# Implementation Handoff

## First rule

Read root `AGENTS.md` before changing implementation.

This repository contains a working Python backend and native SwiftUI macOS app.

## Reuse rule

This is a personal tool. Implementation originality is irrelevant.

If upstream OSS works, use the actual code. Copy whole files/directories, vendor/fork the repo, or run directly from a pinned checkout — whichever is simplest and most reliable.

Do not rewrite a working subsystem just to make it look native to clip resolved.

Keep upstream license/attribution files when code is copied. That is compliance housekeeping, not an architectural reason to rebuild anything.

## What exists now

```text
card/folder scan -> confirmed shoot groups -> checksum-verified Media/Osmo copy
  -> Resolve project/bin scaffold + .drp snapshot
  -> persistent SynthCut CLIP index + optional timed Whisper transcript
  -> arbitrary visual or spoken-word query
  -> VideoHighlighter regions + handled editorial ranges
  -> Resolve AppendToTimeline exact source ranges -> SELECTS timeline
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
- `SoCloseSociety/kontentmanager` @ `900194791bd956f0391fadfaeca768d16bf8e742`
- `t0nyz0/SD-Offload` @ `1d72b3e632f81f5ac361e077d6f9d74764b2bec3`

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
- timed transcript storage

### `src/clip_resolved/ingest.py`

Read-only recursive scan, ffprobe metadata, temporal session proposals, and sidecar grouping through pinned KontentManager format code.

### `src/clip_resolved/transcript.py`

Calls SynthCut's actual Whisper implementation, persists timed cues/words, searches spoken text, and creates handled transcript moments.

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
- converts source seconds to half-open source-frame ranges
- calls `MediaPool.AppendToTimeline(...)`
- saves the current project
- exports/updates the project-root `.drp` after scaffold and SELECTS changes
- refuses unsaved projects and mismatched timeline/playback rates before mutation

### `Sources/ClipResolved/`

Native SwiftUI app with Disk Arbitration card detection, scan/group/name UI, SHA-256 verified ingest using SD-Offload primitives, persistent project library, visual/transcript search, and Resolve SELECTS actions.

Build and launch it with:

```bash
./script/build_and_run.sh
```

The pinned Resolve wrapper's live readback establishes `endFrame` as exclusive on Resolve Studio 21.0. Recheck the resulting range duration on Jonny's installed 21.1 build during the live test.

### `src/clip_resolved/cli.py`

Current commands:

```bash
clip-resolved doctor
clip-resolved doctor --deep
clip-resolved doctor --resolve

clip-resolved scan --source "/path/to/card"
clip-resolved resolve-scaffold --project-root "/path/to/project" --project-name "Project" --source "/path/to/originals"

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

clip-resolved transcribe --project-root "/path/to/Test Project" --source "/path/to/originals"
clip-resolved transcript-search --project-root "/path/to/Test Project" "spoken phrase"
clip-resolved transcript-selects --project-root "/path/to/Test Project" "spoken phrase"
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

## Live evidence on Jonny's Mac

- Resolve Studio 21.1 scripting connection confirmed.
- OSAKA: 65 original Osmo MP4s and 848 saved visual samples.
- Multiple arbitrary post-index queries returned handled timestamped ranges without re-indexing.
- Source-linked SELECTS timelines were appended in Resolve at matched 30/30 project rates.
- SynthCut's Whisper bridge executed against real embedded Osmo audio; silent clips correctly produce no usable speech cues.
- Native app builds, launches, and remains running as a normal macOS process.

## Still intentionally gated

- Card cleanup remains disabled until its exact SD-Offload `WipeGate` execution path is integrated and tested with disposable card media. Normal use never erases the card.
- External DJI Mic 2 sync needs actual matching camera/WAV samples for waveform-offset validation; embedded Osmo audio works now.
- Backup-destination, archive, proxy, and in-Resolve panel policies remain open decisions in `DECISIONS.md`; the standalone app is the working editing companion.

## Do not do these

- do not write another CLIP implementation
- do not write another scene detector
- do not write another Whisper implementation
- do not write another Resolve connection framework
- do not render select ranges into separate MP4s
- do not force fixed FOOD/PEOPLE/etc categories as the only way to query footage
- do not start over because the upstream code style is different from ours
