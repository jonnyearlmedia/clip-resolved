# Assembly Strategy

## Default implementation philosophy

**clip resolved should be assembled from proven open-source tools whenever possible.**

This is a personal workflow tool. Originality of implementation has no value by itself. If an existing open-source project already solves a component well, the preferred approach is to reuse that implementation and connect it to the rest of the pipeline with the smallest amount of glue code necessary.

The ideal end state may legitimately be several open-source projects chained together behind one coherent macOS UI.

Example shape:

```text
card inserted
  -> existing card/offload engine
  -> existing checksum verification
  -> ffprobe / existing metadata parser
  -> existing scene detector
  -> existing semantic-search implementation
  -> existing Whisper implementation
  -> small clip-resolved range/handle logic
  -> existing Resolve API/MCP wrapper
  -> DaVinci Resolve
```

That is considered a **success**, not technical debt, if the pieces are reliable and maintainable.

## Priority order

For every capability:

1. **Use an existing open-source project unchanged** if it fits.
2. **Vendor or fork it and make small changes** if integration requires them.
3. **Extract the useful subsystem/code** if the full project is unnecessary.
4. **Wrap multiple projects behind one adapter/UI** if that gives the user one coherent workflow.
5. **Write new implementation code only for the gaps** or when existing solutions fail real requirements.

Do not recreate a working algorithm by guessing how it might work when source code already exists and is suitable.

## Examples relevant to this project

Potentially reusable rather than rebuilt:

- FilmCan or another proven offload/checksum implementation for card ingest
- FFmpeg / ffprobe for media processing and technical metadata
- PySceneDetect or another existing shot-boundary implementation
- SynthCut's local CLIP/ONNX semantic-search code if it performs well enough
- Omnishot's scene/index/search implementation if parts outperform alternatives
- whisper.cpp / existing Whisper wrappers for transcription
- existing local vector/index libraries rather than inventing one
- existing DaVinci Resolve MCP/API wrappers instead of rebuilding hundreds of API calls
- Wideframe's publicly documented workflow/skill ideas as product/agent inspiration, but not proprietary code

## Glue code is the product-specific code

The code that may actually need to be unique to clip resolved is mostly orchestration and workflow behavior, for example:

- identifying the user's Osmo card and project
- choosing which existing analyzers run for each shoot type
- translating semantic detections into useful editorial ranges
- adding pre/post handles and minimum durations
- merging overlapping detections
- mapping tags/ranges to the preferred Resolve organization
- coordinating progress/state across several underlying tools
- presenting all of it as one clean Mac app
- storing the user's project-specific index and preferences

## Avoid unnecessary rewrites

A coding agent should **not** say things like:

- "I implemented our own scene detector" when PySceneDetect already satisfies the requirement
- "I wrote a custom video metadata parser" when ffprobe already provides the needed data
- "I made a basic semantic-search prototype" when a tested open-source implementation can be reused directly
- "I recreated the Resolve API wrapper" when an existing wrapper already exposes the needed calls

Before implementing a subsystem from scratch, the coding agent must document why existing open-source candidates were insufficient.

## Licensing

Reuse must still comply with upstream licenses and attribution requirements.

Because this GitHub repository is currently public, license compatibility matters for any code committed into it. This does **not** change the product philosophy. It only determines whether a component is:

- included directly
- used as a dependency
- kept as a separate process/service
- forked under compatible terms
- replaced by another open-source implementation

Do not reject a useful open-source project merely because it is not permissively licensed without first checking whether it can legally remain a separate component in the personal-tool stack.

## Benchmark before swapping

Do not rewrite an open-source component based on vibes. If an alternative is proposed, compare it on the user's actual footage/workflow and switch only when it materially improves accuracy, speed, reliability, integration, or usability.