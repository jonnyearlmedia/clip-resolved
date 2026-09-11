# Ingest Flow

## Step 1: Group footage on the card

- Scan the card read-only.
- Propose obvious shooting-session groups from capture-time gaps.
- Every source MP4 must be accounted for exactly once across the groups.
- The user can move clips between groups if the automatic grouping is slightly wrong.
- The user confirms each group before ingest continues.

**OSS baseline:** KontentManager already provides automatic card detection, pre-import browsing/preview, targeted or bulk import, manual triage/reassignment between projects, hash-based dedup, and verified atomic copy. clip resolved should study/reuse that implementation rather than inventing this interaction layer from scratch.

## Step 2: Name and classify each group

For each confirmed group, the user provides:

- **Shoot name**
- **Type:** `Personal` or `Client`

Example:

- `Christmas Eve` → Personal
- `Christmas Lunch` → Personal
- `Carabao` → Client
- `New Year's Eve` → Personal

## Step 3: Automatic destination routing

The normal root is the user's **Active Projects** folder.

clip resolved creates/uses two top-level routing folders:

```text
Active Projects/
├── Personal/
└── Client/
```

The confirmed groups route automatically by type:

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

## Step 4: Verified offload

After the user confirms the groups, names, and Personal/Client classification, the next action is a **verified copy from the card into those destination folders**.

At this stage:

- create the destination folders
- copy each source MP4 to its assigned project
- verify the copied media against the source with a reliable checksum/offload engine
- preserve the original card contents untouched during copy/verification
- show progress per project/group and overall
- do not begin semantic slicing, Resolve organization, or creative analysis yet

Example status:

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

Use proven pieces rather than implementing generic copy/verification logic from scratch.

## Step 5: Human-approved cleanup of only verified source media

After a source file has a verified destination copy, clip resolved may offer to delete **that exact source file from the card**.

This is preferred over automatically formatting the entire card because it preserves anything clip resolved did not ingest or did not understand.

### OSS baseline: SD-Offload WipeGate

SD-Offload already implements the destructive-safety pattern we want. Its `WipeGate.swift` is the primary reference for this stage.

Important behavior to preserve/adapt:

- deletion is based only on the session manifest; it does **not** re-enumerate the card and decide what to erase afterward
- strict fail-closed behavior: any blocker means delete nothing
- only files in verified terminal states are deletion-eligible
- verify the same physical/logical card is still mounted
- reject read-only cards, changed files, symlinks/irregular paths, and paths escaping the card root
- re-stat source files before deletion and verify size/mtime still match the planned source
- require the journal to be durably flushed before destruction
- optionally require a second verified destination before deletion
- maintain an explicit list of planned deletions

This is much closer to clip resolved's desired cleanup model than formatting the entire card.

### Safety invariant

A source file may be deleted only when:

1. clip resolved has an explicit source-path -> destination-path record for it
2. the destination exists
3. the destination has been re-read and checksum-verified against the source
4. the source still matches the file that was planned/imported
5. the user explicitly triggers the cleanup step

If any file fails verification, that source file remains untouched.

Files that were never selected/imported also remain untouched.

### Associated DJI sidecars

DJI cameras can create companion files such as `.LRF` preview files and `.SRT` telemetry files. Cleanup must be manifest-driven and sidecar-aware rather than deleting the whole DCIM tree.

KontentManager's sidecar grouping/rollback behavior is a useful reference here. Recognized sidecars should travel with their parent clip through import and cleanup when appropriate; unknown/unrelated files stay on the card.

### Example checkpoint

```text
123 / 123 imported files verified ✓

[ Delete verified imports from card ]
[ Keep everything on card ]
```

If the user chooses deletion, the app deletes only the verified source manifest (plus explicitly recognized associated sidecars when appropriate), then reports what remains on the card.

A later full in-camera format can remain optional, but it is not required as the default cleanup path.

## Human checkpoint after cleanup

The user is comfortable explicitly triggering the next major stage when a human checkpoint is useful.

No semantic slicing, Resolve organization, or creative analysis starts automatically from the cleanup action.