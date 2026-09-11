# Ingest Flow

## Step 1: Group footage on the card

- Scan the card read-only.
- Propose obvious shooting-session groups from capture-time gaps.
- Every source MP4 must be accounted for exactly once across the groups.
- The user can move clips between groups if the automatic grouping is slightly wrong.
- The user confirms each group before ingest continues.

**OSS baseline:** KontentManager already provides automatic card detection, pre-import browsing/preview, targeted or bulk import, manual triage/reassignment between projects, hash-based dedup, and verified atomic copy. clip resolved should reuse/adapt that implementation rather than inventing this interaction layer from scratch.

## Step 2: Name and classify each group

For each confirmed group, the user provides:

- **Shoot name**
- **Type:** `Personal` or `Client`

Example:

- `Christmas Eve` → Personal
- `Christmas Lunch` → Personal
- `Carabao` → Client
- `New Year's Eve` → Personal

## Step 3: Group confirmation is the main GO action

Once all groups are named/classified and the user confirms them, clip resolved should automatically begin the non-destructive file legwork for **all confirmed groups**.

There is no separate per-project `Prepare` button.

Confirmation triggers:

1. create/rout project folders
2. verified offload
3. register the copied source paths with the local intelligence/indexing layer
4. begin building the derived indexes/analysis artifacts required by the next workflow stages

The user does not need to manually start those stages project-by-project.

## Step 4: Automatic destination routing

The normal root is the user's **Active Projects** folder.

```text
Active Projects/
├── Personal/
└── Client/
```

Confirmed groups route automatically by type:

```text
Active Projects/
├── Personal/
│   ├── Christmas Eve/
│   ├── Christmas Lunch/
│   └── New Year's Eve/
└── Client/
    └── Carabao/
```

The user should not have to manually choose a destination for every group unless they explicitly override the default root.

## Step 5: Verified offload

After group confirmation:

- create destination folders
- copy each source MP4 to its assigned project
- verify copied media against source with a proven checksum/offload engine
- preserve original card contents during copy/verification
- show progress per group and overall

Example:

```text
Christmas Eve      31 / 31 copied and verified
Christmas Lunch    28 / 28 copied and verified
Carabao            42 / 42 copied and verified
New Year's Eve     22 / 22 copied and verified
-----------------------------------------------
TOTAL             123 / 123 copied and verified
```

**OSS baseline:**
- KontentManager: targeted imports + verified atomic copy + sidecar-aware group rollback
- FilmCan: mature fan-out verified copy, resume, xxHash128, paranoid disk re-read mode
- SD-Offload: SHA-256 card-read canonical hash + uncached destination read-back + crash-safe journal

## Step 6: Automatic registration/index-prep after each verified copy

As files finish verified offload, clip resolved can register their new destination paths with the footage-intelligence layer automatically. It should not make another source-media copy.

Reuse existing folder/path-based patterns:

- Omnishot links/watches an existing library folder, indexes videos in place, and keeps a manifest mapping derived chunks back to untouched source paths.
- SynthCut imports assets from absolute local source paths and builds transcript/visual indexes against those assets.

Desired shape:

```text
Active Projects/Client/Carabao/<original media>
        ↓
register existing source paths
        ↓
build local derived indexes/analysis artifacts
```

This happens automatically as part of the confirmed ingest job.

The exact analysis performed is intentionally handled by the next workflow-design stage.

## Step 7: Human-approved cleanup of only verified source media

The one deliberate human checkpoint is destructive cleanup of the card.

After source files have verified destination copies, clip resolved may offer to delete those exact verified source files from the card.

### OSS baseline: SD-Offload WipeGate

Reuse/adapt `WipeGate.swift` rather than authoring a new destructive-safety system.

Important behavior:

- deletion is based only on the session manifest
- any blocker means delete nothing
- only verified terminal-state files are eligible
- verify the same card is still mounted
- reject changed/irregular/escaping paths
- re-stat source files before deletion
- require durable journal state before destruction
- optionally require a second verified destination
- maintain an explicit planned-deletion list

### Safety invariant

A source file may be deleted only when:

1. explicit source-path → destination-path record exists
2. destination exists
3. destination has been re-read and checksum-verified
4. source still matches the planned/imported file
5. user explicitly triggers cleanup

Unknown, unselected, failed, or unrelated files stay on the card.

### DJI sidecars

Cleanup remains manifest-driven and sidecar-aware for recognized `.LRF`, `.SRT`, or other associated DJI files. Unknown files stay untouched.

Example:

```text
123 / 123 imported files verified ✓

[ Delete verified imports from card ]
[ Keep everything on card ]
```

Non-destructive indexing/prep does not need to wait for this cleanup choice.