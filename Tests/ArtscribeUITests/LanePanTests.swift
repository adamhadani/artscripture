import ArtscribeKit
import AudioDecode
import CoreGraphics
import Testing
import Waveform

@testable import ArtscribeUI

/// A drag outside the loop pans; it no longer replaces the loop (2026-11-14).
///
/// Reported by the user after using the app: a touch outside a loop — a tap
/// that wobbled, a reach to pan, the first finger of a pinch — threw away a
/// loop set with care and started a new one. A loop now changes only by being
/// taken hold of or cleared; with no loop a drag still draws the first.
@MainActor
@Suite("A drag outside the loop pans")
struct LanePanTests {

    private static let totalFrames: FrameIndex = 2_000_000
    private static let laneHeight: Double = 300
    /// Near the top of the lanes, clear of the playhead's grip halfway down:
    /// after a tap the playhead is under the next press, and a press on its
    /// grip scrubs rather than pans (`PlayheadScrub`).
    private static let pressY = 30.0
    /// Lane points 500–700 once zoomed in: well clear of the presses at 100–300,
    /// even with a finger's 22 pt reach either side of an edge.
    private static let loop = LoopRegion(
        range: FrameRange(start: 1_000_000, count: 100_000), isEnabled: true)

    private func makeModel(
        on surface: EmptyStatePrompt.Surface = .desktop, withLoop: Bool = true
    ) -> ViewerModel {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.laneSize = CGSize(width: 1000, height: Self.laneHeight)
        model.prefs.handleReach = ControlMetrics.handleReach(on: surface)
        model.prefs.seeksOnSelectionPress = LaneDragPolicy.seeksOnPress(on: surface)
        model.prefs.edgeTapIsAClick = LaneDragPolicy.edgeTapIsAClick(on: surface)
        model.prefs.panSlop = LaneDragPolicy.panSlop(on: surface)
        // Four times in, so there is file on both sides to pan to: 500 frames
        // a point, and the view starts at frame 750 000.
        model.zoom(by: 4, anchorFrame: 1_000_000)
        if withLoop { model.applyLoop(Self.loop) }
        return model
    }

    private func point(_ x: Double, down: Double = 0) -> CGPoint {
        CGPoint(x: x, y: Self.pressY + down)
    }

    private func press(_ model: ViewerModel, at x: Double) {
        model.laneDragChanged(start: point(x), current: point(x), option: false, shift: false)
    }

    private func move(_ model: ViewerModel, from x: Double, to current: CGPoint) {
        model.laneDragChanged(start: point(x), current: current, option: false, shift: false)
    }

    /// One gesture, walked the way `DragGesture` walks it: a change per step
    /// with a stable start, then an end.
    private func drag(_ model: ViewerModel, from x: Double, to endX: Double, now: Double = 0) {
        press(model, at: x)
        for step in 1...8 {
            move(model, from: x, to: point(x + (endX - x) * Double(step) / 8))
        }
        model.laneDragEnded(start: point(x), end: point(endX), now: now)
    }

    private func tap(_ model: ViewerModel, at x: Double, now: Double = 0) {
        press(model, at: x)
        model.laneDragEnded(start: point(x), end: point(x), now: now)
    }

    private func frame(atPoint x: Double, in model: ViewerModel) -> FrameIndex {
        PixelMapping.frame(atPixel: x, in: model.viewport)
    }

    // MARK: - The loop is left alone

    @Test(
        "a drag outside the loop leaves the loop, the engine and the playhead alone",
        arguments: [EmptyStatePrompt.Surface.desktop, .phone])
    func theLoopIsLeftAlone(on surface: EmptyStatePrompt.Surface) {
        let model = makeModel(on: surface)
        model.seek(to: 1_050_000)
        let pushes = model.loopPushes
        drag(model, from: 300, to: 100)
        #expect(model.loop == Self.loop)
        #expect(!model.loopIsStaged)
        #expect(model.loopPushes == pushes)
        #expect(model.playhead == 1_050_000)
    }

    @Test("with no loop a drag still draws one, and does not pan")
    func withNoLoopADragDrawsOne() {
        let model = makeModel(withLoop: false)
        let view = model.viewport
        drag(model, from: 100, to: 300)
        #expect(model.loop.range.start == frame(atPoint: 100, in: model))
        #expect(model.loop.isEnabled)
        #expect(model.viewport == view)
    }

    /// ⇧-drag is an edit of the loop, from anywhere: it keeps the far edge.
    @Test("a Shift-drag outside the loop still extends it")
    func shiftStillExtends() {
        let model = makeModel()
        model.laneDragChanged(start: point(300), current: point(300), option: false, shift: true)
        model.laneDragChanged(start: point(300), current: point(350), option: false, shift: true)
        model.laneDragEnded(start: point(300), end: point(350), now: 0)
        #expect(model.loop.range.end == Self.loop.range.end)
        #expect(model.loop.range.start == frame(atPoint: 350, in: model))
    }

    // MARK: - The view follows the finger

    @Test("the frame under the press stays under the finger")
    func theFrameUnderThePressFollowsTheFinger() {
        let model = makeModel()
        let anchor = frame(atPoint: 200, in: model)
        press(model, at: 200)
        for x in [260.0, 350, 120, 40] {
            move(model, from: 200, to: point(x))
            #expect(abs(model.viewport.pixel(forFrame: anchor) - x) <= 1, "at \(x)")
        }
        model.laneDragEnded(start: point(200), end: point(40), now: 0)
    }

    @Test("a drag that comes back to where it started puts the view back")
    func thereAndBackAgain() {
        let model = makeModel()
        let start = model.viewport.startFrame
        press(model, at: 200)
        move(model, from: 200, to: point(380))
        move(model, from: 200, to: point(200))
        #expect(model.viewport.startFrame == start)
    }

    /// Held against the viewport on every event, not summed: a sum would
    /// still be counting the points the view could not follow into.
    @Test("at the start of the file the view stops, and coming back does not drift")
    func theFileStartDoesNotLeaveADrift() {
        let model = makeModel()
        model.scroll(byPoints: -100_000)
        #expect(model.viewport.startFrame == 0)
        let anchor = frame(atPoint: 300, in: model)
        press(model, at: 300)
        move(model, from: 300, to: point(500))
        #expect(model.viewport.startFrame == 0)
        move(model, from: 300, to: point(100))
        #expect(abs(model.viewport.pixel(forFrame: anchor) - 100) <= 1)
    }

    // MARK: - A tap is still a tap

    /// The half of the bug a finger causes without meaning to drag at all.
    @Test("a finger's tap that wobbles under the slop moves the playhead and nothing else")
    func aWobblyTapIsATap() {
        let model = makeModel(on: .phone)
        let view = model.viewport
        press(model, at: 200)
        move(model, from: 200, to: point(206, down: 3))
        model.laneDragEnded(start: point(200), end: point(206, down: 3), now: 0)
        #expect(model.playhead == frame(atPoint: 206, in: model))
        #expect(model.viewport == view)
        #expect(model.loop == Self.loop)
    }

    /// The Mac seeks on mouse-down only when the press may draw a range. Here
    /// it may become a pan, and a pan must not move what you are hearing — so
    /// the click lands on release, as one on the loop's inside always has.
    @Test("with a pointer the press does not seek and the click does, on release")
    func aPointerClickSeeksOnRelease() {
        let model = makeModel()
        model.seek(to: 1_050_000)
        press(model, at: 200)
        #expect(model.playhead == 1_050_000)
        model.laneDragEnded(start: point(200), end: point(200), now: 0)
        #expect(model.playhead == frame(atPoint: 200, in: model))
    }

    @Test("with a pointer, past the click slop it pans rather than seeks")
    func aPointerPastTheSlopPans() {
        let model = makeModel()
        model.seek(to: 1_050_000)
        let start = model.viewport.startFrame
        drag(model, from: 200, to: 195)
        #expect(model.playhead == 1_050_000)
        #expect(model.viewport.startFrame > start)
    }

    @Test("a vertical swipe is not a tap")
    func aVerticalSwipeIsNotATap() {
        let model = makeModel(on: .phone)
        model.seek(to: 1_050_000)
        let view = model.viewport
        press(model, at: 200)
        move(model, from: 200, to: point(200, down: 40))
        model.laneDragEnded(start: point(200), end: point(200, down: 40), now: 0)
        #expect(model.playhead == 1_050_000)
        #expect(model.viewport == view)
    }

    @Test("a double tap outside the loop plays from there")
    func aDoubleTapPlays() {
        let model = makeModel(on: .phone)
        tap(model, at: 200, now: 0)
        tap(model, at: 200, now: 0.1)
        // No audio session here: an attempt to play is what raises this.
        #expect(model.playbackNotice != nil)
    }

    @Test("a pan is not the first half of a double tap")
    func aPanBreaksADoubleTap() {
        let model = makeModel(on: .phone)
        tap(model, at: 300, now: 0)
        drag(model, from: 300, to: 400, now: 0.1)
        tap(model, at: 300, now: 0.2)
        #expect(model.playbackNotice == nil)
    }

    // MARK: - A pinch, and a gesture that never ended

    /// A pinch's first finger starts a pan. Taking it back must not seek: the
    /// playhead of a playing track has moved on since the press.
    @Test("a pinch that begins as a pan moves neither the loop nor the playhead")
    func aPinchTakesBackAPan() {
        let model = makeModel(on: .phone)
        model.seek(to: 1_050_000)
        let seeks = model.seekGeneration
        let pushes = model.loopPushes
        press(model, at: 200)
        move(model, from: 200, to: point(230))
        model.cancelLaneDrag()
        let view = model.viewport
        // The first finger keeps reporting until the pinch ends.
        move(model, from: 200, to: point(290))
        model.laneDragEnded(start: point(200), end: point(290), now: 0)
        #expect(model.viewport == view)
        #expect(model.seekGeneration == seeks)
        #expect(model.loopPushes == pushes)
        #expect(model.loop == Self.loop)
    }

    /// Left latched, page-following would stay off until the next touch.
    @Test("a pan cut short by the system lets go of the lanes")
    func aCancelledPanLetsGo() {
        let model = makeModel(on: .phone)
        press(model, at: 200)
        move(model, from: 200, to: point(260))
        model.laneGestureCancelled(start: point(200))
        #expect(model.laneDragMode == nil)
        #expect(model.laneDragStart == nil)
    }

    // MARK: - The rules, as values

    @Test("open lane pans only when there is a loop, and everything else outranks it")
    func thePrecedence() {
        let pan = LanePan(anchorFrame: 0)
        #expect(LaneDragMode(option: false, shift: false, panning: pan) == .pan(pan))
        #expect(LaneDragMode(option: false, shift: false) == .range(extending: false))
        #expect(LaneDragMode(option: true, shift: false, panning: pan) == .zoom)
        #expect(LaneDragMode(option: false, shift: true, panning: pan) == .range(extending: true))
        #expect(
            LaneDragMode(option: false, shift: false, onPlayheadGrip: true, panning: pan)
                == .scrub)
        #expect(
            LaneDragMode(option: false, shift: false, handle: .loopBody, panning: pan)
                == .edge(.loopBody))
    }

    @Test("a finger may wander further than a pointer before a tap becomes a pan")
    func theSlop() {
        #expect(LaneDragPolicy.panSlop(on: .desktop) == ViewerModel.clickSlopPoints)
        #expect(LaneDragPolicy.panSlop(on: .phone) == 10)
        #expect(LaneDragPolicy.panSlop(on: .tabletWithDrop) == 10)
    }

    /// The cursor and the gesture must agree: no crosshair promising a new
    /// loop where a drag pans, and the loop's open hand kept for the loop.
    @Test("the cursor says pan where a drag pans")
    func theCursor() {
        func over(
            option: Bool = false, shift: Bool = false, drag: LaneDragMode? = nil,
            hovering: TimelineHandle? = nil, loopIsSet: Bool
        ) -> PointerAffordance {
            PointerAffordance.over(
                .waveformLanes, optionHeld: option, shiftHeld: shift, laneDrag: drag,
                hovering: hovering, loopIsSet: loopIsSet)
        }
        #expect(over(loopIsSet: true) == .panView)
        #expect(over(loopIsSet: false) == .selectRange)
        #expect(over(hovering: .loopBody, loopIsSet: true) == .moveRegion)
        #expect(over(option: true, loopIsSet: true) == .zoom)
        #expect(over(shift: true, loopIsSet: true) == .selectRange)
        let pan = LanePan(anchorFrame: 0)
        var moved = pan
        moved.hasMoved = true
        #expect(over(drag: .pan(pan), loopIsSet: true) == .panView)
        #expect(over(drag: .pan(moved), loopIsSet: true) == .panningView)
    }
}
