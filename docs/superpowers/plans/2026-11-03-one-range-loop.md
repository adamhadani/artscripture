# One Range Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the separate selection with one range — `ViewerModel.loop` — so a drag
defines the passage and one button loops it.

**Architecture:** `LoopRegion` already holds a range and `isEnabled`, is what the engine plays
and is all a sidecar persists; it becomes the only range. `ViewerModel.selection` and every
`selection.*` action go. A new-range drag *stages* the loop (drawn live, engine untold) and
commits it on lift. Handle reach comes from `ControlMetrics` per input surface.

**Tech Stack:** Swift 6.4, SwiftUI, Swift Testing; the acceptance harness (`make acceptance`).

**Spec:** `docs/superpowers/specs/2026-11-03-one-range-loop-design.md`

## Global Constraints

- No sidecar format change: `SessionFile` is untouched (it never stored the selection).
- The engine path is untouched: `applyLoop` stays "the app's one and only `.setLoop` path".
- Touch handle reach **22 pt** either side (44 pt target), body band **22 pt**; desktop stays
  **9 pt** / **14 pt** (`TimelineHandles.grabRadius`, `bodyBandHeight` today).
- Keys: `G` unbound; `C`/`V`, `⌥C`/`⌥V` join `loop.move.*` beside `⇧C`/`⇧V`, `⌥⇧C`/`⌥⇧V`;
  `⇧←`/`⇧→` extend the range; `⌘A` range = whole file; `Esc` = `loop.clear`; `⌘9` zoom to loop;
  `⇧Space` → range start, else 0.
- `make check` green before every commit (serial: `swift test --no-parallel` if the parallel
  run hangs in `AudioDecodeTests` — pre-existing, see PR #74). Never `git add -A`.

## Review Focus

1. **A tap while a loop plays must never move or clear the loop.** `DragGesture(minimumDistance: 0)`
   calls `onChanged` on touch-down, so a range staged there would replace the loop with a
   zero-width one on every tap. Test: `tapDoesNotStageARange` (Task 2).
2. **Cancelling a new-range drag restores the old loop** — and the engine, which was never told,
   needs nothing. Test: `cancelledDragRestoresTheLoop` (Task 2).
3. **A range dragged backwards** (right to left) normalises, as `Selection` did. Test:
   `backwardsDragNormalises` (Task 2).
4. **`⇧←` with no range and the playhead at 0** must not produce an inverted or negative range.
   Test: `extendAtFileStartClamps` (Task 2).
5. **`Esc` with no loop is inert** (no session edit, no push). Test: `escapeWithNoLoopIsInert`
   (Task 2).

---

### Task 1: Handle reach by input device

**Files:**
- Modify: `Sources/ArtscribeUI/TimelineHandles.swift` (`grabRadius`, `bodyBandHeight`, `handle(at:…)`)
- Modify: `Sources/ArtscribeUI/ControlMetrics.swift` (per-surface values)
- Modify: `Sources/ArtscribeUI/ViewerModel+EdgeDrag.swift` (`timelineHandle(at:)` passes the reach)
- Test: `Tests/ArtscribeUITests/TimelineHandleTests.swift`

**Interfaces:**
- Produces: `public struct HandleReach: Equatable, Sendable { let edge: Double; let bodyBand: Double }`,
  `ControlMetrics.handleReach(on surface: EmptyStatePrompt.Surface) -> HandleReach`
  (`.desktop` → 9 / 14, `.tabletWithDrop`, `.phone` → 22 / 22), and
  `TimelineHandles.handle(at:laneHeight:loop:selection:viewport:reach:)`.
- The model reads the surface it already uses for `prefs.seeksOnSelectionPress`.

- [ ] **Step 1:** Tests `aFingerCatchesAnEdgeTwentyPointsAway` (phone reach, pointer 20 pt from
  the loop's out edge → `.loopEnd`), `thePointerDoesNot` (desktop reach, same point → `nil`),
  `touchBodyBandIsDeeper` (phone, 20 pt below the top inside the span → `.loopBody`).
- [ ] **Step 2:** Run `swift test --filter TimelineHandleTests` — FAIL (no `reach:` parameter).
- [ ] **Step 3:** Implement; keep the existing statics as the desktop values.
- [ ] **Step 4:** `swift test --filter TimelineHandleTests` — PASS. `make check`.
- [ ] **Step 5:** Commit "Loop handles: a 44 pt finger target on touch".

### Task 2: The range replaces the selection

The one compile-coupled task: removing `selection` breaks every reader at once, so it lands
whole, compiler-guided, tests first.

**Files (the code-level users, from `grep`):**
- Model: `ViewerModel.swift` (remove `selection`, `selectionBeforeLaneDrag`; add the staging
  state below), `ViewerModel+Interaction.swift` (`dragChanged`/`dragEnded`, `selectAll`,
  `clearSelection`), `ViewerModel+LaneDrag.swift` (`LaneDragMode.select` → `.range`, cancel,
  `zoomToSelection`), `ViewerModel+EdgeDrag.swift` (drop selection-edge cases),
  `ViewerModel+Selection.swift` → **rename** `ViewerModel+Range.swift` (extend; `moveSelection`
  folds into the loop move), `SelectionMoving.swift` (delete if only the selection used it),
  `ViewerModel+Playback.swift` (rewind target), `ViewerModel+Loading.swift`, `PlaybackStart.swift`,
  `TransportLatch.swift` (`selectionStart:` → `rangeStart:`), `LoopEditing.swift`
  (drop `fromSelection`), `Sources/ArtscribeKit/Selection.swift` (delete if unused after).
- Hit-testing and drawing: `TimelineHandles.swift` (drop `.selectionStart/.selectionEnd`),
  `TimelineEdgeOverlay.swift`, `PointerAffordance.swift`, `ZoomDrag.swift`,
  `WaveformLanesView.swift`, `OverviewStripView.swift`, `TimeRulerView.swift`.
- Actions: `ActionID.swift`, `ActionCatalogEntries.swift`, `ActionInvokerTable.swift`,
  `MenuPlan.swift`, `EditCommands.swift`, `LoopCommands.swift`, `PlaybackCommands.swift`,
  `KeyCapCaption.swift`, `CategoryTint.swift`, `TransportControls.swift`,
  `StatusBarFields.swift`, `StatusBarView.swift`, `Sources/ArtscribeApp/ArtscribeAppMain.swift`.
- Settings copy only: `SettingsView.swift`, `InteractionSettings.swift`, `Preferences.swift`
  ("Selection move" → "Loop move"; **the stored keys keep their names**).
- Test: new `Tests/ArtscribeUITests/OneRangeTests.swift`; then every suite the compiler breaks.

**Interfaces:**
- Produces on `ViewerModel`:
  - `@ObservationIgnored var loopBeforeLaneDrag: LoopRegion?` (cancel restore),
  - `@ObservationIgnored var rangeAnchor: FrameIndex?` (the fixed edge of a drag or extend),
  - `@ObservationIgnored internal private(set) var loopIsStaged: Bool`,
  - `func stageLoop(_ next: LoopRegion)` — sets `loop`, marks staged, **no push**,
  - `func commitStagedLoop()` — if staged: push `.setLoop`, `wrapTracker.reset()`,
    `markSessionEdited()`, clear the flag,
  - `public func extendLoop(_ direction: NudgeDirection)`, `public func loopWholeFile()`,
    `public func zoomToLoop()`.
- ActionIDs: delete `loopFromSelection`, `selection*`; add `loopExtendLeft = "loop.extendLeft"`,
  `loopExtendRight = "loop.extendRight"`, `loopSelectAll = "loop.selectAll"`; rename
  `zoomToSelection` → `zoomToLoop = "zoom.toLoop"`. `loopClear` gains `Esc`.
- `PlaybackStart.target(loop:) -> FrameIndex` (range start if `count > 0`, else 0).
- `TransportLatch.rewindTarget(…, rangeStart: FrameIndex?)`.

- [ ] **Step 1: Write the failing tests** in `OneRangeTests` (model built as in `InterruptionTests`,
  zoomed so pixels are frames you can reason about):
  - `aDragDefinesTheRange` — drag 100→300 px; `loop.range == frames(100…300)`, `!loop.isEnabled`.
  - `aDragWhileLoopingReplacesTheLoopAndKeepsLooping` — loop enabled at 500–600; drag 100→300;
    `loop.range == frames(100…300)`, `loop.isEnabled`.
  - `theEngineHearsAboutANewRangeOnLift` — mid-drag `loopIsStaged`; after `laneDragEnded`, `!loopIsStaged`.
  - `tapDoesNotStageARange` — loop 500–600 enabled; press-and-release at 200 (no movement);
    loop unchanged, playhead at frame(200).
  - `doubleTapStillPlays` — unchanged behaviour, loop unchanged.
  - `cancelledDragRestoresTheLoop` — drag, `cancelLaneDrag()`; loop equals the original, `!loopIsStaged`.
  - `backwardsDragNormalises` — drag 300→100 → `frames(100…300)`.
  - `shiftDragKeepsTheFarEdge` — loop 100–300, ⇧-drag from 280 to 400 → `frames(100…400)`.
  - `extendWithNoRangeStartsAtThePlayhead` / `extendAtFileStartClamps` (playhead 0, `⇧←` → no
    negative start, range empty or `0…0`, nothing inverted).
  - `escapeClearsTheLoop` / `escapeWithNoLoopIsInert` — through `KeyBindings.action(for:)` then the invoker.
  - `gIsUnbound` — `KeyBindings.action(for: .key("g")) == nil`.
  - `cAndVMoveTheLoop` — both chords resolve to `.loopMoveLeft/.loopMoveRight`.
  - `selectAllLoopsTheWholeFileWithoutTurningLoopingOn`.
  - `shiftSpaceGoesToTheRangeStartLoopingOrNot`.
  - `theTransportHasNoSelectionButton` — `TransportControl.allCases` lacks it; `.loop` enabled iff
    `loop.range.count > 0`.
- [ ] **Step 2:** `swift build --build-tests` — FAIL to compile (the new API). Record it.
- [ ] **Step 3:** Implement, compiler-guided, in the files above. `dragChanged` stages nothing
  until movement exceeds `clickSlopPoints` (Review Focus 1); the anchor for ⇧ is the edge
  farther from the press; `extendLoop` moves the edge that is not `rangeAnchor` (default anchor
  = `range.start`). Delete dead code rather than leaving it unused.
- [ ] **Step 4:** `swift test --filter OneRangeTests` — PASS.
- [ ] **Step 5:** Migrate the broken suites (`SelectionTests`, `SelectionMovingTests`,
  `ViewerModelInteractionTests`, `ViewerModelEdgeDragTests`, `TimelineHandleTests`,
  `PlaybackStartTests`, `TransportControlTests`, `ActionCatalogTests`, `KeyBindingsTests`,
  `StatusBarFieldsTests`, `ZoomDragTests`, …): a test of the selection becomes a test of the
  range where the behaviour survives, and is deleted where it does not (say which in the commit).
- [ ] **Step 6:** `make check` (or `make format-check lint && swift test --no-parallel`) and
  `make ios-check` — green.
- [ ] **Step 7:** Commit "One range: a drag defines the loop, and Loop turns it on".

### Task 3: Clearing a loop on touch

**Files:** `Sources/ArtscribeUI/TitleBarView.swift` (`⋯` menu), `Sources/ArtscribeUI/TransportBarView.swift`
(context menu on the `.loop` button). Test: `Tests/ArtscribeUITests/TransportControlTests.swift`.

**Interfaces:** Consumes `ViewerModel.clearLoop()`; produces
`TransportControl.contextActions(for:) -> [ActionID]` (`.loop` → `[.loopClear]`, others `[]`),
so the view's context menu is data a test can read.

- [ ] **Step 1:** Test `theLoopButtonOffersClearLoop`. **Step 2:** FAIL. **Step 3:** Implement;
  `⋯` gains "Clear Loop" disabled when `loop.range.count == 0`. **Step 4:** PASS, `make check`.
- [ ] **Step 5:** Commit "Clear Loop is reachable on an iPhone".

### Task 4: Copy and docs

**Files:** `WelcomeSheet.swift` (page 2: "Drag out a passage, then loop it"; controls `.loop`,
`.preroll`), `EmptyStatePrompt.swift` (`loopGuidance`), spec §6.1–6.2, `website/docs.md`,
CLAUDE.md where it names the selection. Test: `WelcomeTests` (page 2 names no removed control).

- [ ] Steps: test → FAIL → copy → PASS → `make check` → commit "The words follow the one range".

### Task 5: The acceptance harness

**Files:** the 20 `Sources/ArtscribeAcceptance` files that mention the selection
(`AcceptanceSelectionChecks.swift` foremost; `AcceptanceEdgeDrag.swift`,
`AcceptanceStartPrecedence.swift`, `AcceptancePointer.swift`, `AcceptanceMenuChecks.swift`,
`AcceptanceShortcutChecks.swift`, `AcceptanceButtonPress.swift`, …), `AcceptanceGroups.swift`
(the `selection` group's description).

- [ ] **Step 1:** Rewrite each selection check as its range equivalent; add **"a real tap inside a
  playing loop leaves the loop alone"** and **"a real drag while looping replaces the loop and
  keeps looping"**; remove `G` checks.
- [ ] **Step 2:** `make acceptance AUDIO=<full-length track> ARGS='--only selection,edge,loop,pointer,start'`
  — 0 failures.
- [ ] **Step 3:** Mutation-test one new check (stage a range on touch-down) — it must FAIL.
- [ ] **Step 4:** Full `make acceptance AUDIO=<full-length track>`; the only permitted failure is
  the pre-existing double-click drift check that fails identically on `main`.
- [ ] **Step 5:** Commit "The harness drives the one range".

### Task 6: Look at the pixels

- [ ] iPhone simulator (landscape) and the Mac window: a drag draws one range in the loop
  colour at reduced opacity; Loop turns it solid; the transport bar has no Selection → Loop
  button; `⋯` shows Clear Loop. Screenshots attached to the PR.

### Task 7: Ship to TestFlight

- [ ] Open the PR; when CI is green on #74, #75 and this, merge them in that order (rebase
  this one if #75 conflicts in `OverviewStripView.swift`).
- [ ] From an up-to-date `main`: `make asc-check && make archive && make upload && make asc-wait`
  (per the `release-artscripture` skill). **Do not** `asc-prepare` or submit for review.
