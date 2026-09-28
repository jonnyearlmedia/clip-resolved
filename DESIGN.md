---
name: Clip Resolved
description: A precise native macOS console for footage intelligence and Resolve preparation.
colors:
  accent: "Highlight"
  canvas: "Canvas"
  primary-text: "CanvasText"
  secondary-text: "GrayText"
typography:
  display:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontWeight: 600
  body:
    fontFamily: "-apple-system, BlinkMacSystemFont, sans-serif"
    fontWeight: 400
  timecode:
    fontFamily: "ui-monospace, SFMono-Regular, monospace"
    fontWeight: 400
rounded:
  thumbnail: "6px"
  surface: "10px"
  message: "12px"
spacing:
  compact: "8px"
  control: "12px"
  section: "20px"
  page: "24px"
components:
  button-primary:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.canvas}"
    rounded: "{rounded.thumbnail}"
    padding: "6px 12px"
  card:
    backgroundColor: "{colors.canvas}"
    textColor: "{colors.primary-text}"
    rounded: "{rounded.surface}"
    padding: "12px"
---

# Design System: Clip Resolved

## Overview

**Creative North Star: "The Edit Console"**

Clip Resolved is a calm, information-dense native macOS companion. The interface should feel like a trustworthy extension of an editing suite: project state is visible, media operations are explicit, and the current task has one obvious place to happen. System materials and controls supply familiarity; the product supplies editorial hierarchy and precise language.

The experience favors durable workspaces over stacked dashboards. Project setup, search, chat, ingest, and activity each have their own navigation destination. Footage preview is an adjustable inspector in the same window, never a floating overlay that hides the active task.

**Key Characteristics:**

- Native macOS navigation, materials, controls, and semantic colors.
- Compact professional density with 24px page margins and 20px section rhythm.
- Source paths, timecodes, sync methods, and mutation boundaries remain visible.
- Responsive horizontal arrangements collapse into vertical stacks before controls crowd or overlap.

## Colors

The palette follows macOS semantic roles so light mode, dark mode, contrast settings, and user accent color remain authoritative.

### Primary

- **System Accent:** Used sparingly for the active primary action, playable evidence, and selected-source emphasis.

### Neutral

- **System Canvas:** The window and native container ground.
- **Primary Text:** High-contrast labels, titles, and source names.
- **Secondary Text:** Paths, metrics, status, explanations, and supporting metadata.

**The Semantic Color Rule.** Never replace adaptive system colors with fixed light-mode grays or decorative brand gradients.

**The One Primary Action Rule.** A region may contain several operations, but only its immediate next step receives prominent accent treatment.

## Typography

**Display Font:** San Francisco through the macOS system font
**Body Font:** San Francisco through the macOS system font
**Label/Mono Font:** SF Mono through the system monospaced design

**Character:** Native, direct, and compact. Weight creates hierarchy; ornamental display faces and excessive uppercase do not belong in the operational interface.

### Hierarchy

- **Display** (semibold, system large title): Workspace and sheet titles only.
- **Headline** (semibold, system title/headline): Project names, confirmation titles, and section-leading facts.
- **Body** (regular, system body/callout): Instructions, explanations, and conversational output.
- **Label** (regular or semibold, system caption): Paths, status, media counts, and secondary metadata.
- **Timecode** (regular, monospaced digits): In/out points, durations, scores, and other values that must align visually.

**The Editorial Precision Rule.** Time-based and numeric editing evidence uses monospaced digits; prose does not.

## Layout

The application uses a native `NavigationSplitView`: stable workspace navigation on the left, one task surface in the detail area, and an optional adjustable inspector on the right. Main content is centered up to 1040px with a 24px page inset. Long explanatory text should remain within roughly 760px.

Horizontal tool rows use `ViewThatFits` or equivalent adaptive composition and become vertical stacks when they no longer fit. The supported window floor is 860x620; fixed-width sidebars or panels must not consume the detail surface. The preview inspector is resizable from 320px to 600px with a 420px ideal width, and its video maintains a 16:9 aspect ratio.

**The No Overlay Rule.** Persistent work surfaces use split views, sheets, or inspectors. They do not cover chat, search results, or primary controls.

## Elevation & Depth

The system is flat by default. Hierarchy comes from native sidebar and bar materials, group boxes, dividers, selection state, and subtle tonal fills. Shadows are not a general-purpose decoration; system sheets, menus, and inspectors own their platform elevation.

**The Native Depth Rule.** Let macOS provide window, sheet, menu, popover, and inspector depth. Do not add custom card shadows to imitate a web dashboard.

## Shapes

Forms are gently rounded and restrained: evidence thumbnails use a 6px clip, operational surfaces use 10px, and chat messages use 12px. Native buttons, fields, group boxes, tables, and segmented controls keep their platform geometry. Circular shapes are reserved for standard icon controls such as close and overflow actions.

## Components

### Buttons

- **Shape:** Native macOS button geometry; custom content surfaces use the 6px small radius.
- **Primary:** `.borderedProminent` only for the next meaningful action, such as Search, Add Source, or confirmed Resolve creation.
- **Hover / Focus:** Inherited from native controls so pointer, keyboard, VoiceOver, and increased-contrast states remain correct.
- **Secondary:** Native bordered, borderless, or menu styles selected by hierarchy rather than decoration.

### Cards / Containers

- **Corner Style:** 10px for custom operational surfaces; use `GroupBox` whenever its semantics fit.
- **Background:** Native adaptive material or low-emphasis semantic fill.
- **Shadow Strategy:** Flat at rest.
- **Border:** System separator or standard group-box border.
- **Internal Padding:** 12px compact content, 20px between major sections, 24px at page edges.

### Inputs / Fields

- **Style:** Native rounded text fields and segmented pickers.
- **Focus:** Native focus ring with descriptive accessibility labels.
- **Error / Disabled:** Disable unavailable operations in place and present operational errors through one app-level alert plus activity history.

### Navigation

Workspace navigation uses a standard macOS sidebar with SF Symbols and stable destinations: Project, Footage Search, Project Chat, Import Media, and Activity. Project-level actions live in Project rather than crowding every workspace toolbar.

### Footage Preview Inspector

The inspector stays in the main window, presents the selected source range by default, and exposes an explicit toggle to the full original source. Playback, close, and reveal controls must remain keyboard and pointer accessible. The player scales with inspector width instead of using a fixed height.

## Do's and Don'ts

### Do:

- **Do** keep project/source readiness visible before Resolve actions.
- **Do** use adaptive stacks and verify the 860px minimum window width.
- **Do** keep selected-range playback distinct from full-source context.
- **Do** preserve native semantics, keyboard behavior, VoiceOver labels, and dark-mode adaptation.
- **Do** use exact editorial language: source, range, chronology, waveform, timecode, multicam, and Resolve.

### Don't:

- **Don't** build fixed-width panels that cover or crush the active workspace.
- **Don't** scatter ingest, indexing, transcription, sync, multicam, and package creation across unrelated toolbars.
- **Don't** present the product as a generic chatbot or decorative AI dashboard.
- **Don't** imply footage was watched, synchronized, or changed when only a request was staged.
- **Don't** hide source paths, original-media boundaries, or the method used for a consequential Resolve operation.
