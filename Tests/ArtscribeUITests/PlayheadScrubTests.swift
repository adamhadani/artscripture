import ArtscribeKit
import AudioDecode
import CoreGraphics
import Testing
import Waveform

@testable import ArtscribeUI

/// The scrub on the model — see `PlayheadScrub`; the pure rules are in
/// `PlayheadScrubRuleTests`.
@MainActor
@Suite("Playhead scrub: the model")
struct PlayheadScrubModelTests {

    private static let totalFrames: FrameIndex = 2_000_000
    private static let framesPerPoint: FrameIndex = 2000
    /// Halfway down 300 pt lanes: the grip's height.
    private static let mid = 150.0

    private func makeModel(at point: Double = 400) -> ViewerModel {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.laneSize = CGSize(width: 1000, height: 300)
        model.seek(to: frame(point))
        return model
    }

    private func frame(_ point: Double) -> FrameIndex { FrameIndex(point) * Self.framesPerPoint }

    private func point(_ x: Double, _ y: Double = mid) -> CGPoint { CGPoint(x: x, y: y) }

    /// A lane drag, delivered a step at a time the way `DragGesture` does.
    private func laneDrag(
        _ model: ViewerModel, from start: CGPoint, to end: CGPoint, lift: Bool = true,
        now: Double = 100
    ) {
        model.laneDragChanged(start: start, current: start, option: false, shift: false)
        for step in 1...10 {
            let t = Double(step) / 10
            let current = CGPoint(
                x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            model.laneDragChanged(start: start, current: current, option: false, shift: false)
        }
        if lift { model.laneDragEnded(start: start, end: end, now: now) }
    }

    /// A unit test has no audio graph, so `play()` reports the missing output
    /// instead of playing — which is how a test sees that it was asked to.
    private func playWasRequested(_ model: ViewerModel) -> Bool { model.playbackNotice != nil }

    @Test("dragging the grip moves the playhead, keeping where it was grabbed, and marks nothing")
    func aDragScrubs() {
        let model = makeModel()
        let zoom = model.zoomFactor
        laneDrag(model, from: point(403), to: point(703, 160))
        #expect(model.playhead == frame(700))
        #expect(model.loop.range.isEmpty, "a scrub marked a loop")
        #expect(model.zoomFactor == zoom, "a scrub zoomed")
    }

    /// One seek, on release: a seek per finger event would reset the stretcher
    /// sixty times a second.
    @Test("the engine is told once, when the finger lifts")
    func oneSeekOnRelease() {
        let model = makeModel()
        let before = model.seekGeneration
        laneDrag(model, from: point(400), to: point(600), lift: false)
        #expect(model.playhead == frame(600), "the playhead did not follow the finger")
        #expect(model.seekGeneration == before, "the engine was told mid-scrub")
        model.laneDragEnded(start: point(400), end: point(600), now: 100)
        #expect(model.seekGeneration == before + 1)
        #expect(model.playhead == frame(600))
    }

    @Test("a tap on the grip is a click: it places the playhead and does not pause")
    func aTapOnTheGripIsAClick() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        laneDrag(model, from: point(402), to: point(403))
        #expect(model.playhead == frame(402), "a click places the playhead at the press")
        #expect(model.isPlaying, "a tap paused the track")
        #expect(model.laneDragMode == nil)
    }

    @Test("a playing track pauses while it is scrubbed, and plays on from where it was left")
    func playingPausesAndResumes() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        laneDrag(model, from: point(400), to: point(550), lift: false)
        #expect(!model.isPlaying, "it went on playing under the finger")
        #expect(!playWasRequested(model))
        model.laneDragEnded(start: point(400), end: point(550), now: 100)
        #expect(playWasRequested(model), "it did not play again")
        #expect(model.playhead == frame(550))
    }

    @Test("a paused track stays paused after a scrub")
    func pausedStaysPaused() {
        let model = makeModel()
        laneDrag(model, from: point(400), to: point(550))
        #expect(!playWasRequested(model))
        #expect(!model.isPlaying)
    }

    /// It is a grip, not a column: the rest of the playhead's line is the
    /// lane's, exactly as before.
    @Test("a drag from above or below the grip, on the playhead's line, marks a loop")
    func theRestOfTheLineIsTheLanes() {
        for y in [40.0, 260.0] {
            let model = makeModel()
            laneDrag(model, from: point(400, y), to: point(600, y))
            #expect(model.loop.range == FrameRange(start: frame(400), count: frame(200)))
        }
    }

    /// Where a new loop leaves the playhead: on its start.
    @Test("with the playhead on a loop edge, a drag there resizes the loop and does not scrub")
    func anEdgeUnderThePlayheadStillResizes() {
        let model = makeModel()
        laneDrag(model, from: point(400, 40), to: point(600, 40))
        model.seek(to: frame(400))
        laneDrag(model, from: point(400), to: point(350))
        #expect(model.loop.range.start == frame(350), "the loop's start did not move")
        #expect(model.playhead == frame(400), "it scrubbed instead")
    }

    @Test("inside a loop the grip scrubs, and the rest of the loop still moves it")
    func insideALoop() {
        let model = makeModel()
        laneDrag(model, from: point(300, 40), to: point(600, 40))
        model.seek(to: frame(450))
        let loop = model.loop.range
        laneDrag(model, from: point(450), to: point(500))
        #expect(model.loop.range == loop, "the grip moved the loop")
        #expect(model.playhead == frame(500))
        laneDrag(model, from: point(450, 40), to: point(480, 40))
        #expect(model.loop.range.start == loop.start + frame(30), "the body no longer moves")
    }

    @Test("the playhead stays on the page, however far the finger goes")
    func heldToThePage() {
        let model = makeModel()
        laneDrag(model, from: point(400), to: point(1600))
        #expect(model.playhead == Self.totalFrames)
        laneDrag(model, from: point(1000), to: point(-300))
        #expect(model.playhead == 0)
    }

    /// A gesture whose end and cancel were both lost must not leave the engine
    /// somewhere other than the playhead — and must never be landed by
    /// starting playback from an unrelated gesture.
    @Test("a pending scrub is landed by the next lane gesture with a seek, never by playing")
    func aLeftoverScrubIsLandedWithoutPlaying() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        let before = model.seekGeneration
        laneDrag(model, from: point(400), to: point(500), lift: false)
        // An ⌥-zoom: a gesture that moves no playhead of its own. (A plain
        // press seeks on mouse-down with a pointer, which would hide this.)
        model.laneDragChanged(
            start: point(100, 40), current: point(100, 40), option: true, shift: false)
        #expect(model.seekGeneration == before + 1)
        #expect(!playWasRequested(model), "an unrelated lane press started playback")
        #expect(model.playhead == frame(500))
    }

    @Test("a cancelled scrub lands where it was left, and does not play again")
    func aCancelledScrubLandsWithoutPlaying() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        let before = model.seekGeneration
        laneDrag(model, from: point(400), to: point(520), lift: false)
        // A late notice about some other gesture lands nothing.
        model.laneGestureCancelled(start: point(100))
        #expect(model.seekGeneration == before)
        model.laneGestureCancelled(start: point(400))
        #expect(model.seekGeneration == before + 1)
        #expect(model.playhead == frame(520))
        #expect(!playWasRequested(model))
        #expect(model.scrub == nil)
        #expect(model.laneDragMode == nil)
        // And after a normal end there is nothing left to cancel.
        laneDrag(model, from: point(520), to: point(600))
        let settled = model.seekGeneration
        model.laneGestureCancelled(start: point(520))
        #expect(model.seekGeneration == settled)
    }

    /// The first finger of a pinch landed on the grip and began a scrub.
    @Test("a pinch puts a scrub back: the playhead where it was, and playing again")
    func aPinchPutsTheScrubBack() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        laneDrag(model, from: point(400), to: point(520), lift: false)
        #expect(!model.isPlaying)
        model.cancelLaneDrag()
        #expect(model.playhead == frame(400))
        #expect(playWasRequested(model), "the pinch left the track paused")
        #expect(model.scrub == nil)
    }

    @Test("closing the track drops a scrub in flight, and the next track's lanes are clean")
    func closingDropsTheScrub() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        laneDrag(model, from: point(400), to: point(500), lift: false)
        model.closeTrack()
        #expect(model.scrub == nil)
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.laneSize = CGSize(width: 1000, height: 300)
        let before = model.seekGeneration
        model.laneDragChanged(
            start: point(100, 40), current: point(100, 40), option: true, shift: false)
        #expect(model.seekGeneration == before, "the old track's scrub landed on the new one")
        #expect(!playWasRequested(model))
    }

    /// Space, a headphone button or the lock screen, mid-scrub: playback starts
    /// from where the finger is, and the finger lets go of the playhead.
    @Test("play pressed mid-scrub starts from the scrubbed spot, and the rest of the drag is spent")
    func playMidScrubLandsTheScrub() {
        let model = makeModel()
        let before = model.seekGeneration
        laneDrag(model, from: point(400), to: point(480), lift: false)
        model.play()
        #expect(model.seekGeneration == before + 1, "playback would start from the old spot")
        #expect(model.playhead == frame(480))
        model.laneDragChanged(
            start: point(400), current: point(700), option: false, shift: false)
        #expect(model.playhead == frame(480), "the finger kept moving the playhead")
        model.laneDragEnded(start: point(400), end: point(700), now: 100)
        #expect(model.seekGeneration == before + 1, "release seeked again")
    }

    /// Review finding: a tap that drifted past the click slop but not the
    /// scrub distance was neither, and did nothing at all.
    @Test("a tap that drifts, on touch, is still a click at the press")
    func aDriftingTapIsAClick() {
        let model = makeModel()
        model.prefs.handleReach = HandleReach(edge: 22)
        laneDrag(model, from: point(410), to: point(416))
        #expect(model.playhead == frame(410))
    }

    @Test("a vertical wobble on the grip while playing does not pause")
    func aVerticalWobbleDoesNotPause() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        laneDrag(model, from: point(401), to: point(401, 160), lift: false)
        #expect(model.isPlaying, "a vertical wobble paused the track")
        model.laneDragEnded(start: point(401), end: point(401, 160), now: 100)
        #expect(!playWasRequested(model))
    }

    /// Review finding: the cancel landed the scrub but left the lanes latched
    /// on `.scrub`, which switches page-following off (and, on the Mac,
    /// leaves the sideways cursor up) until the next lane gesture.
    @Test("a cancelled scrub unlatches the lanes, and the page follows the playhead again")
    func aCancelUnlatches() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        laneDrag(model, from: point(400), to: point(520), lift: false)
        model.laneGestureCancelled(start: point(400))
        #expect(model.laneDragMode == nil)
        model.viewport.zoom(to: FrameRange(start: 0, count: 100_000))
        model.refresh()
        let page = model.viewport.startFrame
        model.playhead = 1_500_000
        model.autoScroll()
        #expect(model.viewport.startFrame != page, "the page did not follow the playhead")
    }

    @Test("on touch a short wobble on the grip is still nothing")
    func touchWobbleIsNothing() {
        let model = makeModel()
        model.prefs.handleReach = HandleReach(edge: 22)
        model.transport.request(true, now: 0)
        let start = point(410)
        model.laneDragChanged(start: start, current: start, option: false, shift: false)
        model.laneDragChanged(start: start, current: point(418, 152), option: false, shift: false)
        #expect(model.isPlaying, "a wobble paused the track")
        #expect(model.playhead == frame(400))
        model.laneDragChanged(start: start, current: point(440, 155), option: false, shift: false)
        #expect(!model.isPlaying)
        #expect(model.playhead == frame(430))
        model.laneDragEnded(start: start, end: point(440, 155), now: 100)
    }
}
