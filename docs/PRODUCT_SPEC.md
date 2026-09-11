# Product Spec

## Product

**clip resolved** is a macOS companion app for camera ingest, local footage intelligence, and DaVinci Resolve workflow automation.

The product should reduce the time between finishing a shoot and reaching a useful, organized editing state in Resolve.

## Primary user flow

The workflow begins when a microSD card containing Osmo footage is inserted into the Mac.

The current intended direction is:

1. Detect the inserted camera card.
2. Identify the card and summarize its media.
3. Let the user choose or confirm the project and shoot type when needed.
4. Perform a verified offload to the working destination, with backup behavior determined by the final ingest policy.
5. Keep camera originals untouched.
6. Analyze the verified working media locally when practical.
7. Detect meaningful shots or moments inside source clips.
8. Expand detected moments with configurable handles and minimum usable durations.
9. Classify and organize those ranges according to the current shoot type.
10. Prepare useful Resolve structures such as bins, metadata, markers, Smart Bins, and selects timelines where supported and beneficial.
11. Keep the entire original shoot available in Resolve.
12. Continue to provide semantic search and assistant actions while editing.

The user should not have to manually review every clip in a separate companion app before Resolve becomes useful.

## Core media model

A source clip may contain multiple semantically useful moments.

Example:

```text
DJI_0188.MP4
00:12-00:18  exterior establishing shot
00:37-00:44  chef plating food
01:05-01:11  customer reaction
```

The intelligence layer can identify those moments, but AI detection boundaries should **not** automatically become final edit boundaries.

The preparation layer should be able to add context:

```text
00:10-00:21  Exterior
00:35-00:47  Food
01:03-01:14  People / Reactions
```

The extra time is an editable handle around the semantic moment.

### Requirements

- Never destructively modify the original source media.
- Prefer references to source time ranges over newly rendered duplicate clips.
- Handle length should eventually be configurable by shoot type or user preference.
- Minimum usable segment duration should prevent tiny AI detections from becoming useless edit fragments.
- A single source range may have multiple tags or semantic categories.

## Shoot-specific behavior

The product should not assume one universal organization taxonomy.

### Restaurant content

Possible useful concepts include:

- food
- drinks
- chef / preparation
- customers
- exterior
- interior
- signage
- details
- atmosphere

### Events

Possible useful concepts include:

- speaker
- crowd
- ceremony
- reactions
- networking
- venue
- details

### Interview / talking head

Visual categorization may be secondary to:

- transcription
- topic segmentation
- transcript search
- usable takes
- long pauses / dead air
- filler words
- speaker changes

These are examples only. Final shoot types and schemas must come from the user's real work rather than assumptions.

## Semantic search

Search is an editing accelerator, not a required pre-import review stage.

Examples:

- `chef using torch`
- `wide exterior with customers`
- `close-up of restaurant sign`
- `people laughing`
- `shots similar to this frame`

Useful result actions may include:

- jump to source moment
- reveal source file
- find similar
- tag or classify
- send to an existing selects timeline
- create a new selects collection
- append a result with handles

## Resolve relationship

DaVinci Resolve remains the editor and primary timeline environment.

clip resolved may prepare and manipulate supported Resolve structures, but should not become a second full NLE.

Potential Resolve-side outputs include:

- original-media bins
- metadata and keywords
- Smart Bins
- semantic/category bins
- source-range based selects timelines
- markers
- transcript/topic markers
- project and timeline creation where useful
- render/export automation where later justified

Each operation must be verified against the current official Resolve scripting API before implementation.

## Interaction model

The current preferred direction is one macOS app as the main control layer.

### Ingest state

When a supported card is inserted, the app may surface:

- card / camera identification
- clip count
- total size
- technical summary such as frame rates and orientations
- project selection
- shoot type
- working destination
- backup destination or status
- ingest / verification status

### Processing state

After verified offload, the app may show background work such as:

- metadata scan
- scene / shot segmentation
- transcription where relevant
- semantic indexing
- classification
- Resolve preparation

The user should not need to babysit every stage.

### Editing companion state

While Resolve is being used, the app may provide:

- semantic search
- similar-shot search
- shoot collections
- assistant commands
- Resolve actions
- analysis / indexing status

Whether some of this belongs inside a Resolve Workflow Integration instead of the standalone app remains open.

## Product principles

- **Protect originals first.** Media safety outranks automation convenience.
- **Automate prep, not judgment blindly.** AI can find and organize, but detected boundaries and subjective quality rankings should remain reviewable.
- **Local first.** Prefer local Apple Silicon processing when accuracy and speed are acceptable.
- **Replaceable engines.** Ingest, segmentation, embeddings, transcription, agent, and Resolve bridge should not be tightly coupled.
- **Different shoots, different logic.** Restaurant, event, interview, and future workflows can use different analysis recipes.
- **No forced dependency.** Omnishot, SynthCut, Wideframe, or any other project is a reference or candidate until benchmarking proves it belongs.
- **No second editor.** Resolve remains the place where editing happens.

## Non-goals for the first implementation

- Replacing DaVinci Resolve
- Generating destructive derivative files for every detected shot
- Uploading all footage to cloud AI by default
- Building a custom ingest copy engine before proven alternatives are evaluated
- Letting an agent make broad creative timeline changes before permissions and verification behavior are designed

## Open product questions

See `DECISIONS.md` for the authoritative unresolved list. Major product questions currently include:

- exact ingest UX and backup policy
- project/folder naming
- timing of Resolve project creation
- bins vs Smart Bins vs metadata vs selects timelines
- default handles and minimum shot lengths
- how automatic "best shot" ranking should be
- standalone app vs partial in-Resolve panel
- level of autonomous Resolve modification allowed