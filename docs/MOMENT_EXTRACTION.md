# Useful Moment Extraction

## Goal

The core job is not merely scene detection. clip resolved must turn long raw Osmo source files into **useful editorial source ranges** that can be placed non-destructively into Resolve SELECTS timelines with handles.

The system should be generous enough to act like an assistant pulling selects, not ruthless like an automatic final-cut/highlight generator.

## Primary OSS baseline: VideoHighlighter

`Aseiel/VideoHighlighter` is the current strongest open-source baseline for the middle of this pipeline.

Its free AGPL-3.0 code already combines multiple signals including:

- scene/change detection
- motion events
- motion peaks
- audio peaks
- object detections
- action sequences
- transcript/keyword matches
- clip-quality signals such as blur penalties
- local visual/CLIP search

Most importantly, `modules/auto_segments.py` already implements the region-building logic we need:

1. convert point signals into time regions
2. use natural start/end bounds for action/transcript/scene signals
3. cluster nearby points
4. optionally snap candidate regions toward scene boundaries
5. merge overlapping / near-adjacent regions
6. enforce minimum/maximum durations
7. preserve provenance explaining why a region exists
8. rank regions using score and score density

Do not rewrite this logic from scratch.

## Key adaptation for clip resolved

VideoHighlighter is designed to create a short highlight reel under a target duration budget. clip resolved is building **editorial selects**, so its final selection policy should differ.

Reuse the candidate-region engine, but do not default to its `select_regions(... target_duration ...)` behavior as the final filter.

clip resolved should instead keep a generous set of usable candidate moments and expose confidence/status, because the editor still makes the final creative decision.

Suggested states:

- strong / approved-by-model candidate
- secondary / review candidate
- rejected only for clear technical/usability reasons

The default should favor recall over ruthless highlight compression.

## Signal stack

### Always-on foundation

- `ffprobe` metadata from the actual verified source
- local visual sampling / embeddings
- scene/change boundaries
- basic motion/continuity signals
- technical-quality checks where cheap and reliable

### Shoot-aware signals

Use additional detectors when they fit the shoot:

- transcript/Whisper for interviews, speeches, dialogue-heavy events
- audio peaks for reactions/events where audio carries meaning
- object/action detection for visual b-roll and event footage
- face/person signals when people are a meaningful category

Do not force every expensive analyzer onto every shoot.

## Semantic layer

Use the existing SynthCut local CLIP/ONNX implementation as a strong candidate for semantic visual indexing/search rather than relying on VideoHighlighter's entire model stack for every semantic task.

The semantic layer should help answer both:

- **what is this moment?** (food, exterior, chef, customer, signage, detail, etc.)
- **where else is something similar?**

A moment may carry multiple semantic labels and may appear in multiple SELECTS timelines.

## Boundaries versus handles

Keep two concepts separate:

1. **detected useful region** — the model's best estimate of where the meaningful action/content lives
2. **editorial handled range** — the range actually placed into Resolve, expanded before/after the detected region

The detection engine may already apply small context padding while building candidate regions. That is not a substitute for the explicit editorial handle policy.

Example:

```text
model region:      00:37.2 -> 00:44.1
editorial handles: 00:35.2 -> 00:47.1
```

Exact handle defaults remain to be tuned on Jonny's real footage.

## No derived MP4 requirement

Candidate moments should remain timestamp ranges into the verified original media.

Do not render separate MP4 files for each detected moment unless a specific downstream component requires temporary derived media for analysis.

Resolve output should use source references/ranges through its scripting API:

```text
MediaPoolItem + startFrame + endFrame
```

## Resolve output

After moment extraction + semantic classification:

```text
SELECTS/
├── FOOD SELECTS
├── PEOPLE SELECTS
├── EXTERIOR SELECTS
├── INTERIOR SELECTS
└── DETAILS SELECTS
```

Each timeline contains handled source ranges referencing the original Media Pool items.

The exact category set is shoot-specific. Do not create empty universal categories.

## Licensing note

VideoHighlighter is AGPL-3.0. Because clip resolved is currently a public repository and is a personal tool, direct reuse remains viable, but the implementation must preserve the upstream license obligations.

Before vendoring source into the repository, decide whether to:

- keep VideoHighlighter-derived code as an AGPL-covered component/subprocess
- make clip resolved compatible with the AGPL obligations
- or selectively use alternative permissive components where distribution goals justify it

Licensing is not a reason to independently reinvent the algorithm.

## Next design/test question

Benchmark this candidate-region engine on Jonny's actual Osmo footage and determine:

- which signals improve useful-select recall for restaurant/event/social footage
- what minimum/maximum moment duration feels editorially useful
- how aggressively nearby evidence should merge
- what confidence threshold separates primary selects from review candidates
- what pre/post handle defaults produce comfortable editing room
