import ArtscribeKit
import CoreGraphics

/// The one gesture in the waveform lanes, and the three things it can turn out
/// to mean.
///
/// Split out of `ViewerModel+Interaction` — which is about the *view* (zoom,
/// pan, fit) — because this is about a **gesture's identity**: what a press
/// gets latched as, how a pinch takes it back, and what a release does when the
/// pointer never really moved. Those rules have bitten this project repeatedly
/// and are worth reading as one piece.
extension ViewerModel {

    // MARK: - The lane drag, and what it was decided to mean

    /// A left-drag in the waveform lanes: a loop handle, a new range, or an
    /// ⌥-modified zoom.
    ///
    /// **The precedence is `LaneDragMode`'s and it is written down there and in
    /// `TimelineHandles`.** In one line: ⌥ zooms and ⇧ extends wherever the
    /// pointer is; otherwise a loop edge within its grab zone is taken hold of,
    /// then the loop's body — anywhere inside it; otherwise the drag draws a new
    /// range exactly as it always has.
    ///
    /// **The mode is latched at mouse-down.** `option` and `shift` are read
    /// live from `NSEvent.modifierFlags` by the view, so they change the moment
    /// the user's finger does; without the latch, pressing ⌥ halfway through a
    /// selection would abandon the selection and start zooming instead, and
    /// releasing it mid-zoom would start selecting. What the gesture is gets
    /// decided once and holds.
    ///
    /// A gesture is recognised as new when it starts somewhere the live one did
    /// not. `DragGesture.Value.startLocation` is stable for one drag's whole
    /// lifetime, so this is self-correcting even if `laneDragEnded` never ran —
    /// the same reasoning `dragChanged` records for `dragOrigin`.
    public func laneDragChanged(start: CGPoint, current: CGPoint, option: Bool, shift: Bool) {
        guard hasTrack else { return }
        // A pinch cancelled this drag, and its first finger is still reporting.
        // Those changes carry the same start; without this they read as a new
        // gesture and could stage — and on lift commit — a fresh range.
        if laneDragCancelled && laneDragStart == start { return }
        let mode: LaneDragMode
        if laneDragStart == start, let live = laneDragMode {
            mode = live
        } else {
            // A range drawn by a drag whose end never arrived (an interrupted
            // gesture) is still the range on screen: it reaches the engine now,
            // before anything else happens, rather than lingering half-applied.
            commitStagedLoop()
            mode = LaneDragMode(
                option: option, shift: shift, handle: timelineHandle(at: start))
            laneDragStart = start
            laneDragMode = mode
            loopBeforeLaneDrag = loop
            playheadBeforeLaneDrag = playhead
            laneDragCancelled = false
            // A new gesture never continues the previous one's zoom or handle
            // drag, even when the two began at the same point.
            zoomDrag = nil
            edgeDrag = nil
        }
        switch mode {
        case .range(let extending):
            dragChanged(startPixel: start.x, currentPixel: current.x, extending: extending)
        case .zoom:
            zoomDragChanged(start: start, current: current)
        case .edge(let handle):
            edgeDragChanged(handle: handle, startPixel: start.x, currentPixel: current.x)
        }
    }

    /// Ends a lane drag, on the terms it began on.
    ///
    /// A zoom drag must **not** fall through to `dragEnded`: an ⌥-drag that
    /// never really moved would otherwise be read as a click, seek the playhead
    /// and throw the selection away — and two of them as a double-click, which
    /// starts playing. A handle drag is excluded for exactly the same reason:
    /// taking hold of a loop edge and thinking better of it must not move the
    /// playhead, and two of them in a second must not start playback.
    ///
    /// With no latched mode this behaves exactly as it did before ⌥-drag
    /// existed, so an end that somehow arrives without a preceding change still
    /// runs the click logic.
    /// Abandons an in-flight lane drag and puts back what it changed.
    ///
    /// **What a pinch needs.** SwiftUI cannot tell a `DragGesture` how many
    /// fingers are down, so the first finger of a pinch starts a selection and
    /// the second cannot cancel it. The pinch is attached `simultaneous`
    /// deliberately — an exclusive one would let the drag win outright — which
    /// leaves this as the way to undo what it began.
    ///
    /// Restoring selection and playhead is only half. The other half is
    /// `laneDragCancelled`: the gesture still delivers its `onEnded`, and without
    /// the flag that end runs the click path — seeking to wherever the pinch
    /// started, and reading two pinches in a second as a double-click, which
    /// starts playback.
    public func cancelLaneDrag() {
        guard laneDragMode != nil else { return }
        if let previous = loopBeforeLaneDrag {
            if loopIsStaged {
                // Never reached the engine, so only the drawing goes back.
                loop = previous
                loopIsStaged = false
            } else {
                // An edge or body drag pushed as it went; undo that too.
                applyLoop(previous)
            }
        }
        if let previous = playheadBeforeLaneDrag { seek(to: previous) }
        loopBeforeLaneDrag = nil
        playheadBeforeLaneDrag = nil
        laneDragMode = nil
        // Kept, with the flag below: changes that keep arriving with this start
        // belong to the cancelled gesture and are ignored until its end.
        dragOrigin = nil
        zoomDrag = nil
        edgeDrag = nil
        laneDragCancelled = true
        refresh()
    }

    /// Forgets any gesture in flight — for a track being loaded or closed under
    /// it. Nothing is committed: the range belonged to the document going away.
    func resetLaneGesture() {
        laneDragMode = nil
        laneDragStart = nil
        laneDragCancelled = false
        loopBeforeLaneDrag = nil
        playheadBeforeLaneDrag = nil
        loopIsStaged = false
        rangeAnchor = nil
        dragOrigin = nil
        zoomDrag = nil
        edgeDrag = nil
    }

    public func laneDragEnded(start: CGPoint, end: CGPoint, now: Double) {
        // A cancelled drag still gets its `onEnded`. Swallow it once — the flag
        // is cleared here rather than in `cancelLaneDrag` so exactly one end is
        // absorbed and the next real gesture is unaffected.
        if laneDragCancelled {
            laneDragCancelled = false
            laneDragStart = nil
            return
        }
        let mode = laneDragMode
        laneDragStart = nil
        laneDragMode = nil
        loopBeforeLaneDrag = nil
        playheadBeforeLaneDrag = nil
        switch mode {
        case .zoom:
            zoomDragEnded()
        case .edge(let handle):
            // A press that never moved is a click, not a grab: it seeks, and
            // two play. Always on the loop's body — it is the whole inside of
            // the loop, and a click there means the playhead, on any device
            // (2026-11). On an edge only on touch, where a finger's reach
            // covers most of a short loop (`LaneDragPolicy.edgeTapIsAClick`);
            // the Mac keeps Task 23's no-seek edge click.
            let stayed = edgeDrag.map { !$0.hasMoved } ?? true
            edgeDragEnded()
            if stayed && (handle == .loopBody || prefs.edgeTapIsAClick) {
                dragEnded(startPixel: start.x, endPixel: end.x, now: now)
            } else if !stayed && handle == .loopBody {
                // A loop you just moved is the one you hear — the rule a new
                // range already follows on lift. The engine takes hold of a
                // loop only on arrival (spec §5.1), so a playing loop dragged
                // back behind the playhead would otherwise play on to the end
                // of the track, and one dragged ahead would play the old
                // passage out first. Moving keeps looping as it was: an edit.
                enterLoopIfOutside()
            }
        case .range, nil:
            dragEnded(startPixel: start.x, endPixel: end.x, now: now)
        }
    }

    public func fitWholeFile() {
        guard hasTrack else { return }
        viewport.fit()
        refresh()
    }

    /// `⌘9`. Fills the view with the loop.
    ///
    /// The loop counts whether or not it is *engaged*: its range is the marked
    /// passage either way — the only range there is since the selection went
    /// (2026-11) — and refusing to zoom to a loop you can plainly see because
    /// playback is not currently cycling it would be a distinction without a
    /// difference.
    public func zoomToLoop() {
        guard hasTrack, let range = zoomTarget else { return }
        viewport.zoom(to: range)
        refresh()
    }

    /// What `⌘9` would zoom to, or `nil` when there is nothing to zoom to.
    ///
    /// Separate so the menu item can grey itself out on exactly the condition
    /// the command acts on, rather than on a second copy of the rule that can
    /// drift from it.
    public var zoomTarget: FrameRange? {
        loop.range.isEmpty ? nil : loop.range
    }

    public func scrollLeft() { scroll(byPoints: -panStep) }
    public func scrollRight() { scroll(byPoints: panStep) }

    public func scroll(byPoints points: Int) {
        guard hasTrack, points != 0 else { return }
        viewport.scroll(byPixels: points)
        refresh()
    }

    /// Centres the viewport on `frame`, used by the overview strip.
    public func centre(on frame: FrameIndex) {
        guard hasTrack else { return }
        let delta = viewport.pixel(forFrame: frame) - Double(lanePointWidth) / 2
        scroll(byPoints: Int(delta.rounded()))
    }

    /// The end of a gesture on the overview strip. A tap seeks; a drag has
    /// already carried the view and does nothing more.
    ///
    /// The strip used to move only the *view*, so pointing at a bar on the
    /// whole-file overview put the window there and left the playhead behind —
    /// reported from an iPhone by someone who kept trying it. The view has
    /// already been centred by the gesture's first event when the tap landed
    /// outside the lens (`OverviewScrub`), so the playhead arrives on screen.
    ///
    /// A drag deliberately does not seek: carrying the view to look somewhere
    /// else must not move what you are listening to. Same slop as a lane click,
    /// so a fingertip's wobble is still a tap.
    public func overviewReleased(startPixel: Double, endPixel: Double, stripWidth: Double) {
        guard hasTrack, stripWidth > 0,
            abs(endPixel - startPixel) < Self.clickSlopPoints
        else { return }
        seek(
            to: PixelMapping.overviewFrame(
                atPixel: endPixel, totalFrames: totalFrames, width: stripWidth))
    }

    private var panStep: Int {
        Swift.max(1, Int((Double(lanePointWidth) * Self.panFraction).rounded()))
    }
}
