import CoreGraphics
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

    /// Review finding #1. A reader that has fallen behind the playhead — a
    /// click while playing, or decoding slower than real time — reads forward
    /// to catch up. Replacing it means decoding from the keyframe again on every
    /// tick, and with a long GOP the picture never catches up at all.
    @Test func aReaderBehindThePlayheadCatchesUp() async throws {
        let (source, info) = try await open()
        source.request(plan(0.0, playing: true, info))
        await source.idle()
        let readers = source.counters.readersCreated
        source.request(plan(0.6, playing: true, info))
        await source.idle()
        #expect(source.counters.readersCreated == readers)
        #expect(index(source, at: 0.65) == 6)
    }

    /// A position *behind* the reader still needs a new one: readers only go
    /// forward.
    @Test func aPositionBehindTheReaderStartsANewOne() async throws {
        let (source, info) = try await open()
        source.request(plan(2.0, playing: true, info))
        await source.idle()
        let readers = source.counters.readersCreated
        source.request(plan(0.5, playing: true, info))
        await source.idle()
        #expect(source.counters.readersCreated == readers + 1)
        #expect(index(source, at: 0.55) == 5)
    }

    /// Review finding #2. A picture that stops decoding after it opened —
    /// here the file is cut short — says why, and does not retry 60 times a second.
    @Test func aFailureLatchesAndIsReported() async throws {
        let copy = FileManager.default.temporaryDirectory
            .appendingPathComponent("vanishing-\(UUID().uuidString).mp4")
        try FileManager.default.copyItem(at: FixtureFrames.indexClip, to: copy)
        let (source, info) = try await open(copy)
        // Truncated in place, not unlinked: an asset keeps its file open, so
        // a deleted file still reads. Truncating takes the samples away.
        let handle = try FileHandle(forWritingTo: copy)
        try handle.truncate(atOffset: 2048)
        try handle.close()
        // Where it fails first is the platform's business — iOS reads a few
        // frames out of what is cached — but fail it must, and then stop.
        var step = 0
        while source.failure == nil, step < 12 {
            source.request(plan(0.15 + Double(step) * 0.25, info))
            await source.idle()
            step += 1
        }
        #expect(source.failure != nil)
        let attempts = source.counters.readerAttempts
        for later in 0..<6 {
            source.request(plan(2.9 - Double(later) * 0.4, info))
            await source.idle()
        }
        #expect(source.counters.readerAttempts == attempts)
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

    /// Review finding #4. The budget is memory, not a frame count: 48 frames
    /// of 4K are about 600 MB, which iOS ends an app for, in the background
    /// with Picture in Picture above all.
    @Test func theBudgetIsInBytes() {
        func info(_ width: CGFloat, _ height: CGFloat) -> VideoTrackInfo {
            VideoTrackInfo(
                naturalSize: CGSize(width: width, height: height), frameRate: 30, duration: 10)
        }
        let uhd = VideoFrameSource.frameBudget(for: info(3840, 2160))
        let fullHD = VideoFrameSource.frameBudget(for: info(1920, 1080))
        let tiny = VideoFrameSource.frameBudget(for: info(48, 32))
        #expect(Double(uhd) * 3840 * 2160 * 1.5 <= 130_000_000)
        #expect(uhd >= 8)
        #expect(fullHD > uhd && fullHD >= 30)
        #expect(tiny == 48)
    }

    /// Hiding the panel lets the decoded frames go, not just stops new ones.
    @MainActor
    @Test func theLastSurfaceLeavingReleasesTheCache() async throws {
        let (source, _) = try await open()
        let presenter = VideoPresenter(source: source)
        let surface = SinkSurface()
        presenter.attach(surface)
        presenter.update(PlaybackSnapshot(position: 1.0, isPlaying: true, speed: 1, loop: nil))
        await source.idle()
        #expect(source.counters.cached > 0)
        presenter.detach(surface)
        await source.idle()
        #expect(source.counters.cached == 0)
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

@MainActor
private final class SinkSurface: VideoSurface {
    func show(_ frame: DecodedFrame) {}
}
