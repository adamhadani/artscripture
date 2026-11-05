import CoreGraphics
import Testing

@testable import Video

/// Which stretches of the picture must already be decoded, given where the
/// sound is and where it is going next.
@Suite("Frame plan")
struct FramePlanTests {

    /// 10 fps, 3 s: the shape of `frame_index.mp4`.
    let info = VideoTrackInfo(
        naturalSize: CGSize(width: 48, height: 32), frameRate: 10, duration: 3)

    private func snapshot(
        _ position: Double, playing: Bool = true, speed: Double = 1,
        loop: Range<Double>? = nil
    ) -> PlaybackSnapshot {
        PlaybackSnapshot(position: position, isPlaying: playing, speed: speed, loop: loop)
    }

    private func close(_ a: Range<Double>, _ b: Range<Double>) -> Bool {
        abs(a.lowerBound - b.lowerBound) < 1e-9 && abs(a.upperBound - b.upperBound) < 1e-9
    }

    @Test func pausedPlansOneFrame() {
        let plan = FramePlan.make(snapshot(1.23, playing: false), info: info)
        #expect(plan.main.count == 1)
        #expect(close(plan.main[0], 1.23..<1.33))
        #expect(plan.loopHead == nil)
    }

    /// Wall time, not media time: at half speed a quarter-second of looking
    /// ahead is an eighth of a second of picture.
    @Test func playingLooksAheadInWallTime() {
        let plan = FramePlan.make(snapshot(1.0, speed: 0.5), info: info)
        #expect(plan.main.count == 1)
        #expect(close(plan.main[0], 1.0..<(1.0 + FramePlan.aheadWallSeconds * 0.5)))
    }

    /// The picture after a loop's end is its start, exactly as the stretcher
    /// is fed across the boundary.
    @Test func aWindowThatCrossesTheLoopEndContinuesAtItsStart() {
        let plan = FramePlan.make(snapshot(1.9, loop: 1.0..<2.0), info: info)
        #expect(plan.main.count == 2)
        #expect(close(plan.main[0], 1.9..<2.0))
        #expect(close(plan.main[1], 1.0..<1.15))
    }

    /// A loop shorter than the look-ahead cannot ask for more than all of itself.
    @Test func aLoopShorterThanTheHorizonIsCapped() {
        let plan = FramePlan.make(snapshot(1.05, speed: 2, loop: 1.0..<1.2), info: info)
        #expect(plan.main.count == 2)
        #expect(close(plan.main[0], 1.05..<1.2))
        #expect(close(plan.main[1], 1.0..<1.2))
    }

    /// The frames at the loop's start stay decoded however far away the wrap
    /// is: re-reading them at the wrap means a seek into a long GOP, which is
    /// the stall at every repetition this exists to prevent.
    @Test func theLoopHeadIsPinnedEvenFarFromTheWrap() {
        let playing = FramePlan.make(snapshot(5.0, loop: 1.0..<9.0), info: info)
        #expect(playing.loopHead.map { close($0, 1.0..<1.25) } == true)
        let paused = FramePlan.make(snapshot(5.0, playing: false, loop: 1.0..<9.0), info: info)
        #expect(paused.loopHead.map { close($0, 1.0..<1.25) } == true)
    }

    @Test func noLoopNoHead() {
        #expect(FramePlan.make(snapshot(1.0), info: info).loopHead == nil)
    }

    /// Nothing outside the picture is ever asked for, whichever end.
    @Test func windowsAreClippedToThePicture() {
        let atEnd = FramePlan.make(snapshot(2.95), info: info)
        #expect(close(atEnd.main[0], 2.95..<3.0))
        let atStart = FramePlan.make(snapshot(0.0), info: info)
        #expect(close(atStart.main[0], 0.0..<0.25))
    }

    /// Just after a wrap the main window and the loop head are the same
    /// stretch, and one reader should serve both.
    @Test func overlappingWindowsMergeInAll() {
        let plan = FramePlan.make(snapshot(1.05, loop: 1.0..<2.0), info: info)
        #expect(plan.all.count == 1)
        #expect(close(plan.all[0], 1.0..<1.3))
    }

    /// Just after a wrap the window must lie inside the pinned loop head.
    /// Reaching a frame behind the position would reach *before the loop*,
    /// which is not decoded, and turn every wrap into a seek.
    @Test func justAfterAWrapTheWindowIsInsideTheLoopHead() throws {
        let plan = FramePlan.make(snapshot(1.01, loop: 1.0..<2.0), info: info)
        let head = try #require(plan.loopHead)
        #expect(plan.main.allSatisfy { $0.lowerBound >= head.lowerBound })
    }

    /// The sound can run past the picture (or start before it). The picture
    /// then holds its last (or first) frame rather than planning nothing.
    @Test func positionsAreClampedIntoThePicture() {
        let late = FramePlan.make(snapshot(9, playing: false), info: info)
        #expect(close(late.main[0], 2.95..<3.0))
        let early = FramePlan.make(snapshot(-1, playing: false), info: info)
        #expect(close(early.main[0], 0.0..<0.1))
    }
}
