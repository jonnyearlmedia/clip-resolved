# Ingest Flow

## Step 1: Group footage on the card

- Scan the card read-only.
- Propose obvious shooting-session groups from capture-time gaps.
- Every source MP4 must be accounted for exactly once across the groups.
- The user can move clips between groups if the automatic grouping is slightly wrong.
- The user confirms each group before ingest continues.

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
- preserve the original card contents untouched
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

## Human checkpoint after offload

Once all files are verified, clip resolved should stop at a clear human checkpoint rather than automatically launching every downstream process.

Example:

```text
123 / 123 files copied and verified ✓

CARD SAFE

[ Continue ]
```

The user is comfortable explicitly triggering the next major stage when a human checkpoint is useful.

No downstream behavior is decided in this document beyond this point.