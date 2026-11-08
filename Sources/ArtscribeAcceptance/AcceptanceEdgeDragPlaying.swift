import AppKit
import ArtscribeKit
import ArtscribeUI
import Foundation

/// Task 23's loop drags with the transport running — split from
/// `AcceptanceEdgeDrag` for length; the helpers (`setLoop`, `within`,
/// `frame(_:atLanePoint:)`) are that file's.
extension AcceptanceRun {

    // MARK: - While playing

    /// A loop edge moved with the transport running has to take effect without
    /// a click or a dropout. It cannot: the edge goes through `applyLoop`, which
    /// is the app's one `PlaybackCommand.setLoop` path, and the engine wraps at
    /// the boundary it is fed without ever resetting the stretcher there.
    ///
    /// What is measurable from here is the *consequence*: the transport is still
    /// running afterwards, the playhead ends up inside the region the drag left
    /// behind, and none of the render-thread degradation counters moved — a
    /// stall, a rejected command or a dropped one is exactly what a dropout
    /// would show up as.
    @MainActor
    static func checkEdgeDragWhilePlaying(model: ViewerModel, log: inout Logger) async {
        let names = [
            "a loop edge dragged during playback is still playing afterwards",
            "the dragged loop's new out point contains the playhead",
            "and no render stall, rejected or dropped command was counted",
            "a playing loop dragged back behind the playhead is still the one you hear"
        ]
        guard model.canPlay else {
            for name in names { log.skip(name, because: "no audio output was opened") }
            return
        }
        if let reason = positionChecksAreImpossible(model: model) {
            for name in names { log.skip(name, because: reason) }
            return
        }
        let lanes = model.laneFrame
        adoptViewerWindow(for: model)
        guard !lanes.isEmpty, await regainKeyWindow() else {
            for name in names {
                log.skip(name, because: "no window is key, so a real drag cannot be delivered")
            }
            return
        }

        model.fitWholeFile()
        setLoop(model, fromPoint: 200, toPoint: 800)
        if !model.loop.isEnabled { press(.d) }
        model.seek(to: model.loop.range.start)
        let before = model.degradation
        model.play()
        await settle(seconds: 1.2)

        // Pull the out point in while the engine is running through the region.
        await pointerDrag(
            from: CGPoint(x: lanes.minX + 800, y: lanes.midY),
            to: CGPoint(x: lanes.minX + 500, y: lanes.midY))
        await settle(seconds: 1.5)
        let playing = model.isPlaying
        let region = model.loop.range
        let position = model.playhead
        let after = model.degradation
        model.pause()
        await settle(seconds: 0.2)

        log.note("loop after the drag", "\(region.start)…\(region.end), playhead \(position)")
        log.check("a loop edge dragged during playback is still playing afterwards", playing)
        log.check(
            "the dragged loop's new out point contains the playhead",
            position >= region.start && position <= region.end)
        log.check(
            "and no render stall, rejected or dropped command was counted", after == before)

        await checkBodyDragWhilePlaying(model: model, lanes: lanes, log: &log)
    }

    /// The loop moved from its middle while playing, back past the playhead.
    /// The engine takes hold of a loop only on arrival, so without the seek on
    /// lift the track plays on to its end with the loop still drawn as on.
    @MainActor
    private static func checkBodyDragWhilePlaying(
        model: ViewerModel, lanes: CGRect, log: inout Logger
    ) async {
        setLoop(model, fromPoint: 250, toPoint: 500)
        if !model.loop.isEnabled { press(.d) }
        model.seek(to: frame(model, atLanePoint: 470))
        model.play()
        await settle(seconds: 0.6)
        await pointerDrag(
            from: CGPoint(x: lanes.minX + 350, y: lanes.midY),
            to: CGPoint(x: lanes.minX + 150, y: lanes.midY))
        await settle(seconds: 1.0)
        let playing = model.isPlaying
        let region = model.loop.range
        let position = model.playhead
        model.pause()
        await settle(seconds: 0.2)
        log.note(
            "loop after dragging it back while playing",
            "\(region.start)…\(region.end), playhead \(position)")
        log.check(
            "a playing loop dragged back behind the playhead is still the one you hear",
            playing && within(model, region.start, ofPoint: 50)
                && position >= region.start && position <= region.end)
    }
}
