import CoreGraphics

/// **Scrubbing: dragging the playhead by its grip.**
///
/// Asked for from an iPhone, with a video open (2026-11): *"dragging the
/// playhead with my finger would be good to quickly move through audio/frames
/// … I can see the frames scroll by quickly as I drag my finger"*, and once a
/// drag inside the loop moves the loop (PR #86) there was no other gesture
/// left for it. The user's own suggestion: give the playhead *"that
/// 'draggable handles' ui"* the loop's edges have, and scrub when that is
/// dragged.
///
/// ## Where the grip is
///
/// Halfway down the waveform lanes, on the playhead, in the loop grips' shape
/// (`PlayheadGrip`) and in line with them. It first shipped on the time ruler
/// (PR #93), on the argument that the lanes hold every loop gesture; in use a
/// grip between the overview and the waveform read as wrong: *"the dragging
/// handle being in the middle of the two wave forms is weird. I thought we'd
/// put it in line with where the looping draggable handles are (e.g. middle of
/// main waveform)"*. The ruler went back to being the zoom drag alone.
///
/// ## Sharing the lanes with the loop
///
/// It is a grip, not a column: only a press on the tab — its height, and the
/// edges' reach either side — takes it (`PlayheadGrip.target`). Above and
/// below it the playhead's line is loop body or open lane exactly as before,
/// so moving the loop or drawing a new one from that column still works.
///
/// Where the grip and a loop edge are both in reach — the playhead parked on a
/// loop's start, which is where a new loop puts it — **a press on the edge's
/// drawn tab is always the edge's**, and elsewhere **the nearer wins, a tie
/// going to the edge** (the edges' own rule between themselves). The loop's
/// grips are drawn over the playhead's, so the tab you can see on top is the
/// one a press takes, and resizing a loop works as it always did — including
/// on a playing loop, where the playhead sweeps past each edge every
/// repetition and "nearer" alone made the same press resize or scrub
/// depending on when it landed.
///
/// ## A drag, not a press
///
/// A press on the grip decides nothing until it has travelled
/// `decisionDistance` **sideways** — then it is a scrub. One that never does
/// is a click at the press, like any other in the lanes, however much a
/// finger wobbled on the way: it places the playhead, and two play. (Up or
/// down never scrubs: a vertical wobble while playing would pause, seek to
/// the same spot and play — an audible hiccup for nothing.)
///
/// ## What a scrub does to the engine
///
/// It pauses (once the press is a drag) and moves the model's playhead, which
/// the lanes, the readout and the video picture all follow — the picture is
/// driven from the playhead on every tick, paused too, and shows each frame
/// the decoder finishes while the finger is still moving (`VideoFrameSource`).
/// The engine is told **once**, on release (`seek(to:)`), and plays again if
/// it was playing. A seek per finger event would reset the stretcher sixty
/// times a second for nothing anyone could hear.
///
/// ## When it does not end normally
///
/// - **Cancelled** (a call, an app switch): landed with the seek and *without*
///   playing again — noticed through the lanes' gesture state, which resets on
///   cancel as on end. Whatever cancelled it is a reason not to start music.
/// - **Taken over by a pinch** (its first finger landed on the grip): put back
///   the way a pinch puts back any lane drag — the playhead where it was, and
///   playing again if it was.
/// - **Play pressed mid-scrub** (Space, headphones, the lock screen): `play()`
///   lands the scrub first, so playback starts from where the finger is, and
///   the rest of that drag is spent.
/// - **The track closes or changes**: dropped, like any lane gesture.
/// - A scrub still pending when the next lane gesture starts is landed with
///   the seek alone — never by starting playback from an unrelated gesture.
struct PlayheadScrub: Equatable {
    /// Where the press began, in lane points: the gesture's identity.
    let startX: Double
    /// Pointer minus playhead at the press, kept for the whole drag, so the
    /// playhead does not jump to the middle of the finger.
    let grabOffset: Double
    /// Whether to play again on release. `nil` until the press has travelled
    /// far enough to be a drag — which is when it pauses.
    var resumes: Bool?

    /// The scrub a press at `point` could become, or `nil` when it is not on
    /// the grip, when a loop edge is at least as near, or when the playhead is
    /// off the page and has no grip.
    static func grabbed(
        at point: CGPoint, playheadX: Double, lanes: CGSize, reach: HandleReach,
        loopEdges: [Double]
    ) -> PlayheadScrub? {
        guard playheadX >= 0, playheadX <= lanes.width else { return nil }
        let target = PlayheadGrip.target(
            atX: playheadX, laneHeight: lanes.height, reach: reach)
        guard point.x >= target.minX, point.x <= target.maxX,
            point.y >= target.minY, point.y <= target.maxY
        else { return nil }
        let distance = abs(point.x - playheadX)
        let edgeTab = LoopGrip.tab(atX: 0, laneHeight: lanes.height, reach: reach).width / 2
        let anEdgeWins = loopEdges.contains { edge in
            let toEdge = abs(point.x - edge)
            return toEdge <= edgeTab || (toEdge <= reach.edge && toEdge <= distance)
        }
        guard !anEdgeWins else { return nil }
        return PlayheadScrub(startX: point.x, grabOffset: point.x - playheadX)
    }

    /// Whether a press on the grip has travelled far enough sideways to be a
    /// scrub rather than a click. `dy` is taken and ignored on purpose: up or
    /// down is never a scrub.
    static func isADrag(dx: Double, dy: Double, distance: Double) -> Bool {
        abs(dx) >= distance
    }

    /// How far a press on the grip travels before it is a scrub: the click
    /// slop with a pointer, more under a finger, whose first points wobble.
    static func decisionDistance(reach: HandleReach) -> Double {
        reach.edge > HandleReach.pointer.edge ? 10 : 3
    }

    /// Where the playhead goes with the pointer at `x`: at its grab offset,
    /// and held to the visible page.
    func playheadX(forPointerAt x: Double, width: Double) -> Double {
        Swift.min(Swift.max(x - grabOffset, 0), width)
    }
}

/// The playhead's grip: the loop grips' exact shape and size (`LoopGrip`), in
/// the playhead's colour, halfway down the lanes — in line with them.
enum PlayheadGrip {
    /// The drawn tab.
    static func tab(atX x: Double, laneHeight: Double, reach: HandleReach) -> CGRect {
        LoopGrip.tab(atX: x, laneHeight: laneHeight, reach: reach)
    }

    /// What a press has to land on to take it: the edges' reach either side of
    /// the playhead, and the tab's height or `2 × reach` — a finger's 44 pt —
    /// whichever is taller, never more than the lanes.
    static func target(atX x: Double, laneHeight: Double, reach: HandleReach) -> CGRect {
        let drawn = tab(atX: x, laneHeight: laneHeight, reach: reach)
        let height = Swift.min(laneHeight, Swift.max(drawn.height, 2 * reach.edge))
        return CGRect(
            x: x - reach.edge, y: laneHeight / 2 - height / 2, width: 2 * reach.edge,
            height: height)
    }
}
