import CoreGraphics
import Foundation
import Testing

@testable import Video

/// What a file's picture is, read before anything is decoded.
@Suite("Video track probe")
struct VideoTrackInfoTests {

    @Test func probesTheFrameIndexClip() async throws {
        let info = try #require(try await VideoTrackInfo.probe(url: FixtureFrames.indexClip))
        #expect(info.naturalSize == CGSize(width: 48, height: 32))
        #expect(info.displaySize == CGSize(width: 48, height: 32))
        #expect(abs(info.frameRate - 10) < 0.01)
        #expect(abs(info.duration - 3.0) < 0.05)
        #expect(!info.isRotated)
    }

    /// A phone held upright records a landscape picture and a "turn this".
    /// The size the panel lays out is the turned one.
    @Test func aRotatedClipReportsItsUprightSize() async throws {
        let info = try #require(try await VideoTrackInfo.probe(url: FixtureFrames.rotatedClip))
        #expect(info.displaySize == CGSize(width: 32, height: 48))
        #expect(info.isRotated)
    }

    @Test func anAudioFileHasNoVideo() async throws {
        #expect(try await VideoTrackInfo.probe(url: FixtureFrames.url("sine.m4a")) == nil)
    }

    /// The "no audio track" fixture: it has no sound, but it does have a picture.
    @Test func aSilentVideoStillHasAPicture() async throws {
        let info = try await VideoTrackInfo.probe(url: FixtureFrames.url("silent_video.mp4"))
        #expect(info?.displaySize == CGSize(width: 16, height: 16))
    }
}
