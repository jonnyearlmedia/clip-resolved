# Architecture

## Status

This document describes the current architectural direction during research. Components are intentionally replaceable until benchmarked.

## Core implementation rule

**Reuse proven open-source implementations aggressively when they solve the problem well.**

Do not rebuild a component merely to make it "ours." For this personal tool, prefer:

1. Direct dependency when practical
2. Fork/adapt an existing project
3. Extract/reuse a focused implementation
4. Reimplement only when integration, performance, licensing, maintenance, or UX gives a concrete reason

When code is reused, preserve and comply with the upstream license and attribution requirements. Because this repository is public, copied or derivative code must remain compliant with its source license even though the intended product is a personal tool.

Do not copy proprietary Wideframe code or bypass paid software. Wideframe is an architectural/workflow reference. Open-source projects such as SynthCut, Omnishot, Resolve MCP implementations, and ingest tools are candidates for direct technical reuse according to their licenses.

## System boundary

```text
microSD / camera media
        |
        v
+------------------------------+
|         clip resolved        |
|                              |
|  card detection / ingest UI  |
|  safe offload orchestration  |
|  media metadata              |
|  scene / shot segmentation   |
|  transcription              |
|  visual / semantic indexing  |
|  shoot-specific classifier   |
|  search / retrieval          |
|  agent / workflow logic      |
|  Resolve bridge              |
+---------------+--------------+
                |
                v
+------------------------------+
|      DaVinci Resolve         |
|                              |
| originals / Media Pool       |
| metadata / bins / markers    |
| selects timelines            |
| editing / color / audio      |
+------------------------------+
```

Resolve is the NLE. clip resolved is the control plane and intelligence layer.

## Major replaceable components

### 1. Card detection

Responsibility:
- detect volume insertion/removal
- identify likely Osmo media card
- enumerate media safely
- provide technical/card summary to the UI

Likely platform path:
- native macOS APIs such as Disk Arbitration / filesystem APIs

Do not build ingest logic into this layer.

### 2. Verified offload engine

Responsibility:
- copy originals safely
- checksum verification
- support one or more destinations if required
- produce an auditable success/failure state
- never silently modify camera originals

Candidates to evaluate/reuse:
- FilmCan
- other proven checksum/offload implementations
- Resolve Clone Tool only if automation/interface constraints are acceptable

Do not write a naive custom copier unless existing engines fail concrete requirements.

### 3. Media probe / technical metadata

Responsibility:
- duration
- codec
- resolution
- frame rate
- orientation
- timestamps
- audio streams
- available camera metadata

Likely reusable tooling:
- ffprobe / FFmpeg
- DJI-specific metadata parsers if useful and reliable

### 4. Scene / shot segmentation

Responsibility:
- identify semantic/visual boundaries or candidate analysis windows
- preserve source-path and exact source-time references
- avoid creating destructive derivative clips

Candidates:
- PySceneDetect as used by Omnishot
- segmentation approaches from SynthCut or other open-source video-search projects
- custom temporal windowing only if it benchmarks better for Osmo shooting patterns

Segmentation and final edit handles are separate concepts.

### 5. Semantic visual engine

Responsibility:
- text -> footage retrieval
- image -> similar footage retrieval
- semantic categorization
- reusable embeddings/index

Candidates to benchmark:
- SynthCut's local CLIP ViT-B/32 ONNX implementation
- Omnishot/Jina architecture
- modern local SigLIP/CLIP-family alternatives
- other permissively licensed Apple-Silicon-friendly models

Preference:
- local
- free per shoot
- commercially/permissively licensed where possible
- accurate enough on real Osmo footage

No engine is selected yet.

### 6. Audio / transcript intelligence

Responsibility:
- transcription when relevant
- word/timestamp search
- topic ranges
- possible silence/filler analysis

Candidate:
- local Whisper / whisper.cpp patterns from SynthCut and similar projects

This may be disabled or deprioritized for mostly silent b-roll shoots.

### 7. Shot-range preparation

Responsibility:
- convert detected semantic moments into editor-usable source ranges
- add configurable pre/post handles
- enforce minimum usable duration
- clamp safely to source boundaries
- merge or deduplicate overlapping detections when appropriate
- maintain multiple tags on one source range

Important separation:

```text
semantic detection: 00:37.2 - 00:43.8
editor range:       00:35.2 - 00:46.8
```

The intelligence layer finds the moment. This preparation layer creates useful editorial context.

### 8. Shoot-specific recipe/classifier

Responsibility:
- define what concepts matter for the current shoot type
- route relevant analyzers
- determine organization outputs

Examples:
- restaurant
- event
- interview/talking head

Recipes should be data/config-driven where possible rather than hardcoded throughout the application.

### 9. Media index / project database

Responsibility:
Store durable relationships between:
- source file
- checksum
- project/shoot
- technical metadata
- detected scenes/ranges
- embeddings/index identifiers
- transcript/timecodes
- semantic tags
- confidence/scores
- Resolve references when available

Technology not selected yet.

Prefer a local database simple enough for a single-user Mac app. Do not introduce Elasticsearch solely because Omnishot uses it if a lighter local store is sufficient.

### 10. Resolve bridge

Responsibility:
- create/open project structures when appropriate
- import originals
- set metadata
- create/manage bins where API allows
- create selects timelines
- append exact source ranges via start/end frame references
- add markers
- expose later assistant actions

Preferred implementation:
- official DaVinci Resolve scripting API
- reuse an existing Resolve MCP/API wrapper if it reduces implementation significantly and remains maintainable

Candidates/references:
- current open-source DaVinci Resolve MCP implementations

Rule:
- verify each action against the current Resolve API before depending on it
- use UI automation only for genuine API gaps

### 11. Agent / orchestration layer

Responsibility:
- convert higher-level requests into deterministic tool calls
- follow shoot-specific workflows
- inspect results and verify before making broader changes

Reference pattern:
- Wideframe's agent + skills + media tools
- SynthCut's MCP + `video-editor-pro` inspect -> plan -> edit -> verify approach

The agent should operate deterministic local tools rather than attempt to reason directly over raw files whenever possible.

## Processing order

Current direction:

```text
card inserted
    -> detect / summarize
    -> confirmed ingest destination/project
    -> verified offload
    -> originals declared safe
    -> technical probe
    -> segmentation / transcription / semantic indexing as appropriate
    -> useful semantic ranges
    -> add handles / normalize ranges
    -> shoot-specific classification
    -> Resolve preparation
    -> continued search/assistant features during editing
```

Parallelizing post-offload analysis is desirable where it does not interfere with media safety or machine usability.

## What should not be tightly coupled

Do not make the UI depend directly on:
- one embedding model
- Jina
- Elasticsearch
- one Whisper wrapper
- one Resolve MCP project
- one checksum engine
- one agent provider

Use interfaces/adapters around these boundaries so the best implementation can change after benchmarking.

## Performance target

The primary machine target is Apple Silicon macOS. Local analysis should be benchmarked for:
- indexing speed
- CPU/GPU/ANE use where applicable
- RAM pressure
- thermal impact
- whether Resolve can remain usable while background work runs

No performance numbers should be invented before real testing.