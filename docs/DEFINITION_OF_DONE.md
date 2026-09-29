# Clip Resolved — System Definition of Done

> Concise completion gate for the authoritative behavioral contract in `PRODUCT_LAW.md`. Scenario status and exact proof live in `SCENARIO_LEDGER.md`; implementation order lives in `EXECUTION_PLAN.md`. A conflict is resolved in favor of `PRODUCT_LAW.md`.

## North-star outcome

Clip Resolved is finished only when it is a practical, repeatable, end-to-end production tool that takes the user from newly connected media to a safe, understood, organized, editable DaVinci Resolve project without Codex, a developer, or hidden command-line intervention babysitting the workflow.

The app must own the system:

```text
connect any supported source
  -> detect and identify it without treating every drive as a camera card
  -> propose shoots and likely project relationships
  -> let each shoot independently create a project, join an existing project, or remain on the source
  -> copy only the confirmed selections with capacity checks and checksum verification
  -> preserve and register later camera, phone, download, and recorder sources in the same durable project
  -> understand visual footage, spoken material, takes, and project-specific editorial categories
  -> automatically prepare a complete source-linked SELECTS package
  -> create or incrementally update the same Resolve project without duplicates
  -> clearly show what is ready, stale, running, failed, safe to remove, and still awaiting confirmation
  -> leave the editor in the correct Resolve project and timeline with every original still available
```

Explicit confirmation remains required for ingest, Resolve mutations, and source deletion. Requiring those safety decisions is not babysitting. Requiring a developer to diagnose, route, run, repair, or remember normal workflow state is babysitting and is a product failure.

## This product is not done when

- one narrow vertical slice works but the surrounding workflow requires manual rescue;
- a single search timeline is presented as the automatic organized SELECTS package;
- indexing is presented as footage understanding or editorial readiness;
- narration SELECTS are presented as visual SELECTS;
- a successful backend operation leaves misleading, stale, or ambiguous UI state;
- adding media creates a second project, loses prior intelligence, silently omits files, or duplicates Resolve timelines;
- fixed generic categories replace adaptation to the actual project and footage;
- tests pass but the installed app has not been exercised at real window sizes on real media;
- the user must ask Codex which button, project, source, or timeline is correct during an ordinary run;
- destructive cleanup can proceed without manifest-scoped re-verification and explicit confirmation;
- the app works only for the exact order in which one test project happened to arrive.

## Required source and project situations

The same system must handle, with explicit visible state and recoverable decisions:

1. One camera card containing several unrelated shoots.
2. A card containing shoots for several existing projects plus one or more new projects.
3. Importing only selected shoots because destination capacity is limited, while every unselected file remains untouched on the source.
4. A later card adding camera footage to an existing project while also containing unrelated work.
5. A recorder connected after camera footage, before camera footage, or on another day; unmatched audio remains safely pending and can later attach to the correct project.
6. Multiple recorders, cameras, iPhone media, downloaded folders, and manually chosen existing folders.
7. Camera WAV sidecars that follow their MP4 and never clutter visual take review as independent takes.
8. External hard drives and destination SSDs that must not be automatically treated as ingest cards.
9. Low-space, disconnected-source, unreadable-file, interrupted-copy, interrupted-analysis, closed-Resolve, and relaunch/recovery paths.
10. Explicit post-verification cleanup that deletes only the confirmed manifest files and fails closed if either copy changed.

The app should automatically detect and propose as much as evidence supports. Ambiguous matches must show the evidence and ask once; they must not be guessed silently or offloaded to the user as unexplained setup work.

## Required footage intelligence

For every verified project source, Clip Resolved must preserve one durable multimodal project brain and incrementally extend it rather than starting over.

It must:

- distinguish camera video, embedded audio, recorder audio, interviews, narration, and b-roll;
- transcribe relevant spoken material with source identity and time ranges;
- separate interviews, speakers, takes, false starts, and complete candidate takes when evidence supports it;
- use actual project/footage evidence to propose editorial categories instead of relying only on fixed FOOD/PEOPLE/EXTERIOR recipes;
- create `00 ALL RAW FOOTAGE STRINGOUT`, deduplicated `ALL B-ROLL SELECTS`, project-appropriate category SELECTS, narration/interview SELECTS, and a complete global review remainder as applicable;
- keep all SELECTS source-linked to the canonical originals with useful handles;
- support new semantic and transcript queries later without re-indexing unchanged footage;
- make new camera media visibly stale only the dependent visual products, then update them idempotently;
- never claim creative certainty or identity beyond the evidence.

## Required Resolve behavior

- A Clip Resolved project is durable before Resolve exists.
- Resolve may be created after the first source and updated as later sources arrive.
- Later sources join the same intended Resolve project and source bins.
- Every mutation requires visible confirmation and post-action readback.
- Retrying, relaunching, or rebuilding must not create duplicate projects, bins, media items, or timelines.
- Readiness separately tracks verified copy, index, transcription, automatic visual package, narration/interview SELECTS, sync, Resolve scaffold, and main edit.
- The app must expose the correct next action and open the intended existing timeline rather than asking the user to infer it.
- No SELECTS workflow renders replacement media merely to represent ranges.

## Required user experience

- Real thumbnails and sufficiently large previews make every take identifiable.
- Per-shoot include, destination, naming, merge, move, and split controls are visible where the decision is made.
- Long cards remain bounded through disclosure, scrolling, filtering, and selection rather than an endless page.
- Text, menus, buttons, progress, confirmation, errors, and completion states remain readable and uncropped at actual supported window sizes.
- Every lengthy scan, copy, verification, analysis, Resolve operation, and cleanup action has visible progress and a truthful terminal state.
- Success screens explain exactly what was copied, verified, analyzed, created, left on the source, and safe or unsafe to remove, with useful reveal/open actions.
- Search results show real thumbnails, playable handled ranges, filenames, source/device identity, and enough path context to disambiguate duplicates.
- Accessibility labels exist for every icon-only action.
- Chat is optional. Normal ingest, organization, readiness, and next actions must be understandable through direct interface controls.

## Proof required before claiming completion

Completion requires all of the following, not a subset:

1. Automated tests for invariants, failure recovery, idempotency, routing, and backward-compatible persisted state.
2. Installed-app testing at actual window sizes, including visual inspection for clipping, unreadable text, misleading controls, placeholder imagery, and static-looking progress.
3. A real mixed-device scenario covering a multi-shoot camera card, partial import, later camera source, recorder source, project matching, analysis, automatic SELECTS, Resolve update, relaunch, and safe cleanup decision.
4. Readback proving originals were preserved, selected copies were checksum-verified, unselected source files remained, visual timelines contain video rather than recorder WAVs, and Resolve objects exist exactly once.
5. A clean run performed through the installed app without developer commands or Codex deciding ordinary workflow steps.
6. Honest documentation of any unsupported source, ambiguity, or failure mode that remains.

Until this proof exists, status must be described as partial, in progress, or a validated subsystem—not as the promised product being complete.

## Priority rule for every future task

Every implementation or design task must answer:

1. Which end-to-end scenario and readiness layer does this advance?
2. Does the fix generalize across projects, devices, ordering, retries, and relaunches?
3. What automated and installed-app evidence proves it?
4. Could this change create a misleading success state or require hidden babysitting elsewhere?

A user-reported symptom is evidence of a missing system invariant. Fix the invariant and its neighboring paths, not only the screenshot or one project instance.
