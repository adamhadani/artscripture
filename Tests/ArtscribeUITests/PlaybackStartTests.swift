import ArtscribeKit
import AudioDecode
import Testing
import Waveform

@testable import ArtscribeUI

/// The one precedence rule behind `⇧Space`, exhaustively.
///
/// It exists because the app used to appear to follow two rules: the UI aimed at
/// the track start with no selection, and `PlaybackEngine`'s loop containment
/// then pulled the cursor into the loop region, so what the user got depended on
/// where the loop happened to sit. See `PlaybackStart`.
@Suite("Play-from-start precedence")
struct PlaybackStartTests {

    private static let loop = LoopRegion(
        range: FrameRange(start: 120_000, count: 140_000), isEnabled: true)

    // MARK: - The rule, since the loop became the only range (2026-11)

    @Test("no range: the start of the track")
    func neither() {
        #expect(PlaybackStart.target(loop: LoopRegion()) == 0)
    }

    @Test("an active loop: its in point, not the track start")
    func loopOnly() {
        #expect(PlaybackStart.target(loop: Self.loop) == 120_000)
    }

    /// The change, as an assertion. A range with looping off is what a
    /// selection used to be, and `⇧Space` aimed at a selection's start; it was
    /// only the *loop* that had to be active to count, and there is one range now.
    @Test("a range with looping off still aims at its start")
    func disabledLoopStillAims() {
        var disabled = Self.loop
        disabled.isEnabled = false
        #expect(PlaybackStart.target(loop: disabled) == 120_000)
    }

    /// `A` pressed once with no `S` yet, on a region that collapsed to nothing:
    /// there is no start worth playing from.
    @Test("a zero-length range does not steer the playhead")
    func emptyLoopIsIgnored() {
        let empty = LoopRegion(range: FrameRange(start: 120_000, count: 0), isEnabled: true)
        #expect(!empty.isActive)
        #expect(PlaybackStart.target(loop: empty) == 0)
    }
}

/// The same rule as the keyboard and the menu reach it: through `ViewerModel`.
///
/// `loadForTesting` leaves the playback session nil, so nothing is audible here
/// and nothing needs to be — what is under test is the frame the model seeks to.
@MainActor
@Suite("Play-from-start through the model")
struct ViewerModelStartPrecedenceTests {

    private static let sampleRate: Double = 44100
    private static let totalFrames: FrameIndex = 441_000  // 10 s

    private func makeModel() -> ViewerModel {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: Self.sampleRate, frameCount: Self.totalFrames,
            storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        return model
    }

    // MARK: - ⇧Space precedence (Task 22 A; the key was Space for Task 28's swap)
    //
    // One rule, four states. `loop only` is the one that was measurably wrong at
    // this level: the old `seek(to: selection.isEmpty ? 0 : …)` aimed at the
    // track start and left the engine to drag the cursor into the region
    // afterwards, which is what made the app read as two competing rules. See
    // `PlaybackStart`.

    /// A range dragged out for real, through the lane drag's own entry points.
    private func drag(_ model: ViewerModel, fromPixel: Double, toPixel: Double) -> FrameIndex {
        model.dragChanged(startPixel: fromPixel, currentPixel: fromPixel, extending: false)
        model.dragChanged(startPixel: fromPixel, currentPixel: toPixel, extending: false)
        model.dragEnded(startPixel: fromPixel, endPixel: toPixel, now: 0)
        return model.loop.range.start
    }

    private func enableLoop(_ model: ViewerModel, from start: FrameIndex, to end: FrameIndex) {
        model.seek(to: start)
        model.setLoopIn()
        model.seek(to: end)
        model.setLoopOut()
        if !model.loop.isEnabled { model.toggleLoop() }
    }

    @Test("Shift-Space with no range goes to the track start")
    func returnToStartWithNeither() {
        let model = makeModel()
        model.seek(to: 300_000)
        model.returnToStart()
        #expect(model.playhead == 0)
    }

    @Test("Shift-Space with a dragged-out range goes to its start")
    func returnToStartWithARange() {
        let model = makeModel()
        let start = drag(model, fromPixel: 200, toPixel: 500)
        model.seek(to: 300_000)
        model.returnToStart()
        #expect(model.playhead == start)
    }

    @Test("Shift-Space with an active loop goes to the loop start")
    func returnToStartWithLoopOnly() {
        let model = makeModel()
        enableLoop(model, from: 120_000, to: 260_000)
        #expect(model.loop.isActive)

        model.seek(to: 300_000)
        model.returnToStart()
        #expect(model.playhead == 120_000)
    }

    /// A drag while looping replaces the loop and keeps it looping, so the aim
    /// follows the new range.
    @Test("Shift-Space after a drag while looping goes to the new range's start")
    func returnToStartAfterReplacingTheLoop() {
        let model = makeModel()
        enableLoop(model, from: 120_000, to: 260_000)
        let start = drag(model, fromPixel: 400, toPixel: 600)
        #expect(model.loop.isActive)
        #expect(start != 120_000)

        model.seek(to: 300_000)
        model.returnToStart()
        #expect(model.playhead == start)
    }

    @Test("a range with looping off still steers Shift-Space to its start")
    func returnToStartWithLoopingOff() {
        let model = makeModel()
        enableLoop(model, from: 120_000, to: 260_000)
        model.toggleLoop()
        #expect(!model.loop.isActive)

        model.seek(to: 300_000)
        model.returnToStart()
        #expect(model.playhead == 120_000)
    }

    @Test("play from start follows the same rule as return to start")
    func playFromStartFollowsThePrecedence() {
        let model = makeModel()
        enableLoop(model, from: 120_000, to: 260_000)
        model.seek(to: 300_000)

        // No audio session in these tests, so this reports rather than plays —
        // the seek half is what is under test.
        model.playFromStart()
        #expect(model.playhead == 120_000)
    }
}
