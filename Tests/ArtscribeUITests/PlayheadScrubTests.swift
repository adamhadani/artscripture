import ArtscribeKit
import AudioDecode
import CoreGraphics
import Testing
import Waveform

@testable import ArtscribeUI

/// Scrubbing from the playhead's grip on the ruler — see `PlayheadScrub`.
@Suite("Playhead scrub: the rules")
struct PlayheadScrubRuleTests {

    @Test("the grip is the playhead's x, within the loop edges' reach")
    func theGripIsWithinReach() {
        let pointer = HandleReach.pointer
        #expect(PlayheadScrub.grabbed(atX: 409, playheadX: 400, reach: pointer, width: 1000) != nil)
        #expect(PlayheadScrub.grabbed(atX: 391, playheadX: 400, reach: pointer, width: 1000) != nil)
        #expect(PlayheadScrub.grabbed(atX: 410, playheadX: 400, reach: pointer, width: 1000) == nil)
        let touch = HandleReach(edge: 22)
        #expect(PlayheadScrub.grabbed(atX: 422, playheadX: 400, reach: touch, width: 1000) != nil)
        #expect(PlayheadScrub.grabbed(atX: 423, playheadX: 400, reach: touch, width: 1000) == nil)
    }

    @Test("a playhead off the page has no grip to take hold of")
    func noGripOffThePage() {
        let touch = HandleReach(edge: 22)
        #expect(PlayheadScrub.grabbed(atX: 5, playheadX: -10, reach: touch, width: 1000) == nil)
        #expect(PlayheadScrub.grabbed(atX: 995, playheadX: 1010, reach: touch, width: 1000) == nil)
    }

    /// The ruler's up-and-down zoom has to survive a press that lands on the
    /// grip, because the playhead is where people start a zoom.
    @Test("only a clearly sideways drag from the grip scrubs; ties and up-or-down zoom")
    func directionDecides() {
        #expect(PlayheadScrub.isScrub(dx: 2, dy: 1, distance: 3) == nil)
        #expect(PlayheadScrub.isScrub(dx: 12, dy: 4, distance: 3) == true)
        #expect(PlayheadScrub.isScrub(dx: -12, dy: 4, distance: 3) == true)
        #expect(PlayheadScrub.isScrub(dx: 12, dy: 6, distance: 3) == false, "a tie scrubbed")
        #expect(PlayheadScrub.isScrub(dx: 10, dy: 10, distance: 3) == false)
        #expect(PlayheadScrub.isScrub(dx: 3, dy: 20, distance: 3) == false)
        #expect(PlayheadScrub.isScrub(dx: 0, dy: -20, distance: 3) == false)
    }

    /// A finger's first points wobble: on touch the grip waits longer.
    @Test("a finger travels further than a pointer before the grip decides")
    func touchWaitsLonger() {
        #expect(PlayheadScrub.decisionDistance(reach: .pointer) == 3)
        #expect(PlayheadScrub.decisionDistance(reach: HandleReach(edge: 22)) == 10)
        #expect(PlayheadScrub.isScrub(dx: 9, dy: 0, distance: 10) == nil)
    }

    @Test("the playhead keeps its grab offset and stays on the page")
    func offsetAndClamp() {
        let scrub = PlayheadScrub(startX: 405, grabOffset: 5)
        #expect(scrub.playheadX(forPointerAt: 605, width: 1000) == 600)
        #expect(scrub.playheadX(forPointerAt: 2000, width: 1000) == 1000)
        #expect(scrub.playheadX(forPointerAt: -50, width: 1000) == 0)
    }

    @Test("the Mac's cursor over the grip says sideways, and the rest of the ruler is unchanged")
    func theCursor() {
        #expect(
            PointerAffordance.over(
                .timeRuler, optionHeld: false, laneDrag: nil, onPlayheadGrip: true)
                == .scrubPlayhead)
        #expect(
            PointerAffordance.over(.timeRuler, optionHeld: false, laneDrag: nil) == .verticalDrag)
    }
}

@MainActor
@Suite("Playhead scrub: the model")
struct PlayheadScrubModelTests {

    private static let totalFrames: FrameIndex = 2_000_000
    private static let framesPerPoint: FrameIndex = 2000

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

    /// A ruler drag, delivered a step at a time the way `DragGesture` does.
    private func rulerDrag(
        _ model: ViewerModel, from start: CGPoint, to end: CGPoint, lift: Bool = true
    ) {
        model.rulerDragChanged(start: start, current: start)
        for step in 1...10 {
            let t = Double(step) / 10
            let current = CGPoint(
                x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            model.rulerDragChanged(start: start, current: current)
        }
        if lift { model.rulerDragEnded() }
    }

    /// A unit test has no audio graph, so `play()` reports the missing output
    /// instead of playing — which is how a test sees that it was asked to.
    private func playWasRequested(_ model: ViewerModel) -> Bool { model.playbackNotice != nil }

    @Test("dragging the grip sideways moves the playhead, keeping where it was grabbed")
    func aSidewaysDragScrubs() {
        let model = makeModel()
        let zoom = model.zoomFactor
        rulerDrag(model, from: CGPoint(x: 403, y: 16), to: CGPoint(x: 703, y: 18))
        #expect(model.playhead == frame(700))
        #expect(model.zoomFactor == zoom, "a scrub zoomed")
    }

    /// One seek, on release: a seek per finger event would reset the stretcher
    /// sixty times a second.
    @Test("the engine is told once, when the finger lifts")
    func oneSeekOnRelease() {
        let model = makeModel()
        let before = model.seekGeneration
        rulerDrag(
            model, from: CGPoint(x: 400, y: 16), to: CGPoint(x: 600, y: 16), lift: false)
        #expect(model.playhead == frame(600), "the playhead did not follow the finger")
        #expect(model.seekGeneration == before, "the engine was told mid-scrub")
        model.rulerDragEnded()
        #expect(model.seekGeneration == before + 1)
        #expect(model.playhead == frame(600))
    }

    @Test("a tap on the grip changes nothing, and does not pause")
    func aTapOnTheGripIsNothing() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        let before = model.seekGeneration
        rulerDrag(model, from: CGPoint(x: 401, y: 16), to: CGPoint(x: 402, y: 17))
        #expect(model.playhead == frame(400))
        #expect(model.seekGeneration == before)
        #expect(model.isPlaying)
    }

    @Test("a playing track pauses while it is scrubbed, and plays on from where it was left")
    func playingPausesAndResumes() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        rulerDrag(
            model, from: CGPoint(x: 400, y: 16), to: CGPoint(x: 550, y: 16), lift: false)
        #expect(!model.isPlaying, "it went on playing under the finger")
        #expect(!playWasRequested(model))
        model.rulerDragEnded()
        #expect(playWasRequested(model), "it did not play again")
        #expect(model.playhead == frame(550))
    }

    @Test("a paused track stays paused after a scrub")
    func pausedStaysPaused() {
        let model = makeModel()
        rulerDrag(model, from: CGPoint(x: 400, y: 16), to: CGPoint(x: 550, y: 16))
        #expect(!playWasRequested(model))
        #expect(!model.isPlaying)
    }

    /// The zoom people start at the playhead.
    @Test("up or down from the grip is still the zoom, and leaves the playhead alone")
    func verticalFromTheGripZooms() {
        let model = makeModel()
        let zoom = model.zoomFactor
        rulerDrag(model, from: CGPoint(x: 400, y: 8), to: CGPoint(x: 402, y: 200))
        #expect(model.zoomFactor > zoom * 1.5)
        #expect(model.playhead == frame(400))
    }

    @Test("off the grip the ruler zooms as it always did, and never scrubs")
    func offTheGripZooms() {
        let model = makeModel()
        let zoom = model.zoomFactor
        rulerDrag(model, from: CGPoint(x: 100, y: 16), to: CGPoint(x: 300, y: 16))
        #expect(model.playhead == frame(400), "a drag off the grip moved the playhead")
        #expect(model.zoomFactor == zoom, "sideways travel zoomed")
        rulerDrag(model, from: CGPoint(x: 100, y: 8), to: CGPoint(x: 100, y: 200))
        #expect(model.zoomFactor > zoom * 1.5)
        #expect(model.playhead == frame(400))
    }

    @Test("the playhead stays on the page, however far the finger goes")
    func heldToThePage() {
        let model = makeModel()
        rulerDrag(model, from: CGPoint(x: 400, y: 16), to: CGPoint(x: 1600, y: 16))
        #expect(model.playhead == Self.totalFrames)
        rulerDrag(model, from: CGPoint(x: 1000, y: 16), to: CGPoint(x: -300, y: 16))
        #expect(model.playhead == 0)
    }

    /// A gesture whose end and cancel were both lost must not leave the engine
    /// somewhere other than the playhead — and must never be landed by
    /// starting playback from an unrelated gesture (found in review: a zoom
    /// drag minutes later started the music).
    @Test("a pending scrub is landed by the next ruler drag with a seek, never by playing")
    func aLeftoverScrubIsLandedWithoutPlaying() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        let before = model.seekGeneration
        rulerDrag(
            model, from: CGPoint(x: 400, y: 16), to: CGPoint(x: 500, y: 16), lift: false)
        model.rulerDragChanged(start: CGPoint(x: 100, y: 16), current: CGPoint(x: 100, y: 16))
        #expect(model.seekGeneration == before + 1)
        #expect(!playWasRequested(model), "an unrelated ruler drag started playback")
        #expect(model.playhead == frame(500))
    }

    @Test("a cancelled scrub lands where it was left, and does not play again")
    func aCancelledScrubLandsWithoutPlaying() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        let before = model.seekGeneration
        rulerDrag(
            model, from: CGPoint(x: 400, y: 16), to: CGPoint(x: 520, y: 16), lift: false)
        model.rulerDragCancelled()
        #expect(model.seekGeneration == before + 1)
        #expect(model.playhead == frame(520))
        #expect(!playWasRequested(model))
        #expect(model.rulerDrag == nil)
        // And after a normal end there is nothing left to cancel.
        rulerDrag(model, from: CGPoint(x: 520, y: 16), to: CGPoint(x: 600, y: 16))
        let settled = model.seekGeneration
        model.rulerDragCancelled()
        #expect(model.seekGeneration == settled)
    }

    @Test("closing the track drops a scrub in flight, and the next track's ruler is clean")
    func closingDropsTheScrub() {
        let model = makeModel()
        model.transport.request(true, now: 0)
        rulerDrag(
            model, from: CGPoint(x: 400, y: 16), to: CGPoint(x: 500, y: 16), lift: false)
        model.closeTrack()
        #expect(model.rulerDrag == nil)
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        let before = model.seekGeneration
        rulerDrag(model, from: CGPoint(x: 100, y: 8), to: CGPoint(x: 100, y: 200))
        #expect(model.seekGeneration == before, "the old track's scrub landed on the new one")
        #expect(!playWasRequested(model))
    }

    /// Space, a headphone button or the lock screen, mid-scrub: playback starts
    /// from where the finger is, and the finger lets go of the playhead.
    @Test("play pressed mid-scrub starts from the scrubbed spot, and the rest of the drag is spent")
    func playMidScrubLandsTheScrub() {
        let model = makeModel()
        let before = model.seekGeneration
        rulerDrag(
            model, from: CGPoint(x: 400, y: 16), to: CGPoint(x: 480, y: 16), lift: false)
        model.play()
        #expect(model.seekGeneration == before + 1, "playback would start from the old spot")
        #expect(model.playhead == frame(480))
        model.rulerDragChanged(start: CGPoint(x: 400, y: 16), current: CGPoint(x: 700, y: 16))
        #expect(model.playhead == frame(480), "the finger kept moving the playhead")
        model.rulerDragEnded()
        #expect(model.seekGeneration == before + 1, "release seeked again")
    }

    @Test("on touch a short sideways wobble on the grip is still nothing")
    func touchWobbleIsNothing() {
        let model = makeModel()
        model.prefs.handleReach = HandleReach(edge: 22)
        model.transport.request(true, now: 0)
        let start = CGPoint(x: 410, y: 16)
        model.rulerDragChanged(start: start, current: start)
        model.rulerDragChanged(start: start, current: CGPoint(x: 418, y: 17))
        #expect(model.isPlaying, "a wobble paused the track")
        #expect(model.playhead == frame(400))
        model.rulerDragChanged(start: start, current: CGPoint(x: 440, y: 18))
        #expect(!model.isPlaying)
        #expect(model.playhead == frame(430))
        model.rulerDragEnded()
    }

    @Test("a diagonal drag from the grip is the zoom, not a scrub")
    func aDiagonalFromTheGripZooms() {
        let model = makeModel()
        let zoom = model.zoomFactor
        rulerDrag(model, from: CGPoint(x: 400, y: 8), to: CGPoint(x: 500, y: 108))
        #expect(model.playhead == frame(400))
        #expect(model.zoomFactor != zoom)
    }

    /// The point of putting the grip on the ruler: the lanes, and every loop
    /// gesture in them, are exactly as they were.
    @Test("a drag in the lanes from the playhead still marks a loop rather than scrubbing")
    func theLanesDoNotScrub() {
        let model = makeModel()
        let start = CGPoint(x: 400, y: 150)
        model.laneDragChanged(start: start, current: start, option: false, shift: false)
        for step in 1...8 {
            let current = CGPoint(x: 400 + 25 * Double(step), y: 150)
            model.laneDragChanged(start: start, current: current, option: false, shift: false)
        }
        model.laneDragEnded(start: start, end: CGPoint(x: 600, y: 150), now: 0)
        #expect(model.loop.range == FrameRange(start: frame(400), count: frame(200)))
    }
}
