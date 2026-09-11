# AGENTS.md — clip resolved

This file is the first-read instruction set for any coding agent working in this repository.

## What this project is

clip resolved is a macOS companion for Jonny's DJI Osmo → DaVinci Resolve workflow.

Its job is to:

1. detect and safely ingest mixed camera-card footage
2. group footage into user-confirmed shoots/projects
3. create a portable project root and Resolve project scaffold
4. analyze the verified source media locally
5. build a persistent Wideframe-like multimodal footage index
6. detect useful editorial moments inside long source clips
7. add generous handles without rendering new media
8. create/query SELECTS timelines in DaVinci Resolve using exact source ranges
9. continue answering new semantic footage queries after ingest

The product is NOT just a card importer and NOT just automatic bins.

Core product principle:

> analyze once, understand deeply, query repeatedly.

## Mandatory implementation rule

**Do not rebuild working open-source systems from scratch.**

Before implementing any subsystem, read `docs/ASSEMBLY_STRATEGY.md`.

Default priority:

1. use/vendor the actual OSS implementation
2. fork + minimally patch it
3. extract its real subsystem/code
4. wrap it behind an adapter
5. write new code only for genuine integration gaps

If you decide to replace an existing OSS implementation, document the concrete reason first.

## Mandatory reading order

Read these before material implementation work:

1. `docs/ASSEMBLY_STRATEGY.md`
2. `docs/PRODUCT_SPEC.md`
3. `docs/INGEST_FLOW.md`
4. `docs/RESOLVE_PROJECT_FLOW.md`
5. `docs/WIDEFRAME_BENCHMARK.md`
6. `docs/MOMENT_EXTRACTION.md`
7. `docs/ARCHITECTURE.md`
8. `docs/SCENARIOS.md`
9. `docs/DECISIONS.md`
10. `docs/IMPLEMENTATION_HANDOFF.md`

If documents conflict, prefer the newest, more specific decision document and flag the conflict instead of silently choosing.

## Locked product behavior

### Card / ingest

- A card is a container, not necessarily one shoot.
- Scan read-only first.
- Propose temporal groups, including cross-midnight continuity.
- Every MP4 must be accounted for exactly once before confirmation.
- User may move one or many clips between groups.
- User names each group and chooses Personal or Client.
- Confirmation is the GO trigger. There is no separate Prepare button.
- After confirmation, create the final project root and begin verified offload + non-destructive analysis.
- Deleting verified source files from the card is a separate explicit human action and must fail closed.

### Canonical media

After ingest there is one authoritative source-media copy inside the project's portable root.

Resolve and clip resolved reference those exact files. Do not create a second working source copy.

### Resolve

- DaVinci Resolve is the NLE; clip resolved is the intelligence/control layer.
- Live Resolve project lives in the Project Library.
- `.drp` is an exported portable snapshot, not a live Premiere-style project file.
- `.dra` is an explicit handoff/archive artifact.
- AI selects are source ranges referencing original Media Pool items, not rendered MP4 chunks.
- Prefer category SELECTS timelines over creating hundreds of subclips.
- Default short-form editing intent is 30fps delivery with commonly 60fps Osmo acquisition. Do not auto-interpret 60fps media as slow motion.

### UX surfaces

Treat the product as two surfaces sharing one brain:

1. **Mac ingest/setup app** — card grouping, naming, verified copy, project creation, analysis progress, safe cleanup.
2. **Resolve editing companion** — footage search, current-clip intelligence, SELECTS, transcripts, on-demand queries/actions.

Do NOT force the editor to stare at ingest UI while editing.

The Resolve surface should be search-first. Chat/Ask is optional for complex requests, not the default interaction.

Potential Resolve integration path: Workflow Integration plugin / panel when supported on the user's installed Resolve Studio version. Keep heavy analysis in the local clip-resolved service rather than inside the panel.

### Wideframe-quality intelligence target

Wideframe is the product benchmark, not source code.

Required experience includes:

- distinguish interview footage from b-roll
- separate multiple interviews
- timestamped transcription
- associate names/entities only when evidence supports them
- visual semantic search
- chat/query over indexed footage
- generate NEW selects later that were not predefined at ingest

Example:

`all the luxury cars` → search existing index → matching exact ranges → optionally create `LUXURY CARS SELECTS` in Resolve.

Do not reduce the system to a fixed FOOD/PEOPLE/EXTERIOR classifier.

## Existing OSS candidates already inspected

Use the actual code/repositories where appropriate.

### Ingest

- `SoCloseSociety/kontentmanager` — primary baseline: DiskArbitration detection, card gallery, sidecars, verified atomic copy, hashing/dedup, project reassignment. MIT.
- `t0nyz0/SD-Offload` — especially `Sources/OffloadEngine/WipeGate.swift` for manifest-only destructive cleanup safety. MIT.
- `qtld88/FilmCan` — copy verification / paranoid reread / fanout / MHL ideas or components. GPL-3.0.

### Intelligence

- `Relo-video/SynthCut` — source-direct local media import, CLIP ViT-B/32 ONNX visual embeddings/search, transcript/search patterns. GPLv3.
- `Aseiel/VideoHighlighter` — useful-moment signals, `modules/auto_segments.py` variable-length candidate-region engine, framing/quality analysis, detector routing. AGPL-3.0.
- `PySceneDetect` — visual change/boundary signal only; not a definition of useful raw-camera shots.
- `Omnishot` — watcher/manifest/index ideas; do NOT copy its physical MP4 chunking as our Resolve output architecture.

### Resolve control

- `samuelgursky/davinci-resolve-mcp` — preferred current Resolve scripting/API wrapper and measured API-truth reference.

Reuse its guarded/live-tested behavior rather than writing a new wrapper for hundreds of calls.

Important verified Resolve concept:

`MediaPool.AppendToTimeline([{mediaPoolItem, startFrame, endFrame, ...}])`

This is the basis of non-destructive SELECTS creation.

## What is product-specific glue

Original code should concentrate on:

- Osmo/project identification
- temporal shoot grouping UX
- Personal/Client routing
- project-root manifests/state
- orchestration across reused tools
- shoot-aware analyzer routing
- durable multimodal index schema
- converting signals into editorial moments
- handle policy
- dedupe/merge policy
- semantic query → source-range results
- query result → Resolve SELECTS timeline actions
- clean macOS/Resolve UX

## Current implementation priority

Do NOT try to finish the whole polished app first.

Build a real-footage vertical slice as early as practical:

```text
real Osmo folder
  -> index verified source
  -> search/query footage semantically
  -> return exact timestamp ranges
  -> add provisional handles
  -> create a Resolve SELECTS timeline referencing those ranges
```

Required proof queries should include at least:

- a normal preplanned category such as `food shots`
- an unplanned post-hoc query such as `all the luxury cars`
- a transcript-driven query when interview footage is available

Only tune thresholds from misses/false positives on real footage.

## Safety / data rules

- Never modify original camera media during analysis.
- Never delete from the card except through explicit verified cleanup flow.
- Do not silently omit clips.
- Do not invent semantic identity/person names without evidence.
- Do not render derivative source clips merely to represent selects.
- Derived caches/indexes may be regenerated and should not be treated as irreplaceable media.

## User / machine constraints

Primary target:

- macOS
- MacBook Pro M2 Pro, 19-core GPU, 16 GB RAM
- DaVinci Resolve Studio

Optimize for local/free processing where practical. The main expected limitation is throughput/resource pressure, not theoretical feasibility.

The user does not want to touch `.env` files, manually assemble backend plumbing, or answer questions that should have sensible defaults.

## When blocked

Do not invent missing behavior.

1. inspect the actual upstream repo/API
2. check existing project docs
3. build the smallest empirical test
4. document the unresolved edge
5. continue with independent work instead of stopping the entire project
