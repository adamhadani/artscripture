import AppKit
import ArtscribeKit
import ArtscribeUI
import CoreGraphics

/// Scrubbing from the playhead's grip, halfway down the lanes, with the real
/// pointer — see `PlayheadScrub`. Run with the pointer group, which has already
/// made sure a window is key.
extension AcceptanceRun {

    @MainActor
    static func checkPlayheadScrub(model: ViewerModel, lanes: CGRect, log: inout Logger) async {
        model.fitWholeFile()
        model.clearLoop()
        let fromPoint = lanes.width * 0.3
        model.seek(to: PixelMapping.frame(atPixel: fromPoint, in: model.viewport))
        let zoom = model.zoomFactor
        let gripX = lanes.minX + model.viewport.pixel(forFrame: model.playhead)

        await pointerDrag(
            from: CGPoint(x: gripX, y: lanes.midY), to: CGPoint(x: gripX + 160, y: lanes.midY))
        let landed = model.viewport.pixel(forFrame: model.playhead)
        log.check(
            "a real drag on the playhead's grip in the lanes scrubs it there "
                + "(\(rounded(fromPoint)) pt -> \(rounded(landed)) pt, "
                + "wanted \(rounded(fromPoint + 160)))",
            abs(landed - (fromPoint + 160)) <= 2)
        log.check(
            "and the scrub neither zooms nor marks a loop",
            model.zoomFactor == zoom && model.loop.range.isEmpty)

        // The same column above the grip is open lane, as it always was.
        let column = lanes.minX + landed
        let high = lanes.minY + lanes.height * 0.12
        await pointerDrag(
            from: CGPoint(x: column, y: high), to: CGPoint(x: column + 120, y: high))
        let marked = model.loop.range
        log.check(
            "a drag from above the grip, on the playhead's own line, marks a loop "
                + "(\(marked.count) frames)",
            !marked.isEmpty)

        // The playhead on the loop's start: the edge wins, so the loop is
        // resized and the playhead stays put.
        model.seek(to: marked.start)
        let parked = model.playhead
        let edgeX = lanes.minX + model.viewport.pixel(forFrame: marked.start)
        await pointerDrag(
            from: CGPoint(x: edgeX, y: lanes.midY), to: CGPoint(x: edgeX - 60, y: lanes.midY))
        log.check(
            "with the playhead on a loop edge, a drag there resizes the loop, not a scrub "
                + "(start \(marked.start) -> \(model.loop.range.start), "
                + "playhead \(parked) -> \(model.playhead))",
            model.loop.range.start < marked.start && model.playhead == parked)

        model.clearLoop()
        model.fitWholeFile()
        // Out of the way of the lane drags that follow, which start mid-lane.
        model.seek(to: 0)
    }
}
