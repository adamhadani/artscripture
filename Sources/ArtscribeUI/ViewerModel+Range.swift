import ArtscribeKit

/// Moving and extending the range — the loop, which since 2026-11 is the only
/// range there is (the separate selection was removed). Spec §6.2's
/// `loop.move` and `loop.extend` actions.
///
/// Its own extension file rather than more of `ViewerModel+Interaction`, which
/// already holds the pointer state machine. The clamping arithmetic is
/// `LoopMoving`, where it can be tested at both file boundaries without a model.
extension ViewerModel {

    // MARK: - Marking the range

    /// `⌘A`: the whole file becomes the range. Looping stays as it was — a
    /// range is something you set, looping is something you switch on.
    public func loopWholeFile() {
        guard hasTrack else { return }
        rangeAnchor = nil
        applyLoop(
            LoopRegion(range: FrameRange(start: 0, count: totalFrames), isEnabled: loop.isEnabled))
    }

    /// The loop as the lanes should draw it, without telling the engine yet.
    ///
    /// A range being dragged out starts at zero width, and pushing every step
    /// would switch the engine's loop off and back on under a playing track for
    /// the whole gesture — and drop a loop someone is listening to the moment
    /// they reach for the next passage. So the drag is drawn live and committed
    /// on lift (`commitStagedLoop`), and the old loop plays on until then.
    func stageLoop(_ next: LoopRegion) {
        guard next != loop else { return }
        loop = next
        loopIsStaged = true
    }

    /// Hands a staged loop to the engine, through `applyLoop` — still the
    /// app's one `.setLoop` path; its guard lets an unchanged-but-staged loop
    /// through. A no-op when nothing is staged.
    ///
    /// **And if looping is on, playback goes to the new passage.** The engine
    /// only captures a loop when playback *arrives* at it, so a passage dragged
    /// out behind the playhead while looping would otherwise play on to the end
    /// of the track — on touch, where a press never seeks, every time. One
    /// deliberate seek on lift, as Transcribe! and Anytune do; never a reset at
    /// the loop boundary, which is the thing CLAUDE.md forbids.
    func commitStagedLoop() {
        guard loopIsStaged else { return }
        applyLoop(loop)
        guard loop.isActive, !loop.range.contains(playhead) else { return }
        seek(to: loop.range.start)
    }

    // MARK: - Moving the loop

    /// Slides one of the loop's edges, or the whole region — spec §6.2's
    /// `loop.move` actions.
    ///
    /// **One pair of amounts** (`selectionMoveAmounts`, named for the selection
    /// it was first written for; the stored keys keep that name) rather than a
    /// preference per region. "Nudge a region into place" is one
    /// job with one pair of sizes — a touch and a lot — and it is the same job
    /// whichever edge or region it is.
    ///
    /// The playhead is deliberately left alone: this moves what you are
    /// listening *to*, not where you are
    /// listening *from*, and a seek is one of the two things that reset the
    /// stretcher (CLAUDE.md on looping). Going out through `applyLoop` — the
    /// app's one `PlaybackCommand.setLoop` path — is what makes a move while
    /// playing take effect without a click: the engine adopts the new boundary on
    /// its next feed and never resets there (spec §5.1).
    public func moveLoop(
        _ target: LoopMoveTarget, _ tier: SelectionMoveTier, direction: NudgeDirection
    ) {
        guard hasTrack, !loop.range.isEmpty else { return }
        let moved = LoopMoving.moved(
            loop, target: target, bySeconds: prefs.selectionMoveAmounts[tier] * direction.sign,
            sampleRate: sampleRate, totalFrames: totalFrames)
        guard moved != loop else { return }
        applyLoop(moved)
        // Follow the edge that moved, so a loop nudged off the visible page is
        // not nudged blind. Page-flip, like everything else that moves the view
        // (spec §6.1).
        reveal(revealTarget(for: target, in: moved, direction: direction))
    }

    /// The frame worth having on screen after a loop move: the edge that moved,
    /// and for a whole-loop move the edge it is travelling towards.
    private func revealTarget(
        for target: LoopMoveTarget, in moved: LoopRegion, direction: NudgeDirection
    ) -> FrameIndex {
        switch target {
        case .inPoint: return moved.range.start
        case .outPoint: return moved.range.end
        case .whole: return direction == .backward ? moved.range.start : moved.range.end
        }
    }

    /// `⇧←` / `⇧→` — `loop.extendLeft` / `.extendRight`.
    ///
    /// The anchor edge stays put and the other one moves, which is the same
    /// shape as a ⇧-drag in the lanes and the macOS text convention: press `⇧→`
    /// twice and `⇧←` once, and you are one step out from where you began. It
    /// moves by the **normal nudge amount**, the step `←`/`→` move the playhead
    /// by, so the two arrow gestures agree about how far one press goes.
    ///
    /// With no range, one starts at the playhead, so the key does something
    /// useful from a bare cursor rather than nothing. Looping is left as it was.
    public func extendLoop(_ direction: NudgeDirection) {
        guard hasTrack else { return }
        let range = loop.range
        let anchor: FrameIndex
        let head: FrameIndex
        if range.isEmpty {
            anchor = playhead
            head = playhead
        } else if rangeAnchor == range.end {
            anchor = range.end
            head = range.start
        } else {
            anchor = range.start
            head = range.end
        }
        let moved = NudgeStepping.target(
            from: head, bySeconds: prefs.nudgeAmounts[.normal] * direction.sign,
            sampleRate: sampleRate, totalFrames: totalFrames)
        let low = Swift.min(anchor, moved)
        rangeAnchor = anchor
        applyLoop(
            LoopRegion(
                range: FrameRange(start: low, count: Swift.max(anchor, moved) - low),
                isEnabled: loop.isEnabled))
        reveal(moved)
    }

    /// Brings `frame` onto the visible page if it is off it, and holds still if
    /// it is not. The page-flip rule of `AutoScroll`, asked about an arbitrary
    /// frame rather than about the playhead.
    func reveal(_ frame: FrameIndex) {
        guard let start = AutoScroll.pageStart(revealing: frame, viewport: viewport) else {
            return
        }
        let delta = Double(start - viewport.startFrame) / viewport.framesPerPixel
        guard delta.isFinite, abs(delta) < Double(Int.max) else { return }
        scroll(byPoints: Int(delta.rounded()))
    }
}
