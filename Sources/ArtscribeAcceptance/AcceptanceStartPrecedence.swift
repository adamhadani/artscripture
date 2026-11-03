import AppKit
import ArtscribeKit
import ArtscribeUI
import Foundation

/// Task 22, driven end to end: the one precedence rule behind Shift-Space, and
/// the double-click that now plays from where it landed.
///
/// Both are P0 fixes for behaviour the user hit while driving the real app, and
/// both were "arbitrary" rather than broken -- which is why they are checked here
/// against real keystrokes and real `NSEvent` clicks rather than only against the
/// model. They need an audio graph, so `AcceptanceRun` calls them after
/// `checkPlayback` rather than beside the other pointer checks.
extension AcceptanceRun {

    // MARK: - ⇧Space precedence (Task 22 A)

    /// One rule for where `⇧Space` aims, driven with real keystrokes through the
    /// whole four-state matrix.
    ///
    /// It reads `model.playhead` **immediately** after the press, before any
    /// settling: `playFromStart` seeks and then plays synchronously, so that read
    /// is the aim point itself rather than wherever the render thread has since
    /// carried it. Each case pauses again before the next, because `⇧Space`
    /// pressed while already playing would still be a play-from-start but leaves
    /// the transport in a state the next case would have to undo.
    ///
    /// **This is also where "`⇧Space` takes no preroll" is checked.** Every aim
    /// point below is asserted by exact equality against a range start or a
    /// loop in point far past Task 29's default 2 s, so a preroll leaking into
    /// this key would fail three of these four cases outright.
    ///
    /// The loop is set with `A`/`S`/`D` — real keys — so a regression in the loop
    /// bindings cannot masquerade as a precedence pass.
    @MainActor
    static func checkStartPrecedence(model: ViewerModel, log: inout Logger) async {
        guard model.canPlay else {
            log.skip("⇧Space precedence", because: "no audio output was opened")
            return
        }
        model.fitWholeFile()
        let quarter = model.totalFrames / 4
        let half = model.totalFrames / 2

        func aimOfShiftSpace() async -> FrameIndex {
            model.seek(to: model.totalFrames * 3 / 4)
            press(.shiftSpace)
            let aim = model.playhead
            press(.space)
            await settle(seconds: 0.1)
            return aim
        }

        // 1. No range at all.
        model.clearLoop()
        let neither = await aimOfShiftSpace()
        log.check("⇧Space with no range aims at the track start", neither == 0)

        // 2. An active loop. This is the case the user reported: it used to aim
        //    at 0 and let the engine drag the cursor into the region, which is
        //    what made the app read as two competing rules.
        model.seek(to: quarter)
        press(.a)
        model.seek(to: half)
        press(.s)
        press(.d)
        let loopStart = model.loop.range.start
        log.check(
            "A, S and D really set an active loop (\(loopStart)…\(model.loop.range.end))",
            model.loop.isActive && loopStart > 0)
        let loopOnly = await aimOfShiftSpace()
        log.check(
            "⇧Space with an active loop aims at the loop's in point "
                + "(\(loopOnly) vs \(loopStart))",
            loopOnly == loopStart)

        // 3. A drag while looping: it replaces the loop, and looping stays on
        //    (design 2026-11-03), so the new range's start is the aim.
        model.dragChanged(startPixel: 300, currentPixel: 300, extending: false)
        model.dragChanged(startPixel: 300, currentPixel: 520, extending: false)
        model.dragEnded(
            startPixel: 300, endPixel: 520, now: ProcessInfo.processInfo.systemUptime)
        let rangeStart = model.loop.range.start
        log.check(
            "a drag while looping replaces the loop and keeps it looping "
                + "(\(rangeStart) vs the old \(loopStart))",
            model.loop.isActive && rangeStart != loopStart)
        let replaced = await aimOfShiftSpace()
        log.check(
            "⇧Space aims at the new range's start (\(replaced) vs \(rangeStart))",
            replaced == rangeStart)

        // 4. Looping switched off: the range is still the passage you marked,
        //    as a selection used to be, so ⇧Space still aims at its start.
        press(.d)
        log.check("D really switched looping off", !model.loop.isActive)
        let disabled = await aimOfShiftSpace()
        log.check(
            "with looping off ⇧Space still aims at the range's start (\(disabled))",
            disabled == rangeStart)

        model.clearLoop()
        model.seek(to: 0)
    }

    /// Task 22 B: a real double-click in the lanes places the playhead and plays
    /// from **there**.
    ///
    /// Driven as four `NSEvent`s through `NSWindow.sendEvent` — the same door a
    /// real click comes through — so `DragGesture(minimumDistance: 0)`, the click
    /// state machine and the transport are all under test rather than assumed.
    ///
    /// Deliberately set up with an active loop in place, which is where B has to
    /// compose with A: `⇧Space` would aim at the loop's in point, and a
    /// double-click must not. The first click lands inside the loop,
    /// so neither candidate start can be what put the playhead there; the last
    /// pair of clicks lands past the out point, which is Task 24 A's case 3.
    @MainActor
    static func checkDoubleClickPlays(model: ViewerModel, log: inout Logger) async {
        let lanes = model.laneFrame
        guard model.canPlay else {
            log.skip("a real double-click plays from the click point", because: "no audio output")
            return
        }
        adoptViewerWindow(for: model)
        guard !lanes.isEmpty, await regainKeyWindow() else {
            log.skip(
                "a real double-click plays from the click point",
                because: "no window is key, so NSWindow.sendEvent drops every click")
            return
        }

        model.fitWholeFile()
        model.pause()
        model.seek(to: model.totalFrames / 5)
        press(.a)
        model.seek(to: model.totalFrames * 4 / 5)
        press(.s)
        if !model.loop.isActive { press(.d) }
        let loopBefore = model.loop
        let loopStart = model.loop.range.start
        log.check("the double-click check starts with an active loop", model.loop.isActive)

        // Well inside the loop, and nowhere near either candidate start.
        let clickX = lanes.minX + lanes.width * 0.6
        let expected = PixelMapping.frame(atPixel: clickX - lanes.minX, in: model.viewport)
        let point = CGPoint(x: clickX, y: lanes.midY)
        await click(at: point)
        let afterFirst = model.playhead
        log.check(
            "a single real click places the playhead without playing "
                + "(\(afterFirst) vs \(expected))",
            abs(afterFirst - expected) <= 1 && !model.isPlaying)
        // Review focus 1 of the one-range plan, end to end: a touch-down reaches
        // the gesture as a change, and a range begun there would replace the loop.
        log.check(
            "and a single real click inside the loop leaves the loop alone "
                + "(\(model.loop.range.start)…\(model.loop.range.end))",
            model.loop == loopBefore)

        await click(at: point)
        let afterSecond = model.playhead
        log.check("a real double-click starts playing", model.isPlaying)
        // Not an equality: it is *playing* by now, so the display-link poll has
        // already carried the playhead a fraction of a second past the click.
        // The bound is a quarter of a second of source, which is two orders of
        // magnitude smaller than the distance to either wrong answer — the
        // loop's in point is over a million frames
        // away — so this cannot be confused with a re-route.
        let drift = afterSecond - expected
        let tolerance = FrameIndex(model.sampleRate / 4)
        log.check(
            "and from the click point, not the loop's in point (\(loopStart)) "
                + "— \(afterSecond) vs \(expected), "
                + "drift \(drift) of \(tolerance) allowed",
            drift >= -1 && drift < tolerance)
        log.check(
            "a double-click leaves the loop exactly as it was", model.loop == loopBefore)

        // A third click must not chain: the double-click consumed the state, so
        // this is a plain click that places the playhead and plays nothing.
        model.pause()
        await settle(seconds: 0.2)
        let thirdX = clickX + 40
        await click(at: CGPoint(x: thirdX, y: lanes.midY))
        let thirdExpected = PixelMapping.frame(atPixel: thirdX - lanes.minX, in: model.viewport)
        log.check(
            "a third click does not chain into another play",
            !model.isPlaying && abs(model.playhead - thirdExpected) <= 1)

        await checkDoubleClickPastTheLoopIsHonoured(model: model, lanes: lanes, log: &log)

        model.pause()
        model.clearLoop()
        model.seek(to: 0)
    }

    /// Task 24 A case 3, driven rather than asserted.
    ///
    /// Task 22 decided a double-click past an active loop's out point should be
    /// pulled back into the region; the user overruled it, and reported it also
    /// behaved differently before the loop than after it. The click is now
    /// honoured and playback runs on towards the end of the file. The loop is
    /// **not** cleared or disabled — it stays on and stays drawn, and `F` puts
    /// playback back inside it in one key.
    ///
    /// Called with the loop and selection left in place by `checkDoubleClickPlays`.
    @MainActor
    private static func checkDoubleClickPastTheLoopIsHonoured(
        model: ViewerModel, lanes: CGRect, log: inout Logger
    ) async {
        model.pause()
        await settle(seconds: 0.2)
        let stalled = positionChecksAreImpossible(model: model)
        let outsideX = lanes.minX + lanes.width * 0.95
        let outside = PixelMapping.frame(atPixel: outsideX - lanes.minX, in: model.viewport)
        log.check(
            "the escape check really aims past the loop's out point "
                + "(\(outside) > \(model.loop.range.end))",
            outside > model.loop.range.end)
        await click(at: CGPoint(x: outsideX, y: lanes.midY))
        await click(at: CGPoint(x: outsideX, y: lanes.midY))
        await settle(seconds: 0.4)
        let escaped = model.playhead
        // Forward of the click, never behind it: being snapped back to the in
        // point is the one outcome this exists to rule out.
        log.check(
            "a double-click past an active loop plays from the click, not from the loop "
                + "(\(escaped), loop \(model.loop.range.start)…\(model.loop.range.end))",
            escaped >= outside - 1 && escaped > model.loop.range.end,
            unless: stalled)
        log.check(
            "and the loop itself is left switched on rather than silently cleared",
            model.loop.isActive)
    }

    /// One click, as a real down/up pair. `minimumDistance: 0` means SwiftUI's
    /// `DragGesture` reports both a change and an end for a click that never
    /// moved, which is exactly what `ViewerModel.dragEnded` reads as one.
    ///
    /// The `.mouseMoved` first is not decoration. Without it a run was measured
    /// in which the *first* click of the pair reached nothing at all — the
    /// playhead never left where the preceding check had put it — while the
    /// second behaved as a lone click. Moving the pointer into the view before
    /// pressing is what a hand does, and it makes the delivery repeatable.
    ///
    /// The trailing settle is deliberately short: after a double-click the
    /// transport is running, and every millisecond spent here is playhead drift
    /// the caller then has to tolerate.
    @MainActor
    private static func click(at point: CGPoint) async {
        sendMouse(.mouseMoved, at: point)
        await settle(seconds: 0.05)
        sendMouse(.leftMouseDown, at: point)
        await settle(seconds: 0.05)
        sendMouse(.leftMouseUp, at: point)
        await settle(seconds: 0.05)
    }
}
