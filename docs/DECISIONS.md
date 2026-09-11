# Decisions

This file is the authoritative log of product and technical decisions for **clip resolved**.

Do not silently turn an unresolved question into an implementation assumption. When a decision changes, record the new decision and why.

## Accepted decisions

### Resolve remains the editor

**Decision:** clip resolved will not become a replacement NLE.

DaVinci Resolve remains the primary editing, color, audio, and timeline environment. clip resolved handles ingest orchestration, media intelligence, organization, search, and supported Resolve automation.

### One main interaction layer is preferred

**Decision:** The current preferred UX is one macOS app as the user's primary control layer from card ingest through editing assistance.

This does not mean one monolithic backend. The app should orchestrate replaceable engines and tools underneath.

### Protect camera originals first

**Decision:** Verified offload precedes semantic analysis as the authoritative working path.

Do not rely on analysis directly from the microSD as the main workflow. After verified offload, analysis can run from the working copy.

### Preserve originals

**Decision:** Detected shots/moments do not replace the original media.

The system should retain full source clips and preferably represent extracted editorial moments as source-time ranges rather than rendered derivative files.

### Semantic moment extraction is part of the core concept

**Decision:** The footage-intelligence goal is more than search.

The system should be capable of identifying useful moments within longer source clips, expanding those detections with handles/minimum duration, and preparing organized Resolve-ready ranges/selects.

### Search remains available during editing

**Decision:** Natural-language and similarity search are additional editing tools after indexing.

Search should not become a mandatory manual review stage before footage reaches Resolve.

### Different shoot types require different recipes

**Decision:** Do not design one universal semantic taxonomy.

Restaurant, event, interview/talking-head, and future workflows may emphasize different categories, analyzers, and outputs.

### Prefer local/free media intelligence

**Decision:** Prefer on-device processing on Apple Silicon when quality is sufficient.

Cloud analysis is allowed as an optional/fallback path only when it provides a material benefit in accuracy or capability.

### Open-source code should be reused aggressively

**Decision:** Do not rebuild solved open-source components for originality's sake.

Priority order:
1. use an existing dependency
2. fork/adapt
3. extract/reuse a focused implementation
4. reimplement only for a concrete reason

License and attribution requirements must be respected. The repository is public, so copied/derived code must be compatible with how this repository is distributed.

### No forced Omnishot dependency

**Decision:** Omnishot is a candidate/reference, not the chosen footage engine.

Its ideas and code can be reused if they win on accuracy, integration, local cost, and maintainability.

### Keep Wideframe and SynthCut as active references

**Decision:** Continue studying both.

- Wideframe: workflow architecture, agent/skills patterns, deterministic media tools, verification loops
- SynthCut: open-source local media intelligence, CLIP, Whisper, MCP tool design, inspect-plan-edit-verify patterns

### AI detection boundaries are not edit boundaries

**Decision:** Add editorial context around detected moments.

The system should support pre/post handles, minimum range duration, and later configurable behavior rather than clipping exactly to model detections.

### Prefer official Resolve APIs

**Decision:** Use DaVinci Resolve's supported scripting APIs for project/media/timeline operations when available.

Reuse existing Resolve wrappers/MCP projects when useful. UI automation is a fallback for genuine API gaps, not the default.

## Rejected assumptions

### "Import everything, then manually search for clips"

Rejected as the primary workflow.

The target is automatic prep of useful moments and organization, with search available in addition.

### "Omnishot is the product backend"

Rejected.

The desired capability is semantic footage intelligence. The implementation remains open.

### "Build every backend ourselves"

Rejected.

Proven open-source code is preferred when suitable.

### "One bin taxonomy fits every shoot"

Rejected.

Shoot-specific recipes are required.

### "Analyze from the camera card because it is already mounted"

Rejected as the default authoritative workflow.

Media safety and verified offload come first.

## Open decisions

### Ingest

- Which verified offload engine should be used or adapted?
- Is one working copy enough for the user's normal workflow, or should a second backup destination be default/optional?
- What verification level is appropriate by default?
- Should the app auto-detect known destination drives?
- What exact interaction happens immediately after an Osmo card is inserted?
- When is a card officially marked safe to erase/eject?

### Project structure

- What filesystem folder structure should be created?
- How should projects/shoots be named?
- How are multi-card or multi-camera shoots represented?
- Does a new card join an existing shoot automatically based on date/project?

### Resolve timing

- When is the Resolve project created?
- Should originals import immediately after verified offload while analysis continues?
- Should organization update incrementally as analysis completes?
- How should the system behave if Resolve is closed during processing?

### Resolve organization

- Which information belongs in physical bins?
- Which belongs in metadata/keywords?
- Which belongs in Smart Bins?
- Which belongs in selects timelines?
- Can one semantic range cleanly appear in multiple useful organizational views without duplication problems?

### Shot detection and handles

- Which segmentation method works best on actual Osmo footage?
- Default pre-handle length?
- Default post-handle length?
- Minimum usable range duration?
- Should handles differ for b-roll, events, interviews, or slow motion?
- How should overlapping or adjacent semantic detections merge?

### Semantic engine

- Which local visual model performs best on real shoots?
- Is frame/image embedding enough, or does true temporal/video/audio embedding materially improve results?
- Which licenses are acceptable for code/models included in this public repository?
- What local index/database is simplest and fast enough?

### Quality ranking

- Should v1 merely classify/find footage or also attempt to rank "best" shots?
- If ranking, what measurable signals should be used?
- How should subjective ranking remain inspectable/reviewable?

### Transcription

- Which shoot types automatically transcribe?
- Which Whisper implementation/model is appropriate on the target Mac?
- What transcript data should be written into Resolve versus stored only in clip resolved?

### App vs Resolve panel

- Which interactions belong in the standalone Mac app?
- Would an in-Resolve Workflow Integration improve search/assistant use enough to justify a second UI surface?
- Can the standalone app focus/jump Resolve reliably through supported APIs?

### Agent autonomy

- Which actions can the assistant perform immediately?
- Which actions need preview/approval?
- Should the agent ever modify the main edit timeline, or initially only create/select auxiliary bins/timelines/markers?
- What verification loop is required after agent actions?

### Background processing

- How much analysis can run while Resolve is editing without hurting performance?
- Should processing pause/throttle automatically when Resolve is under load?
- Can Apple Silicon acceleration be used for chosen local models?

## Decision template

When adding a decision, use:

```text
### Decision title

Status: accepted | rejected | superseded
Date: YYYY-MM-DD

Decision:
...

Why:
...

Alternatives considered:
...

Consequences:
...
```
