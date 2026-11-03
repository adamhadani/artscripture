import ArtscribeKit
import AudioDecode
import Testing
import Waveform

@testable import ArtscribeUI

/// `⌘9` falling back to the loop when nothing is selected.
///
/// The key's job is "show me the bit I care about", and with a loop set and no
/// selection it used to do nothing at all.
@MainActor
@Suite("Zoom to loop")
struct ViewerModelZoomTargetTests {

    private func makeModel() -> ViewerModel {
        let frames: FrameIndex = 441_000
        let storage = AudioStorage(channels: 1, capacityFrames: Int(frames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: frames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        return model
    }

    @Test("with no range there is nothing to zoom to")
    func nothingToZoomTo() {
        let model = makeModel()
        model.fitWholeFile()
        let before = model.framesPerPixel
        #expect(model.zoomTarget == nil)
        model.zoomToLoop()
        #expect(model.framesPerPixel == before)
    }

    /// The behaviour that was asked for.
    @Test("with a loop it zooms to the loop")
    func fallsBackToTheLoop() {
        let model = makeModel()
        model.fitWholeFile()
        let before = model.framesPerPixel
        // A loop narrow enough that zooming to it is visibly not a whole-file
        // fit.
        model.applyLoop(
            LoopRegion(range: FrameRange(start: 44_100, count: 44_100), isEnabled: false))
        #expect(model.zoomTarget == model.loop.range)
        model.zoomToLoop()
        #expect(model.framesPerPixel < before, "the view did not zoom in on the loop")
    }

    /// A loop that is merely *marked* still counts. Refusing to zoom to a region
    /// you can plainly see, because playback is not currently cycling it, is a
    /// distinction without a difference.
    @Test("a disengaged loop is still a zoom target")
    func disengagedLoopStillCounts() {
        let model = makeModel()
        model.applyLoop(
            LoopRegion(range: FrameRange(start: 1000, count: 5000), isEnabled: false))
        #expect(!model.loop.isEnabled)
        #expect(model.zoomTarget == model.loop.range)
    }
}
