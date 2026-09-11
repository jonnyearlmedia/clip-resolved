# Realistic Workflow Scenarios

## Scenario 1: One microSD contains several unrelated days and events

Example card contents:

- December 24: Christmas Eve opening gifts
- December 25: Christmas Day lunch
- December 27: Carabao client video shoot
- December 31 into January 1: New Year's Eve party and countdown

This scenario is intentionally realistic and should drive ingest design.

## Key product rule

**A physical card is a container, not a project.**

clip resolved must not assume that every file on one microSD belongs to one Resolve project, client, event, or destination folder.

## First-stage behavior

When a card is inserted, clip resolved should initially perform a lightweight, read-only scan sufficient to understand:

- media files present
- internal creation timestamps when available
- filesystem timestamps as fallback/supporting evidence
- clip duration
- technical metadata needed to sort and summarize

This initial scan is not the semantic footage-analysis stage and should not modify originals.

## Session discovery

The app should propose **shoot sessions/events** inside the card before ingest destinations are assigned.

Calendar date alone is insufficient.

Example failure:

- New Year's Eve begins December 31
- countdown/party footage continues after midnight on January 1
- splitting strictly by date would incorrectly create two projects/events

The better initial signal is temporal continuity:

1. Sort clips by reliable capture/start time.
2. Compare each clip's end time to the next clip's start time.
3. Treat large inactive gaps as candidate session boundaries.
4. Treat midnight/date changes as weak evidence, not hard boundaries.
5. Allow proposed sessions to be merged, split, or relabeled before offload.

Potential proposed result for this example:

```text
SESSION A
Dec 24 evening
Christmas Eve opening gifts

SESSION B
Dec 25 midday
Christmas Day lunch

SESSION C
Dec 27
Carabao shoot

SESSION D
Dec 31 evening -> Jan 1 after midnight
New Year's Eve party + countdown
```

The app does not need to know those human-friendly names automatically at first. It can initially show timestamp-based session cards and let the user name/confirm them.

## Timestamp confidence

Do not blindly trust one timestamp source.

DJI Pocket footage can have incorrect capture dates if the camera clock is wrong or loses sync. The grouping layer should therefore keep track of timestamp confidence and compare available sources rather than assuming all metadata is correct.

Possible signals:

- embedded media creation time
- filesystem creation/modification time
- filename sequence/order
- continuity between consecutive clip numbers
- clip duration/end time
- later, optional semantic similarity or visual context if timestamps are suspicious

If timestamps are clearly invalid, clip resolved should flag the card rather than silently create wrong projects.

## User interaction goal

The user should not have to individually select hundreds of clips.

A better interaction is:

```text
OSMO CARD DETECTED
126 clips · 184 GB

We found 4 likely shooting sessions:

[ Dec 24 · 6:12 PM–9:03 PM · 34 clips ]
[ Dec 25 · 12:08 PM–3:41 PM · 27 clips ]
[ Dec 27 · 2:02 PM–5:28 PM · 41 clips ]
[ Dec 31 8:16 PM–Jan 1 1:37 AM · 24 clips ]

Review / merge / split / name sessions
```

After session confirmation, each session can receive its own:

- project/event name
- shoot type
- destination
- backup behavior
- Resolve project behavior
- later semantic-analysis recipe

## Why this matters downstream

The four sessions should not necessarily receive the same processing.

Examples:

### Christmas Eve / Christmas Day / New Year's Eve
Personal/family footage may eventually use a personal-event workflow rather than a commercial b-roll workflow.

Potential priorities:
- people/faces
- moments/reactions
- gifts/food/countdown
- chronological continuity
- audio/dialogue

### Carabao
Commercial restaurant workflow may prioritize:
- food
- drinks
- chef/preparation
- interiors/exteriors
- customers
- signage
- details/atmosphere
- stronger Resolve selects/bin preparation

The physical card therefore must be separated into logical sessions **before shoot-specific semantic recipes are applied**.

## Open implementation question

The exact session-boundary algorithm is not selected yet. It should be benchmarked on real cards.

Potential strategy:
- time-gap clustering as the primary method
- adaptive rather than one universal fixed threshold if possible
- optional visual/semantic confirmation only for ambiguous boundaries
- easy manual merge/split in the app

The goal is very high-confidence grouping with minimal user interaction, not pretending AI can always infer event names automatically.