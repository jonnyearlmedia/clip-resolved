# Wideframe Intelligence Benchmark

> System priority: intelligence quality is part of the installed-app completion contract in `DEFINITION_OF_DONE.md`. Fixed categories or one successful query do not satisfy footage understanding.

Wideframe is a product-quality benchmark for clip resolved's footage-understanding layer, based on direct user experience.

## Required capability level

clip resolved must not stop at a one-time ingest taxonomy or a fixed set of prebuilt SELECTS timelines.

The analyzed footage should become a reusable multimodal corpus that supports both automatic initial organization and **new semantic requests after ingest**.

Examples of benchmark behavior observed in Wideframe:

- distinguish interview footage from b-roll
- separate multiple interviews
- use transcription to understand/name interview subjects when the footage provides that context
- understand broad visual content beyond literal filenames/metadata
- chat over the indexed footage
- create new selects on demand that were not part of the original ingest plan
- answer queries such as `all the luxury cars` and return matching source moments

## Architectural implication

The initial automatic SELECTS timelines are only the first materialized views of the footage index.

The canonical intelligence layer must preserve enough information to later generate additional views without re-ingesting footage:

```text
verified source media
        ↓
multimodal index
├── visual embeddings / semantic frames
├── transcript + timestamped words/segments
├── shot / moment ranges
├── framing / quality / people signals
├── semantic labels and descriptions
└── source-path + exact timestamp mapping
        ↓
initial SELECTS timelines
        +
on-demand semantic queries
        ↓
new SELECTS timelines / source ranges in Resolve
```

Example:

```text
User: "give me all the luxury cars"

clip resolved searches the existing index
        ↓
returns matching handled source ranges
        ↓
optionally creates:
SELECTS / LUXURY CARS SELECTS
```

No full re-analysis should be required for ordinary post-hoc semantic queries after the visual/transcript index exists.

## Interview intelligence

Interview-heavy shoots should use transcription as a first-class signal, not just optional subtitles.

The system should be able to:

- identify separate interview/talking segments
- preserve exact transcript timestamps
- search by what a person said
- associate an interview with a person's name when the transcript/context provides reliable evidence
- keep each interview logically separable from b-roll and other speakers

Do not invent identity when the evidence does not support it.

## Automatic intelligence begins during ingest

The editor should not need to know the right search terms before the product has
explained what arrived. After each selected source is copied and verified, the
project intelligence pipeline should update incrementally:

1. identify the source role (camera, dedicated recorder, scratch audio, or unknown)
2. transcribe speech-bearing sources with source-local timecodes
3. separate speakers, recording sessions, complete takes, false starts, setup
   chatter, and silence while preserving uncertainty
4. cluster spoken material by topic or interview question
5. rank candidate takes using completeness, delivery, audio quality, and visual
   usability without hiding alternates
6. relate the spoken spine to visual coverage and identify missing or weak
   coverage
7. propose the output that fits the evidence: verbatim stringout, topic-sorted
   interview selects, narration spine, alternates, b-roll coverage selects,
   multicam, or a review queue

These are proposals, not irreversible conclusions. A later recorder or camera
card may change the source-role assignment, speaker map, topic structure, sync
evidence, and recommended outputs. The intelligence record must therefore be
incremental, source-linked, confidence-aware, and reversible.

Current public Wideframe material reinforces this distinction: transcription is
followed by speaker labeling, topic clustering, take ranking, and editable native
NLE output. A transcript is evidence; it is not itself the prepared edit. Clip
Resolved should preserve separate review stringouts, story assemblies, and
alternates so the editor can override its judgment without returning to an
unorganized source folder.

Required behavior for the Andaan-type case:

- a dedicated recorder added after camera footage supersedes scratch audio as
  the preferred narration/interview source without discarding either source
- the full clean narration take is proposed as an exact source-linked range
- false starts and setup chatter remain available as alternates/review material
- visual searches are derived from the narration's actual concepts
- no Resolve timeline is created until the user confirms the visible proposal

## Product principle

Wideframe-level behavior is the target experience:

**analyze once, understand deeply, query repeatedly.**

VideoHighlighter's region-building/quality logic and SynthCut's local semantic/transcript/search implementations are building blocks toward this benchmark, not the final ceiling.

Do not reduce clip resolved to CLIP category tagging. The end product needs multimodal footage reasoning and on-demand SELECTS generation.

## Review experience requirements

A text list of filenames and timecodes is not a complete footage-chat experience. Search results must let the editor:

- see a representative frame from each returned range
- play the original source beginning at that range
- scrub surrounding source context
- understand which query or transcript evidence caused the match
- keep or reject individual ranges before materializing a collection
- refine the request conversationally without losing the prior result set
- retain the result and its named NLE action after app relaunch

Current implementation provides thumbnails, handled-range playback with source-context scrubbing, persisted result evidence, and durable Resolve actions. Remaining benchmark work includes individual include/exclude and in/out adjustment, cross-query collections, local visual descriptions explaining matches, find-similar from a chosen frame, and richer multimodal interview reasoning.
