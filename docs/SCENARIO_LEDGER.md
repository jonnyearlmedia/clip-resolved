# Clip Resolved Scenario Ledger

This ledger is the executable status companion to `PRODUCT_LAW.md`. Evidence must include the exact test/run artifact. A checkbox, build, or source inspection is not evidence by itself.

Last audited: 2026-09-29

| ID | Scenario | Current state | Evidence today | Missing proof |
|---|---|---|---|---|
| S01 | Single clean camera shoot | AUTOMATED ONLY | scan/offload/index/Resolve unit and fake-API tests | clean installed-app real-card run |
| S02 | Multi-shoot card to new projects | APP SMOKE | installed app shows 7 proposed shoots and independent cards; re-scanned same real card via CLI after today's Gate 1/6 fixes, reproduced identical 201 videos / 7 groups / 0 unassigned / 0 issues | confirm into disposable destinations and read back |
| S03 | Mixed new and existing projects | AUTOMATED ONLY | per-shoot routing tests | installed-app mixed card with several real destinations |
| S04 | Partial import under limited capacity | AUTOMATED ONLY | routing/capacity tests; real destination has less free space than full source | real selected-only ingest and source readback |
| S05 | Regrouping and undo | APP SMOKE | move/split/merge/sidecar tests plus installed-app split 7→8 and Undo 8→7 on the real card | installed multi-move/merge/redo/reset matrix at all target sizes |
| S06 | Later camera card | NOT TESTED | partial incremental project support exists | app flow, staleness, package update, Resolve readback |
| S07 | Recorder after camera | AUTOMATED ONLY | recorder match/transcription tests | real DJI Mic device run through installed app |
| S08 | Recorder before camera | NOT TESTED | project-first model exists | pending-source and later-match app flow |
| S09 | Ambiguous/unmatched recorder | AUTOMATED ONLY | rejection test | installed evidence/review UI and persistence |
| S10 | Multiple recorders/cameras | NOT TESTED | Resolve API exposes sync/multicam paths | real multi-device samples and false-match testing |
| S11 | Phone/downloaded media | AUTOMATED ONLY | source identity test | installed import and project routing run |
| S12 | Ordinary external drive | AUTOMATED ONLY | drive exclusion tests | repeated live mounts and manual-folder fallback |
| S13 | Insufficient space | AUTOMATED ONLY | aggregate headroom test | installed UI with readable required/available/shortfall |
| S14 | Copy interruption/relaunch | NOT TESTED | journal primitives exist | fault injection at copy/verify/register/analyze stages |
| S15 | Duplicate/collision | PARTIAL | dedupe/collision code exists | explicit integration tests and UI result language |
| S16 | Cleanup success | AUTOMATED ONLY | manifest-scoped disposable-file test | installed disposable-card run with visible progress |
| S17 | Cleanup blocked | AUTOMATED ONLY | changed destination blocks deletion | wrong card, changed source, missing destination, read-only cases |
| S18 | Camera-only readiness | PARTIAL | embedded audio and Resolve scaffold exist | clean app run without recorder attached |
| S19 | Narration plus b-roll | APP SMOKE | Andaan has narration and visual package in Resolve | repeat from raw sources without Codex/CLI assistance |
| S20 | Multiple interview takes | NOT TESTED | timed transcript search exists | take-boundary/speaker evaluation on real interview footage |
| S21 | Event/family chronology | AUTOMATED ONLY | event chronology and profile tests | real family/event package audit |
| S22 | Evidence-adaptive package | PARTIAL | `propose_categories()` built (workflow.py), gates fixed-profile + general-vocabulary candidates on real multi-asset evidence instead of asserting them blindly; unit-tested with fake embeddings; real dry-run against the live OSAKA index at a stricter threshold correctly dropped FOOD/DRINKS and kept SAKE BOTTLES/JAPANESE FOOD for a real Japanese-market shoot — one real project, not the required set | four-project real benchmark (restaurant, gallery/community story, interview, event/family), human review of proposed vs. correct categories, default-threshold tuning from that data (still opt-in via --adaptive, not the default path) |
| S23 | New post-index query | REAL PASS (subsystem) | OSAKA arbitrary query and Resolve source-range proof; re-ran a fresh unplanned query ("people walking through a market") against the real OSAKA index after today's fixes, still returns real timestamped source hits | preserve as regression; not full product proof |
| S24 | Two searches in one session | NOT TESTED | saved query structures exist | UI association and exact Resolve action test |
| S25 | Later-source package update | NOT TESTED | readiness can become stale | idempotent package/Resolve update implementation and run |
| S26 | Resolve unavailable/wrong | AUTOMATED ONLY | rate/unsaved/interrupted-empty-timeline tests | installed UI recovery for every failure path |
| S27 | Relaunch persistence | PARTIAL | project/chat/cleanup recovery code exists | full state/recovery app run |
| S28 | Duplicate filename identity | PARTIAL | paths/source labels available in models | search-card visual verification with duplicate names |
| S29 | Empty/audio-only project | AUTOMATED ONLY | readiness test coverage | installed activity/project UI proof |
| S30 | Unsupported/corrupt media | AUTOMATED ONLY | unreadable scan test | installed mixed-readable/corrupt source test |
| S31 | Window/theme/keyboard/VoiceOver | APP SMOKE | live default-window inspection and some labels | minimum/large sizes, both themes, keyboard and VoiceOver pass |
| S32 | Long-card performance | APP SMOKE | real 201-video card scans and displays | instrument scroll/thumbnail responsiveness at 250+ takes |

## Current executed evidence

- Real read-only scan of `/Volumes/SD_Card`: 201 videos, 200 audio files, 94 sidecars, 168,130,268,309 bytes, 7 proposed groups, zero unassigned sidecars, zero scan issues.
- `/Volumes/Extreme SSD`: approximately 119 GiB available during the audit; the full source does not fit with safe headroom, so partial import is a real required path.
- Swift suite: 42 tests passed, including grouping Undo/Redo/Reset with sidecar preservation.
- Python suite: 45 tests passed.
- Installed app was visually inspected at its current 1228×768 window on Project, Import Media, Footage Search, Project Chat, and Activity.
- Rebuilt installed app rendered real thumbnails for Shoot 2; a real proposed take was split and then undone, restoring 7 shoots and 201/201 assigned videos. A final read-only rescan cleared the temporary history; zero shoots remain selected.
- No ingest, Resolve mutation, cleanup, or card deletion was triggered during this audit.

## Rules for updating this ledger

1. Never replace a missing proof with optimistic prose.
2. Link or name the exact automated test, screenshot, manifest, log, or readback artifact.
3. A real pass must say which app build, source/device, destination, project, and Resolve version were used.
4. After a code change, rerun every scenario whose invariant or shared component changed.
5. Any user-discovered ordinary-workflow failure immediately demotes the affected scenario and neighboring shared-invariant scenarios until re-proven.
