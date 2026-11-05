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
