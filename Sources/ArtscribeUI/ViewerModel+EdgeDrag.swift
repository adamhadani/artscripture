import ArtscribeKit
import CoreGraphics

/// The loop's edges and body, dragged (Task 23).
///
/// **An edge moves by how far the pointer moved, and only once it has moved past
/// the click slop** (2026-11). It used to jump to wherever the pointer was —
/// harmless inside a pointer's 9 pt reach, but a finger's is 22, and every tap
/// near a loop moved its edge, pushed it and saved it. Below the slop it is not
/// a drag at all, and on touch it is a tap (`LaneDragPolicy.edgeTapIsAClick`).
///
/// The arithmetic is all in `TimelineHandles`, which is pure and tested on its
/// own; what lives here is the state machine — latching what was grabbed at
/// mouse-down and holding it, so that an edge dragged past its opposite number
/// keeps following the pointer instead of becoming a different gesture.
///
/// A loop edge dragged during playback goes through `applyLoop`, which is the
/// app's one and only `PlaybackCommand.setLoop` path. That is deliberate: the
/// engine wraps at the boundary it is fed and never resets the stretcher there
/// (spec §5.1), so an edge moved mid-loop takes effect on the next pass with no
/// click and no dropout. There is no second path to invent.
extension ViewerModel {

    /// What the guide line, the live readout and the cursor draw from while an
    /// edge or the loop body is being dragged. `nil` between gestures.
    ///
    /// Observed, unlike `laneDragStart` and `zoomDrag`: the readout has to
    /// follow the pointer, so this one really is drawn from. It is written once
    /// per pointer event, which is the rate the selection and the loop are
    /// already written at during any drag.
    public struct EdgeDrag: Equatable, Sendable {
        public let handle: TimelineHandle
        /// Where the gesture began, which is what identifies it across events —
        /// the same reasoning `dragChanged` records for `dragOrigin`.
        let startPixel: Double
        /// The edge that stays put. `nil` for a body drag, which pivots on
        /// nothing.
        let anchorFrame: FrameIndex?
        /// Body drag: the region as it stood at mouse-down, and how far into it
        /// the pointer took hold.
        let originalRange: FrameRange
        let grabOffset: FrameIndex
        /// The frame under the pointer when it went down. An edge moves by the
        /// pointer's travel from here, not to the pointer.
        let grabbedFrame: FrameIndex
        /// Whether the gesture has travelled past the click slop. Until then
        /// nothing moves, and lifting there is a tap, not an edit.
        public internal(set) var hasMoved = false
        /// The frame the guide and the readout show: the moving edge, or the
        /// region's new start for a body drag.
        public internal(set) var currentFrame: FrameIndex

        /// Which side of the region the guide is on *now*.
        ///
        /// Recomputed rather than latched, because a drag past the opposite edge
        /// swaps them: the in point you grabbed is the out point you are now
        /// holding, and the wash has to fall the other way.
        public var side: TimelineEdgeSide? {
            guard let anchorFrame else { return nil }
            return currentFrame <= anchorFrame ? .leading : .trailing
        }
    }

    /// The handle under a point in the lanes, for the hover treatment and the
    /// cursor. Answers `nil` with no track, so an empty window offers nothing.
    /// Only the point's `x` decides it: every handle is full height.
    public func timelineHandle(at point: CGPoint) -> TimelineHandle? {
        guard hasTrack else { return nil }
        return TimelineHandles.handle(
            atPixel: point.x, loop: loop, viewport: viewport, reach: prefs.handleReach)
    }

    /// One event of a handle drag.
    ///
    /// The grabbed handle, its anchor and the region's original length are all
    /// read **once**, on the gesture's first event. Re-reading them per event
    /// would chase a moving target — after the first event the loop is no longer
    /// where it was — and would turn a drag past the opposite edge into an
    /// edge that ran away from the pointer.
    func edgeDragChanged(handle: TimelineHandle, startPixel: Double, currentPixel: Double) {
        guard hasTrack else { return }
        var drag =
            liveEdgeDrag(handle: handle, startPixel: startPixel)
            ?? beganEdgeDrag(handle: handle, atPixel: startPixel)
        guard drag.hasMoved || abs(currentPixel - startPixel) >= Self.clickSlopPoints else {
            edgeDrag = drag
            return
        }
        drag.hasMoved = true
        let pointer = PixelMapping.frame(atPixel: currentPixel, in: viewport)
        let travel = pointer - drag.grabbedFrame
        switch handle {
        case .loopStart, .loopEnd:
            let edge = handle == .loopStart ? drag.originalRange.start : drag.originalRange.end
            let moved = Swift.max(0, Swift.min(edge + travel, totalFrames))
            let range = TimelineHandles.resized(
                anchor: drag.anchorFrame ?? moved, to: moved, totalFrames: totalFrames)
            applyLoop(LoopRegion(range: range, isEnabled: loop.isEnabled))
            drag.currentFrame = moved
        case .loopBody:
            let range = TimelineHandles.moved(
                drag.originalRange, toStart: pointer - drag.grabOffset, totalFrames: totalFrames)
            applyLoop(LoopRegion(range: range, isEnabled: loop.isEnabled))
            drag.currentFrame = range.start
        }
        edgeDrag = drag
    }

    func edgeDragEnded() {
        edgeDrag = nil
    }

    /// The gesture already in flight, when this event belongs to it.
    ///
    /// Identified by its start point and its handle rather than by "is there
    /// one?", so a gesture whose end phase never ran — a cancelled drag, or one
    /// another recognizer took — cannot leak its anchor into the next drag. The
    /// same self-correcting shape as `dragChanged`'s `dragOrigin` check.
    private func liveEdgeDrag(handle: TimelineHandle, startPixel: Double) -> EdgeDrag? {
        guard let live = edgeDrag, live.handle == handle, live.startPixel == startPixel else {
            return nil
        }
        return live
    }

    private func beganEdgeDrag(handle: TimelineHandle, atPixel pixel: Double) -> EdgeDrag {
        let grabbed = PixelMapping.frame(atPixel: pixel, in: viewport)
        let region = loop.range
        return EdgeDrag(
            handle: handle,
            startPixel: pixel,
            anchorFrame: TimelineHandles.anchor(for: handle, loop: loop),
            originalRange: region,
            grabOffset: grabbed - region.start,
            grabbedFrame: grabbed,
            currentFrame: handle == .loopBody ? region.start : grabbed)
    }
}
