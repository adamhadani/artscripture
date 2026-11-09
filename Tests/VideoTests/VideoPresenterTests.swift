import Foundation
import Testing

@testable import Video

/// Records what it was shown, as frame numbers.
@MainActor
private final class RecordingSurface: VideoSurface {
    var shown: [Int] = []
    func show(_ frame: DecodedFrame) { shown.append(FixtureFrames.index(of: frame.pixelBuffer)) }
}

/// Picks the frame for the audible position and hands it to every surface.
@MainActor
@Suite("Video presenter")
struct VideoPresenterTests {

    private func presenter() async throws -> (VideoPresenter, VideoFrameSource) {
        let clip = FixtureFrames.indexClip
        let info = try #require(try await VideoTrackInfo.probe(url: clip))
        let source = try await VideoFrameSource.open(url: clip, info: info)
        return (VideoPresenter(source: source), source)
    }

    private func paused(_ position: Double) -> PlaybackSnapshot {
        PlaybackSnapshot(position: position, isPlaying: false, speed: 1, loop: nil)
    }

    /// Hidden panel, no mini player: the decoder is not asked for anything.
    @Test func aPresenterWithNoSurfaceDoesNotDecode() async throws {
        let (presenter, source) = try await presenter()
        for step in 0..<10 { presenter.update(paused(Double(step) / 5)) }
        await source.idle()
        #expect(source.counters.framesDecoded == 0)
    }

    /// Suspended — iOS in the background with no Picture in Picture — the
    /// presenter decodes nothing even with a surface attached.
    @Test func aSuspendedPresenterDecodesNothing() async throws {
        let (presenter, source) = try await presenter()
        // Held here: the presenter keeps surfaces weakly, and one that went
        // away would make this pass for the wrong reason.
        let surface = RecordingSurface()
        presenter.attach(surface)
        presenter.isSuspended = true
        for step in 0..<10 { presenter.update(paused(Double(step) / 5)) }
        await source.idle()
        #expect(source.counters.framesDecoded == 0)
        #expect(surface.shown.isEmpty)
    }

    @Test func theSameFrameIsNotSentTwice() async throws {
        let (presenter, source) = try await presenter()
        let surface = RecordingSurface()
        presenter.attach(surface)
        presenter.update(paused(1.05))
        await source.idle()
        presenter.update(paused(1.05))
        presenter.update(paused(1.07))  // still frame 10
        #expect(surface.shown == [10])
    }

    /// The mini player opening mid-phrase shows the picture at once, not on
    /// the next frame change — which, paused, might never come.
    @Test func aNewSurfaceGetsTheCurrentFrame() async throws {
        let (presenter, source) = try await presenter()
        let first = RecordingSurface()
        presenter.attach(first)
        presenter.update(paused(1.05))
        await source.idle()
        presenter.update(paused(1.05))
        let second = RecordingSurface()
        presenter.attach(second)
        #expect(second.shown == [10])
    }

    @Test func aClosedPresenterShowsNothingMore() async throws {
        let (presenter, source) = try await presenter()
        let surface = RecordingSurface()
        presenter.attach(surface)
        presenter.update(paused(1.05))
        await source.idle()
        presenter.update(paused(1.05))
        presenter.close()
        presenter.update(paused(2.05))
        await source.idle()
        presenter.update(paused(2.05))
        #expect(surface.shown == [10])
    }

    /// Scrubbing (2026-11): the picture follows the finger *while it moves*.
    /// From an iPhone with a video open: "while I drag my finger with the
    /// playhead I want to see video frames changing, currently only happens
    /// when I stop dragging". Positions arrive far faster than a frame decodes
    /// — here as fast as the loop can spin, which on a device is 60 a second
    /// against a seek into a long GOP — so a decoder that abandons every
    /// superseded request never finishes one until the finger stops. Each
    /// decode now finishes and is shown, and the next goes to the newest
    /// position: Apple's "chase time" (Technical Q&A QA1820). Backwards, every
    /// position is a fresh reader; forwards, the main reader reads on.
    @Test(arguments: [false, true])
    func aScrubShowsFramesWhileItMoves(forwards: Bool) async throws {
        let (presenter, source) = try await presenter()
        let surface = RecordingSurface()
        presenter.attach(surface)
        let clock = ContinuousClock()
        let began = clock.now
        let sweep = Duration.milliseconds(600)
        while clock.now - began < sweep {
            let progress = (clock.now - began) / sweep
            presenter.update(paused(forwards ? 0.1 + 2.8 * progress : 2.9 - 2.8 * progress))
            await Task.yield()
        }
        let whileMoving = surface.shown
        #expect(Set(whileMoving).count >= 3, "shown while the finger moved: \(whileMoving)")
        // In the order the finger went: a scrub that showed frames out of order
        // would read as the picture jumping about.
        #expect(whileMoving == (forwards ? whileMoving.sorted() : whileMoving.sorted(by: >)))
        // And once it stops, the exact frame for where it stopped.
        let last = forwards ? 2.9 : 0.1
        presenter.update(paused(last))
        await source.idle()
        presenter.update(paused(last))
        #expect(surface.shown.last == (forwards ? 29 : 1))
    }

    /// The scrub fallback is a paused thing. Playing, a miss is a seek or a
    /// wrap catching up, and the decoder's last answer can be a position the
    /// sound has already left — so the frame on screen holds instead.
    @Test func playingNeverFallsBackOnAnOldAnswer() async throws {
        let (presenter, source) = try await presenter()
        let surface = RecordingSurface()
        presenter.attach(surface)
        presenter.update(paused(1.05))
        await source.idle()
        presenter.update(paused(1.05))
        // Decoded and answered, but never shown: the presenter is not asked
        // again while paused there.
        presenter.update(paused(2.05))
        await source.idle()
        presenter.update(PlaybackSnapshot(position: 0.55, isPlaying: true, speed: 1, loop: nil))
        #expect(surface.shown == [10])
    }

    /// A surface the presenter outlives is not kept alive by it.
    @Test func surfacesAreNotRetained() async throws {
        let (presenter, _) = try await presenter()
        weak var gone: RecordingSurface?
        do {
            let surface = RecordingSurface()
            gone = surface
            presenter.attach(surface)
        }
        #expect(gone == nil)
    }
}
