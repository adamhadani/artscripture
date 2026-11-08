import ArtscribeKit
import AudioDecode
import CoreGraphics
import Testing
import Waveform

@testable import ArtscribeUI

/// One range, and looping is its switch (design 2026-11-03).
///
/// Reported from an iPhone: looping a passage took a drag, *Selection → Loop*
/// and then *Loop* — three steps, the middle one invisible — and a drag that
/// missed a loop edge started an orange selection instead of moving the edge.
/// The loop is now the only range: a drag defines it, one button loops it.
@MainActor
@Suite("One range: a drag defines the loop")
struct OneRangeTests {

    private static let totalFrames: FrameIndex = 2_000_000
    private static let framesPerPoint: FrameIndex = 2000
    private static let laneHeight: Double = 300
    private static let midLane = laneHeight / 2

    private func makeModel() -> ViewerModel {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.laneSize = CGSize(width: 1000, height: Self.laneHeight)
        return model
    }

    private func frame(_ point: Double) -> FrameIndex { FrameIndex(point) * Self.framesPerPoint }

    private func range(_ from: Double, _ to: Double) -> FrameRange {
        FrameRange(start: frame(from), count: frame(to) - frame(from))
    }

    private func drag(_ model: ViewerModel, from x: Double, to endX: Double, shift: Bool = false) {
        let start = CGPoint(x: x, y: Self.midLane)
        model.laneDragChanged(start: start, current: start, option: false, shift: shift)
        for step in 1...8 {
            let current = CGPoint(x: x + (endX - x) * Double(step) / 8, y: Self.midLane)
            model.laneDragChanged(start: start, current: current, option: false, shift: shift)
        }
        model.laneDragEnded(start: start, end: CGPoint(x: endX, y: Self.midLane), now: 0)
    }

    private func tap(_ model: ViewerModel, at x: Double, now: Double = 0) {
        let point = CGPoint(x: x, y: Self.midLane)
        model.laneDragChanged(start: point, current: point, option: false, shift: false)
        model.laneDragEnded(start: point, end: point, now: now)
    }

    // MARK: - The drag

    /// A new loop loops: the user's *"should be opt out rather than opt in"*.
    @Test("a drag defines the range, and the new loop loops")
    func aDragDefinesTheRange() {
        let model = makeModel()
        drag(model, from: 100, to: 300)
        #expect(model.loop.range == range(100, 300))
        #expect(model.loop.isEnabled)
    }

    /// Switching looping off is for *this* loop. The next one marked is a new
    /// loop, and loops — otherwise one "off" would quietly bring back the
    /// opt-in behaviour this replaced.
    @Test("with looping switched off, a newly marked passage still loops")
    func aNewPassageLoopsEvenAfterLoopingWasSwitchedOff() {
        let model = makeModel()
        drag(model, from: 100, to: 300)
        model.toggleLoop()
        #expect(!model.loop.isEnabled)
        drag(model, from: 500, to: 700)
        #expect(model.loop.range == range(500, 700))
        #expect(model.loop.isEnabled)
    }

    /// The edits keep it off: dragging an edge or the middle is adjusting the
    /// loop you switched off, not making a new one.
    @Test("with looping switched off, adjusting the loop leaves it off")
    func editingALoopKeepsLoopingOff() {
        let model = makeModel()
        drag(model, from: 100, to: 300)
        model.toggleLoop()
        drag(model, from: 300, to: 400)  // its end edge
        #expect(model.loop.range == range(100, 400))
        #expect(!model.loop.isEnabled)
        drag(model, from: 250, to: 350)  // its middle
        #expect(model.loop.range == range(200, 500))
        #expect(!model.loop.isEnabled)
    }

    @Test("a drag while looping replaces the loop, and the new passage keeps looping")
    func aDragWhileLoopingReplacesTheLoopAndKeepsLooping() {
        let model = makeModel()
        model.applyLoop(LoopRegion(range: range(500, 600), isEnabled: true))
        drag(model, from: 100, to: 300)
        #expect(model.loop.range == range(100, 300))
        #expect(model.loop.isEnabled)
    }

    @Test("a dragged-out range reaches the engine when the finger lifts, not on every event")
    func theEngineHearsAboutANewRangeOnLift() {
        let model = makeModel()
        let start = CGPoint(x: 100, y: Self.midLane)
        model.laneDragChanged(start: start, current: start, option: false, shift: false)
        model.laneDragChanged(
            start: start, current: CGPoint(x: 200, y: Self.midLane), option: false, shift: false)
        #expect(model.loopIsStaged)
        #expect(model.loop.range == range(100, 200))
        model.laneDragEnded(start: start, end: CGPoint(x: 200, y: Self.midLane), now: 0)
        #expect(!model.loopIsStaged)
    }

    /// Review focus 1. `DragGesture(minimumDistance: 0)` reports a touch-down as
    /// a change, so a range begun there would replace a playing loop with an
    /// empty one on every tap.
    @Test("a tap places the playhead and leaves the loop alone")
    func tapDoesNotStageARange() {
        let model = makeModel()
        let loop = LoopRegion(range: range(500, 600), isEnabled: true)
        model.applyLoop(loop)
        tap(model, at: 200)
        #expect(model.loop == loop)
        #expect(!model.loopIsStaged)
        #expect(model.playhead == frame(200))
    }

    @Test("a double tap leaves the loop alone too")
    func doubleTapKeepsTheLoop() {
        let model = makeModel()
        let loop = LoopRegion(range: range(500, 600), isEnabled: true)
        model.applyLoop(loop)
        tap(model, at: 200, now: 0)
        tap(model, at: 200, now: 0.1)
        #expect(model.loop == loop)
    }

    @Test("cancelling a drag puts the previous loop back")
    func cancelledDragRestoresTheLoop() {
        let model = makeModel()
        let loop = LoopRegion(range: range(500, 600), isEnabled: true)
        model.applyLoop(loop)
        let start = CGPoint(x: 100, y: Self.midLane)
        model.laneDragChanged(start: start, current: start, option: false, shift: false)
        model.laneDragChanged(
            start: start, current: CGPoint(x: 250, y: Self.midLane), option: false, shift: false)
        model.cancelLaneDrag()
        #expect(model.loop == loop)
        #expect(!model.loopIsStaged)
    }

    @Test("a drag from right to left gives the same range")
    func backwardsDragNormalises() {
        let model = makeModel()
        drag(model, from: 300, to: 100)
        #expect(model.loop.range == range(100, 300))
    }

    @Test("a shift-drag keeps the far edge and moves the near one")
    func shiftDragKeepsTheFarEdge() {
        let model = makeModel()
        model.applyLoop(LoopRegion(range: range(100, 300)))
        drag(model, from: 280, to: 400, shift: true)
        #expect(model.loop.range == range(100, 400))
    }

    // MARK: - Keys

    @Test("shift-arrow with no range starts one at the playhead")
    func extendWithNoRangeStartsAtThePlayhead() {
        let model = makeModel()
        model.seek(to: frame(500))
        model.extendLoop(.forward)
        let step = FrameIndex((model.prefs.nudgeAmounts[.normal] * 44100).rounded())
        #expect(model.loop.range == FrameRange(start: frame(500), count: step))
    }

    @Test("shift-left at the file start makes nothing inverted")
    func extendAtFileStartClamps() {
        let model = makeModel()
        model.extendLoop(.backward)
        #expect(model.loop.range.start == 0)
        #expect(model.loop.range.count == 0)
    }

    @Test("shift-arrow extends the edge it last moved")
    func extendKeepsItsAnchor() {
        let model = makeModel()
        model.seek(to: frame(500))
        model.extendLoop(.forward)
        model.extendLoop(.forward)
        model.extendLoop(.backward)
        let step = FrameIndex((model.prefs.nudgeAmounts[.normal] * 44100).rounded())
        #expect(model.loop.range == FrameRange(start: frame(500), count: step))
    }

    @Test("the selection's keys now drive the loop")
    func keysDriveTheLoop() {
        #expect(KeyBindings.action(for: .key("g")) == nil)
        #expect(KeyBindings.action(for: .key("c")) == .loopMoveLeft)
        #expect(KeyBindings.action(for: .key("v")) == .loopMoveRight)
        #expect(KeyBindings.action(for: .key("c", .option)) == .loopMoveLeftFar)
        #expect(KeyBindings.action(for: .key("v", .option)) == .loopMoveRightFar)
        // The loop's own chords stay, as aliases.
        #expect(KeyBindings.action(for: .key("c", .shift)) == .loopMoveLeft)
        #expect(KeyBindings.action(for: KeyChord(.leftArrow, .shift)) == .loopExtendLeft)
        #expect(KeyBindings.action(for: KeyChord(.rightArrow, .shift)) == .loopExtendRight)
        #expect(KeyBindings.action(for: KeyChord(.escape)) == .loopClear)
        #expect(KeyBindings.action(for: .key("a", .command)) == .loopSelectAll)
        #expect(KeyBindings.action(for: .key("9", .command)) == .zoomToLoop)
    }

    @Test("clear empties the loop; with no loop it does nothing")
    func clearLoop() {
        let model = makeModel()
        model.clearLoop()
        #expect(model.loop == LoopRegion())
        #expect(!model.isDirty)
        model.applyLoop(LoopRegion(range: range(100, 300), isEnabled: true))
        model.clearLoop()
        #expect(model.loop == LoopRegion())
    }

    @Test("select all makes the whole file the loop, and it loops")
    func selectAllLoopsTheWholeFile() {
        let model = makeModel()
        model.loopWholeFile()
        #expect(model.loop.range == FrameRange(start: 0, count: Self.totalFrames))
        #expect(model.loop.isEnabled)
    }

    @Test("shift-space goes to the range start, looping or not, else to 0")
    func shiftSpaceGoesToTheRangeStart() {
        let model = makeModel()
        model.seek(to: frame(800))
        model.returnToStart()
        #expect(model.playhead == 0)
        model.applyLoop(LoopRegion(range: range(300, 400)))
        model.seek(to: frame(800))
        model.returnToStart()
        #expect(model.playhead == frame(300))
    }

    @Test("zoom to loop frames the range")
    func zoomToLoopFramesTheRange() {
        let model = makeModel()
        model.applyLoop(LoopRegion(range: range(300, 400)))
        model.zoomToLoop()
        #expect(model.viewport.startFrame == frame(300))
    }

    // MARK: - The transport bar

    @Test("there is no Selection → Loop button, and Loop is live whenever a range exists")
    func theTransportHasNoSelectionButton() {
        #expect(!TransportControl.allCases.map(\.rawValue).contains("loopFromSelection"))
        let model = makeModel()
        #expect(!TransportControl.loop.isEnabled(in: model.transportState))
        drag(model, from: 100, to: 300)
        #expect(TransportControl.loop.isEnabled(in: model.transportState))
    }
}
