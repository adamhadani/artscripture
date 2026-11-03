import ArtscribeKit
import AudioDecode
import Testing
import Waveform

@testable import ArtscribeUI

/// A tap — or a click — on the overview strip moves the playhead there.
///
/// Reported from an iPhone: "I found myself trying to do it a few times." The
/// strip only ever moved the *view*, so pointing at the bar you wanted on the
/// whole-file overview put the window there and left the playhead behind.
/// A drag still only carries the view; it is the tap that seeks.
@MainActor
@Suite("Overview strip: a tap seeks")
struct OverviewTapTests {

    private static let totalFrames: FrameIndex = 2_000_000
    private static let stripWidth: Double = 400

    private func makeModel() -> ViewerModel {
        let storage = AudioStorage(channels: 1, capacityFrames: Int(Self.totalFrames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44100, frameCount: Self.totalFrames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.zoom(by: 8, anchorFrame: 0)
        return model
    }

    private func frame(atPixel x: Double) -> FrameIndex {
        PixelMapping.overviewFrame(
            atPixel: x, totalFrames: Self.totalFrames, width: Self.stripWidth)
    }

    @Test("a tap moves the playhead to the frame under it")
    func tapSeeks() {
        let model = makeModel()
        #expect(model.playhead == 0)

        model.overviewReleased(startPixel: 300, endPixel: 300, stripWidth: Self.stripWidth)

        #expect(model.playhead == frame(atPixel: 300))
        #expect(model.playhead > 0)
    }

    /// A finger is never perfectly still: the same slop a lane click allows.
    @Test("a tap that wobbles by a point or two still seeks")
    func wobblyTapSeeks() {
        let model = makeModel()
        model.overviewReleased(startPixel: 250, endPixel: 252, stripWidth: Self.stripWidth)
        #expect(model.playhead == frame(atPixel: 252))
    }

    /// Dragging is how the view is carried along the strip, and a carry that
    /// also dragged the playhead with it would move what you are listening to
    /// every time you looked somewhere else.
    @Test("a drag carries the view and leaves the playhead where it was")
    func dragDoesNotSeek() {
        let model = makeModel()
        model.seek(to: 1000)

        model.overviewReleased(startPixel: 100, endPixel: 220, stripWidth: Self.stripWidth)

        #expect(model.playhead == 1000)
    }

    /// The tap is about the playhead and nothing else: a loop set on purpose,
    /// and the transport's state, are not the strip's to change.
    @Test("a tap leaves the loop and the transport alone")
    func tapTouchesNothingElse() {
        let model = makeModel()
        model.applyLoop(
            LoopRegion(range: FrameRange(start: 10_000, count: 40_000), isEnabled: true))
        let loop = model.loop

        model.overviewReleased(startPixel: 300, endPixel: 300, stripWidth: Self.stripWidth)

        #expect(model.loop == loop)
        #expect(!model.isPlaying)
    }

    @Test("a strip with no width yet does nothing rather than seek to the end")
    func zeroWidthIsInert() {
        let model = makeModel()
        model.overviewReleased(startPixel: 300, endPixel: 300, stripWidth: 0)
        #expect(model.playhead == 0)
    }
}
