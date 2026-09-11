# Wideframe Intelligence Benchmark

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

## Product principle

Wideframe-level behavior is the target experience:

**analyze once, understand deeply, query repeatedly.**

VideoHighlighter's region-building/quality logic and SynthCut's local semantic/transcript/search implementations are building blocks toward this benchmark, not the final ceiling.

Do not reduce clip resolved to CLIP category tagging. The end product needs multimodal footage reasoning and on-demand SELECTS generation.