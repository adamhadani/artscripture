import AppKit
import ArtscribeKit
import ArtscribeUI

extension AcceptanceRun {

    /// The overview strip, clicked and dragged for real: a click moves the
    /// playhead there, a drag only carries the view.
    ///
    /// `OverviewTapTests` proves the decision; this proves the gesture reaches
    /// it. The strip's `DragGesture` hands its start and end to
    /// `ViewerModel.overviewReleased`, and a wiring slip there — the wrong
    /// coordinate space, the width read before layout — would pass every unit
    /// test and seek nowhere. So the checks state the frame they expect, not
    /// just that something moved.
    @MainActor
    static func checkOverviewClick(model: ViewerModel, log: inout Logger) async {
        let strip = model.overviewFrame
        guard !strip.isEmpty, model.totalFrames > 0 else {
            log.check("overview geometry is known to the click check", false)
            return
        }
        model.fitWholeFile()
        model.zoom(by: 8, anchorFrame: 0)
        model.seek(to: 0)

        let x = strip.width * 0.7
        let target = PixelMapping.overviewFrame(
            atPixel: x, totalFrames: model.totalFrames, width: strip.width)
        let point = CGPoint(x: strip.minX + x, y: strip.midY)
        sendMouse(.leftMouseDown, at: point)
        await settle(seconds: 0.05)
        sendMouse(.leftMouseUp, at: point)
        await settle(seconds: 0.2)
        // Two strip pixels of slack: the strip is a few hundred points wide over
        // the whole file, so one point is a large number of frames.
        let slack = Double(model.totalFrames) / strip.width * 2
        log.check(
            "a real click on the overview strip moves the playhead there "
                + "(\(model.playhead) vs \(target))",
            abs(Double(model.playhead - target)) <= slack)

        let before = model.playhead
        let viewBefore = model.viewport.startFrame
        await pointerDrag(
            from: CGPoint(x: strip.minX + strip.width * 0.3, y: strip.midY),
            to: CGPoint(x: strip.minX + strip.width * 0.5, y: strip.midY))
        log.check(
            "a real drag on the strip carries the view "
                + "(\(viewBefore) -> \(model.viewport.startFrame))",
            model.viewport.startFrame != viewBefore)
        log.check(
            "and leaves the playhead where it was (\(before) -> \(model.playhead))",
            model.playhead == before)

        model.fitWholeFile()
        model.seek(to: 0)
    }
}
