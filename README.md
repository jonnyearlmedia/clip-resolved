# clip resolved

**clip resolved** is a macOS workflow and footage-intelligence companion for DaVinci Resolve.

The goal is not to replace Resolve. The goal is to remove repetitive work between plugging in a camera card and actually editing, while giving Resolve local semantic footage intelligence that can find, organize, and prepare useful moments from source media.

> **Current status: implementation has started. A first local vertical slice now exists for source indexing, semantic search, handled moment creation, and Resolve SELECTS timeline generation.**

## Core target

The product benchmark is Wideframe-style footage understanding:

**analyze once, understand deeply, query repeatedly.**

That means clip resolved should support both automatic initial organization and brand-new later requests such as:

- `food shots`
- `all the luxury cars`
- `show me wide shots of the restaurant interior`
- transcript-driven interview searches

without rebuilding the full footage corpus for every new query.

## Current implemented vertical slice

```text
local source folder
  -> ffprobe metadata
  -> SynthCut actual CLIP image embeddings
  -> persistent SQLite visual index
  -> arbitrary text query using SynthCut actual text embeddings
  -> VideoHighlighter actual region-building functions
  -> clip-resolved editorial handles
  -> Resolve MCP actual connection helper
  -> DaVinci Resolve SELECTS timeline via exact source ranges
```

No detected select is rendered into a replacement MP4.

## Quick start for Claude Code / Codex / local development

Read [`AGENTS.md`](AGENTS.md) first.

Then:

```bash
bash scripts/bootstrap_upstreams.sh
source .venv/bin/activate
clip-resolved doctor --deep
```

The bootstrap script pulls exact inspected upstream commits for:

- `Relo-video/SynthCut`
- `Aseiel/VideoHighlighter`
- `samuelgursky/davinci-resolve-mcp`

These are working code dependencies, not merely references.

Example local test:

```bash
clip-resolved index \
  --project-root "/path/to/Test Project" \
  --source "/path/to/Test Project/Media/Osmo"

clip-resolved search \
  --project-root "/path/to/Test Project" \
  "all the luxury cars"

clip-resolved moments \
  --project-root "/path/to/Test Project" \
  "all the luxury cars"

clip-resolved selects \
  --project-root "/path/to/Test Project" \
  "all the luxury cars"
```

The final command changes the currently open Resolve project and should first be tested in a disposable project.

## Product direction

The complete product still includes:

1. Camera-card detection and safe ingest
2. Mixed-card temporal grouping and user confirmation
3. Verified offload into the final portable project root
4. Local multimodal footage analysis and indexing
5. Detection of useful moments inside long source clips
6. Expansion of moments with editorial handles
7. Shoot-specific initial SELECTS timelines
8. Arbitrary later semantic/transcript queries
9. Resolve-side search/selects companion UI
10. Safe project portability/relink/archive behavior

DaVinci Resolve remains the editing environment.

## OSS-first rule

Implementation originality has no value here.

If public OSS already works, use the actual code: clone it, copy it, vendor it, fork it, or patch it directly. Do not rewrite working systems merely to make them look native to clip resolved.

Current major upstream implementations include:

- [SynthCut](https://github.com/Relo-video/SynthCut) for local semantic video intelligence and transcript/search pieces
- [VideoHighlighter](https://github.com/Aseiel/VideoHighlighter) for useful-moment region construction, framing, quality, and detection logic
- [DaVinci Resolve MCP](https://github.com/samuelgursky/davinci-resolve-mcp) for tested Resolve scripting/control
- [KontentManager](https://github.com/SoCloseSociety/kontentmanager) for later verified ingest/card workflow reuse
- [SD-Offload](https://github.com/t0nyz0/SD-Offload) for later safe card-cleanup logic

Wideframe is the product-quality benchmark for footage understanding, not a source-code dependency.

## Documentation

- [`AGENTS.md`](AGENTS.md) — mandatory coding-agent source of truth
- [`CLAUDE.md`](CLAUDE.md) — Claude Code-specific entrypoint
- [`docs/IMPLEMENTATION_HANDOFF.md`](docs/IMPLEMENTATION_HANDOFF.md) — what is implemented, how to run it, what to test next
- [`docs/PRODUCT_SPEC.md`](docs/PRODUCT_SPEC.md) — product behavior
- [`docs/INGEST_FLOW.md`](docs/INGEST_FLOW.md) — locked ingest flow
- [`docs/RESOLVE_PROJECT_FLOW.md`](docs/RESOLVE_PROJECT_FLOW.md) — Resolve/project portability rules
- [`docs/WIDEFRAME_BENCHMARK.md`](docs/WIDEFRAME_BENCHMARK.md) — footage-intelligence quality target
- [`docs/MOMENT_EXTRACTION.md`](docs/MOMENT_EXTRACTION.md) — useful-moment strategy
- [`docs/ASSEMBLY_STRATEGY.md`](docs/ASSEMBLY_STRATEGY.md) — aggressive OSS reuse strategy
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — broader architecture

## What still requires Jonny's Mac

This environment cannot run his local Resolve instance or real Osmo footage. The next local session needs to validate:

- semantic retrieval quality on actual footage
- indexing throughput / RAM pressure
- VideoHighlighter region grouping quality
- Resolve source-frame boundary behavior
- direct Media Pool path matching/import behavior
- the first real generated SELECTS timeline

After that test, tune from actual misses and false positives instead of adding more theory.
