import ArtscribeKit
import AudioDecode
import CoreGraphics
import Testing
import Waveform

@testable import ArtscribeUI

/// **A new loop starts with looping on; editing a loop keeps it as it was.**
///
/// The user, 2026-11: *"when user creates a loop we should turn on looping mode
/// by default … should be opt out rather than opt in. Otherwise frustrating
/// experience to mark a loop only to see the playback continuing after it."*
/// The drag paths are in `OneRangeTests`; this suite is every other way a loop
/// comes into being, and the edits that must not switch a loop back on. See
/// `ViewerModel.enterLoopIfOutside`.
@MainActor
@Suite("A new loop loops")
struct NewLoopLoopsTests {

    private static let totalFrames: FrameIndex = 2_000_000
    private static let framesPerPoint: FrameIndex = 2000
    private static let midLane: Double = 150

    private func makeModel() -> ViewerModel {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.laneSize = CGSize(width: 1000, height: Self.midLane * 2)
        return model
    }

    private func frame(_ point: Double) -> FrameIndex { FrameIndex(point) * Self.framesPerPoint }

    private func drag(_ model: ViewerModel, from x: Double, to endX: Double, shift: Bool = false) {
        let start = CGPoint(x: x, y: Self.midLane)
        model.laneDragChanged(start: start, current: start, option: false, shift: shift)
        for step in 1...8 {
            let current = CGPoint(x: x + (endX - x) * Double(step) / 8, y: Self.midLane)
            model.laneDragChanged(start: start, current: current, option: false, shift: shift)
        }
        model.laneDragEnded(start: start, end: CGPoint(x: endX, y: Self.midLane), now: 0)
    }

    /// A loop that exists, with looping switched off by hand.
    private func switchedOffLoop(_ model: ViewerModel) {
        drag(model, from: 200, to: 400)
        model.toggleLoop()
        #expect(model.loop.range == FrameRange(start: frame(200), count: frame(200)))
        #expect(!model.loop.isEnabled)
    }

    // MARK: - The keys that make a loop

    @Test("A with no loop makes one that loops, from the playhead on")
    func aMakesALoop() {
        let model = makeModel()
        model.seek(to: frame(300))
        model.setLoopIn()
        #expect(model.loop.isActive)
        #expect(model.playhead == frame(300))
    }

    /// `S` from nothing makes a loop from the start of the file to here, and the
    /// playhead is at its end — outside it — so it goes back to the start, or
    /// the engine would play straight past (spec §5.1).
    @Test("S with no loop makes one from the start, which loops and is where playback goes")
    func sMakesALoopAndGoesToIt() {
        let model = makeModel()
        model.seek(to: frame(300))
        model.setLoopOut()
        #expect(model.loop.range == FrameRange(start: 0, count: frame(300)))
        #expect(model.loop.isActive)
        #expect(model.playhead == 0)
    }

    @Test("⇧→ from a bare playhead makes a loop that loops")
    func shiftRightMakesALoop() {
        let model = makeModel()
        model.seek(to: frame(300))
        model.extendLoop(.forward)
        #expect(!model.loop.range.isEmpty)
        #expect(model.loop.isActive)
        #expect(model.playhead == frame(300))
    }

    @Test("⇧← from a bare playhead makes a loop behind it, and goes to its start")
    func shiftLeftMakesALoopAndGoesToIt() {
        let model = makeModel()
        model.seek(to: frame(300))
        model.extendLoop(.backward)
        #expect(model.loop.isActive)
        #expect(model.loop.range.end == frame(300))
        #expect(model.playhead == model.loop.range.start)
    }

    @Test("⌘A replaces a switched-off loop with the whole file, which loops")
    func selectAllLoops() {
        let model = makeModel()
        switchedOffLoop(model)
        model.loopWholeFile()
        #expect(model.loop.range == FrameRange(start: 0, count: Self.totalFrames))
        #expect(model.loop.isActive)
    }

    // MARK: - Edits keep looping off

    @Test("A and S on a switched-off loop move its edges and leave it off")
    func inAndOutPointsAreEdits() {
        let model = makeModel()
        switchedOffLoop(model)
        model.seek(to: frame(250))
        model.setLoopIn()
        model.seek(to: frame(350))
        model.setLoopOut()
        #expect(model.loop.range == FrameRange(start: frame(250), count: frame(100)))
        #expect(!model.loop.isEnabled)
    }

    @Test("⇧-arrows on a switched-off loop extend it and leave it off")
    func shiftArrowsAreEdits() {
        let model = makeModel()
        switchedOffLoop(model)
        model.extendLoop(.forward)
        #expect(model.loop.range.end > frame(400))
        #expect(!model.loop.isEnabled)
    }

    /// A `⇧`-drag goes down the new-range path (`dragChanged`), so it is the
    /// one edit that could pick up "new loop, switch it on" by accident.
    @Test("a ⇧-drag on a switched-off loop extends it and leaves it off")
    func shiftDragIsAnEdit() {
        let model = makeModel()
        switchedOffLoop(model)
        drag(model, from: 600, to: 700, shift: true)
        #expect(model.loop.range == FrameRange(start: frame(200), count: frame(500)))
        #expect(!model.loop.isEnabled)
    }

    @Test("a ⇧-drag with no loop is a new loop, and loops")
    func shiftDragFromNothingLoops() {
        let model = makeModel()
        drag(model, from: 600, to: 700, shift: true)
        #expect(model.loop.isActive)
    }
}
