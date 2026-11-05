import ArtscribeKit
import AudioDecode
import CoreGraphics
import Foundation
import Testing
import Video
import Waveform

@testable import ArtscribeUI

/// The ways to show and hide the picture: a key, a menu item, a transport
/// button — present for a video file, and absent or disabled for audio.
@MainActor
@Suite("Video controls")
struct VideoControlsTests {

    private func model(withVideo: Bool) -> ViewerModel {
        let frames: FrameIndex = 144_000
        let storage = AudioStorage(channels: 1, capacityFrames: Int(frames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 48_000, frameCount: frames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        if withVideo {
            let info = VideoTrackInfo(
                naturalSize: CGSize(width: 48, height: 32), frameRate: 10, duration: 3)
            model.adoptPicture(LoadedPicture(info: info, source: nil, failure: nil))
        }
        return model
    }

    @Test func videoActionsAreBoundInTheCatalog() {
        #expect(ActionCatalog.chord(.viewVideoToggle)?.display == "I")
        #expect(ActionCatalog.chord(.viewVideoPictureInPicture)?.display == "⇧I")
        #expect(ActionCatalog.entry(.viewVideoToggle).kind == .toggle)
        #expect(TransportControl.video.shortcut == ActionCatalog.chord(.viewVideoToggle)?.display)
    }

    @Test func videoActionsAreDisabledForAnAudioFile() {
        let audio = model(withVideo: false)
        let video = model(withVideo: true)
        for id in [ActionID.viewVideoToggle, .viewVideoPictureInPicture] {
            #expect(!ActionAvailability.isEnabled(id, model: audio, documentIsKey: true))
        }
        #expect(ActionAvailability.isEnabled(.viewVideoToggle, model: video, documentIsKey: true))
        #expect(!ActionAvailability.isEnabled(.viewVideoToggle, model: video, documentIsKey: false))
    }

    /// An audio file's bar is exactly today's bar.
    @Test func theVideoButtonOnlyShowsForVideo() {
        let audio = model(withVideo: false).transportState
        #expect(TransportControl.visibleGroups(in: audio) == TransportControl.groups.dropLast())
        #expect(!TransportControl.visibleGroups(in: audio).joined().contains(.video))
        let video = model(withVideo: true).transportState
        #expect(TransportControl.visibleGroups(in: video) == TransportControl.groups)
    }

    @Test func theVideoButtonIsOnWhileThePictureShows() {
        let model = model(withVideo: true)
        #expect(TransportControl.video.isOn(in: model.transportState))
        model.perform(.video)
        #expect(!TransportControl.video.isOn(in: model.transportState))
        #expect(TransportControl.video.title(in: model.transportState) == "Show Video")
    }

    @Test func videoToggleFlipsThePreference() {
        let model = model(withVideo: true)
        model.toggleVideo()
        #expect(!model.prefs.video.shown)
        model.toggleVideo()
        #expect(model.prefs.video.shown)
    }

    /// With no picture there is nothing to toggle, and the preference is the
    /// user's, not the key's: a stray press on an audio file changes nothing.
    @Test func theToggleDoesNothingWithoutAPicture() {
        let model = model(withVideo: false)
        model.toggleVideo()
        #expect(model.prefs.video.shown)
    }
}
