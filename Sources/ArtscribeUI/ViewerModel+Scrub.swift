import ArtscribeKit
import CoreGraphics

/// A lane drag from the playhead's grip: a scrub. See `PlayheadScrub` for the
/// design, and `LaneDragMode` for where it sits in the lanes' precedence.
extension ViewerModel {

    /// The scrub a press at `point` in the lanes would start, or `nil` when it
    /// is not on the playhead's grip — or a loop edge is at least as near.
    func playheadGrip(at point: CGPoint) -> PlayheadScrub? {
        guard hasTrack else { return nil }
        let edges =
            loop.range.isEmpty
            ? []
            : [viewport.pixel(forFrame: loop.range.start), viewport.pixel(forFrame: loop.range.end)]
        return PlayheadScrub.grabbed(
            at: point, playheadX: viewport.pixel(forFrame: playhead),
            lanes: CGSize(width: Double(lanePointWidth), height: laneSize.height),
            reach: prefs.handleReach, loopEdges: edges)
    }

    /// Whether the pointer at `point` is over the playhead's grip — for the
    /// Mac's cursor, which is asked the same question a press is.
    func isOverPlayheadGrip(at point: CGPoint) -> Bool { playheadGrip(at: point) != nil }

    /// One event of a lane drag latched as `.scrub`. Nothing until the press
    /// has travelled far enough to be a drag; then it pauses, and from there
    /// the playhead follows the pointer — drawn, read out and shown in the
    /// picture at once, with the engine told on release.
    func scrubChanged(start: CGPoint, current: CGPoint) {
        // Spent: `play()` took over mid-drag.
        guard var scrub else { return }
        if scrub.resumes == nil {
            let distance = PlayheadScrub.decisionDistance(reach: prefs.handleReach)
            guard
                PlayheadScrub.isADrag(
                    dx: current.x - start.x, dy: current.y - start.y, distance: distance)
            else { return }
            scrub.resumes = isPlaying
            if isPlaying { pause() }
            self.scrub = scrub
        }
        let x = scrub.playheadX(forPointerAt: current.x, width: Double(lanePointWidth))
        let frame = Swift.max(
            0, Swift.min(PixelMapping.frame(atPixel: x, in: viewport), totalFrames))
        if frame != playhead { playhead = frame }
    }

    /// The finger lifted. A scrub lands, and plays again if it was playing; a
    /// press on the grip that never became one is a click **at the press** —
    /// a finger that drifted past the click slop but short of a scrub was
    /// otherwise neither, and did nothing (review finding).
    func scrubEnded(start: CGPoint, end: CGPoint, now: Double) {
        guard let scrub else { return }
        if scrub.resumes == nil {
            self.scrub = nil
            dragEnded(startPixel: start.x, endPixel: start.x, now: now)
        } else {
            landScrub(resuming: true)
        }
    }

    /// The lanes' gesture that began at `start` went away without an end — a
    /// call, an app switch, another recogniser. If it was a scrub it lands
    /// where it was left, without playing, and the lanes let go of it: left
    /// latched on `.scrub`, page-following stayed off and the Mac kept the
    /// sideways cursor until the next lane gesture (review finding).
    ///
    /// A no-op after a normal end, which has already cleared the gesture, and
    /// for any other gesture: the notice arrives a beat late, and must never
    /// land a newer drag mid-flight.
    public func laneGestureCancelled(start: CGPoint) {
        guard laneDragStart == start, laneDragMode == .scrub else { return }
        landScrub(resuming: false)
        laneDragStart = nil
        laneDragMode = nil
        loopBeforeLaneDrag = nil
        playheadBeforeLaneDrag = nil
    }

    /// `play()` arriving mid-scrub — Space, a headphone button, the lock
    /// screen. The scrub lands first, so playback starts from where the finger
    /// put the playhead, and the rest of the drag is spent: from here the
    /// engine moves the playhead, not the finger.
    func landScrubForPlayback() {
        guard let scrub, scrub.resumes != nil else { return }
        self.scrub = nil
        seek(to: playhead)
    }

    /// Lands the scrub in flight, if any: one seek to where the playhead was
    /// left, and — on a normal release only — play again if it was playing. A
    /// press on the grip that never became a drag changed nothing, and is
    /// simply dropped.
    func landScrub(resuming: Bool) {
        guard let scrub else { return }
        self.scrub = nil
        guard let resumes = scrub.resumes else { return }
        seek(to: playhead)
        if resuming && resumes { play() }
    }
}
