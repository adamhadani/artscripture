# One range, and looping is its switch — design

**Date:** 2026-11-03 · **Status:** for approval · **Supersedes:** the selection/loop split in
spec §6.2 and §6.1's pointer catalog.

## Why

Reported from an iPhone. To loop a passage today you drag out an orange **selection**, press
**Selection → Loop** (`G`), then press **Loop** (`D`): three steps, and nothing on screen
says the middle one exists. Once a loop is set, a drag that misses its edge by a few points
starts a fresh orange selection instead of moving the edge. Both come from one root: the
selection is the primary object and the loop is derived from it, when for a practice tool the
loop is the point and a separate selection is a detour.

What the user asked for, in their words: *"a single button to just loop on/off once a range is
selected"*, loop edges that are *"easier to catch"*, and bookmark-style markers only as an
**opt-in** later, not now.

## Decisions taken with the user (2026-11-03)

1. **One range.** A drag defines *the* range. There is no separate selection.
2. **Looping on + a drag in open lane replaces the loop**, and the new passage keeps looping
   (Transcribe!/Anytune behaviour). Edge handles get a **44 pt** finger target.
3. **A tap keeps the range.** It only places the playhead. Clearing is explicit.
4. **All platforms.** The waveform code is shared, and so is the behaviour.

> **Changed 2026-11-08: a new loop starts with looping on.** The user, from using 1.4:
> *"when user creates a loop we should turn on looping mode by default … should be opt out
> rather than opt in. Otherwise frustrating experience to mark a loop only to see the
> playback continuing after it."* So decision 2 now holds whether looping was on or not:
> every new loop — a drag that marks a new passage, `A` or `S` with no loop, `⌘A`, a
> `⇧`-arrow from a bare playhead — loops, and with the playhead outside it playback goes to
> its start (the engine captures a loop only on arrival, §5.1). Edits to an existing loop
> (its edges, its middle, `C`/`V`, `A`/`S` on it, a `⇧`-extend) keep looping as it was, so
> switching it off holds until the next new loop. `D` and the Loop button are now how you
> opt out. See `ViewerModel.enterLoopIfOutside`.

## The model

The range *is* `LoopRegion` — `range` plus `isEnabled` — which already exists, is already
what the engine plays and is already the only thing a session sidecar persists. So:

- `ViewerModel.selection` is **removed**. Everything that read it reads `loop.range`.
- "Looping on/off" is `loop.isEnabled`; `loop.isActive` (enabled and non-empty) is unchanged.
- **No sidecar change and no migration.** Sessions never stored the selection.
- A range with looping off is drawn exactly as a disabled loop is today
  (`Palette.loopDisabledOpacity`), so there is no new visual vocabulary to learn.

## Pointer and touch, in the lanes

The precedence rule (`TimelineHandles`), latched at touch-down as today:

| # | Press | Means |
|---|---|---|
| 1 | ⌥ held | Zoom (unchanged) |
| 2 | ⇧ held | Extend the range: the far edge stays put, the near edge follows |
| 3 | Within the grab radius of a loop edge | Drag that edge (live, as today) |
| 4 | On the loop's top/bottom bar, inside its span | Move the whole loop (unchanged) |
| 5 | Anything else, moved past the click slop | **A new range**, replacing the old; looping state unchanged |
| — | Tap / click | Place the playhead. **The range is kept** |
| — | Double tap / click | Place the playhead and play (unchanged) |

> **Changed 2026-11-08 (PR after #85):** row 4 is now *anywhere inside the loop's span*, at any
> height, on every platform — asked for from an iPhone ("when I drag my finger inside of a looped
> area typically the intent is to move the whole loop along"), and taken for the Mac too. A press
> there that never moves is still a click (row "Tap / click"), on the Mac as well. Row 5 is
> therefore *outside the loop*: a new loop can no longer be drawn starting inside the current
> one. The body band is gone. See `TimelineHandles` for the reasoning.

- **Grab radius by input device**, from `ControlMetrics` keyed on `EmptyStatePrompt.Surface`:
  9 pt either side on the Mac (the 20 pt target it has now), **22 pt** on touch (44 pt, the
  HIG minimum). The body band grows the same way: 14 pt → 22 pt on touch. *My call.*
  (The band itself went on 2026-11-08 — the body is the whole inside of the loop; see the note
  above.)
- **A new-range drag reaches the engine when the finger lifts**, not on every event: a range
  that starts at zero width would otherwise switch the engine's loop off and on under a
  playing track for the length of the gesture. It is drawn live. Edge and body drags stay
  live, as now. *My call.*
- Selection edges (`TimelineHandle.selectionStart/End`) go away with the selection.

## Keyboard (Mac, and iPad with a keyboard)

`A` `S` `D` `F` and the `⇧`/`⌥⇧` loop-edge moves are **unchanged**. The selection's keys
now act on the range, so muscle memory carries over:

| Key | Was | Now |
|---|---|---|
| `G` | Selection → Loop | **Removed** (and freed) |
| `C` / `V`, `⌥C` / `⌥V` | Move the selection | Move the loop — the same action as `⇧C` / `⇧V`, which stay as aliases. *My call* |
| `⇧←` / `⇧→` | Extend the selection | Extend the range: the edge last moved follows, or a new range from the playhead |
| `⌘A` | Select all | Range = the whole file; looping state unchanged |
| `Esc` | Clear the selection | **Clear Loop.** With one range, "deselect" and "clear the loop" are the same act. *My call — the one most worth a second look* |
| `⌘9` | Zoom to selection, else loop | Zoom to the loop |
| `⇧Space` | Selection start, else active loop's in, else 0 | The range's start, else 0 |

The `selection.*` action IDs are renamed into `loop.*` (`loop.extendLeft`, …). No ID is
persisted anywhere, so nothing outside the binary notices.

## Transport bar, menus, first run

- **Transport bar:** the *Selection → Loop* button is removed. *Loop* is enabled whenever a
  range exists and toggles looping.
- **Menus:** Edit keeps *Select All* (`⌘A`). The selection items leave Edit; extend and move
  join the Loop menu beside *Clear Loop*.
- **Clearing on touch.** An iPhone has no menu bar, and its `⋯` menu holds only Settings,
  Shortcuts, Practice and About — so today a loop can never be removed there. `⋯` gains
  **Clear Loop** (disabled with no range), and a long-press on the Loop button offers the
  same in a context menu, the idiomatic iOS place for a secondary action. *My call.*
- **Status bar:** the *Selection* field is removed; *Loop* already shows the range.
- **Welcome sheet, page 2** becomes *"Drag out a passage, then loop it"*, noting Loop and
  Preroll only. `EmptyStatePrompt.loopGuidance` is rewritten to match.
- **Overview strip** draws the loop only.

## What is not changing

The engine, the seamless-loop rule (never `reset()` at the boundary), preroll's clamp at an
active loop's in point, the practice ramp, nudging across a loop, the loop-edge swap rule, and
session persistence.

## Out of scope

Bookmarks / markers — an opt-in, separate feature, later if wanted.

## Testing

Each behaviour change lands test-first (red on the current code, then green), as the
interruption fix did: the lane precedence (`TimelineHandles`) per surface, a drag replacing a
looping loop, a tap keeping it, `⇧`-extend, the remapped keys through `KeyBindings`, `Esc`,
`⇧Space`, and the transport control set. The acceptance harness's `selection` checks are
rewritten against the range rather than deleted, the edge-drag group loses its
selection-edge cases and gains a touch-radius case, and the full run is compared against
`main` with a full-length track (the bundled 28 s sample is too short for the timed loop
checks — they fail identically on `main` with it).

## Docs

Spec §6.1 pointer catalog and §6.2 action catalog, `website/docs.md`, CLAUDE.md where it
names the selection, and the in-app keyboard-shortcut window (rendered from the live binding
table, so it follows the catalog).
