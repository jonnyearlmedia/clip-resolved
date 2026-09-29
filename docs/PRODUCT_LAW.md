# Clip Resolved Product Law

Status: authoritative

This document is the binding product and verification contract for Clip Resolved. It converts the original workflow promise, the historical `Design Osmo DaVinci Workflow` conversation, the Notion source of truth, observed real-card behavior, and subsequent user corrections into testable system rules.

If another repository document, implementation shortcut, mockup, test, or historical milestone conflicts with this document, this document wins unless the user explicitly changes the product goal. `DEFINITION_OF_DONE.md` is the concise completion gate; this file is the complete behavioral law beneath it.

## 1. Product outcome

Clip Resolved must let one editor connect supported media and reach a safe, understood, organized, editable DaVinci Resolve project without needing Codex, a developer, Terminal commands, or hidden manual repair.

The normal workflow is:

```text
connect media
  -> recognize whether it is an ingest source, recorder, ordinary folder, or destination drive
  -> scan read-only and account for every supported file
  -> propose shoots and likely project relationships with evidence
  -> let every shoot independently be imported now or left untouched
  -> let every included shoot independently create a project or join an existing project
  -> copy only confirmed files after aggregate capacity preflight
  -> checksum-verify every copied file and preserve the source
  -> register the source in one durable project brain
  -> analyze new material incrementally
  -> build or update the complete project-appropriate SELECTS package
  -> create or update exactly one intended Resolve project without duplicates
  -> show what happened, what remains, what is safe, and the correct next action
  -> optionally remove only verified imported source files after a separate confirmation
```

The app may require explicit confirmations for copy, Resolve mutation, and deletion. It may not require the user to understand internal architecture, decide routine routing, run commands, or ask an agent what to do next.

## 2. Product boundaries

Clip Resolved is:

- the workflow control plane for ingest, project assembly, media intelligence, readiness, and deterministic Resolve operations;
- a persistent multimodal project brain that is extended whenever new source media arrives;
- a search and SELECTS layer over canonical original media;
- a source-safety system with manifest-scoped cleanup.

Clip Resolved is not:

- a replacement nonlinear editor;
- a card copier with an AI search box;
- a fixed FOOD/PEOPLE/EXTERIOR classifier;
- a chatbot the user must negotiate with to perform ordinary work;
- a system that renders new MP4 files merely to represent SELECTS;
- complete when one project or one vertical slice works with developer assistance.

## 3. Canonical vocabulary

These meanings are stable throughout code, UI, tests, and documentation.

### Source

A mounted device or chosen folder containing media. A source can be a camera card, recorder storage, phone import, downloaded folder, existing media folder, or unsupported/ordinary volume.

### Logical take

A picture source plus its directly related camera-generated media. For DJI Pocket footage, the MP4 is the visible take; a same-take camera WAV and LRF are children. Camera WAV sidecars follow the MP4 during move, split, import, and cleanup and do not appear as independent visual takes.

Recorder masters are separate sources until evidence associates them with camera takes or a project.

### Shoot

A user-reviewable proposed group of logical takes that likely belong together. A source can contain zero, one, or many shoots. Temporal grouping is a proposal, never an irreversible classification.

### Project

The durable container for one real edit. It exists independently of Resolve and can accumulate camera, recorder, phone, downloaded, and manually chosen sources in any arrival order.

### Import plan

The complete pre-confirmation set of per-shoot decisions: included or left on source, name, ownership, destination project, and regrouping edits. It is reversible until confirmation.

### Canonical media

The one verified working copy inside the project root. Resolve and Clip Resolved reference this copy. The original source remains untouched until an optional later cleanup.

### Project brain

The persistent project index containing source identity, metadata, visual embeddings, transcripts, speaker/take evidence, moment ranges, saved queries, readiness, and Resolve materialization state.

### Automatic visual package

The initial complete source-linked editorial preparation appropriate to the actual footage. At minimum, when camera footage exists, it contains:

- `00 ALL RAW FOOTAGE STRINGOUT`;
- deduplicated `ALL B-ROLL SELECTS` when b-roll exists;
- evidence-appropriate category SELECTS;
- interview/narration SELECTS where supported by spoken material;
- `ALL FOOTAGE NOT SELECTED REVIEW` as the exact complement of selected visual ranges.

A single query timeline, an index, or narration-only SELECTS is not the automatic visual package.

## 4. Non-negotiable invariants

### 4.1 Source safety

1. Initial scanning is read-only.
2. No copy starts before explicit confirmation of the visible import plan.
3. Every supported source file is either assigned to exactly one included/excluded logical take or visibly reported as unassigned/unsupported.
4. No original is changed during copy, analysis, indexing, transcription, search, or Resolve preparation.
5. A source file is never deleted merely because a copy command returned success.
6. Cleanup is a distinct action, names the exact scope, re-verifies source identity and every destination hash, and fails closed before the first deletion if any item is uncertain.
7. Unselected shoots, unsupported files, and unassociated recorder files are never included in cleanup.

### 4.2 Per-shoot independence

Every proposed shoot has controls at the shoot itself for:

- include this shoot now / leave it on the source;
- shoot/project name;
- Personal or Client ownership;
- create a new project / add to one named existing project;
- review takes;
- select one or many takes;
- move selected takes to another shoot;
- split selected takes into a new shoot;
- merge the whole shoot into another compatible shoot.

There may be an `Import all` shortcut, but there is no global destination that silently overrides every shoot. Long cards use bounded disclosure and virtualized scrolling. The primary page never expands hundreds of take cards at once.

Regrouping changes are preview-only until confirmation. The user must have Undo and Redo for move, split, and merge, plus a clearly labeled reset-to-scan option. Relaunching before confirmation must not create files or projects.

### 4.3 Partial import and capacity

1. Importing one shoot while leaving every other shoot untouched is a first-class path.
2. Aggregate destination capacity is calculated only from included shoots, including verification headroom, before the first copy.
3. The UI shows required, available, and shortfall on the actual destination in readable units.
4. If capacity is insufficient, nothing starts and the app explains which included shoots can be deselected.
5. If interruption occurs after some files were verified, the journal makes the partial state explicit and a retry resumes or safely deduplicates it.
6. Confirmation text states how many shoots create new projects, how many join existing projects, how many remain on the source, and total bytes to copy.

### 4.4 Source classification and automatic detection

1. Known removable camera cards and supported recorder storage may trigger a read-only scan automatically.
2. Destination SSDs, ordinary external hard drives, project roots, backup drives, and broad user storage are not treated as camera cards solely because they contain media.
3. Manually chosen folders are supported without pretending they are removable cards.
4. Device/source identity is inferred from structure, metadata, filenames, and known volume evidence when possible. The user should not have to type `Osmo` merely to make the workflow work.
5. Ambiguous identity is represented as an evidence-backed choice, never an unexplained text field or a silent guess.
6. Unsupported devices remain mounted and untouched, with a useful explanation and manual-folder fallback.

### 4.5 Project matching and source arrival order

The following arrival orders are equivalent supported workflows:

- camera only;
- camera then recorder;
- recorder then camera;
- later camera card then later recorder;
- phone/downloaded media before or after camera media;
- multiple cameras and recorders in any order.

Matching uses evidence such as capture windows, source manifests, file counts, device identity, user-confirmed project context, and waveform evidence. Exact matches may be preselected with their evidence shown. Likely or ambiguous matches require one local confirmation. A weak match never silently joins a project.

Camera-only media must already yield a usable Resolve project using embedded audio. Recorder media is an upgrade or additional source, not a prerequisite for basic editability.

### 4.6 Durable incremental intelligence

1. Each project has one brain that is extended, not replaced, when new media arrives.
2. Unchanged files are not re-embedded or retranscribed.
3. Changed or new files stale only dependent products.
4. Visual indexing, transcription, take/interview separation, source matching, category generation, and Resolve materialization have separate readiness states.
5. Readiness is based on durable evidence and readback, not the existence of a button press or a chat claim.
6. The system must distinguish camera b-roll, on-camera interviews, narration/voice-over, embedded audio, camera ambient backups, and independent recorder masters.
7. When evidence supports it, the system separates speakers, interviews, false starts, and complete candidate takes. It never invents a person's identity.
8. Project categories come from footage and project evidence. Profile recipes are priors, not fixed truth.
9. The project remains queryable with new visual and transcript requests without re-indexing unchanged media.

### 4.7 Complete editorial preparation

For each project, the app determines the applicable preparation layers:

- chronological raw coverage;
- visual b-roll coverage;
- interview/topic/take coverage;
- narration/voice-over coverage;
- event/reaction/ceremony coverage;
- sync and multicam coverage where supported.

Every selected range references an original canonical media item and retains useful handles. Category overlap is allowed. The global review remainder is the exact source-frame complement of the union of selected visual ranges. Recorder WAVs never appear as visual b-roll.

The app does not claim creative certainty. It exposes review and can learn project-specific preferences without hiding the complete source record.

### 4.8 Resolve determinism

1. Resolve creation is optional until the editor is ready, but project state exists beforehand.
2. Every Resolve mutation has a plain-language preview and explicit confirmation.
3. The app reads back the current Resolve project, frame rates, bins, media, timelines, and resulting item counts after mutation.
4. Retrying, relaunching, or updating later media does not create duplicate projects, bins, media items, or timelines.
5. Later sources join the same intended Resolve project and update only stale preparation.
6. Existing user edit timelines are never replaced or edited without a separate explicit action naming that timeline.
7. The app opens or focuses the correct project/timeline and says where the editor should begin.
8. Closed Resolve, wrong project, unsaved project, frame-rate mismatch, API failure, and partial mutation produce recoverable states rather than misleading success.

### 4.9 Operational truth and progress

Every operation longer than an immediate interaction exposes:

- what is running;
- current stage;
- determinate file/byte progress when knowable, otherwise an indeterminate state;
- the specific current file or task when useful;
- cancel/stop behavior where safe;
- a terminal success, partial, blocked, cancelled, or failed state;
- a retry or next action.

Idle is neutral, never a full green progress bar. `Ready`, `Indexed`, `Transcribed`, `Visual package current`, `Resolve prepared`, and `Edit ready` are different states.

### 4.10 Completion and cleanup result

The verified-copy result is a project-by-project summary, not several shoots compressed onto one line. Each project/shoot shows:

- destination;
- files and bytes copied;
- checksum status;
- indexing/transcription status;
- Resolve status;
- what remains on the source;
- whether cleanup is available;
- `Open Project Folder`, `Open in Clip Resolved`, and appropriate Resolve action.

Cleanup displays live re-verification and deletion progress. Completion states exactly what was removed and what remains. If cleanup is not chosen, the app says the source is unchanged and can be ejected or retained as appropriate.

### 4.11 Search and preview

Search results show:

- a real representative thumbnail;
- a sufficiently large playable handled range;
- filename;
- device/source label;
- capture time and source time range;
- enough normalized path context to distinguish duplicate filenames;
- match evidence or score explained in human terms when exposed;
- whether the result is visual, transcript, or combined evidence.

Opaque decimal scores are never presented without a label and explanation. Preview is large enough to judge focus, action, framing, and content. Placeholder stripes are loading/failure states only, never a successful result.

Two different searches preserve distinct result sets and proposed timeline names. A Resolve action always names the exact search and timeline it will materialize.

### 4.12 Project Chat

Chat is optional and conversational, but it is not operational authority. Live project state comes from deterministic app data. Claude may interpret intent, explain evidence, propose searches, and stage supported actions. It may not invent counts, claim mutations, or use stale prompt context as current truth.

Normal project setup, ingest, readiness, next steps, visual package creation, and cleanup remain usable through direct controls without chat.

### 4.13 Visual and accessibility floor

1. The primary target is a MacBook Pro at common working window sizes; minimum supported size is explicitly tested.
2. Body text, metadata, controls, badges, menus, and status text are readable without leaning in. Dense information does not justify tiny type.
3. Native controls, keyboard navigation, focus indicators, VoiceOver labels, semantic colors, reduced motion, and sufficient contrast are required.
4. Icon-only controls have visible help and accessibility labels.
5. Menus and dropdowns never clip or extend beyond their window/screen bounds.
6. Real-thumbnail grids are lazy/virtualized and do not decode full-resolution frames synchronously during scrolling.
7. The UI is inspected in both themes and at minimum, default, and large window sizes before release.

## 5. Required scenario families

Each scenario receives an executable fixture or real-device run, a stable ID, expected state transitions, and saved evidence. Variations inside a family are additional test rows, not excuses to omit the family.

### S01 — Single clean camera shoot

One camera card, one shoot, embedded audio, optional camera WAV/LRF children, new project.

### S02 — Multi-shoot card to new projects

Several unrelated shoots on one card; each independently named and routed to a new project.

### S03 — Mixed new and existing projects

One card contains media for multiple existing projects and at least one new project. Every shoot chooses its own destination.

### S04 — Partial import under limited capacity

Only selected shoots fit. Included shoots copy and verify; excluded shoots and children remain untouched and excluded from cleanup.

### S05 — Regrouping and undo

Move one take, multi-select move, split into new shoot, merge whole shoot, undo/redo every action, reset scan, and verify each video is assigned exactly once with its sidecars.

### S06 — Later camera card

Add new camera footage to an existing project while unrelated shoots on the same card route elsewhere or remain on the card.

### S07 — Recorder after camera

Camera project already exists; supported recorder is detected and matched using evidence; narration/interview audio joins the correct project.

### S08 — Recorder before camera

Recorder source is safely registered or pending; later camera media produces an evidence-backed match without creating a duplicate project.

### S09 — Unmatched and ambiguous recorder

No confident match or several candidates. The app shows evidence and keeps audio pending until one confirmation.

### S10 — Multiple recorders and cameras

Two paired microphones, optional third standalone recorder, multiple cameras, channel identity uncertainty, high/low-confidence sync results, and no silent false match.

### S11 — Phone and downloaded media

iPhone/Photos export and downloaded/manual folders can join an existing project without pretending to be camera cards or requiring fake device names.

### S12 — Ordinary external drive

A destination SSD or media archive mounts. It does not auto-scan as a camera card. Manual folder selection still works.

### S13 — Insufficient space

Required, available, and shortfall are correct for the selected destinations; no file is copied before the user changes the plan.

### S14 — Copy interruption and relaunch

Disconnect, app termination, and read error at multiple points. Journal recovery reports verified, incomplete, and retryable work without duplicate copies.

### S15 — Changed duplicate and filename collision

Identical existing destination deduplicates; different content with the same filename never overwrites; UI explains resulting canonical names and identity.

### S16 — Cleanup success

Only imported manifest files are removed after full re-verification. Excluded shoots and unrelated card files remain.

### S17 — Cleanup blocked

Wrong card, modified source, missing/changed destination, read-only source, or incomplete journal blocks all deletion before the first unlink.

### S18 — Camera-only edit readiness

The project can be prepared and edited using embedded audio without waiting for recorder masters.

### S19 — Spoken narration with b-roll

Narration takes are transcribed and separated while visual footage independently produces full b-roll SELECTS and review coverage.

### S20 — Multiple interview takes

Several complete and false-start takes across one or more speakers produce inspectable transcript/take candidates without invented identity.

### S21 — Event/family chronology

Chronological source truth, reactions, ceremony, speakers, and ambient material are organized without inheriting restaurant categories.

### S22 — Evidence-adaptive visual package

An art gallery, restaurant, family event, and interview project each produce relevant categories and no obviously irrelevant fixed taxonomy.

### S23 — New post-index query

A phrase unknown during ingest returns source ranges without re-indexing unchanged footage and can create a uniquely named timeline after confirmation.

### S24 — Two searches in one session

Results, previews, selected ranges, and Resolve actions remain associated with the correct query and timeline.

### S25 — Later-source package update

New camera media marks visual products stale, updates them idempotently, preserves prior sources, and leaves each Resolve object exactly once.

### S26 — Resolve unavailable or wrong

Closed Resolve, wrong open project, unsaved project, frame-rate mismatch, API timeout, and interrupted append are detected before or recovered after mutation.

### S27 — Relaunch persistence

Projects, sources, intelligence readiness, pending import/cleanup recovery, saved searches, chat memory scope, and Resolve actions restore truthfully.

### S28 — Duplicate filenames and source identity

Results from different devices/folders with the same filename remain visually and textually distinguishable.

### S29 — Empty and audio-only project

The app never calls an empty or audio-only project visually ready. It exposes appropriate spoken-audio readiness and next action.

### S30 — Unsupported or corrupt media

Unreadable, corrupt, unsupported, and permission-blocked items are surfaced and accounted for; supported items are not silently omitted.

### S31 — Window, theme, keyboard, and VoiceOver

Every primary workflow is operable at minimum/default/large sizes, in both themes, by keyboard, and with useful VoiceOver labels and focus order.

### S32 — Long-card performance

At least 250 video takes plus children remain responsive; take review is bounded, lazy, and previews do not turn into an endless import page.

## 6. Evidence law

No feature or scenario is `passed` without the evidence appropriate to its risk:

1. domain/unit test for pure invariants;
2. service/integration test for filesystem, persistence, process, and Resolve adapter behavior;
3. installed-app interaction test for state transitions and direct controls;
4. screenshot/visual inspection for anything visible;
5. real-device/media run for hardware, mounted-volume, decoding, waveform, performance, Resolve, and destructive-safety claims;
6. readback of resulting files, hashes, project records, media items, timelines, and source preservation.

Build success proves only that the app builds. A mocked Resolve API proves only adapter behavior. A real backend command proves only that backend path. A manually repaired project proves nothing about app autonomy.

## 7. Completion ledger states

Every scenario in `SCENARIO_LEDGER.md` uses one of:

- `NOT TESTED` — no current evidence;
- `AUTOMATED ONLY` — automated invariant/integration evidence exists;
- `APP SMOKE` — installed app path was exercised, but not the full real scenario;
- `REAL PASS` — installed app completed the real scenario with saved readback evidence;
- `BLOCKED` — a named external dependency or unsupported capability prevents completion;
- `REGRESSION` — previously passed evidence now fails.

Only `REAL PASS` satisfies a proof gate that calls for real hardware/media. No narrative wording may silently promote a lesser state.

## 8. Current truth

As of 2026-09-29, Clip Resolved has substantial working subsystems and passing automated tests. It has not completed the clean installed-app mixed-device proof required by this law. The product is in progress, not finished.

The next priority is not a new isolated feature. It is to close the earliest failing scenario/invariant in the execution plan, preserve existing working behavior as regression coverage, and continue until the full clean run passes.
