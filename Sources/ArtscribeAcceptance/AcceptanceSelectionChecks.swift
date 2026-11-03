import AppKit
import ArtscribeKit
import ArtscribeUI
import Foundation

/// Task 18 in the running window: the move cluster (the selection's keys, which
/// drive the loop since 2026-11), extending the range, and the zoom-direction preference.
///
/// Everything that can be driven by a real keystroke is, through
/// `press(…)` — `NSApp.sendEvent`, the same route a real key takes, menu bar
/// first. What that also proves is single-fire: `C` is both a menu key
/// equivalent and a `DocumentView` binding, so a selection that moved by two
/// steps on one press would fail these checks rather than pass them quietly.
extension AcceptanceRun {

    @MainActor
    static func checkRangeMovement(model: ViewerModel, log: inout Logger) async {
        model.fitWholeFile()
        let step = { (seconds: Double) in FrameIndex((seconds * model.sampleRate).rounded()) }
        let gentle = step(model.prefs.selectionMoveAmounts[.gentle])
        let aggressive = step(model.prefs.selectionMoveAmounts[.aggressive])

        // Marked the way a user does — through the lane drag's own entry points
        // — so the drag that defines the range is exercised, not bypassed.
        let lanes = model.laneFrame
        guard !lanes.isEmpty else {
            log.check("lane geometry is known to the loop-move check", false)
            return
        }
        func markMiddle() -> FrameRange {
            model.clearLoop()
            let from = CGPoint(x: lanes.width * 0.3, y: lanes.height / 2)
            let to = CGPoint(x: lanes.width * 0.45, y: lanes.height / 2)
            model.laneDragChanged(start: from, current: from, option: false, shift: false)
            model.laneDragChanged(start: from, current: to, option: false, shift: false)
            model.laneDragEnded(start: from, end: to, now: ProcessInfo.processInfo.systemUptime)
            return model.loop.range
        }
        // Enough presses to cross the whole file from anywhere in it, whatever
        // the file and the configured amount are.
        let crossings = Int(model.totalFrames / Swift.max(aggressive, 1)) + 3

        var before = markMiddle()
        press(.v)
        var after = model.loop.range
        log.check(
            "V moves the loop right by exactly one gentle step "
                + "(\(after.start - before.start) frames, one step is \(gentle))",
            after.start - before.start == gentle && after.count == before.count)
        press(.c)
        log.check("C moves it back, once", model.loop.range == before)

        before = markMiddle()
        press(.optionC)
        after = model.loop.range
        log.check(
            "Option-C moves it left by the far step "
                + "(\(before.start - after.start) frames, one step is \(aggressive))",
            before.start - after.start == aggressive && after.count == before.count)
        press(.optionV)
        log.check("Option-V moves it back, once", model.loop.range == before)

        // Both walls. A loop pushed against an end must stop with its
        // length intact rather than shrink against it or invert past it.
        before = markMiddle()
        for _ in 0..<crossings { press(.optionC) }
        after = model.loop.range
        log.check(
            "pushed against the start it stops, keeping its length "
                + "(\(after.start)…\(after.end))",
            after.start == 0 && after.count == before.count)
        for _ in 0..<(2 * crossings) { press(.optionV) }
        after = model.loop.range
        log.check(
            "pushed against the end it stops, keeping its length "
                + "(\(after.start)…\(after.end) of \(model.totalFrames))",
            after.end == model.totalFrames && after.count == before.count)

        await checkExtendRange(model: model, log: &log)
        model.clearLoop()
        model.fitWholeFile()
    }

    /// `⇧←` / `⇧→`, which spec §6.2 has documented since the design was
    /// approved and which nothing implemented until Task 18 — the third such
    /// gap found in this project, after the nudge tiers and the sidecar.
    @MainActor
    private static func checkExtendRange(model: ViewerModel, log: inout Logger) async {
        let normal = FrameIndex((model.prefs.nudgeAmounts[.normal] * model.sampleRate).rounded())
        model.clearLoop()
        model.seek(to: model.totalFrames / 2)
        let anchor = model.playhead

        press(.shiftRight)
        await settle(seconds: 0.05)
        log.check(
            "Shift-Right extends the range from the playhead "
                + "(\(model.loop.range.start)…\(model.loop.range.end))",
            model.loop.range == FrameRange(start: anchor, count: normal))
        press(.shiftRight)
        log.check(
            "and a second press extends it by exactly one more step, not two",
            model.loop.range == FrameRange(start: anchor, count: 2 * normal))
        press(.shiftLeft)
        log.check(
            "Shift-Left brings the moving edge back",
            model.loop.range == FrameRange(start: anchor, count: normal))
        log.check("and the anchor never moved", model.loop.range.start == anchor)
        model.clearLoop()
    }

    /// The zoom-direction preference (Task 18): down zooms in, and one switch
    /// flips every zoom gesture in the window rather than only the drag.
    @MainActor
    static func checkZoomDirection(model: ViewerModel, log: inout Logger) async {
        model.fitWholeFile()
        model.clearLoop()
        // Away from the whole-file floor, where `Viewport` clamps and "it
        // zoomed out" would pass on a build that merely stopped.
        model.zoom(by: 16, anchorFrame: model.totalFrames / 2)
        let start = CGPoint(x: 400, y: 12)
        let travel = ViewerModel.zoomDragPointsPerDoubling

        func drag(down: Bool) -> Double {
            let before = model.zoomFactor
            for offset in 1...Int(travel) {
                let dy = down ? Double(offset) : -Double(offset)
                model.zoomDragChanged(start: start, current: CGPoint(x: 400, y: 12 + dy))
            }
            model.zoomDragEnded()
            return model.zoomFactor / before
        }

        log.check("with the preference off, dragging down zooms in", drag(down: true) > 1.9)
        log.check("and dragging up zooms out", drag(down: false) < 0.55)

        model.prefs.setInvertZoomDrag(true)
        log.check(
            "with it on, the same downward drag zooms out instead", drag(down: true) < 0.55)
        log.check("and dragging up zooms in", drag(down: false) > 1.9)

        // The wheel follows the same switch, which is the half that keeps one
        // window from holding two conventions at once. Driven as a real scroll
        // event through the local monitor.
        let lanes = model.laneFrame
        if !lanes.isEmpty {
            warp(toX: lanes.midX, y: lanes.midY)
            await settle(seconds: 0.2)
            let before = model.zoomFactor
            for _ in 0..<4 { scroll(deltaY: 1, units: .line) }
            await settle(seconds: 0.3)
            log.check(
                "with it on, a forward wheel roll zooms out too "
                    + "(\(rounded(before))x -> \(rounded(model.zoomFactor))x)",
                model.zoomFactor < before)
        }

        model.prefs.setInvertZoomDrag(false)
        log.check("the preference is back off for the rest of the run", !model.prefs.invertZoomDrag)
        model.fitWholeFile()
    }
}
