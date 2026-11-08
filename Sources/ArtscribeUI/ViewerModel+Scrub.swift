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
    /// is a new gesture. A scrub still pending from an earlier one — its end
    /// and its cancel both lost — is landed with a seek, so the engine is not
    /// left somewhere other than the playhead, and *never* by playing.
    public func rulerDragChanged(start: CGPoint, current: CGPoint) {
        guard hasTrack else { return }
        if rulerDrag?.startX != start.x { latchRulerDrag(atX: start.x) }
        switch rulerDrag {
        case .scrub(let latched):
            let scrub =
                latched.resumes == nil
                ? decideGripDrag(latched, start: start, current: current) : latched
            if let scrub { moveScrubbedPlayhead(scrub, pointerX: current.x) }
        case .spent:
            return
        case .zoom, nil:
            zoomDragChanged(start: start, current: current)
        }
    }

    /// A new press: the grip's scrub-to-be, or the zoom.
    private func latchRulerDrag(atX x: Double) {
        finishScrub(resuming: false)
        let grabbed = PlayheadScrub.grabbed(
            atX: x, playheadX: viewport.pixel(forFrame: playhead),
            reach: prefs.handleReach, width: Double(lanePointWidth))
        rulerDrag = grabbed.map(RulerDrag.scrub) ?? .zoom(startX: x)
    }

    /// A press on the grip that has not decided yet. Returns the scrub once it
    /// is one (and has paused); `nil` while it is still a tap, or once it has
    /// turned out to be the zoom — which it hands over to here, from where it
    /// began.
    private func decideGripDrag(
        _ scrub: PlayheadScrub, start: CGPoint, current: CGPoint
    ) -> PlayheadScrub? {
        let decided = PlayheadScrub.isScrub(
            dx: current.x - start.x, dy: current.y - start.y,
            distance: PlayheadScrub.decisionDistance(reach: prefs.handleReach))
        switch decided {
        case nil:
            return nil
        case false?:
            rulerDrag = .zoom(startX: start.x)
            zoomDragChanged(start: start, current: current)
            return nil
        case true?:
            var begun = scrub
            begun.resumes = isPlaying
            if isPlaying { pause() }
            rulerDrag = .scrub(begun)
            return begun
        }
    }

    /// Drawn, read out and shown in the picture at once; the engine is told on
    /// release. Paused, nothing polls over it (`tickPlayback`).
    private func moveScrubbedPlayhead(_ scrub: PlayheadScrub, pointerX: Double) {
        let x = scrub.playheadX(forPointerAt: pointerX, width: Double(lanePointWidth))
        let frame = Swift.max(
            0, Swift.min(PixelMapping.frame(atPixel: x, in: viewport), totalFrames))
        if frame != playhead { playhead = frame }
    }

    /// The finger lifted: a scrub lands, and plays again if it was playing.
    public func rulerDragEnded() {
        if case .zoom = rulerDrag { zoomDragEnded() }
        finishScrub(resuming: true)
        rulerDrag = nil
    }

    /// The gesture was cancelled rather than ended — a call, an app switch,
    /// another recogniser. A scrub lands where it was left, without playing:
    /// whatever cancelled it is a reason not to start the music. A no-op after
    /// a normal end, which has already cleared the drag.
    public func rulerDragCancelled() {
        if case .zoom = rulerDrag { zoomDragEnded() }
        finishScrub(resuming: false)
        rulerDrag = nil
    }

    /// `play()` arriving mid-scrub — Space, a headphone button, the lock
    /// screen. The scrub lands first, so playback starts from where the finger
    /// put the playhead, and the rest of the drag is spent: from here the
    /// engine moves the playhead, not the finger.
    func landScrubForPlayback() {
        guard case .scrub(let scrub) = rulerDrag, scrub.resumes != nil else { return }
        rulerDrag = .spent(startX: scrub.startX)
        seek(to: playhead)
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
    /// — on a normal release only — play again if it was playing. A press on
    /// the grip that never became a scrub changed nothing and has nothing to
    /// land.
    private func finishScrub(resuming: Bool) {
        guard case .scrub(let scrub) = rulerDrag, let resumes = scrub.resumes else { return }
        rulerDrag = nil
        seek(to: playhead)
        if resuming && resumes { play() }
    }
}
