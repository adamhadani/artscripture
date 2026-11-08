import ArtscribeKit
import CoreGraphics

/// A drag on the time ruler: the zoom, or — from the playhead's grip, sideways
/// — a scrub. See `PlayheadScrub` for the design and why it lives here and not
/// in the lanes.
extension ViewerModel {

    /// One event of a ruler drag, in ruler points (the lanes' x, since the two
    /// are full-width siblings).
    ///
    /// The press is latched by its start point, like a lane drag: a new start
    /// is a new gesture, which also covers one whose end never arrived — and a
    /// scrub left that way is landed first, so the engine is never left
    /// pointing somewhere other than the playhead.
    public func rulerDragChanged(start: CGPoint, current: CGPoint) {
        guard hasTrack else { return }
        if rulerDrag?.startX != start.x {
            finishScrub()
            let grabbed = PlayheadScrub.grabbed(
                atX: start.x, playheadX: viewport.pixel(forFrame: playhead),
                reach: prefs.handleReach, width: Double(lanePointWidth))
            rulerDrag = grabbed.map(RulerDrag.scrub) ?? .zoom(startX: start.x)
        }
        guard case .scrub(var scrub) = rulerDrag else {
            zoomDragChanged(start: start, current: current)
            return
        }
        if scrub.resumes == nil {
            let decided = PlayheadScrub.isScrub(
                dx: current.x - start.x, dy: current.y - start.y, slop: Self.clickSlopPoints)
            switch decided {
            case nil:
                return
            case false?:
                // Up or down from the grip: the zoom, from where it began.
                rulerDrag = .zoom(startX: start.x)
                zoomDragChanged(start: start, current: current)
                return
            case true?:
                scrub.resumes = isPlaying
                if isPlaying { pause() }
                rulerDrag = .scrub(scrub)
            }
        }
        let x = scrub.playheadX(forPointerAt: current.x, width: Double(lanePointWidth))
        let frame = Swift.max(
            0, Swift.min(PixelMapping.frame(atPixel: x, in: viewport), totalFrames))
        // Drawn, read out and shown in the picture at once; the engine is told
        // on release. Paused, nothing polls over it (`tickPlayback`).
        if frame != playhead { playhead = frame }
    }

    public func rulerDragEnded() {
        if case .zoom = rulerDrag { zoomDragEnded() }
        finishScrub()
        rulerDrag = nil
    }

    /// Whether the pointer at `x` is over the playhead's grip — for the Mac's
    /// cursor, which is asked the same question the press is.
    func isOverPlayheadGrip(atX x: Double) -> Bool {
        hasTrack
            && PlayheadScrub.grabbed(
                atX: x, playheadX: viewport.pixel(forFrame: playhead),
                reach: prefs.handleReach, width: Double(lanePointWidth)) != nil
    }

    /// Lands a scrub that began: one seek to where the playhead was left, and
    /// play again if it was playing. A press on the grip that never became a
    /// scrub changed nothing and has nothing to land.
    private func finishScrub() {
        guard case .scrub(let scrub) = rulerDrag, let resumes = scrub.resumes else { return }
        rulerDrag = nil
        seek(to: playhead)
        if resumes { play() }
    }
}
