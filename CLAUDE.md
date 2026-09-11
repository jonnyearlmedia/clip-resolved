# CLAUDE.md — clip resolved

Read `AGENTS.md` first. It is the primary coding-agent contract for this repository.

Then read the project documents in the order listed there before material implementation work.

## Critical Claude Code rules

- Do not make Jonny re-explain product decisions already documented in the repo.
- Do not replace inspected OSS systems with fresh custom implementations just because writing new code feels cleaner.
- Do not ask whether basic engineering hygiene is wanted (Git, tests, CI, state files, logging, safe rollback, etc.). Use sensible defaults.
- Do not stop all work because one credential, Resolve version detail, model, or external dependency is missing. Continue every independent task and surface the blocked edge clearly.
- Do not require Jonny to manually edit `.env` files. If credentials are later needed, provide a simple first-run/input flow.
- Treat real-footage validation as the authority for thresholds and quality, not invented constants.
- Keep source media non-destructive.
- Keep Resolve SELECTS as source ranges into originals, not newly rendered MP4s.
- Treat the Wideframe-like persistent footage intelligence layer as the core product, not merely automatic initial bins.

## First implementation objective

Before polishing the full app, prove the vertical slice described in `docs/IMPLEMENTATION_HANDOFF.md`:

`real Osmo media → persistent multimodal index → semantic query → exact source ranges → handled ranges → Resolve SELECTS timeline`

A successful implementation must also support a query that was not predefined during ingest (for example, `all the luxury cars`) without rebuilding the entire corpus.
