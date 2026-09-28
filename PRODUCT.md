# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

## Users

Clip Resolved is built first for Jonny, a working editor shooting restaurant interviews, community stories, family events, and social content on a MacBook Pro. He uses DaVinci Resolve Studio and needs to move from several cameras and cards to an organized, editable project without becoming the ingest technician for every shoot.

## Product Purpose

Clip Resolved safely assembles source media into one durable project, analyzes it once, and turns new natural-language requests into exact source-linked moments and Resolve timelines. Success means the editor can ingest or register every source, understand what is ready or missing, review the actual returned footage, and continue editing in Resolve without rendered duplicate selects.

## Positioning

The product combines a persistent multimodal footage index with deterministic Resolve operations. It is not a second NLE and not a one-time automatic classifier: the same indexed source corpus remains queryable throughout the edit.

## Operating Context

- Camera media may arrive on different cards and at different times.
- A project may combine Osmo, iPhone, Insta360 GO Ultra, DJI Mic 2, and other camera/recorder sources.
- Restaurant/community-story edits need interview transcription plus visual b-roll retrieval.
- Family and event edits need a trustworthy chronological record before semantic categories.
- Simultaneously recorded cameras should become a synchronized or multicam source when Resolve and the available audio/timecode evidence support it.
- Resolve remains open during editing and is the authority for Media Pool items and timelines.
- The working project root normally lives under `/Volumes/Extreme SSD/ACTIVE PROJECTS`.

## Capabilities and Constraints

- Protect and preserve original media; verified ingest never erases the card.
- Treat a card as a container that can include more than one shoot.
- Allow later cards and cameras to join an existing project without rebuilding prior index work.
- Detect mounted camera and recorder media automatically, switch to ingest, and run the lightweight read-only session scan without requiring a manual folder-selection step.
- Keep one canonical working copy per source and organize it by source/camera.
- Reuse the integrated SynthCut, VideoHighlighter, SD-Offload, and Resolve implementations.
- Search results must include representative frames, exact time ranges, and in-window playback.
- Resolve SELECTS use original Media Pool items and exact source ranges, never rendered select clips.
- Every professional package includes complete source coverage through a chronological stringout and a review complement.
- Restaurant, interview/community-story, and event projects use different preparation recipes.
- Multicam and external-audio actions must expose their sync method and must not claim successful alignment without Resolve readback or a human review state.
- Cloud conversation may interpret requests, but media judgment and Resolve mutations remain deterministic local operations with visible confirmation.

Open decisions that require real device samples remain the default camera clock-offset policy and the confidence threshold for accepting waveform synchronization automatically.

## Brand Commitments

The product name is Clip Resolved. The app should feel like a precise professional editing companion: calm, direct, source-safe, and native to macOS. It should not resemble a generic chatbot, a toy AI dashboard, or another video editor.

## Evidence on Hand

- The OSAKA project has a real persistent SynthCut index and source-linked Resolve SELECTS.
- Real restaurant/community-story folders and a family-event folder exist on the Extreme SSD.
- Resolve Studio 21.1 is installed and its local official scripting definitions include multicam creation, waveform/timecode sync, and record-frame placement.
- Current app history includes persisted project chat, query evidence, and Resolve actions.
- No durable visual design system existed in the repository before this product record; the existing SwiftUI implementation is evidence, not a finished design authority.

## Product Principles

1. Account for every source before automating editorial judgment.
2. Preserve chronology and originals as the fallback truth.
3. Analyze once, then query and materialize many editorial views.
4. Make sync, confidence, and Resolve mutations visible and reviewable.
5. Validate the real editor-facing result, not only the build or backend command.

## Accessibility & Inclusion

Use native macOS controls, keyboard navigation, VoiceOver labels, semantic colors, scalable text, and layouts that remain operable across the supported window-size range.
