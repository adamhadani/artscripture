import ArtscribeKit
import CoreGraphics

/// Everything the user can do to the view: zoom, pan, and mark a range.
///
/// Split out of `ViewerModel` so the state and loading half stays readable. All
/// of it is deliberately guarded — calling any of these without a loaded track,
/// or with an empty range, is a no-op rather than an error, because the menu
/// bar can invoke them at any time.
extension ViewerModel {

    public func zoomIn() { zoom(by: Self.zoomStep) }
    public func zoomOut() { zoom(by: 1 / Self.zoomStep) }

    /// Zoom always anchors on the playhead — never the viewport centre, which
    /// slides the thing you are looking at out from under the pointer (spec
    /// §6.1). It used to prefer a selection's start; the range that replaced the
    /// selection is the loop, which persists, and anchoring every zoom on it
    /// would move the anchor away from the playhead for as long as a loop is set.
    public var zoomAnchor: FrameIndex { playhead }

    public func zoom(by factor: Double, anchorFrame: FrameIndex? = nil) {
        guard hasTrack else { return }
        viewport.zoom(by: factor, anchorFrame: anchorFrame ?? zoomAnchor)
        refresh()
    }

    /// Zoom driven by the pointer — a wheel, a pinch, or a `⌘`-scroll.
    ///
    /// It anchors on the frame under the pointer, not on the playhead: a
    /// cursor-driven zoom that anchors elsewhere slides the thing you are
    /// pointing at out from under you. Over the overview strip the anchor is a
    /// frame in the *whole file* and it is still the main viewport that zooms —
    /// the strip is always fitted. With the pointer over neither lane (or before
    /// the first layout pass) this is exactly `zoom(by:)`, playhead-anchored.
    ///
    /// - Parameter point: pointer position in window content coordinates.
    public func zoom(by factor: Double, at point: CGPoint?) {
        guard hasTrack else { return }
        guard
            let point,
            let target = PointerZoom.target(at: point, lanes: laneFrame, overview: overviewFrame)
        else {
            zoom(by: factor)
            return
        }
        switch target {
        case .lanes(let x):
            zoom(by: factor, anchorFrame: PixelMapping.frame(atPixel: x, in: viewport))
        case .overview(let x):
            zoom(
                by: factor,
                anchorFrame: PixelMapping.overviewFrame(
                    atPixel: x, totalFrames: totalFrames, width: overviewFrame.width))
        }
    }

    /// Pinch-to-zoom on the waveform lanes.
    ///
    /// `x` is in the **lanes' own** coordinate space, not the window's — which is
    /// why this exists rather than the view calling `zoom(by:at:)`. That one
    /// takes a window point because a pointer can be over the lanes, the
    /// overview strip, or neither; a pinch arrives already attached to the view
    /// it happened on, so the hit-testing step is not merely unnecessary but
    /// wrong: converting to window coordinates and back can land the anchor in
    /// the overview strip when the lanes are short.
    ///
    /// The mapping is direct — `Viewport.zoom(by:)` treats a factor above 1 as
    /// zooming in, and so does `MagnifyGesture.magnification`. Anchoring on the
    /// frame under the fingers is the whole point: a pinch that anchored on the
    /// playhead would slide the passage you are pinching out from under them.
    public func pinchZoom(by factor: Double, atLaneX x: CGFloat) {
        guard hasTrack, factor > 0, factor.isFinite, x.isFinite else { return }
        zoom(by: factor, anchorFrame: PixelMapping.frame(atPixel: x, in: viewport))
    }

    // MARK: - Drag to zoom

    /// How far the drag-to-zoom travels per doubling. Published so the
    /// acceptance run can assert the *rate* a real pointer drag produces rather
    /// than its direction alone: a `.local` coordinate space that arrived
    /// scaled or offset would still zoom, and only the number catches it.
    public static var zoomDragPointsPerDoubling: Double { ZoomDrag.pointsPerDoubling }

    /// A vertical drag that zooms, smoothly and continuously: bare on the time
    /// ruler, ⌥-modified in the waveform lanes. See `ZoomDrag` for the maths
    /// and the direction, and for why the natural-scrolling preference does not
    /// enter into a drag.
    ///
    /// - Parameters:
    ///   - start: where the drag began, local to the dragged view. Its `x` is
    ///     the anchor: the frame under it when the mouse went down stays under
    ///     it for the whole gesture.
    ///   - current: where the pointer is now, in the same space. Only `y` is
    ///     used. **Horizontal travel is deliberately ignored** rather than
    ///     panning as Ableton's ruler does: the gesture's whole contract is
    ///     that the frame under the cursor holds still, and panning at the same
    ///     time would slide it out from under the pointer — as would any
    ///     sideways wobble during what the hand meant as a vertical drag. The
    ///     app has three other ways to pan.
    public func zoomDragChanged(start: CGPoint, current: CGPoint) {
        guard hasTrack else { return }
        var gesture =
            liveZoomDrag(startingAt: start)
            ?? ZoomDrag(
                start: start,
                anchorFrame: PixelMapping.frame(atPixel: start.x, in: viewport),
                startFramesPerPixel: viewport.framesPerPixel,
                // Latched with the gesture, not read per event: see `ZoomDrag`.
                inverted: prefs.invertZoomDrag)
        defer { zoomDrag = gesture }
        guard
            let factor = gesture.factor(
                atY: current.y, currentFramesPerPixel: viewport.framesPerPixel)
        else { return }
        zoom(by: factor, anchorFrame: gesture.anchorFrame)
        gesture.appliedFramesPerPixel = viewport.framesPerPixel
    }

    /// The gesture already in flight, when this event belongs to it: same start
    /// point, and nothing else has moved the viewport since its last event.
    /// `nil` otherwise, which starts a fresh gesture from wherever the viewport
    /// now is — see `ZoomDrag.appliedFramesPerPixel`.
    private func liveZoomDrag(startingAt start: CGPoint) -> ZoomDrag? {
        guard let live = zoomDrag, live.start == start else { return nil }
        return live.appliedFramesPerPixel == viewport.framesPerPixel ? live : nil
    }

    public func zoomDragEnded() {
        zoomDrag = nil
    }

    // MARK: - The range

    /// A drag in the waveform lane, which marks *the* range — the loop, since
    /// the 2026-11 change that removed the separate selection. `extending` is
    /// shift-drag: it keeps the far edge and moves the near one.
    ///
    /// The "is this a new drag" check compares against `startPixel` rather than
    /// testing `dragOrigin == nil`. `DragGesture.Value.startLocation` is stable
    /// for the whole lifetime of one drag, so a mismatch always means a new
    /// gesture started — this is self-correcting even if `dragEnded` never ran
    /// (a cancelled gesture, or another gesture winning the recognizer race),
    /// where a nil-only check would leave `dragOrigin` stuck from the previous
    /// drag and silently extend its range from a stale anchor.
    ///
    /// **Nothing is staged until the gesture moves past the click slop.** A
    /// touch-down arrives here as a change (`DragGesture(minimumDistance: 0)`),
    /// and a range begun on it would replace a playing loop with an empty one
    /// on every tap. The range is *staged* — drawn, not yet played — and
    /// `dragEnded` commits it; see `stageLoop`.
    public func dragChanged(startPixel: Double, currentPixel: Double, extending: Bool) {
        guard hasTrack else { return }
        if dragOrigin != startPixel {
            dragOrigin = startPixel
            let pressed = PixelMapping.frame(atPixel: startPixel, in: viewport)
            if extending && !loop.range.isEmpty {
                let range = loop.range
                let startIsFarther = abs(pressed - range.start) > abs(pressed - range.end)
                rangeAnchor = startIsFarther ? range.start : range.end
            } else {
                rangeAnchor = pressed
                // **Not on touch.** See `LaneDragPolicy`: a finger going down is
                // the start of a gesture nobody has decided the meaning of yet,
                // and seeking there interrupts playback exactly when someone is
                // reaching for a passage. A tap still seeks, from `dragEnded`.
                if prefs.seeksOnSelectionPress { seek(to: pressed) }
            }
        }
        guard abs(currentPixel - startPixel) >= Self.clickSlopPoints, let anchor = rangeAnchor
        else { return }
        let head = PixelMapping.frame(atPixel: currentPixel, in: viewport)
        // Deep in, a few points can still be less than a frame; an empty range
        // committed on lift would clear the loop rather than make a new one.
        guard head != anchor else { return }
        let low = Swift.min(anchor, head)
        stageLoop(
            LoopRegion(
                range: FrameRange(start: low, count: Swift.max(anchor, head) - low),
                isEnabled: loop.isEnabled))
    }

    /// Ends a drag. A drag that never really moved is a click: it places the
    /// playhead and leaves the range alone, and two of them in quick succession
    /// do that **and start playing from there**.
    ///
    /// Double-click was Select All until Task 22. `⌘A` still is, so nothing was
    /// lost — only the gesture was reassigned, to the thing a transcriber
    /// actually wants from pointing at a spot twice.
    ///
    /// It plays from the click point and from nowhere else. In particular it is
    /// **not** routed through `PlaybackStart`, which is what `⇧Space` uses: that
    /// rule picks a start when the user has not named one, and a double-click
    /// names one. Aiming it at a selection or a loop's in point would make the
    /// pointer land somewhere the finger did not.
    ///
    /// The playhead is placed before playing, so `play`'s end-of-file rewind sees
    /// the clicked position rather than the one being left behind.
    ///
    /// **And the engine honours it.** Task 22 decided that a double-click outside
    /// an active loop should still be pulled into the region; the user overruled
    /// that in Task 24, having also found it behaved differently before the loop
    /// than after it. `PlaybackEngine.feedSource` now captures on *arrival* only,
    /// so all three cases read the same way and match Ableton and Logic:
    ///
    /// - click **before** the loop → plays from the click, runs on, is captured
    ///   at the out point, then loops;
    /// - click **inside** → plays from the click and loops normally;
    /// - click **after** → plays from the click to the end of the file.
    ///
    /// Nothing here clears or disables the loop, so no state the user set on
    /// purpose is destroyed by a transient click: the loop is still on, still
    /// drawn, and `F` puts playback back inside it in one key.
    ///
    /// The `dragOrigin` reset here is a courtesy, not the correctness
    /// mechanism — see `dragChanged`, which recovers on its own if this never
    /// runs.
    public func dragEnded(startPixel: Double, endPixel: Double, now: Double) {
        defer { dragOrigin = nil }
        guard hasTrack else { return }
        // A range that was drawn is the range you get, even if the pointer
        // wandered back inside the slop before letting go.
        guard abs(endPixel - startPixel) < Self.clickSlopPoints, !loopIsStaged else {
            lastClick = nil
            commitStagedLoop()
            return
        }
        // Cleared, not advanced: consuming it is what stops a third click from
        // chaining into another double-click.
        let isDouble = isSecondClick(at: endPixel, now: now)
        lastClick = isDouble ? nil : (endPixel, now)
        // The range is kept: a tap is about the playhead, and a loop set on
        // purpose is not a tap's to clear (design 2026-11-03, decision 3).
        seek(to: PixelMapping.frame(atPixel: endPixel, in: viewport))
        if isDouble { play() }
    }

    private func isSecondClick(at pixel: Double, now: Double) -> Bool {
        guard let previous = lastClick else { return false }
        return now - previous.time < Self.doubleClickSeconds
            && abs(previous.pixel - pixel) < Self.clickSlopPoints
    }
}
