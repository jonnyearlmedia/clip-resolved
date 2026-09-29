---
name: Clip Resolved
description: A warm, precise native macOS workspace for ingest, footage intelligence, project chat, and Resolve preparation.
source:
  project: "Claude Design 65ade083-5ddb-4664-840e-78958f4a3474"
  files:
    - "Clip Resolved App.dc.html"
    - "support.js"
colors:
  dark-background: "#0F0D0C"
  dark-card: "#1A1715"
  dark-bar: "#161311"
  dark-surface: "#211D1A"
  dark-surface-alt: "#2A2521"
  dark-text: "#F3ECE3"
  accent: "#5B8CFF"
  success: "#7FC488"
  warm: "#F0A860"
  danger: "#E2685F"
typography:
  ui-reference: "Manrope"
  metadata-reference: "IBM Plex Mono"
  native-implementation: "San Francisco and the system monospaced design"
rounded:
  thumbnail: "6px"
  control: "8px"
  surface: "10px"
  message: "12px"
spacing:
  compact: "8px"
  control: "12px"
  section: "20px"
  page: "28px"
---

# Design System: Clip Resolved

## Creative direction

Clip Resolved follows the imported Claude Design project, adapted to the real native macOS product rather than treated as a static web mockup. The visual character is a warm, near-black editorial console with compact controls, blue primary actions, monospaced source metadata, and restrained status colors.

The design must support the full product that now exists:

- automatic removable-card detection and read-only scanning
- temporal shoot grouping and naming
- verified offload into portable projects
- multiple cameras and recorder sources added at different times
- local visual indexing and later arbitrary searches
- transcript search when transcripts are available
- project chat with local memory and preferences
- source-linked Resolve bins, SELECTS packages, NOT SELECTED coverage, audio sync, and multicam
- an in-window source-range preview inspector

Matching the old artifact never permits removing these capabilities.

## Product structure

The main window uses five numbered workflow destinations:

1. Project
2. Import Media
3. Footage Search
4. Project Chat
5. Activity

The top bar carries the `cr` mark, the active project/index summary, theme control, and Settings. A persistent bottom status bar reports the actual current operation and Resolve state.

Project is the control center for sources, workflow profile, indexing, transcription, and consequential Resolve operations. Import Media remains automatic-card-first while also allowing an existing folder. Footage Search is search-first and supports arbitrary future phrases against the persistent index. Project Chat handles complex footage questions, project memory, and staged actions that still require confirmation. Activity shows truthful operational state and project readiness.

## Color

The dark palette is the reference presentation:

- application background: `#0F0D0C`
- content card: `#1A1715`
- top, tab, and bottom bars: `#161311`
- primary surface: `#211D1A`
- secondary surface: `#2A2521`
- primary text: `#F3ECE3`
- accent: `#5B8CFF`
- success: `#7FC488`
- attention: `#F0A860`
- destructive/error: `#E2685F`

The light palette is a first-class equivalent, not a simple inversion. Both themes must maintain readable text, visible borders, native focus behavior, and the same hierarchy.

Blue is reserved for active navigation, playback, links, and the next meaningful action. Green means verified or ready. Orange means attention or a consequential staged action. Red means a real error or destructive action.

## Typography

The Claude source uses Manrope for UI and IBM Plex Mono for metadata. The native SwiftUI implementation uses the closest platform-safe equivalents: San Francisco for interface text and the system monospaced design for paths, timecodes, scores, counts, and logs. This keeps the app legible, native, and dependency-free while preserving the source hierarchy.

Large heavy type is limited to page and project titles. Section labels are compact uppercase monospaced labels. Body copy stays plain and short. Source evidence always keeps filenames and timecodes visually precise.

## Layout and responsiveness

The supported window floor is `860 x 620`; the default window is `1320 x 860`. Main content is centered up to 1200 points with 28-point page padding. Horizontal groups use `ViewThatFits`, adaptive grids, or horizontal scrolling before they overlap.

The preview is a real SwiftUI inspector in the same main window:

- minimum width: 320
- ideal width: 420
- maximum width: 600
- video keeps a 16:9 presentation area
- selected handled range plays by default
- full original source is an explicit toggle
- close, replay, toggle, and reveal controls remain pointer and keyboard accessible

The inspector may reduce the main content width, but it must never float above or intercept the chat/search interface.

## Operational truth

The interface must not invent completion percentages, media understanding, sync success, or Resolve changes. Unknown-duration work uses indeterminate progress. Exact counts come from project state. Consequential Resolve operations remain disabled until prerequisites exist and show confirmation before mutation.

Search results represent handled source ranges. Preview and Resolve timelines reference the original source files. No UI copy may imply that SELECTS are rendered derivative videos.

## Component rules

- Primary buttons use the blue filled style only for the immediate next action.
- Secondary buttons use a warm dark surface, subtle border, and compact weight.
- Cards are flat tonal surfaces with one-pixel borders and no decorative shadow stack.
- Inputs use the bar color with a stronger one-pixel outline.
- Badges are small status facts, not decoration.
- Chips are appropriate for search suggestions and operation stages.
- Thumbnails use real extracted frames when available and a restrained diagonal-stripe placeholder while loading.
- Sheets and Settings inherit the same palette and control styles.
- Every icon-only control requires an accessibility description and help text.

## Do

- Preserve automatic detection and the project-first multi-source workflow.
- Keep original-media paths and exact time ranges visible.
- Keep new arbitrary searches available without re-indexing.
- Make selected range and full source visibly distinct.
- Confirm package creation, waveform sync, multicam creation, and staged chat actions.
- Verify both themes and the minimum supported window size in the running app.

## Do not

- Do not remove automation to make the UI resemble the older mockup.
- Do not turn the product into a generic chatbot.
- Do not place preview in a separate window or overlay it above the active task.
- Do not show fake progress or imply Resolve changed before confirmation succeeds.
- Do not hide source paths, source-link behavior, or what each Resolve action will create.
- Do not render duplicate SELECTS media.
