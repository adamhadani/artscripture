import ArtscribeKit
import AudioDecode
import CoreGraphics
import Foundation
import Testing
import Video
import Waveform

@testable import ArtscribeUI

/// The model's half of the picture: finding it while loading, owning the
/// presenter, and saying where the sound is.
@MainActor
@Suite("Viewer model: video")
struct ViewerModelVideoTests {

    private static func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ArtscribeUITests
            .deletingLastPathComponent()  // Tests
            .appendingPathComponent("Fixtures")
            .appendingPathComponent(name)
    }

    /// Three seconds at 48 kHz, loaded the way the other model tests load.
    private func model() -> ViewerModel {
        let frames: FrameIndex = 144_000
        let storage = AudioStorage(channels: 1, capacityFrames: Int(frames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 48_000, frameCount: frames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        return model
    }

    @Test func snapshotConvertsFramesToSeconds() {
        let model = model()
        model.seek(to: 72_000)
        #expect(model.videoSnapshot.position == 1.5)
        #expect(model.videoSnapshot.loop == nil)
        #expect(!model.videoSnapshot.isPlaying)
        model.loop = LoopRegion(range: FrameRange(start: 48_000, count: 48_000), isEnabled: false)
        #expect(model.videoSnapshot.loop == nil)  // drawn, but not looping
        model.loop = LoopRegion(range: FrameRange(start: 48_000, count: 48_000), isEnabled: true)
        #expect(model.videoSnapshot.loop == 1.0..<2.0)
    }

    @Test func theLoaderFindsThePicture() async throws {
        let picture = try #require(
            await TrackLoader.loadPicture(url: Self.fixture("frame_index.mp4")))
        #expect(picture.info.displaySize == CGSize(width: 48, height: 32))
        #expect(picture.source != nil)
        #expect(picture.failure == nil)
    }

    @Test func anAudioFileHasNoPicture() async {
        #expect(await TrackLoader.loadPicture(url: Self.fixture("sine.m4a")) == nil)
    }

    @Test func adoptingAPictureExposesIt() async throws {
        let model = model()
        #expect(!model.hasVideo)
        model.adoptPicture(await TrackLoader.loadPicture(url: Self.fixture("frame_index.mp4")))
        #expect(model.hasVideo)
        #expect(model.video?.info.displaySize == CGSize(width: 48, height: 32))
        #expect(model.videoPresenter != nil)
    }

    /// The sound still plays; the panel says why it is empty.
    @Test func aPictureThatCannotBeDecodedSaysWhy() throws {
        let model = model()
        let info = VideoTrackInfo(
            naturalSize: CGSize(width: 48, height: 32), frameRate: 10, duration: 3)
        model.adoptPicture(LoadedPicture(info: info, source: nil, failure: "Unsupported codec."))
        #expect(model.hasVideo)
        #expect(model.video?.failure == "Unsupported codec.")
        #expect(model.videoPresenter == nil)
    }

    @Test func closingTheTrackClosesThePresenter() async throws {
        let model = model()
        let picture = try #require(
            await TrackLoader.loadPicture(url: Self.fixture("frame_index.mp4")))
        model.adoptPicture(picture)
        model.closeTrack()
        #expect(!model.hasVideo)
        #expect(model.videoPresenter == nil)
        // The decoder itself is shut, not merely forgotten.
        picture.source?.request(FramePlan.make(model.videoSnapshot, info: picture.info))
        await picture.source?.idle()
        #expect(picture.source?.frame(at: 0) == nil)
    }
}
