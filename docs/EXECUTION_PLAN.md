# Clip Resolved Execution Plan

This plan is subordinate to `PRODUCT_LAW.md` and drives implementation until every required scenario reaches its required evidence state. Work proceeds by systemic dependency and end-to-end risk, not by whichever screenshot was mentioned most recently.

## Gate 0 — Establish truth and preserve working evidence

Status: in progress

- Keep the existing dirty working tree intact.
- Keep the source-linked semantic query vertical slice as a regression test.
- Baseline current automated suites, installed app, real card inventory, destination capacity, Resolve state, and project records.
- Record every scenario in `SCENARIO_LEDGER.md` without inflating evidence.
- Make `PRODUCT_LAW.md` the first-read authority for every coding agent.

Exit gate: baseline is repeatable; failures and unsupported paths are explicit; no completion claim depends on old chat memory.

## Gate 1 — Make import planning safe, reversible, and obvious

Owning scenarios: S02–S05, S13, S31, S32.

Implementation work:

1. Add an explicit `ImportPlan` domain model separate from mutable scan results.
2. Add undo/redo/reset for take move, multi-move, split, and merge.
3. Keep per-shoot include and destination controls permanently visible in the collapsed card header/summary.
4. Replace tiny/dense type with a documented macOS type scale and larger control metrics.
5. Ensure one bounded expanded shoot at a time; virtualize take cells and thumbnail loading.
6. Add per-shoot filtering, select-all/none, filename/source/capture metadata, and large preview.
7. Show aggregate destination capacity before confirmation: required, available, headroom, shortfall.
8. Make confirmation a project-by-project plan review with explicit `new`, `existing`, and `left on source` sections.
9. Ensure cancel/relaunch before confirmation produces zero filesystem/project changes.

Required proof:

- model tests for undo/redo/reset and exactly-once accounting;
- UI tests at 860×620, default, and large sizes;
- installed-app real 200+ take review with real thumbnails and no endless page;
- mixed synthetic card with at least four shoots routed new/existing/excluded;
- no copy triggered during planning tests.

## Gate 2 — Make copy, verification, recovery, and cleanup production-safe

Owning scenarios: S04, S13–S17, S27, S30.

Implementation work:

1. Fault-injection harness for copy, destination reread, manifest write, registration, and app termination.
2. Persist operation state after each file/stage and expose resume/retry/abandon-safe-copy choices.
3. Guarantee aggregate preflight across all selected destinations before the first byte copies.
4. Define and test collision/dedup identity across devices and project sources.
5. Enrich completion by project/shoot with folders, verified counts, analysis state, and source remainder.
6. Keep cleanup a separate manifest-scoped flow with visible rehash and deletion progress.
7. Add disposable-media tests for wrong card, modified source, changed/missing destination, read-only source, and interrupted cleanup.

Required proof:

- service integration tests on disposable volumes/folders;
- installed-app interrupted/relaunch recovery;
- real partial import with unselected source readback;
- cleanup success and blocked cases on disposable files only;
- manifests and hashes inspected after every run.

## Gate 3 — Make multi-source project assembly work in any arrival order

Owning scenarios: S06–S12, S18, S27–S30.

Implementation work:

1. Persist pending/unmatched sources independently of a project.
2. Implement evidence-backed match candidates with explicit exact/likely/ambiguous thresholds.
3. Prove camera-first, recorder-first, and later-camera routing without duplicate projects.
4. Treat embedded camera audio as immediately usable; treat recorder masters as optional upgrades/additions.
5. Integrate or vendor the researched audio synchronization engine rather than inventing waveform matching.
6. Preserve separate transmitter/channel identity when evidence supports it.
7. Add phone/downloaded/manual-folder flows and keep destination/archive drives excluded from auto-scan.
8. Make source identity automatic where possible and explain ambiguity where not.

Required proof:

- synthetic fixtures for every order/permutation;
- real DJI Mic device run with matching and non-matching samples;
- wrong-project false-match tests;
- relaunch between first and later source;
- project source manifest readback.

## Gate 4 — Complete the footage-intelligence system

Owning scenarios: S18–S25, S28–S30.

Implementation work:

1. Build a durable source-role model: b-roll, on-camera interview, narration, ambient backup, recorder master, unknown.
2. Evaluate real interview/take segmentation and speaker evidence; retain uncertainty.
3. Replace fixed profile output with footage-evidence category proposal while retaining profile priors.
4. Build every applicable automatic package layer, including deduplicated `ALL B-ROLL SELECTS` and exact review complement.
5. Keep query results separate from automatic-package readiness.
6. Add incremental invalidation/rebuild so only new or changed media is analyzed and dependent products are updated.
7. Add quality/coverage evaluation against manually reviewed real projects rather than judging one arbitrary search.

Required proof:

- benchmark corpus across restaurant, gallery/community story, interview, and event/family projects;
- labeled misses/false positives and source-range accuracy;
- multiple-interview/take test;
- narration plus b-roll proof;
- new arbitrary query without re-index;
- later-source incremental update without discarded intelligence.

## Gate 5 — Make Resolve materialization deterministic and idempotent

Owning scenarios: S18–S27.

Implementation work:

1. Persist stable identities for Resolve project, bins, source items, timelines, and package versions.
2. Preview every mutation with the exact project and objects affected.
3. Read back every mutation and reconcile partial/interrupted results.
4. Update existing intended package timelines without accidental duplicates.
5. Keep the main edit isolated unless a separate named action is confirmed.
6. Implement recovery for closed/wrong/unsaved Resolve, frame-rate mismatch, API timeout, and interrupted append.
7. Open/focus the correct project and intended edit or SELECTS timeline and state the editor's next step.

Required proof:

- fake-API failure matrix;
- live Resolve 21.1 runs for create, retry, relaunch, later-source update, and no-op repeat;
- readback proving each original and Resolve object exists exactly once;
- source paths show canonical project media, not rendered derivatives.

## Gate 6 — Make search, preview, chat, and activity trustworthy

Owning scenarios: S23, S24, S27–S32.

Implementation work:

1. Replace successful placeholder thumbnails with real cached frames and explicit loading/failure states.
2. Enlarge the primary preview and include filename, source/device, time range, capture time, and disambiguating path.
3. Label or remove opaque decimal scores.
4. Preserve independent state for simultaneous/recent searches and name the exact timeline each action will create/open.
5. Make deterministic project state the only source for counts/readiness shown to chat.
6. Give Claude a warmer project-aware response contract without templated false certainty; keep direct controls primary.
7. Make Activity a truthful operation/readiness ledger with useful next actions and no fake progress.
8. Finish keyboard, VoiceOver, focus order, reduced-motion, contrast, and both-theme passes.

Required proof:

- duplicate-filename search fixture;
- two-search action association test;
- installed preview playback of handled and full source;
- stale-chat-state regression test;
- visual/accessibility matrix at supported sizes/themes.

## Gate 7 — Clean end-to-end production proof

Owning scenarios: all.

Run through the installed app only:

1. Connect a real multi-shoot camera card.
2. Regroup takes and use undo.
3. Route some shoots to new projects, one to an existing project, and leave at least one on the card.
4. Confirm a partial import that fits available space.
5. Observe copy, verification, registration, and analysis progress.
6. Relaunch and confirm truthful recovery/state.
7. Connect a later camera/phone source and add it to one existing project.
8. Connect a recorder source in a tested arrival order and review project matching/sync evidence.
9. Generate the complete evidence-adaptive package.
10. Prepare/update Resolve after confirmation.
11. Read back media, bins, timelines, source paths, counts, and idempotency.
12. Exercise visual and transcript search and create one new post-index SELECTS timeline.
13. Review completion details and choose either safe cleanup on disposable media or leave the source untouched.
14. Open the intended edit timeline and continue editing without Codex instructions.

Exit gate:

- all required scenario rows have the mandated evidence level;
- the clean run needs no hidden commands or ordinary-step decisions from an agent;
- no original or excluded file is lost;
- user-facing UI is visually approved at actual sizes;
- unsupported cases are explicit and fail safe.

## Work selection rule

At the beginning of each implementation turn:

1. identify the earliest gate with an unmet prerequisite;
2. choose one shared invariant and all neighboring scenario rows it affects;
3. implement it without discarding existing working behavior;
4. run its automated, integration, and installed-app checks;
5. update the ledger with exact evidence;
6. continue to the next unmet invariant instead of declaring the product complete.

User-reported failures always override convenience. They update the law/ledger if they reveal a missing general situation; they do not become one-off special cases.
