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

/// The lanes change width when the picture appears, when it is toggled, and
/// when the divider moves. A view of the whole file should still be one.
@MainActor
@Suite("Lane resize keeps a fitted view fitted")
struct LaneResizeFitTests {
    private func model() -> ViewerModel {
        let frames: FrameIndex = 441_000
        let storage = AudioStorage(channels: 1, capacityFrames: Int(frames))
        let audio = DecodedAudio(
            channels: 1, sampleRate: 44_100, frameCount: frames, storage: storage)
        let model = ViewerModel()
        model.loadForTesting(audio: audio, pyramid: PeakPyramid.build(audio), widthPixels: 1000)
        model.setLaneSize(CGSize(width: 1000, height: 300), scale: 2)
        return model
    }

    @Test func aFittedViewStaysFittedWhenTheLanesNarrow() {
        let model = model()
        #expect(model.zoomFactor == 1)
        model.setLaneSize(CGSize(width: 640, height: 300), scale: 2)
        #expect(abs(model.zoomFactor - 1) < 0.001)
        #expect(model.viewport.startFrame == 0)
    }

    @Test func aZoomedViewKeepsItsScale() {
        let model = model()
        model.zoomIn()
        let scale = model.framesPerPixel
        model.setLaneSize(CGSize(width: 640, height: 300), scale: 2)
        #expect(model.framesPerPixel == scale)
    }
}
