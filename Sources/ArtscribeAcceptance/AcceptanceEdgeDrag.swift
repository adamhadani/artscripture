import AppKit
import ArtscribeKit
import ArtscribeUI
import Foundation

/// Task 23, driven with real `NSEvent`s: the loop and selection edges dragged,
/// the loop body moved, and — the half that matters most — every gesture that
/// was already on this surface still doing exactly what it did.
///
/// Nothing here goes through the model's entry points. `pointerDrag` posts real
/// mouse events through `NSWindow.sendEvent`, so SwiftUI's `DragGesture`, the
/// `.local` coordinate space and `LaneDragMode`'s latch are all genuinely under
/// test. The one thing a synthesised event cannot do is move the system cursor,
/// so the *hover* half uses `hover(x:y:)` — warp plus a posted crossing — and
/// reads `NSCursor.currentSystem` back, exactly as Task 17's checks do.
extension AcceptanceRun {

    /// Every check name this can run, for the skip path.
    private static let edgeDragChecks =
        [
            "hovering a loop edge changes the cursor",
            "and over open lane beside the loop it is the arrow, where a drag pans",
            "hovering the loop's bar offers a different cursor again",
            "hovering inside the loop offers the bar's move cursor too",
            "a real drag on the loop's in point moves it",
            "and leaves the out point exactly where it was",
            "a loop edge drag does not move the playhead",
            "dragging the out point past the in point swaps rather than collapsing",
            "a real drag on the loop's top bar moves the whole loop",
            "and preserves its length exactly",
            "a real drag from the middle of the loop moves the whole loop",
            "and preserves its length exactly, from the middle too",
            "a real click inside the loop places the playhead",
            "and leaves the loop exactly where it was",
            "a real drag dragged out a range, and its edge then moves",
            "a plain drag outside a playing loop leaves it where it was",
            "and it keeps looping",
            "and the drag pans the view, the frame under the press following it"
        ] + loopUndoChecks

    @MainActor
    static func checkEdgeDrag(
        model: ViewerModel, theme: ThemeController, log: inout Logger, outputDirectory: String
    ) async {
        let lanes = model.laneFrame
        guard !lanes.isEmpty else {
            log.check("lane geometry is known to the edge-drag check", false)
            return
        }
        adoptViewerWindow(for: model)
        guard await regainKeyWindow() else {
            let reason = "no window is key, so NSWindow.sendEvent drops every click"
            for name in edgeDragChecks { log.skip(name, because: reason) }
            return
        }
        model.fitWholeFile()

        await checkEdgeHover(model: model, lanes: lanes, log: &log)
        await checkLoopEdgeDrags(model: model, lanes: lanes, log: &log)
        await checkLoopBodyDrag(model: model, lanes: lanes, log: &log)
        await checkNewRangeEdgeDrag(model: model, lanes: lanes, log: &log)
        await checkPlainDragSurvives(model: model, lanes: lanes, log: &log)
        await checkLoopUndo(model: model, lanes: lanes, log: &log)
        await captureTreatment(
            model: model, theme: theme, lanes: lanes, outputDirectory: outputDirectory)

        model.clearLoop()
        model.fitWholeFile()
    }

    // MARK: - Setup

    /// Puts a loop between two lane points using the real `A`/`S` bindings, so a
    /// regression in those cannot masquerade as an edge-drag pass.
    @MainActor
    static func setLoop(_ model: ViewerModel, fromPoint: Double, toPoint: Double) {
        model.clearLoop()
        model.seek(to: PixelMapping.frame(atPixel: fromPoint, in: model.viewport))
        press(.a)
        model.seek(to: PixelMapping.frame(atPixel: toPoint, in: model.viewport))
        press(.s)
        model.seek(to: 0)
    }

    @MainActor
    static func frame(_ model: ViewerModel, atLanePoint point: Double) -> FrameIndex {
        PixelMapping.frame(atPixel: point, in: model.viewport)
    }

    /// One point of slack in either direction: a frame round-trips through the
    /// viewport's `Double` arithmetic on the way in and on the way out.
    @MainActor
    static func within(
        _ model: ViewerModel, _ actual: FrameIndex, ofPoint point: Double
    ) -> Bool {
        abs(model.viewport.pixel(forFrame: actual) - point) <= 1.5
    }

    // MARK: - Hover

    /// The affordance has to arrive **before** the mouse goes down. A cursor
    /// that only changes once the drag is under way tells the user nothing they
    /// could have acted on.
    @MainActor
    private static func checkEdgeHover(
        model: ViewerModel, lanes: CGRect, log: inout Logger
    ) async {
        setLoop(model, fromPoint: 300, toPoint: 700)
        let crosshair = signature(NSCursor.crosshair)
        let arrow = signature(NSCursor.arrow)
        let restoreTo = NSEvent.mouseLocation

        func read(_ x: Double, _ y: Double) async -> String? {
            await hover(x: x, y: y)
            guard pointerIsAt(x: x, y: y) else { return nil }
            return signature(NSCursor.currentSystem)
        }

        // Open lane is outside the loop: inside it is the loop's body now,
        // at any height (2026-11), and offers the move cursor.
        let overOpenLane = await read(lanes.minX + 150, lanes.midY)
        let overEdge = await read(lanes.minX + 300, lanes.midY)
        let backOverOpenLane = await read(lanes.minX + 150, lanes.midY)
        let overBar = await read(lanes.minX + 500, lanes.minY + 3)
        let overInside = await read(lanes.minX + 500, lanes.midY)
        CGWarpMouseCursorPosition(
            CGPoint(
                x: restoreTo.x,
                y: (NSScreen.screens.first?.frame.maxY ?? restoreTo.y) - restoreTo.y))

        let unread = "the pointer would not stay where it was put"
        log.note("cursor over open lane", overOpenLane ?? "not read")
        log.note("cursor over the loop's in point", overEdge ?? "not read")
        log.note("cursor over the loop's top bar", overBar ?? "not read")
        log.note("cursor mid-lane inside the loop", overInside ?? "not read")
        // Named against the crosshair rather than merely "different": what the
        // lane offers by default is documented as `rectSelection`, so a reading
        // that matched it would mean the edge announced nothing at all.
        log.check(
            "hovering a loop edge changes the cursor",
            overEdge != nil && overEdge != crosshair && overEdge != arrow,
            unless: overEdge == nil ? unread : nil)
        // The arrow, not the crosshair: with a loop on the track a drag in open
        // lane pans rather than drawing one (2026-11-14, `LanePan`), and the
        // open hand is the loop's own. The arrow is also what a cursor that
        // never changes reads, so the edge has to have read differently or
        // this would pass on a machine where no cursor reaches the screen.
        log.check(
            "and over open lane beside the loop it is the arrow, where a drag pans",
            backOverOpenLane == arrow && overOpenLane == arrow
                && overEdge != nil && overEdge != arrow,
            unless: backOverOpenLane == nil || overOpenLane == nil ? unread : nil)
        log.check(
            "hovering the loop's bar offers a different cursor again",
            overBar != nil && overBar != crosshair && overBar != overEdge,
            unless: overBar == nil ? unread : nil)
        log.check(
            "hovering inside the loop offers the bar's move cursor too",
            overInside != nil && overInside == overBar && overInside != crosshair,
            unless: overInside == nil || overBar == nil ? unread : nil)
    }

    // MARK: - The edges

    @MainActor
    private static func checkLoopEdgeDrags(
        model: ViewerModel, lanes: CGRect, log: inout Logger
    ) async {
        setLoop(model, fromPoint: 300, toPoint: 700)
        let outPointBefore = model.loop.range.end
        model.seek(to: frame(model, atLanePoint: 100))
        let playheadBefore = model.playhead

        await pointerDrag(
            from: CGPoint(x: lanes.minX + 300, y: lanes.midY),
            to: CGPoint(x: lanes.minX + 380, y: lanes.midY))
        let moved = model.loop.range
        log.note("loop after dragging the in point", "\(moved.start)…\(moved.end)")
        log.check(
            "a real drag on the loop's in point moves it",
            within(model, moved.start, ofPoint: 380))
        log.check(
            "and leaves the out point exactly where it was", moved.end == outPointBefore)
        log.check("a loop edge drag does not move the playhead", model.playhead == playheadBefore)

        // The inversion decision, for real: the out point taken past the in
        // point keeps following the pointer and the region reappears the other
        // side of it, rather than sticking at zero length.
        await pointerDrag(
            from: CGPoint(x: lanes.minX + 700, y: lanes.midY),
            to: CGPoint(x: lanes.minX + 250, y: lanes.midY))
        let swapped = model.loop.range
        log.note(
            "loop after dragging the out point past the in point",
            "\(swapped.start)…\(swapped.end)")
        log.check(
            "dragging the out point past the in point swaps rather than collapsing",
            swapped.count > 0 && within(model, swapped.start, ofPoint: 250)
                && within(model, swapped.end, ofPoint: 380))
    }

    // MARK: - The body

    @MainActor
    private static func checkLoopBodyDrag(
        model: ViewerModel, lanes: CGRect, log: inout Logger
    ) async {
        setLoop(model, fromPoint: 300, toPoint: 700)
        let lengthBefore = model.loop.range.count
        // On the bar the loop draws along the top of the lanes — the body's
        // only handle until 2026-11, and still part of it.
        await pointerDrag(
            from: CGPoint(x: lanes.minX + 500, y: lanes.minY + 3),
            to: CGPoint(x: lanes.minX + 600, y: lanes.minY + 3))
        let moved = model.loop.range
        log.note("loop after dragging its bar", "\(moved.start)…\(moved.end)")
        log.check(
            "a real drag on the loop's top bar moves the whole loop",
            within(model, moved.start, ofPoint: 400))
        log.check("and preserves its length exactly", moved.count == lengthBefore)

        // Mid-lane: the gesture the user asked for. It drew a new loop until
        // 2026-11.
        setLoop(model, fromPoint: 300, toPoint: 700)
        await pointerDrag(
            from: CGPoint(x: lanes.minX + 500, y: lanes.midY),
            to: CGPoint(x: lanes.minX + 420, y: lanes.midY))
        let fromMiddle = model.loop.range
        log.note("loop after dragging its middle", "\(fromMiddle.start)…\(fromMiddle.end)")
        log.check(
            "a real drag from the middle of the loop moves the whole loop",
            within(model, fromMiddle.start, ofPoint: 220))
        log.check(
            "and preserves its length exactly, from the middle too",
            fromMiddle.count == lengthBefore)

        // And a click there is still a click: the playhead, not a grab.
        model.seek(to: frame(model, atLanePoint: 100))
        let loopBefore = model.loop
        let at = CGPoint(x: lanes.minX + 450, y: lanes.midY)
        // Moved there first, as `click(at:)` does: a first press delivered
        // without one was not reliably seen.
        sendMouse(.mouseMoved, at: at)
        await settle(seconds: 0.05)
        sendMouse(.leftMouseDown, at: at)
        await settle(seconds: 0.05)
        sendMouse(.leftMouseUp, at: at)
        await settle(seconds: 0.15)
        let landed = model.viewport.pixel(forFrame: model.playhead)
        log.check(
            "a real click inside the loop places the playhead (at \(Int(landed)) pt, wanted 450)",
            within(model, model.playhead, ofPoint: 450))
        log.check("and leaves the loop exactly where it was", model.loop == loopBefore)
        // Past the double-click interval, so the next check's first press can
        // never pair with this click.
        await settle(seconds: 0.45)
    }

    @MainActor
    private static func checkNewRangeEdgeDrag(
        model: ViewerModel, lanes: CGRect, log: inout Logger
    ) async {
        model.clearLoop()
        // Dragged out for real, so the edge being grabbed is one the pointer
        // actually made — and, since the one-range change, is the loop's.
        await pointerDrag(
            from: CGPoint(x: lanes.minX + 500, y: lanes.midY),
            to: CGPoint(x: lanes.minX + 800, y: lanes.midY))
        let startBefore = model.loop.range.start
        await pointerDrag(
            from: CGPoint(x: lanes.minX + 800, y: lanes.midY),
            to: CGPoint(x: lanes.minX + 900, y: lanes.midY))
        let moved = model.loop.range
        log.note("range after dragging its trailing edge", "\(moved.start)…\(moved.end)")
        log.check(
            "a real drag dragged out a range, and its edge then moves",
            moved.start == startBefore && within(model, moved.end, ofPoint: 900))
    }

    // MARK: - The regression that would be instantly visible

    /// The handles must not have eaten the first gesture. A plain drag that
    /// starts outside the loop pans the view since 2026-11-14 (`LanePan`):
    /// before that it drew a new passage over the loop, and on a phone a tap
    /// that wobbled or a reach to pan threw away a loop set with care.
    ///
    /// Zoomed in around the middle first. The fitted view has nowhere to pan
    /// to, and a pan that cannot move would pass the "loop kept" half alone.
    @MainActor
    private static func checkPlainDragSurvives(
        model: ViewerModel, lanes: CGRect, log: inout Logger
    ) async {
        model.seek(to: model.totalFrames / 2)
        model.zoom(by: 4)
        setLoop(model, fromPoint: 200, toPoint: 450)
        if !model.loop.isEnabled { press(.d) }
        let loop = model.loop
        let underThePress = frame(model, atLanePoint: 600)
        let viewBefore = model.viewport.startFrame
        await pointerDrag(
            from: CGPoint(x: lanes.minX + 600, y: lanes.midY),
            to: CGPoint(x: lanes.minX + 800, y: lanes.midY))
        log.check(
            "a plain drag outside a playing loop leaves it where it was "
                + "(\(model.loop.range.start)…\(model.loop.range.end))",
            model.loop.range == loop.range)
        log.check("and it keeps looping", model.loop.isEnabled)
        log.check(
            "and the drag pans the view, the frame under the press following it "
                + "(start \(viewBefore) -> \(model.viewport.startFrame))",
            model.viewport.startFrame < viewBefore && within(model, underThePress, ofPoint: 800))
        model.fitWholeFile()
    }

    // MARK: - What it looks like

    /// Snapshots of the hover and the active drag, in both themes.
    ///
    /// Views are not snapshot-*tested* in this project — there is no golden
    /// image to compare against, and a pixel diff over a live waveform would be
    /// noise. These are for a person to look at, which is the only honest way
    /// to check "nuanced but palpable": the mid-drag one is taken with the
    /// mouse button still down, which is the only moment the guide line and the
    /// time flag exist at all.
    @MainActor
    private static func captureTreatment(
        model: ViewerModel, theme: ThemeController, lanes: CGRect, outputDirectory: String
    ) async {
        let wanted = theme.preference
        for (appearance, name) in [(ThemePreference.dark, "dark"), (.light, "light")] {
            theme.preference = appearance
            await settle(seconds: 0.5)
            setLoop(model, fromPoint: 300, toPoint: 700)
            model.seek(to: 0)

            await hover(x: lanes.minX + 300, y: lanes.midY)
            snapshot(to: "\(outputDirectory)/11-edge-hover-\(name).png")

            // Held open: mouse down, dragged part-way, captured, then released.
            let from = CGPoint(x: lanes.minX + 700, y: lanes.midY)
            let to = CGPoint(x: lanes.minX + 560, y: lanes.midY)
            sendMouse(.leftMouseDown, at: from)
            await settle(seconds: 0.05)
            await pointerDragged(from: from, to: to, steps: 6)
            await settle(seconds: 0.25)
            snapshot(to: "\(outputDirectory)/12-edge-drag-\(name).png")
            sendMouse(.leftMouseUp, at: to)
            await settle(seconds: 0.15)
        }
        theme.preference = wanted
        await settle(seconds: 0.4)
    }
}
