import ArtscribeKit
import CoreGraphics

/// Something on the timeline a pointer can take hold of and move.
///
/// Three: the loop's two edges and its body. The selection's edges went with the
/// selection (2026-11) — the loop is the only range now.
public enum TimelineHandle: Equatable, Sendable, CaseIterable {
    case loopStart
    case loopEnd
    /// The whole loop, moved with its length preserved. Grabbable only on the
    /// bars the loop draws along the top and bottom of the lanes.
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
/// 4. **On the loop's top or bottom bar, inside its span → move the whole
///    loop.** Edges are tested first.
/// 5. **Anything else → a new range**, replacing the loop — looping stays as
///    it was, so a passage dragged out while looping loops at once. A click
///    and a double-click arrive through here too, and leave the range alone.
///
/// ## Why the loop body is only the bars
///
/// A full-height body handle over the loop would take "drag out a passage" —
/// the app's most-used gesture — away from precisely the stretch of timeline you
/// are working on. So the body handle lives where the ink is: the 4 pt bars the
/// loop already draws along the top and bottom of the lanes, given a grab band
/// (14 pt for a pointer, 22 for a finger). Ableton's loop brace works the same
/// way and for the same reason. `C`/`V` move the whole loop by keyboard.
/// How far from a drawn handle a press still takes hold of it — a question
/// about the input device, not about taste, so it comes from `ControlMetrics`
/// per surface rather than being one constant.
public struct HandleReach: Equatable, Sendable {
    /// Points either side of a loop edge.
    public let edge: Double
    /// Depth of the loop-body grab band at the top and the bottom of the lanes.
    public let bodyBand: Double

    public init(edge: Double, bodyBand: Double) {
        self.edge = edge
        self.bodyBand = bodyBand
    }

    /// A pointer's: `TimelineHandles.grabRadius` and `.bodyBandHeight`.
    public static let pointer = HandleReach(
        edge: TimelineHandles.grabRadius, bodyBand: TimelineHandles.bodyBandHeight)
}

public enum TimelineHandles {

    /// How far either side of a drawn edge counts as grabbing it.
    ///
    /// The edge itself is 2 pt. Nine points of slop on each side makes it a
    /// 20 pt target, which clears Fitts's law comfortably without swallowing
    /// enough of the lane to matter — at any zoom, a plain drag started 10 pt
    /// from an edge still selects.
    public static let grabRadius: Double = 9

    /// How deep the loop-body grab band is at the top and at the bottom.
    /// The drawn bar is 4 pt; 14 makes it hittable while leaving the great
    /// majority of the lane to the range drag.
    public static let bodyBandHeight: Double = 14

    /// The handle under `point`, or `nil` when the pointer is over open lane.
    ///
    /// - Parameters:
    ///   - point: local to the waveform lanes, top-left origin.
    ///   - laneHeight: the lanes' height, which is what makes "the bottom bar"
    ///     a position rather than a guess.
    public static func handle(
        at point: CGPoint,
        laneHeight: Double,
        loop: LoopRegion,
        viewport: Viewport,
        reach: HandleReach = .pointer
    ) -> TimelineHandle? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let edge = edge(
            atPixel: point.x, loop: loop, viewport: viewport, radius: reach.edge)
        if let edge { return edge }
        return body(
            at: point, laneHeight: laneHeight, loop: loop, viewport: viewport,
            band: reach.bodyBand)
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

    /// Step 4: the loop's own bars, and only within its own span.
    private static func body(
        at point: CGPoint, laneHeight: Double, loop: LoopRegion, viewport: Viewport,
        band bandHeight: Double
    ) -> TimelineHandle? {
        guard !loop.range.isEmpty, laneHeight > 0 else { return nil }
        // Never more than a quarter of the lane at each end, however short the
        // lane gets. Two fixed 14 pt bands in a 28 pt lane would leave no lane
        // at all, and the plain drag — which selects — would vanish from a
        // window the user had merely made small.
        let band = Swift.min(bandHeight, laneHeight / 4)
        let onABar = point.y < band || point.y > laneHeight - band
        guard onABar else { return nil }
        let startX = viewport.pixel(forFrame: loop.range.start)
        let endX = viewport.pixel(forFrame: loop.range.end)
        guard startX.isFinite, endX.isFinite else { return nil }
        return point.x >= startX && point.x <= endX ? .loopBody : nil
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
