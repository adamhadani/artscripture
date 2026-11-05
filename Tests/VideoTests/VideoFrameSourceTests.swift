import CoreVideo
import Foundation
import Testing

@testable import Video

/// Decoding against `frame_index.mp4`, whose every frame says its own number.
@Suite("Video frame source")
struct VideoFrameSourceTests {

    private func open(
        _ clip: URL = FixtureFrames.indexClip, budget: Int = 48
    ) async throws -> (VideoFrameSource, VideoTrackInfo) {
        let info = try #require(try await VideoTrackInfo.probe(url: clip))
        return (try await VideoFrameSource.open(url: clip, info: info, frameBudget: budget), info)
    }

    private func plan(
        _ position: Double, playing: Bool = false, speed: Double = 1,
        loop: Range<Double>? = nil, _ info: VideoTrackInfo
    ) -> FramePlan {
        FramePlan.make(
            PlaybackSnapshot(position: position, isPlaying: playing, speed: speed, loop: loop),
            info: info)
    }

    private func index(_ source: VideoFrameSource, at time: Double) -> Int? {
        source.frame(at: time).map { FixtureFrames.index(of: $0.pixelBuffer) }
    }

    @Test func theFrameAtATimeIsThatFrame() async throws {
        let (source, info) = try await open()
        source.request(plan(1.05, info))
        await source.idle()
        #expect(index(source, at: 1.05) == 10)
        source.request(plan(2.95, info))
        await source.idle()
        #expect(index(source, at: 2.95) == 29)
        #expect(source.failure == nil)
    }

    @Test func positionsOutsideThePictureClamp() async throws {
        let (source, info) = try await open()
        source.request(plan(-1, info))
        await source.idle()
        #expect(index(source, at: -1) == 0)
        source.request(plan(9, info))
        await source.idle()
        #expect(index(source, at: 9) == 29)
    }

    /// Halfway through a loop, the frames at its start are already decoded.
    @Test func theLoopHeadIsReadyBeforeTheWrap() async throws {
        let (source, info) = try await open()
        source.request(plan(1.5, playing: true, loop: 1.0..<2.0, info))
        await source.idle()
        #expect([1.05, 1.15, 1.22].map { index(source, at: $0) } == [10, 11, 12])
        #expect([1.55, 1.65, 1.72].map { index(source, at: $0) } == [15, 16, 17])
    }

    /// At the wrap the picture is there at once, and the reader parked at the
    /// end of the loop head carries on — no seek into the GOP.
    @Test func theWrapHandsOffWithoutANewReader() async throws {
        let (source, info) = try await open()
        let loop = 1.0..<2.0
        source.request(plan(1.9, playing: true, loop: loop, info))
        await source.idle()
        source.request(plan(1.0, playing: true, loop: loop, info))
        #expect(index(source, at: 1.0) == 10)  // no idle(): already decoded
        await source.idle()
        source.request(plan(1.2, playing: true, loop: loop, info))
        await source.idle()
        #expect(source.counters.handoffs == 1)
        #expect([1.35, 1.42].map { index(source, at: $0) } == [13, 14])
    }

    /// Scrubbing while paused: the latest position wins, and the ones it
    /// replaced are not decoded one after another.
    @Test func rapidSeeksEndOnTheLatest() async throws {
        let (source, info) = try await open()
        for step in 1...20 { source.request(plan(Double(step) / 10, info)) }
        await source.idle()
        #expect(index(source, at: 2.0) == 20)
        #expect(source.counters.framesDecoded < 20 * 10)
    }

    /// Frames from a turned clip come out turned: the panel never has to.
    @Test func aRotatedClipDecodesUpright() async throws {
        let (source, info) = try await open(FixtureFrames.rotatedClip)
        source.request(plan(1.05, info))
        await source.idle()
        let frame = try #require(source.frame(at: 1.05))
        #expect(CVPixelBufferGetWidth(frame.pixelBuffer) == 32)
        #expect(CVPixelBufferGetHeight(frame.pixelBuffer) == 48)
    }

    @Test func budgetIsRespected() async throws {
        let (source, info) = try await open(budget: 8)
        source.request(plan(1.0, playing: true, speed: 4, info))
        await source.idle()
        #expect(source.counters.cached <= 8)
        #expect(source.counters.cached > 0)
    }

    /// Nothing comes out of a closed source, however much it had decoded.
    @Test func aClosedSourceAnswersNothing() async throws {
        let (source, info) = try await open()
        source.request(plan(1.05, info))
        await source.idle()
        source.close()
        #expect(source.frame(at: 1.05) == nil)
    }
}
