import ArtscribeKit
import AudioDecode
import CoreGraphics
import Testing
import Waveform

@testable import ArtscribeUI

/// The final review's findings on the one-range change (2026-11-03), each as a
/// test that failed before its fix.
@MainActor
@Suite("One range: the review's findings")
struct OneRangeReviewTests {

    private static let totalFrames: FrameIndex = 2_000_000
    private static let framesPerPoint: FrameIndex = 2000
    private static let laneHeight: Double = 300
    private static let midLane = laneHeight / 2

    private func makeModel(touch: Bool = false) -> ViewerModel {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.laneSize = CGSize(width: 1000, height: Self.laneHeight)
        if touch {
            let surface = EmptyStatePrompt.Surface.phone
            model.prefs.handleReach = ControlMetrics.handleReach(on: surface)
            model.prefs.seeksOnSelectionPress = LaneDragPolicy.seeksOnPress(on: surface)
            model.prefs.edgeTapIsAClick = LaneDragPolicy.edgeTapIsAClick(on: surface)
        }
        return model
    }

    private func frame(_ point: Double) -> FrameIndex { FrameIndex(point) * Self.framesPerPoint }

    private func range(_ from: Double, _ to: Double) -> FrameRange {
        FrameRange(start: frame(from), count: frame(to) - frame(from))
    }

    private func point(_ x: Double) -> CGPoint { CGPoint(x: x, y: Self.midLane) }

    private func drag(_ model: ViewerModel, from x: Double, to endX: Double, now: Double = 0) {
        model.laneDragChanged(start: point(x), current: point(x), option: false, shift: false)
        for step in 1...8 {
            let current = point(x + (endX - x) * Double(step) / 8)
            model.laneDragChanged(start: point(x), current: current, option: false, shift: false)
        }
        model.laneDragEnded(start: point(x), end: point(endX), now: now)
    }

    private func tap(_ model: ViewerModel, at x: Double, now: Double = 0) {
        model.laneDragChanged(start: point(x), current: point(x), option: false, shift: false)
        model.laneDragEnded(start: point(x), end: point(x), now: now)
    }

    // MARK: - Critical 1: a tap inside a finger's edge reach

    /// The widened touch reach turned most taps near a loop into a grab of its
    /// edge — which jumped to the finger, was saved, and swallowed the tap.
    @Test("on touch, a tap within an edge's reach places the playhead and leaves the loop alone")
    func aTapNearAnEdgeOnTouchIsATap() {
        let model = makeModel(touch: true)
        let loop = LoopRegion(range: range(200, 600), isEnabled: true)
        model.applyLoop(loop)
        let pushes = model.loopPushes
        tap(model, at: 615)
        #expect(model.loop == loop)
        #expect(model.loopPushes == pushes)
        #expect(model.playhead == frame(615))
    }

    @Test("on touch, a double tap within an edge's reach still plays")
    func aDoubleTapNearAnEdgeOnTouchPlays() {
        let model = makeModel(touch: true)
        model.applyLoop(LoopRegion(range: range(200, 600), isEnabled: true))
        tap(model, at: 615, now: 0)
        tap(model, at: 615, now: 0.1)
        // No audio session here: an attempt to play is what raises this.
        #expect(model.playbackNotice != nil)
    }

    /// The edge follows the finger's *movement*, not its position: grabbed
    /// 15 pt past the out point and moved 30 pt, it lands 30 pt further on.
    @Test("an edge moves by how far the finger moved, not to where the finger is")
    func anEdgeMovesByTheDrag() {
        let model = makeModel(touch: true)
        model.applyLoop(LoopRegion(range: range(200, 600), isEnabled: true))
        drag(model, from: 615, to: 645)
        #expect(model.loop.range == range(200, 630))
    }

    // MARK: - Important 1: a new passage while looping is the one you hear

    @Test("a range dragged out while looping brings the playhead into it")
    func aNewLoopIsWhereThePlayheadGoes() {
        let model = makeModel(touch: true)
        model.applyLoop(LoopRegion(range: range(500, 600), isEnabled: true))
        model.seek(to: frame(550))
        drag(model, from: 100, to: 300)
        #expect(model.playhead == frame(100))
    }

    @Test("with looping off a new range leaves the playhead alone on touch")
    func aNewRangeWithLoopingOffDoesNotSeek() {
        let model = makeModel(touch: true)
        model.seek(to: frame(550))
        drag(model, from: 100, to: 300)
        #expect(model.playhead == frame(550))
    }

    @Test("a playhead already inside the new loop stays where it is")
    func aPlayheadInsideTheNewLoopStays() {
        let model = makeModel(touch: true)
        model.applyLoop(LoopRegion(range: range(500, 600), isEnabled: true))
        model.seek(to: frame(200))
        drag(model, from: 100, to: 300)
        #expect(model.playhead == frame(200))
    }

    // MARK: - Important 2: a staged range with no lift

    @Test("a drag whose end never came is committed when the next gesture starts")
    func aLeftoverStagedRangeIsCommitted() {
        let model = makeModel()
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        #expect(model.loopIsStaged)
        let pushes = model.loopPushes
        tap(model, at: 700)
        #expect(!model.loopIsStaged)
        #expect(model.loopPushes == pushes + 1)
        #expect(model.loop.range == range(100, 300))
        // And the tap was a tap.
        #expect(model.playhead == frame(700))
    }

    @Test("loading a track mid-drag leaves no drag state behind")
    func loadingClearsTheDrag() {
        let model = makeModel()
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        #expect(!model.loopIsStaged)
        #expect(model.loopBeforeLaneDrag == nil)
        #expect(model.laneDragMode == nil)
    }

    // MARK: - Important 3: a pinch never replaces the loop

    @Test("changes that keep arriving after a pinch cancelled the drag change nothing")
    func aCancelledDragStaysCancelled() {
        let model = makeModel()
        let loop = LoopRegion(range: range(500, 600), isEnabled: true)
        model.applyLoop(loop)
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(200), option: false, shift: false)
        model.cancelLaneDrag()
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        model.laneDragEnded(start: point(100), end: point(300), now: 0)
        #expect(model.loop == loop)
        #expect(!model.loopIsStaged)
    }

    // MARK: - Important 4: the engine hears about a new range exactly once

    @Test("a dragged-out range is pushed once, on lift, and never mid-drag")
    func oneRangeOnePush() {
        let model = makeModel()
        let before = model.loopPushes
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(200), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        #expect(model.loopPushes == before)
        model.laneDragEnded(start: point(100), end: point(300), now: 0)
        #expect(model.loopPushes == before + 1)
    }

    @Test("a cancelled range drag pushes nothing")
    func aCancelledDragPushesNothing() {
        let model = makeModel()
        let before = model.loopPushes
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        model.cancelLaneDrag()
        model.laneDragEnded(start: point(100), end: point(300), now: 0)
        #expect(model.loopPushes == before)
    }

    @Test("Esc with no loop is not an edit; with one it is")
    func clearingIsAnEditOnlyWhenThereWasALoop() throws {
        let model = SessionTestModel.make(try SessionScratch())
        model.clearLoop()
        #expect(!model.isDirty)
        model.applyLoop(LoopRegion(range: FrameRange(start: 1000, count: 5000)))
        model.isDirty = false
        model.clearLoop()
        #expect(model.isDirty)
    }

    // MARK: - Important 5: no page flip under a finger

    @Test("auto-scroll holds still while a lane drag is in flight")
    func noAutoScrollMidDrag() {
        // Touch: the press does not seek, so the playhead stays off-page — on a
        // pointer the press would put it under the cursor and nothing would flip.
        let model = makeModel(touch: true)
        model.zoom(by: 8, anchorFrame: 0)
        model.seek(to: Self.totalFrames - 1000)
        model.scroll(byPoints: -100_000)
        let start = model.viewport.startFrame
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        model.autoScroll()
        #expect(model.viewport.startFrame == start)
    }

    // MARK: - Minors

    @Test("a drag too short to cover a frame does not clear the loop")
    func anEmptyDragKeepsTheLoop() {
        let model = makeModel()
        let loop = LoopRegion(range: FrameRange(start: 1000, count: 500), isEnabled: true)
        model.applyLoop(loop)
        model.zoom(by: 1e9, anchorFrame: 1200)
        let x = model.viewport.pixel(forFrame: 1200)
        drag(model, from: x - 10, to: x - 4)
        #expect(model.loop == loop)
    }

    @Test("D with no range switches nothing on")
    func toggleNeedsARange() {
        let model = makeModel()
        model.toggleLoop()
        #expect(!model.loop.isEnabled)
    }
}
