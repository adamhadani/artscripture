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

    /// A model with a real, decodable picture — or, `decodable: false`, one
    /// whose picture this machine could not open.
    private func model(decodable: Bool = true) async -> ViewerModel {
        let frames: FrameIndex = 144_000
        let storage = AudioStorage(channels: 1, capacityFrames: Int(frames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 48_000, frameCount: frames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        if decodable {
            let clip = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Fixtures/frame_index.mp4")
            model.adoptPicture(await TrackLoader.loadPicture(url: clip))
        } else {
            let info = VideoTrackInfo(
                naturalSize: CGSize(width: 48, height: 32), frameRate: 10, duration: 3)
            model.adoptPicture(LoadedPicture(info: info, source: nil, failure: "No decoder."))
        }
        return model
    }

    /// No real windows in a unit test: they would float over every Space on
    /// the developer's screen for the length of each `make check`.
    private func controller(_ model: ViewerModel) -> MiniPlayerController {
        MiniPlayerController(model: model, showsWindows: false)
    }

    /// The play button reaches the transport. With no audio output the model
    /// says so — which is only possible if the press arrived at `play()`.
    @Test func theControllerTheAppBuildsDrivesTheModel() async {
        let model = await model()
        let controller = controller(model)
        #expect(model.playbackNotice == nil)
        controller.playPause()
        #expect(model.playbackNotice != nil)
    }

    @Test func openingByHandShowsTheWindowAndMarksThePanel() async {
        let model = await model()
        let controller = controller(model)
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
        let model = await model()
        let controller = controller(model)
        controller.toggleByUser()
        model.closeTrack()
        // The controller hears about it through observation, on the next turn.
        for _ in 0..<20 where controller.isShowing { await Task.yield() }
        #expect(!controller.isShowing)
    }

    /// Review finding #8: a file whose picture could not be opened has nothing
    /// to float — not an empty black window with a play button.
    @Test func anUndecodablePictureDoesNotFloat() async {
        let model = await model(decodable: false)
        let controller = controller(model)
        controller.toggleByUser()
        #expect(!controller.isShowing)
        #expect(
            !ActionAvailability.isEnabled(
                .viewVideoPictureInPicture, model: model, documentIsKey: true))
        // The panel itself still shows, with its reason.
        #expect(ActionAvailability.isEnabled(.viewVideoToggle, model: model, documentIsKey: true))
    }
}
#endif
