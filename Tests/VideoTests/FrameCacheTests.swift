import Testing

@testable import Video

/// Decoded frames keyed by presentation time. Generic over the payload, so
/// these run on integers rather than pixel buffers.
@Suite("Frame cache")
struct FrameCacheTests {

    /// Ten frames a second from `from`, payload = frame number.
    private func cache(_ indices: [Int]) -> FrameCache<Int> {
        var cache = FrameCache<Int>()
        for index in indices { cache.insert(pts: Double(index) / 10, duration: 0.1, index) }
        return cache
    }

    @Test func lookupFindsTheFrameCoveringATime() {
        let frames = cache(Array(0..<10))
        #expect(frames.entry(at: 0.0)?.payload == 0)
        #expect(frames.entry(at: 0.35)?.payload == 3)
        // Start inclusive, end exclusive: 0.4 is frame 4's, not frame 3's.
        #expect(frames.entry(at: 0.4)?.payload == 4)
        #expect(frames.entry(at: 0.999)?.payload == 9)
    }

    /// A time between two decoded stretches is a miss. Answering with the
    /// nearest earlier frame would show a picture from seconds ago as current.
    @Test func aGapIsAMissNotAStaleFrame() {
        let frames = cache([0, 1, 2, 7, 8])
        #expect(frames.entry(at: 0.45) == nil)
        #expect(frames.entry(at: 0.75)?.payload == 7)
        #expect(frames.entry(at: 1.5) == nil)
    }

    @Test func coverageNeedsAnUnbrokenRun() {
        let frames = cache([0, 1, 2, 3, 6, 7])
        #expect(frames.covers(0.05..<0.38))
        #expect(!frames.covers(0.05..<0.5))
        #expect(abs((frames.coveredEnd(from: 0.05) ?? 0) - 0.4) < 1e-9)
        #expect(frames.coveredEnd(from: 0.45) == nil)
    }

    @Test func evictionKeepsOnlyPlannedWindows() {
        var frames = cache(Array(0..<20))
        frames.evict(outside: [0.25..<0.45, 1.5..<1.6])
        // Frame 2 spans 0.2..<0.3 and so meets the first window.
        #expect(frames.payloads == [2, 3, 4, 15])
    }

    @Test func insertingTheSamePtsReplaces() {
        var frames = cache([0, 1, 2])
        frames.insert(pts: 0.1, duration: 0.1, 99)
        #expect(frames.count == 3)
        #expect(frames.entry(at: 0.15)?.payload == 99)
    }

    /// H.264 with B-frames is decoded out of presentation order. However the
    /// frames arrive, a time finds the frame shown at that time.
    @Test func decodedFramesFollowPresentationOrder() {
        let frames = cache([0, 3, 1, 2, 6, 4, 5])
        #expect(frames.payloads == [0, 1, 2, 3, 4, 5, 6])
        #expect(frames.entry(at: 0.25)?.payload == 2)
        #expect(frames.covers(0.0..<0.7))
    }
}
