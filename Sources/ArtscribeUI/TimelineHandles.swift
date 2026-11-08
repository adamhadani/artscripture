import ArtscribeKit

/// Something on the timeline a pointer can take hold of and move.
///
/// Three: the loop's two edges and its body. The selection's edges went with the
/// selection (2026-11) — the loop is the only range now.
public enum TimelineHandle: Equatable, Sendable, CaseIterable {
    case loopStart
    case loopEnd
    /// The whole loop, moved with its length preserved. Grabbable anywhere
    /// inside its span, at any height, once neither edge is in reach.
    case loopBody

    var isLoop: Bool {
        switch self {
        case .loopStart, .loopEnd, .loopBody: return true
        }
    }

    /// Which side of the region this handle sits on, for the resize cursor and
    /// for which way the guide line's wash falls. `nil` for the body.
    var side: TimelineEdgeSide? {
        switch self {
        case .loopStart: return .leading
        case .loopEnd: return .trailing
        case .loopBody: return nil
        }
    }
}

/// Which end of a region an edge handle is.
public enum TimelineEdgeSide: Equatable, Sendable {
    case leading
    case trailing
}

/// Hit-testing the timeline's draggable handles, and the arithmetic a drag of
/// one produces. Pure, `Viewport`-relative, and therefore testable without a
/// view — which matters, because every interesting case here is a boundary one.
///
/// ## The precedence rule
///
/// A mouse-down in the waveform lanes is resolved in this order, and the answer
/// is latched for the whole gesture (`LaneDragMode`):
///
/// 1. **⌥ held → zoom.** Unchanged, and it wins over everything: an ⌥-drag on
///    top of a loop edge still zooms.
/// 2. **⇧ held → extend the range.** It too wins over a handle: the far edge
///    stays put and the near one follows.
/// 3. **Within reach of a loop edge → drag that edge.** If both are in reach
///    the *nearer* wins. Reach is per input device (`HandleReach`): a finger
///    gets the 44 pt target a pointer does not need.
/// 4. **Inside the loop, at any height → move the whole loop.** Edges are
///    tested first, so a short loop is still resizable from either end. A
///    press that never moves is a click, not a grab: it places the playhead,
///    and two play, exactly as they do outside the loop (`laneDragEnded`).
/// 5. **Outside the loop → a new range**, replacing the loop — looping stays
///    as it was, so a passage dragged out while looping loops at once. A click
///    and a double-click arrive through here too, and leave the range alone.
///
/// ## Why the whole inside of the loop moves it (2026-11)
///
/// From Task 23 until 2026-11 the body was only the 4 pt bars the loop draws
/// along its top and bottom, given a grab band, on the argument that a
/// full-height body would take "drag out a passage" away from the stretch of
/// timeline you are working on. In use it read the other way round. The user,
/// from an iPhone: *"when I drag my finger inside of a looped area typically
/// the intent is to move the whole loop along"* — and on a phone the bars were
/// a strip a finger mostly missed, so the drag redrew the loop from under it.
/// Asked to choose, they took it for the Mac as well, with a click inside
/// still only placing the playhead.
///
/// It is the cycle region's behaviour in Logic and Ableton's loop brace — drag
/// the middle to move it, drag an end to resize it — over the waveform rather
/// than on a strip of its own. Those DAWs keep it to a strip because the space
/// under a loop is where regions are edited; here it had one other use,
/// drawing a new loop over the old one, and that is what this gives up. A new
/// loop is drawn starting outside the current one, or after `Esc` (Clear
/// Loop), or by dragging the edges; `C`/`V` move the whole loop by keyboard.
/// How far from a drawn edge a press still takes hold of it — a question about
/// the input device, not about taste, so it comes from `ControlMetrics` per
/// surface rather than being one constant.
///
/// It used to carry a second number, the depth of the loop body's grab band at
/// the top and bottom of the lanes. The body is the whole inside of the loop
/// now (see above), so there is no band to size.
public struct HandleReach: Equatable, Sendable {
    /// Points either side of a loop edge.
    public let edge: Double

    public init(edge: Double) {
        self.edge = edge
    }

    /// A pointer's: `TimelineHandles.grabRadius`.
    public static let pointer = HandleReach(edge: TimelineHandles.grabRadius)
}

public enum TimelineHandles {

    /// How far either side of a drawn edge counts as grabbing it.
    ///
    /// The edge itself is 2 pt. Nine points of slop on each side makes it a
    /// 20 pt target, which clears Fitts's law comfortably without swallowing
    /// enough of the lane to matter — at any zoom, a plain drag started 10 pt
    /// from an edge still selects.
    public static let grabRadius: Double = 9

    /// The handle under the lanes' pixel column `x`, or `nil` when it is open
    /// lane outside the loop.
    ///
    /// A column, not a point: every handle is full height now that the body is
    /// the whole inside of the loop, so where in the lanes' height a press
    /// lands no longer changes what it takes hold of.
    public static func handle(
        atPixel x: Double,
        loop: LoopRegion,
        viewport: Viewport,
        reach: HandleReach = .pointer
    ) -> TimelineHandle? {
        guard x.isFinite else { return nil }
        if let edge = edge(atPixel: x, loop: loop, viewport: viewport, radius: reach.edge) {
            return edge
        }
        return body(atPixel: x, loop: loop, viewport: viewport)
    }

    /// Step 3 of the precedence rule: the nearest edge within `grabRadius`,
    /// ties going to the loop's.
    ///
    /// The candidates are listed loop-first and the comparison is strict, so a
    /// later candidate only displaces an earlier one by being genuinely nearer.
    /// That is the whole of the tie-break, and it is why it cannot depend on
    /// sort stability.
    private static func edge(
        atPixel x: Double, loop: LoopRegion, viewport: Viewport, radius: Double
    ) -> TimelineHandle? {
        var candidates: [(TimelineHandle, FrameIndex)] = []
        if !loop.range.isEmpty {
            candidates.append((.loopStart, loop.range.start))
            candidates.append((.loopEnd, loop.range.end))
        }
        var bestHandle: TimelineHandle?
        var bestDistance = Double.infinity
        for (handle, frame) in candidates {
            let distance = abs(viewport.pixel(forFrame: frame) - x)
            guard distance.isFinite, distance <= radius, distance < bestDistance else {
                continue
            }
            bestHandle = handle
            bestDistance = distance
        }
        return bestHandle
    }

    /// Step 4: anywhere within the loop's own span.
    private static func body(
        atPixel x: Double, loop: LoopRegion, viewport: Viewport
    ) -> TimelineHandle? {
        guard !loop.range.isEmpty else { return nil }
        let startX = viewport.pixel(forFrame: loop.range.start)
        let endX = viewport.pixel(forFrame: loop.range.end)
        guard startX.isFinite, endX.isFinite else { return nil }
        return x >= startX && x <= endX ? .loopBody : nil
    }

    /// The edge that stays put while `handle` is dragged. `nil` for the body,
    /// which pivots on nothing.
    public static func anchor(
        for handle: TimelineHandle, loop: LoopRegion
    ) -> FrameIndex? {
        switch handle {
        case .loopStart: return loop.range.end
        case .loopEnd: return loop.range.start
        case .loopBody: return nil
        }
    }

    /// The region an edge drag produces: the fixed `anchor` and wherever the
    /// pointer has got to, in whichever order they now stand.
    ///
    /// **Inversion swaps, it does not clamp.** Dragging the in point past the
    /// out point hands the drag to the other edge and carries on following the
    /// pointer, which is what Ableton and Logic both do. Clamping at zero length
    /// would leave the pointer moving with nothing happening — the "the app has
    /// stopped responding" feeling — and, worse, would strand the region
    /// collapsed and invisible at the crossing point. It is also the stance the
    /// rest of this app already takes: `LoopEditing.settingIn`/`settingOut`
    /// refuse to collapse the loop when `A` and `S` cross, pushing the other
    /// edge to a file boundary instead.
    ///
    /// The region is empty only at the single frame where the two coincide, and
    /// `LoopRegion.isActive` already treats an empty region as not looping, so
    /// nothing downstream needs to know about that instant.
    public static func resized(
        anchor: FrameIndex, to frame: FrameIndex, totalFrames: FrameIndex
    ) -> FrameRange {
        let fixed = clamp(anchor, totalFrames)
        let moving = clamp(frame, totalFrames)
        let lo = Swift.min(fixed, moving)
        let hi = Swift.max(fixed, moving)
        return FrameRange(start: lo, count: hi - lo)
    }

    /// The region a body drag produces: the same length, somewhere else.
    ///
    /// Clamped **as a whole** rather than edge by edge, exactly as
    /// `Selection.translated(by:within:)` is: a loop pushed against the end of
    /// the file stops there with its length intact instead of shrinking against
    /// the wall. A region longer than the file — which nothing in the app can
    /// make, but a hand-edited sidecar can — has no legal position, so it is
    /// clamped to the file.
    public static func moved(
        _ range: FrameRange, toStart start: FrameIndex, totalFrames: FrameIndex
    ) -> FrameRange {
        let length = Swift.max(0, range.count)
        guard length < totalFrames else { return range.clamped(to: totalFrames) }
        let bounded = Swift.max(0, Swift.min(start, totalFrames - length))
        return FrameRange(start: bounded, count: length)
    }

    private static func clamp(_ frame: FrameIndex, _ totalFrames: FrameIndex) -> FrameIndex {
        Swift.max(0, Swift.min(frame, totalFrames))
    }
}
