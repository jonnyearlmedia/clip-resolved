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

## Whole-repo reuse is the default

When an open-source repository already implements a major portion of a required stage, **do not treat it merely as inspiration or a reference implementation. Start by assuming we will use the actual repository/code.**

Preferred behavior:

- clone/vendor/fork the actual open-source repo
- preserve as much of its working implementation as possible
- disable/remove only pieces that conflict with clip resolved
- add thin adapters around it
- patch the smallest possible surfaces for Jonny's workflow
- keep upstream history/license/attribution intact where appropriate

A coding agent must **not** read an OSS repo, understand how it works, then rewrite an equivalent subsystem from scratch unless there is a concrete technical reason the existing code cannot be used.

If two or more repos solve different stages well, chaining those repos together is preferred over replacing them with a bespoke unified implementation.

## Priority order

For every capability:

1. **Use/vendor the existing open-source repository substantially unchanged.**
2. **Fork it and make the minimum required modifications.**
3. **Extract its existing subsystem/code directly** when bringing the full repo is impractical.
4. **Wrap multiple existing projects behind one adapter/UI.**
5. **Write new code only for integration gaps or genuinely unsolved behavior.**

Do not recreate a working algorithm by guessing how it might work when source code already exists and is suitable.

## Current ingest implication

For ingest, the likely implementation should be built by directly reusing code from the repos already inspected rather than authoring a new ingest engine:

- **KontentManager**: card detection, card browsing/previews, targeted/bulk selection, project reassignment, sidecar grouping, verified atomic import, dedup
- **SD-Offload**: manifest/journal safety model and `WipeGate` destructive-cleanup safeguards
- **FilmCan**: mature copy/verification concepts and potentially reusable copy-engine pieces where they improve on the above

The intended task is to combine/adapt these working implementations into clip resolved's UX, **not reproduce their behavior independently**.

## Examples relevant to later stages

Potentially reusable rather than rebuilt:

- FFmpeg / ffprobe for media processing and technical metadata
- PySceneDetect or another existing shot-boundary implementation
- SynthCut's local CLIP/ONNX semantic-search implementation if it performs well enough
- Omnishot's existing scene/index/search code if parts outperform alternatives
- whisper.cpp / existing Whisper wrappers for transcription
- existing local vector/index libraries rather than inventing one
- existing DaVinci Resolve MCP/API wrappers instead of rebuilding hundreds of API calls
- Wideframe's publicly documented workflow/skill ideas as product/agent inspiration, but not proprietary code

## Glue code is the product-specific code

The code that may actually need to be unique to clip resolved is mostly orchestration and workflow behavior, for example:

- identifying the user's Osmo card and project
- proposing multi-day/multi-project session groups
- routing groups into Personal/Client project folders
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

- "I implemented our own offload engine" when KontentManager / SD-Offload / FilmCan already provide working implementations to reuse
- "I implemented our own scene detector" when PySceneDetect already satisfies the requirement
- "I wrote a custom video metadata parser" when ffprobe already provides the needed data
- "I made a basic semantic-search prototype" when a tested open-source implementation can be reused directly
- "I recreated the Resolve API wrapper" when an existing wrapper already exposes the needed calls

Before implementing a subsystem from scratch, the coding agent must document why the actual source code from existing open-source candidates could not be reused.

## Licensing

Reuse must still comply with upstream licenses and attribution requirements.

Because this GitHub repository is currently public, license compatibility matters for code committed into it. This does **not** change the product philosophy. It only determines whether a component is:

- vendored directly
- forked
- used as a dependency
- kept as a separate process/service
- incorporated under compatible terms

Do not reject a useful open-source project merely because it is copyleft without first checking the actual license obligations and whether keeping it as a separate component satisfies the intended personal-tool architecture.

Never copy proprietary/private source code or bypass licensing/access controls. Publicly available open-source source code is the intended reuse target.

## Benchmark before replacing

Do not rewrite an open-source component based on vibes. If an alternative is proposed, compare it on the user's actual footage/workflow and switch only when it materially improves accuracy, speed, reliability, integration, or usability.