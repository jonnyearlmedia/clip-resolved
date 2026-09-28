# clip resolved

**clip resolved** is a macOS workflow and footage-intelligence companion for DaVinci Resolve.

The goal is not to replace Resolve. The goal is to remove repetitive work between plugging in a camera card and actually editing, while giving Resolve local semantic footage intelligence that can find, organize, and prepare useful moments from source media.

> **Current status:** the local macOS app covers card/folder discovery, shoot confirmation, checksum-verified ingest, project creation, visual indexing, timed transcripts, arbitrary search, persistent project chat/memory, shoot-aware SELECTS packages, and source-linked Resolve timelines.

## Core target

The product benchmark is Wideframe-style footage understanding:

**analyze once, understand deeply, query repeatedly.**

That means clip resolved should support both automatic initial organization and brand-new later requests such as:

- `food shots`
- `all the luxury cars`
- `show me wide shots of the restaurant interior`
- transcript-driven interview searches

without rebuilding the full footage corpus for every new query.

## Implemented workflow

```text
camera card or existing footage folder
  -> read-only scan + temporal shoot proposals
  -> user naming/classification/merge/split confirmation
  -> SHA-256 copy + uncached destination re-read + durable manifest
  -> final project Media/Osmo originals
  -> live Resolve project + minimal bins + portable .drp snapshot
  -> SynthCut CLIP visual index and optional SynthCut/Whisper transcripts
  -> arbitrary later visual or spoken-word queries
  -> VideoHighlighter region grouping + configurable handles
  -> shoot-aware category package + complete raw-footage stringout
  -> DaVinci Resolve SELECTS timeline with exact original source ranges
```

No detected select is rendered into a replacement MP4.

## Run the Mac app

Read [`AGENTS.md`](AGENTS.md) first.

Then:

```bash
bash scripts/bootstrap_upstreams.sh
source .venv/bin/activate
clip-resolved doctor --deep
./script/build_and_run.sh
```

The bootstrap script pulls exact inspected upstream commits for:

- `Relo-video/SynthCut`
- `Aseiel/VideoHighlighter`
- `samuelgursky/davinci-resolve-mcp`
- `SoCloseSociety/kontentmanager`
- `t0nyz0/SD-Offload`

These are working code dependencies, not merely references.

The app bundle is created at `dist/Clip Resolved.app`. Keep DaVinci Resolve Studio open on the saved project you intend to change before creating SELECTS. The app refuses to modify an unsaved Resolve project.

## Project Chat and memory

The **Project Chat** workspace uses the Claude Code installation already authenticated on this Mac. A Claude Max subscription works through Claude Code; no Anthropic API key is required by Clip Resolved.

Claude interprets the request into a narrow structured action. Clip Resolved performs the actual local index search and Resolve operation through its existing deterministic backends. Claude receives project status, saved preferences, recent conversation text, and timestamp evidence returned by the local search. It does not receive the original MP4 files.

Chat history and memory survive app relaunches. Memory is visible and editable, with separate scopes for:

- **All projects** — durable editing/workflow preferences
- **This project** — project goals, client requirements, and known facts

Explicit requests to change pre-roll, post-roll, or minimum SELECTS duration update the same persisted defaults shown in Settings, so remembered operational preferences affect later searches and timelines.

Searches run immediately. Any action that changes Resolve is shown as a pending action and requires an explicit **Confirm in Resolve** click. The app does not use Claude's own tools or let it directly modify files or Resolve.

## CLI equivalent

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

clip-resolved smart-selects \
  --project-root "/path/to/Test Project" \
  --profile restaurant
```

Optional embedded-audio transcription:

```bash
clip-resolved transcribe --project-root "/path/to/Test Project" --source "/path/to/Test Project/Media/Osmo"
clip-resolved transcript-search --project-root "/path/to/Test Project" "welcome to the event"
clip-resolved transcript-selects --project-root "/path/to/Test Project" "welcome to the event"
```

The `index` command runs once per source change. New search wording does not re-index footage. SELECTS reference original MP4s; no replacement video is rendered.

Every visual or transcript SELECTS creation also creates a paired `<QUERY> NOT SELECTED` review timeline by default. The second timeline is the exact source-frame complement of the handled SELECTS ranges across the complete indexed source set, including whole clips with no match. Together the pair accounts for the full source corpus without rendering or hiding footage. Pass `--no-remainder` only when that review timeline is intentionally unwanted.

The restaurant smart package creates, in `00 TIMELINES / SELECTS`:

- `00 ALL RAW FOOTAGE STRINGOUT`, containing every indexed original once in source order
- `FOOD SHOTS SELECTS`
- `EXTERIOR STOREFRONT SELECTS`
- `INTERIOR DINING ROOM SELECTS`
- `DRINKS SELECTS`
- `SIGNAGE LOGO SELECTS`
- `JAPANESE FOOD CLOSE UPS SELECTS`
- `SAKE BOTTLES SELECTS`
- `ALL FOOTAGE NOT SELECTED REVIEW`, the exact complement of the union of all category ranges

The stringout is the single long all-raw timeline for delivery/export. Category timelines are organized editorial views, and the global review timeline exposes anything the semantic categories did not select. All three forms reference the same original MP4s; Clip Resolved does not render or upload them automatically.

DaVinci Resolve remains the editing environment. Clip Resolved prepares originals, indexes, handled source ranges, and auxiliary SELECTS; it does not replace the NLE.

## OSS-first rule

Implementation originality has no value here.

If public OSS already works, use the actual code: clone it, copy it, vendor it, fork it, or patch it directly. Do not rewrite working systems merely to make them look native to clip resolved.

Current major upstream implementations include:

- [SynthCut](https://github.com/Relo-video/SynthCut) for local semantic video intelligence and transcript/search pieces
- [VideoHighlighter](https://github.com/Aseiel/VideoHighlighter) for useful-moment region construction, framing, quality, and detection logic
- [DaVinci Resolve MCP](https://github.com/samuelgursky/davinci-resolve-mcp) for tested Resolve scripting/control
- [KontentManager](https://github.com/SoCloseSociety/kontentmanager) for media/sidecar recognition during card scans
- [SD-Offload](https://github.com/t0nyz0/SD-Offload) for Disk Arbitration card detection, SHA-256 I/O, and crash-safe journal primitives

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

## Safety boundaries

- Camera/card sources are read-only during scanning, indexing, and normal ingest.
- A destination file is accepted only after SHA-256 copy and destination re-read verification.
- Unknown card files are ignored and preserved.
- Resolve mutations stop on an unsaved project or frame-rate mismatch.
- Card erasure is not automatic. The current app deliberately leaves source media intact.
