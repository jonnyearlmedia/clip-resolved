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
- shot/framing classification using sparse samples, face fraction, motion, brightness, and sharpness

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

## Always-on foundation

These are cheap/useful enough to run for essentially every verified visual clip:

1. `ffprobe` source metadata
2. source-direct local CLIP/visual index
3. scene/change analysis as a **boundary hint**, not a definition of a shot
4. sparse framing analysis from VideoHighlighter `shot_type.py`
   - close subject / subject / wide
   - face presence/fraction
   - camera/frame change amount
   - brightness
   - sharpness
5. VideoHighlighter candidate-region construction/merging
6. cheap quality measurement such as median Laplacian sharpness

### Quality policy

Blur/sharpness should begin as a **penalty / review signal**, not an absolute reject.

Intentional motion blur, rack focus, whip moves, or brief soft starts can still be useful with handles. Hard rejection should be reserved for obviously unusable ranges after real-footage testing.

## Default shoot profiles

### Restaurant / commercial social b-roll

**Primary signals**

- CLIP semantic visual index/search
- shot/framing analysis
- scene/change boundaries
- sharpness/quality signal
- face/person presence where useful

**Secondary signals**

- generic object detection only for classes it actually knows reliably, such as people and common objects
- motion/change evidence as supporting information

**Off by default**

- action recognition
- audio-peak scoring
- Whisper/transcript

Reasoning:

- VideoHighlighter's own detector guide recommends CLIP first for scene, setting, framing, and general visual meaning.
- YOLO's built-in vocabulary is limited to its trained classes; restaurant-specific concepts such as a particular dish or plating state are not guaranteed.
- Action recognition is only useful when the desired category is truly temporal and is inside Kinetics-400 or a custom trained model. Do not spend compute on it by default.
- handheld Osmo camera movement can create strong motion deltas that are not automatically useful moments, so motion peaks should not dominate selection.

Example semantic categories that can be queried after one CLIP index:

- food / plated dish / food close-up
- drink / cocktail
- chef / staff / customer / people
- food preparation / cooking scene
- exterior / storefront
- interior / dining room
- signage / logo
- detail / texture / close-up
- wide establishing shot

These are runtime queries, not permanently trained categories.

### Event coverage

Keep the restaurant foundation, then enable selectively:

- audio peaks for applause, cheers, laughter, crowd reactions
- Whisper/transcript when speeches/interviews matter
- stronger person/face presence signal
- motion peaks at low-to-moderate weight for obvious bursts of activity

Do not automatically equate loud or high-motion with good. They are candidate generators/supporting evidence.

### Interview / talking footage

Primary:

- Whisper transcript + timestamped search
- silence/dead-air analysis
- face/subject framing
- sharpness/quality

Secondary:

- CLIP for visual cutaways and framing labels
- scene changes when actual edits/camera changes exist

Motion/action/object scoring should normally be low priority here.

### Personal / travel / family footage

Use the same visual foundation and dynamically enable:

- faces/people
- audio peaks for reactions
- CLIP scene queries
- transcript when spoken moments matter

No universal fixed category list is required.

## Why CLIP is the main semantic layer

VideoHighlighter's detector guide makes an important distinction:

- CLIP is good for **whole-scene / framing / appearance semantics** and embeds frames once, after which additional text queries are nearly free.
- object detection is better for small discrete trained objects.
- action recognition is better when the category is defined by movement over time.

For clip resolved, the source-direct SynthCut CLIP/ONNX implementation remains a strong reuse candidate for the primary semantic index. VideoHighlighter can contribute the higher-level detector routing and region logic.

The semantic layer should answer both:

- **what is this moment?**
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

Exact handle defaults remain to be tuned on real footage.

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

## Editor-workflow validation

This output matches established Resolve editing behavior rather than inventing a proprietary organization system:

- editors commonly build stringouts/selects timelines from long b-roll sources
- stacked/source timelines are then used to pull selections into the real edit
- rough in/out points are intentionally generous and refined later

clip resolved is automating the logging/selects pass, not replacing the editor's final trim decisions.

## Licensing note

VideoHighlighter is AGPL-3.0. Because clip resolved is currently a public repository and is a personal tool, direct reuse remains viable, but the implementation must preserve the upstream license obligations.

Before vendoring source into the repository, decide whether to:

- keep VideoHighlighter-derived code as an AGPL-covered component/subprocess
- make clip resolved compatible with the AGPL obligations
- or selectively use alternative permissive components where distribution goals justify it

Licensing is not a reason to independently reinvent the algorithm.

## Next implementation test

The next useful milestone is not another architecture document. It is a real-footage benchmark:

1. take representative Osmo restaurant/event source clips
2. build the CLIP index
3. run sparse shot/framing + sharpness analysis
4. run scene/change analysis
5. feed those signals into the reused VideoHighlighter region builder
6. classify resulting regions with a restaurant/event semantic query set
7. apply provisional handles
8. inspect what percentage of genuinely useful shots were found and how much junk was included

Tune only from those misses/false positives.
