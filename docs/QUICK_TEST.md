# Same-Day Quick Test

Purpose: test the core Clip Resolved experience on a real no-Mic-2 edit without building the full Mac app.

## Scope

Build/fix only this path:

```text
existing footage folder
  -> make/open Resolve project
  -> import original MP4s
  -> create minimal bins
  -> build persistent visual index
  -> arbitrary semantic query
  -> handled source ranges
  -> create SELECTS timeline in Resolve
```

No card UI. No shoot-grouping UI. No Mic 2. No audio sync. No LRF cleanup. No polished app shell. No Workflow Integration UI. No transcription unless it is already trivially working.

The point of this test is to learn whether the footage brain + Resolve source-range workflow is actually useful while Jonny edits a real video.

## Required bins

```text
00 TIMELINES
  SELECTS
  EDITS
01 FOOTAGE
  OSMO
```

Nothing else is required for this test.

## Required commands / flow

1. `bash scripts/bootstrap_upstreams.sh`
2. `source .venv/bin/activate`
3. `clip-resolved doctor --deep --resolve`
4. `clip-resolved index --project-root <project> --source <footage-folder>`
5. `clip-resolved moments --project-root <project> "food shots"`
6. `clip-resolved selects --project-root <project> "food shots"`
7. Run at least one completely unplanned query after indexing, e.g. `all the luxury cars` or something Jonny remembers being in the shoot.

## Codex task

Do not add architecture or UI first.

Run the current implementation locally on Jonny's Mac and fix whatever prevents the above flow from completing end-to-end.

Priority order:

1. bootstrap/install failures
2. SynthCut CLIP bridge failures
3. ffprobe/index failures
4. VideoHighlighter region adapter failures
5. Resolve connection/import failures
6. Resolve source-frame placement/off-by-one issues
7. poor command ergonomics only after the above works

## Acceptance test

This is successful when:

- a folder of original Osmo MP4s is indexed without modifying them
- `clip-resolved search` returns sensible timestamped hits
- `clip-resolved moments` returns handled source ranges
- `clip-resolved selects` creates a real Resolve SELECTS timeline
- the timeline references the original MP4s, not rendered derivatives
- a new query that was not known during indexing works without re-indexing the footage

## Do not spend time on tonight

- full macOS GUI
- Claude Design implementation
- card insertion detection
- verified offload
- session grouping
- LRF handling
- Mic 2 USB detection
- external audio matching
- transcript/speaker system
- Resolve-hosted companion UI
- packaging/notarization
- settings screen

Those remain part of the real product. They are intentionally excluded from this quick real-footage test.

## Important

If current semantic moment grouping is noisy, do not redesign the whole system. Preserve the raw semantic hits and make the smallest adjustment needed to let Jonny edit with it tonight. Capture misses/false positives for the real benchmark afterward.
