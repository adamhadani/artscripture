import ArtscribeKit
import AudioDecode
import CoreGraphics
import Foundation
import Testing
import Waveform

@testable import ArtscribeUI

/// Undo and redo for the loop (2026-11-14): one step per thing the user did,
/// on the window's undo manager, and nothing for anything else.
///
/// A real `UndoManager` throughout, with `groupsByEvent` off — a window's
/// groups by run-loop pass, which a synchronous test does not have — so what
/// is asserted is what Edit ▸ Undo would read and do.
@MainActor
@Suite("Loop undo")
struct LoopUndoTests {

    private static let totalFrames: FrameIndex = 2_000_000
    /// Near the top of the lanes, clear of the playhead's grip halfway down.
    private static let pressY = 30.0
    /// Lane points 500–550 in the fitted view (2 000 frames a point).
    private static let loop = LoopRegion(
        range: FrameRange(start: 1_000_000, count: 100_000), isEnabled: true)

    private final class Clock {
        var time = 0.0
    }

    /// A fresh one per test: Swift Testing builds the suite anew for each.
    private let clock = Clock()

    private func makeModel(withLoop: Bool = true) -> (ViewerModel, UndoManager) {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.laneSize = CGSize(width: 1000, height: 300)
        let surface = EmptyStatePrompt.Surface.desktop
        model.prefs.handleReach = ControlMetrics.handleReach(on: surface)
        model.prefs.seeksOnSelectionPress = LaneDragPolicy.seeksOnPress(on: surface)
        model.prefs.edgeTapIsAClick = LaneDragPolicy.edgeTapIsAClick(on: surface)
        model.prefs.tapSlop = LaneDragPolicy.tapSlop(on: surface)
        if withLoop { model.applyLoop(Self.loop) }
        let manager = UndoManager()
        manager.groupsByEvent = false
        model.attachUndoManager(manager)
        let clock = self.clock
        model.loopUndo.now = { clock.time }
        return (model, manager)
    }

    private func point(_ x: Double) -> CGPoint { CGPoint(x: x, y: Self.pressY) }

    private func drag(_ model: ViewerModel, from x: Double, to endX: Double) {
        model.laneDragChanged(start: point(x), current: point(x), option: false, shift: false)
        for step in 1...8 {
            let current = point(x + (endX - x) * Double(step) / 8)
            model.laneDragChanged(start: point(x), current: current, option: false, shift: false)
        }
        model.laneDragEnded(start: point(x), end: point(endX), now: 0)
    }

    // MARK: - One step per gesture

    @Test("moving the loop by its inside is one step, Move Loop, and it undoes and redoes")
    func aBodyDragIsOneStep() {
        let (model, manager) = makeModel()
        drag(model, from: 525, to: 600)
        let moved = model.loop
        #expect(moved.range.start > Self.loop.range.start)
        #expect(manager.undoActionName == "Move Loop")
        manager.undo()
        #expect(model.loop == Self.loop)
        #expect(!manager.canUndo, "eight drag events, one step")
        #expect(manager.redoActionName == "Move Loop")
        manager.redo()
        #expect(model.loop == moved)
    }

    @Test("an edge drag is Move Loop End, or Start")
    func anEdgeDragIsNamedForItsEdge() {
        let (model, manager) = makeModel()
        drag(model, from: 550, to: 600)
        #expect(manager.undoActionName == "Move Loop End")
        drag(model, from: 500, to: 450)
        #expect(manager.undoActionName == "Move Loop Start")
        manager.undo()
        manager.undo()
        #expect(model.loop == Self.loop)
    }

    @Test("a loop drawn where there was none is New Loop, and undoing it leaves none")
    func aNewLoopUndoesToNothing() {
        let (model, manager) = makeModel(withLoop: false)
        drag(model, from: 100, to: 300)
        #expect(!model.loop.range.isEmpty)
        #expect(manager.undoActionName == "New Loop")
        manager.undo()
        #expect(model.loop.range.isEmpty)
    }

    /// The gesture's end never came — a call, an app switch — so its range
    /// reaches the engine when the next gesture starts, and is recorded then.
    @Test("a drag whose end never came is recorded when the next gesture starts")
    func anUnfinishedDragIsRecordedLate() {
        let (model, manager) = makeModel(withLoop: false)
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        #expect(!manager.canUndo, "only drawn so far")
        model.laneDragChanged(start: point(700), current: point(700), option: false, shift: false)
        model.laneDragEnded(start: point(700), end: point(700), now: 0)
        #expect(manager.undoActionName == "New Loop")
        manager.undo()
        #expect(model.loop.range.isEmpty)
    }

    // MARK: - The keys and the menu

    @Test("Clear Loop comes back exactly as it was, looping included")
    func clearLoopUndoes() {
        let (model, manager) = makeModel()
        model.clearLoop()
        #expect(manager.undoActionName == "Clear Loop")
        manager.undo()
        #expect(model.loop == Self.loop)
    }

    @Test("switching looping off is a step of its own")
    func loopingOffIsAStep() {
        let (model, manager) = makeModel()
        model.toggleLoop()
        #expect(manager.undoActionName == "Turn Looping Off")
        manager.undo()
        #expect(model.loop.isEnabled)
        #expect(manager.redoActionName == "Turn Looping Off")
    }

    @Test("A, S and ⌘A are steps, each named for what it did")
    func theMarkingKeysAreSteps() {
        let (model, manager) = makeModel()
        model.seek(to: 900_000)
        model.setLoopIn()
        #expect(manager.undoActionName == "Set Loop Start")
        model.seek(to: 1_300_000)
        model.setLoopOut()
        #expect(manager.undoActionName == "Set Loop End")
        model.loopWholeFile()
        #expect(manager.undoActionName == "Loop Whole File")
        manager.undo()
        manager.undo()
        manager.undo()
        #expect(model.loop == Self.loop)
    }

    // MARK: - A held key

    @Test("a held C is one step for the whole run")
    func aKeyRepeatRunIsOneStep() {
        let (model, manager) = makeModel()
        for press in 0..<6 {
            clock.time = Double(press) * 0.05
            model.moveLoop(.whole, .gentle, direction: .forward)
        }
        #expect(model.loop.range.start > Self.loop.range.start)
        manager.undo()
        #expect(model.loop == Self.loop)
        #expect(!manager.canUndo)
    }

    @Test("presses with a pause between them are separate steps")
    func aPauseEndsTheRun() {
        let (model, manager) = makeModel()
        model.moveLoop(.whole, .gentle, direction: .forward)
        let first = model.loop
        clock.time = LoopUndo.coalescingWindow + 0.5
        model.moveLoop(.whole, .gentle, direction: .forward)
        manager.undo()
        #expect(model.loop == first)
    }

    @Test("a run broken by another edit is two runs")
    func anotherEditEndsTheRun() {
        let (model, manager) = makeModel()
        model.moveLoop(.whole, .gentle, direction: .forward)
        let first = model.loop
        clock.time = 0.1
        model.toggleLoop()
        clock.time = 0.2
        model.moveLoop(.whole, .gentle, direction: .forward)
        manager.undo()
        #expect(model.loop.range == first.range)
        #expect(manager.undoActionName == "Turn Looping Off")
    }

    // MARK: - What is not a step

    @Test("a pan, a tap and a pinch-cancelled drag record nothing")
    func gesturesThatLeaveTheLoopRecordNothing() {
        let (model, manager) = makeModel()
        model.zoom(by: 4, anchorFrame: 1_000_000)
        drag(model, from: 100, to: 300)  // a pan: there is a loop
        model.laneDragChanged(start: point(150), current: point(150), option: false, shift: false)
        model.laneDragEnded(start: point(150), end: point(150), now: 1)  // a tap
        #expect(!manager.canUndo)

        let (bare, bareManager) = makeModel(withLoop: false)
        bare.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        bare.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        bare.cancelLaneDrag()
        bare.laneDragEnded(start: point(100), end: point(300), now: 0)
        #expect(!bareManager.canUndo)
    }

    @Test("an edit that changes nothing records nothing")
    func aNoOpIsNoStep() {
        let (model, manager) = makeModel(withLoop: false)
        model.clearLoop()
        #expect(!manager.canUndo)
    }

    // MARK: - What an undo does

    /// The engine captures a loop only on arrival (spec §5.1). A loop that
    /// comes back somewhere else is the one you hear, as a moved one is.
    @Test("undoing a move of a playing loop takes the playhead back into it")
    func undoBringsThePlayheadIntoTheLoop() {
        let (model, manager) = makeModel()
        model.seek(to: 1_050_000)
        drag(model, from: 525, to: 800)
        #expect(!Self.loop.range.contains(model.playhead))
        let pushes = model.loopPushes
        manager.undo()
        #expect(model.loop == Self.loop)
        #expect(model.playhead == Self.loop.range.start)
        #expect(model.loopPushes == pushes + 1, "the engine hears the undo")
    }

    @Test("another track starts with no history")
    func aNewTrackForgets() {
        let (model, manager) = makeModel()
        model.clearLoop()
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        #expect(!manager.canUndo)
    }

    @Test("closing the track forgets its history")
    func closingForgets() {
        let (model, manager) = makeModel()
        model.clearLoop()
        model.closeTrack()
        #expect(!manager.canUndo)
    }

    @Test("a different undo manager starts empty, and the old one is cleared")
    func reattachingStartsClean() {
        let (model, first) = makeModel()
        model.clearLoop()
        let second = UndoManager()
        second.groupsByEvent = false
        model.attachUndoManager(second)
        #expect(!first.canUndo)
        #expect(!second.canUndo)
    }

    @Test("with no undo manager attached, edits still work")
    func noManagerNoProblem() {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.applyLoop(Self.loop)
        model.clearLoop()
        #expect(model.loop.range.isEmpty)
    }

    /// SwiftUI may hand the environment's manager over as `nil` in passing.
    @Test("a nil undo manager in passing keeps the history")
    func aPassingNilKeepsTheHistory() {
        let (model, manager) = makeModel()
        model.clearLoop()
        model.attachUndoManager(nil)
        model.attachUndoManager(manager)
        #expect(manager.undoActionName == "Clear Loop")
    }

    // MARK: - The review's findings (PR #101)

    /// Control Centre or a call cuts the drag short. Its step is recorded
    /// then, so an edit made before the next touch sits above it, in order.
    @Test("a drag the system cuts short is its undo step at once, in order")
    func aSystemCancelledDragIsRecordedInOrder() {
        let (model, manager) = makeModel()
        model.laneDragChanged(start: point(550), current: point(550), option: false, shift: false)
        model.laneDragChanged(start: point(550), current: point(600), option: false, shift: false)
        model.laneGestureCancelled(start: point(550))
        #expect(model.laneDragMode == nil)
        #expect(manager.undoActionName == "Move Loop End")
        let dragged = model.loop
        model.toggleLoop()
        manager.undo()
        #expect(model.loop == dragged, "only the toggle came off")
        manager.undo()
        #expect(model.loop == Self.loop)
    }

    @Test("a range the system cuts short reaches the engine, as a New Loop")
    func aSystemCancelledRangeIsANewLoop() {
        let (model, manager) = makeModel(withLoop: false)
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        model.laneGestureCancelled(start: point(100))
        #expect(!model.loopIsStaged)
        #expect(manager.undoActionName == "New Loop")
    }

    /// A range only drawn has not reached the engine: not a state to restore.
    @Test("Clear Loop in the middle of drawing a first loop records nothing")
    func clearingAHalfDrawnRangeIsNoStep() {
        let (model, manager) = makeModel(withLoop: false)
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: false)
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: false)
        model.clearLoop()
        model.laneDragChanged(start: point(100), current: point(350), option: false, shift: false)
        model.laneDragEnded(start: point(100), end: point(350), now: 0)
        #expect(model.loop.range.isEmpty)
        #expect(!manager.canUndo)
    }

    @Test("a Shift-drag with no loop makes a New Loop, not an extension")
    func aShiftDragFromNothingIsANewLoop() {
        let (model, manager) = makeModel(withLoop: false)
        model.laneDragChanged(start: point(100), current: point(100), option: false, shift: true)
        model.laneDragChanged(start: point(100), current: point(300), option: false, shift: true)
        model.laneDragEnded(start: point(100), end: point(300), now: 0)
        #expect(manager.undoActionName == "New Loop")
    }

    /// An undo off screen looks like one that did nothing.
    @Test("an undo brings the loop it put back on screen")
    func undoRevealsTheLoop() {
        let (model, manager) = makeModel()
        model.zoom(by: 8, anchorFrame: 1_050_000)
        drag(model, from: 500, to: 700)  // the loop's inside, at this zoom
        model.scroll(byPoints: 5000)
        let restored = Self.loop.range
        #expect(restored.end < model.viewport.startFrame, "scrolled well past it")
        manager.undo()
        #expect(model.loop.range == restored)
        #expect(
            restored.start >= model.viewport.startFrame && restored.start <= model.viewport.endFrame
        )
    }
}
