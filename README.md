# clip resolved

**clip resolved** is a macOS workflow and footage-intelligence companion for DaVinci Resolve.

The goal is not to replace Resolve. The goal is to remove repetitive work between plugging in a camera card and actually editing, while giving Resolve local semantic footage intelligence that can find, organize, and prepare useful moments from source media.

> **Current status: research and product-design phase. Do not begin implementation from assumptions in this repository until the open workflow decisions in `docs/DECISIONS.md` are resolved.**

## Product direction

The current working concept is one macOS app as the main interaction layer for:

1. Camera-card detection and safe ingest
2. Verified offload of originals
3. Local media analysis and indexing
4. Detection of useful shots and moments inside longer source clips
5. Expansion of detected moments with editable handles
6. Shoot-specific organization of those ranges
7. Preparation of Resolve bins, metadata, selects timelines, and other supported structures
8. Semantic search during editing
9. Resolve automation through supported APIs and scripts

DaVinci Resolve remains the editing environment.

## Core requirement

The system is **not** merely:

`offload -> import everything -> manually search footage`

The stronger target is:

`verified originals -> local analysis -> useful moment detection -> handles -> organized Resolve-ready ranges/selects + untouched originals -> semantic search remains available during editing`

The source media must remain intact. Useful shot ranges should preferably reference the original media rather than create newly rendered duplicate clips.

## Design principles

- Research every workflow stage before locking architecture.
- Do not force a previously discussed tool just because it already exists.
- Prefer local and effectively free processing on Apple Silicon when quality is good enough.
- Different shoot types should use different organization and analysis priorities.
- Keep backend components replaceable so better models and tools can be swapped in later.
- Use official Resolve scripting APIs where possible. Avoid brittle UI automation when a supported API exists.
- The companion app should remove prep work, not move manual prep into another app.

## Reference projects and ideas

These are active references, not mandatory dependencies:

- [Wideframe](https://try.wideframe.com/) for agent-driven editing workflow patterns and skills
- [SynthCut](https://github.com/Relo-video/SynthCut) for local semantic search, Whisper, MCP tooling, and inspect-plan-edit-verify patterns
- [Omnishot](https://github.com/jdarmada/omnishot) for multimodal b-roll search, scene-level indexing, and semantic retrieval
- DaVinci Resolve scripting and MCP projects for direct Resolve automation

## Documentation

- [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md) - product behavior and UX direction
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) - current system architecture and replaceable components
- [`docs/DECISIONS.md`](docs/DECISIONS.md) - accepted decisions, rejected assumptions, and unresolved questions
- [`docs/RESEARCH.md`](docs/RESEARCH.md) - researched tools, repos, workflows, and benchmark plan
- [`docs/HANDOFF.md`](docs/HANDOFF.md) - instructions for the future coding agent

## Current phase

We are still mapping the real Osmo-to-Resolve workflow step by step. The repository should capture decisions as they are made. Implementation starts only after the workflow and first build scope are sufficiently defined.