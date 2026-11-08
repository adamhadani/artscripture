import AppKit
import ArtscribeKit
import ArtscribeUI
import CoreGraphics

/// Scrubbing from the playhead's grip on the ruler, with the real pointer —
/// see `PlayheadScrub`. Run with the pointer group, which has already made
/// sure a window is key.
extension AcceptanceRun {

    @MainActor
    static func checkPlayheadScrub(model: ViewerModel, ruler: CGRect, log: inout Logger) async {
        model.fitWholeFile()
        model.clearLoop()
        let fromPoint = ruler.width * 0.3
        model.seek(to: PixelMapping.frame(atPixel: fromPoint, in: model.viewport))
        let zoom = model.zoomFactor
        let gripX = ruler.minX + model.viewport.pixel(forFrame: model.playhead)

        await pointerDrag(
            from: CGPoint(x: gripX, y: ruler.midY), to: CGPoint(x: gripX + 160, y: ruler.midY))
        let landed = model.viewport.pixel(forFrame: model.playhead)
        log.check(
            "a real sideways drag on the playhead's grip scrubs it there "
                + "(\(rounded(fromPoint)) pt -> \(rounded(landed)) pt, "
                + "wanted \(rounded(fromPoint + 160)))",
            abs(landed - (fromPoint + 160)) <= 2)
        log.check(
            "and the scrub neither zooms nor marks a loop",
            model.zoomFactor == zoom && model.loop.range.isEmpty)

        // Up or down from the grip is still the zoom — the one people start at
        // the playhead.
        let gripNow = ruler.minX + landed
        let travel = ViewerModel.zoomDragPointsPerDoubling
        await pointerDrag(
            from: CGPoint(x: gripNow, y: ruler.midY),
            to: CGPoint(x: gripNow, y: ruler.midY + travel))
        log.check(
            "a drag down from the playhead's grip still zooms "
                + "(\(rounded(zoom))x -> \(rounded(model.zoomFactor))x)",
            model.zoomFactor > zoom * 1.5)
        model.fitWholeFile()
    }
}
