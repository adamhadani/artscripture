#if os(macOS)
import ArtscribeKit
import AudioDecode
import CoreGraphics
import Foundation
import Testing
import Video
import Waveform

@testable import ArtscribeUI

/// The object the app builds — not a look-alike — wired to a real model.
@MainActor
@Suite("Mini player controller")
struct MiniPlayerControllerTests {

    private func model() -> ViewerModel {
        let frames: FrameIndex = 144_000
        let storage = AudioStorage(channels: 1, capacityFrames: Int(frames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 48_000, frameCount: frames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        let info = VideoTrackInfo(
            naturalSize: CGSize(width: 48, height: 32), frameRate: 10, duration: 3)
        model.adoptPicture(LoadedPicture(info: info, source: nil, failure: nil))
        return model
    }

    /// The play button reaches the transport. With no audio output the model
    /// says so — which is only possible if the press arrived at `play()`.
    @Test func theControllerTheAppBuildsDrivesTheModel() {
        let model = model()
        let controller = MiniPlayerController(model: model)
        #expect(model.playbackNotice == nil)
        controller.playPause()
        #expect(model.playbackNotice != nil)
    }

    @Test func openingByHandShowsTheWindowAndMarksThePanel() {
        let model = model()
        let controller = MiniPlayerController(model: model)
        controller.toggleByUser()
        #expect(controller.isShowing)
        #expect(model.video?.isFloating == true)
        controller.handle(.appActivated)
        #expect(controller.isShowing)
        controller.toggleByUser()
        #expect(!controller.isShowing)
        #expect(model.video?.isFloating == false)
    }

    /// The track going away takes the window with it.
    @Test func closingTheTrackClosesTheWindow() async {
        let model = model()
        let controller = MiniPlayerController(model: model)
        controller.toggleByUser()
        model.closeTrack()
        // The controller hears about it through observation, on the next turn.
        for _ in 0..<20 where controller.isShowing { await Task.yield() }
        #expect(!controller.isShowing)
    }
}
#endif
