import ArtscribeKit
import CoreGraphics
import Testing

@testable import ArtscribeUI

/// The pure half of Task 23: which handle — if any — is under a pixel, and what
/// a drag of that handle does to the region.
///
/// All of it is `Viewport`-relative arithmetic with no view involved, which is
/// the only way the interesting cases can be pinned down: two edges landing on
/// the same pixel (which `G` makes routine), an edge dragged past its opposite
/// number, and a region pushed against either end of the file.
@Suite("Timeline handles")
struct TimelineHandleTests {

    /// 2 000 000 frames across 1000 points is exactly 2000 frames per point, so
    /// every expectation below can be written in whole points.
    private static let totalFrames: FrameIndex = 2_000_000
    private static let framesPerPoint: FrameIndex = 2000
    private static let laneHeight: Double = 300

    private func viewport() -> Viewport {
        Viewport(totalFrames: Self.totalFrames, widthPixels: 1000)
    }

    private func frame(atPoint point: Double) -> FrameIndex {
        FrameIndex(point) * Self.framesPerPoint
    }

    /// A loop from 200 pt to 600 pt.
    private func loop(enabled: Bool = true) -> LoopRegion {
        LoopRegion(
            range: FrameRange(start: frame(atPoint: 200), count: frame(atPoint: 400)),
            isEnabled: enabled)
    }

    /// A selection from 700 pt to 900 pt — clear of the loop above.
    private func handle(
        atPoint x: Double,
        y: Double = laneHeight / 2,
        loop: LoopRegion = LoopRegion()
    ) -> TimelineHandle? {
        TimelineHandles.handle(
            at: CGPoint(x: x, y: y), laneHeight: Self.laneHeight, loop: loop,
            viewport: viewport())
    }

    // MARK: - Nothing to grab

    @Test("with no loop there is nothing to grab anywhere")
    func emptyTimelineOffersNoHandle() {
        for x in stride(from: 0.0, through: 1000.0, by: 50) {
            #expect(handle(atPoint: x) == nil)
        }
    }

    // MARK: - Loop edges

    @Test("the loop's in and out points are grabbable exactly on the drawn edge")
    func loopEdgesAreGrabbable() {
        #expect(handle(atPoint: 200, loop: loop()) == .loopStart)
        #expect(handle(atPoint: 600, loop: loop()) == .loopEnd)
    }

    /// Fitts's law: the drawn edge is 2 pt, the grab zone is far wider, and it is
    /// symmetric — an edge you can only catch from the inside is half an edge.
    @Test("the grab zone reaches the documented radius on both sides and stops there")
    func grabZoneIsWiderThanTheDrawnEdge() {
        let radius = TimelineHandles.grabRadius
        #expect(radius >= 8 && radius <= 10)
        #expect(handle(atPoint: 200 - radius, loop: loop()) == .loopStart)
        #expect(handle(atPoint: 200 + radius, loop: loop()) == .loopStart)
        #expect(handle(atPoint: 200 - radius - 1, loop: loop()) == nil)
        // Just inside the loop, past the zone: the body band is only at the top
        // and bottom, so mid-lane there is nothing here.
        #expect(handle(atPoint: 200 + radius + 1, loop: loop()) == nil)
    }

    /// A loop that exists but is switched off is still drawn, so it is still
    /// grabbable — otherwise the only way to adjust it would be to enable it
    /// first, which changes what you hear.
    @Test("a disabled loop is still grabbable")
    func disabledLoopIsStillGrabbable() {
        #expect(handle(atPoint: 200, loop: loop(enabled: false)) == .loopStart)
        #expect(handle(atPoint: 600, loop: loop(enabled: false)) == .loopEnd)
    }

    @Test("an empty loop has no edges")
    func emptyLoopOffersNoHandle() {
        let none = LoopRegion(range: FrameRange(start: frame(atPoint: 300), count: 0))
        #expect(handle(atPoint: 300, loop: none) == nil)
    }

    /// Within reach the *nearer* edge wins, so neither edge of a short loop is
    /// ever unreachable.
    @Test("when both edges of a short loop are in reach, the nearer one wins")
    func nearerEdgeWins() {
        let short = LoopRegion(
            range: FrameRange(start: frame(atPoint: 200), count: frame(atPoint: 10)),
            isEnabled: true)
        #expect(handle(atPoint: 203, loop: short) == .loopStart)
        #expect(handle(atPoint: 208, loop: short) == .loopEnd)
    }

    // MARK: - The loop body

    /// The body handle lives on the bars the loop already draws along the top
    /// and bottom of the lanes, and nowhere else. That is what keeps a plain
    /// drag inside the loop doing what it has always done — selecting.
    @Test("the loop body is grabbable on the top and bottom bars only")
    func loopBodyIsGrabbableOnTheBars() {
        #expect(handle(atPoint: 400, y: 2, loop: loop()) == .loopBody)
        #expect(handle(atPoint: 400, y: Self.laneHeight - 2, loop: loop()) == .loopBody)
        #expect(handle(atPoint: 400, y: Self.laneHeight / 2, loop: loop()) == nil)
    }

    @Test("the body band stops at the documented height")
    func bodyBandHeightIsRespected() {
        let band = TimelineHandles.bodyBandHeight
        #expect(handle(atPoint: 400, y: band - 0.5, loop: loop()) == .loopBody)
        #expect(handle(atPoint: 400, y: band + 0.5, loop: loop()) == nil)
        #expect(handle(atPoint: 400, y: Self.laneHeight - band + 0.5, loop: loop()) == .loopBody)
        #expect(handle(atPoint: 400, y: Self.laneHeight - band - 0.5, loop: loop()) == nil)
    }

    /// A window squeezed down must not lose the plain drag. Two fixed 14 pt
    /// bands in a 28 pt lane would leave nothing between them, and selecting a
    /// passage would silently stop working in a small window.
    @Test("in a very short lane the body band never takes more than half of it")
    func bodyBandShrinksWithTheLane() {
        let short: Double = 28
        let handleAt = { (y: Double) in
            TimelineHandles.handle(
                at: CGPoint(x: 400, y: y), laneHeight: short, loop: self.loop(),
                viewport: self.viewport())
        }
        #expect(handleAt(1) == .loopBody)
        #expect(handleAt(short - 1) == .loopBody)
        // Deliberately off-centre on both sides. Exactly the midpoint passes
        // even with the band unclamped — the two fixed bands meet there and
        // neither strict comparison holds — so a test that only probed it would
        // be one that cannot fail.
        #expect(handleAt(short * 0.35) == nil)
        #expect(handleAt(short * 0.6) == nil)
    }

    @Test("the body band does not extend past the loop's own span")
    func bodyBandIsBoundedByTheLoop() {
        #expect(handle(atPoint: 100, y: 2, loop: loop()) == nil)
        #expect(handle(atPoint: 800, y: 2, loop: loop()) == nil)
    }

    // MARK: - The anchor a drag pivots on

    @Test("each edge handle pivots on its opposite number")
    func anchorsAreTheOppositeEdge() {
        let loop = loop()
        #expect(
            TimelineHandles.anchor(for: .loopStart, loop: loop)
                == loop.range.end)
        #expect(
            TimelineHandles.anchor(for: .loopEnd, loop: loop)
                == loop.range.start)
        #expect(TimelineHandles.anchor(for: .loopBody, loop: loop) == nil)
    }

    // MARK: - Resizing from one edge

    @Test("an edge drag moves the dragged edge and leaves the anchor alone")
    func resizeKeepsTheAnchor() {
        let range = TimelineHandles.resized(
            anchor: 1000, to: 4000, totalFrames: Self.totalFrames)
        #expect(range == FrameRange(start: 1000, count: 3000))
    }

    /// The inversion decision, in one test: dragging the in point past the out
    /// point **swaps** rather than clamping. The drag carries on following the
    /// pointer, which is what Ableton and Logic both do, and the region is never
    /// left collapsed to nothing.
    @Test("dragging one edge past the other swaps rather than inverting or clamping")
    func draggingPastTheOtherEdgeSwaps() {
        let range = TimelineHandles.resized(anchor: 1000, to: 400, totalFrames: Self.totalFrames)
        #expect(range == FrameRange(start: 400, count: 600))
        #expect(range.count > 0)
    }

    @Test("an edge dragged exactly onto its anchor gives an empty region at that frame")
    func edgeOnTheAnchorIsEmpty() {
        let range = TimelineHandles.resized(anchor: 1000, to: 1000, totalFrames: Self.totalFrames)
        #expect(range == FrameRange(start: 1000, count: 0))
    }

    @Test("an edge dragged past either end of the file stops at the file")
    func resizeClampsToTheFile() {
        let low = TimelineHandles.resized(
            anchor: 1000, to: -500_000, totalFrames: Self.totalFrames)
        #expect(low == FrameRange(start: 0, count: 1000))
        let high = TimelineHandles.resized(
            anchor: 1000, to: Self.totalFrames + 500_000, totalFrames: Self.totalFrames)
        #expect(high == FrameRange(start: 1000, count: Self.totalFrames - 1000))
    }

    // MARK: - Moving the whole region

    @Test("a body drag preserves the region's length")
    func moveKeepsTheLength() {
        let range = FrameRange(start: 1000, count: 500)
        let moved = TimelineHandles.moved(range, toStart: 7000, totalFrames: Self.totalFrames)
        #expect(moved == FrameRange(start: 7000, count: 500))
    }

    /// Clamped as a whole, exactly as `Selection.translated(by:within:)` is: a
    /// region pushed against an end stops there with its length intact rather
    /// than shrinking against the wall.
    @Test("a body drag clamps as a whole at the start of the file")
    func moveClampsAtTheStart() {
        let range = FrameRange(start: 1000, count: 500)
        let moved = TimelineHandles.moved(range, toStart: -9000, totalFrames: Self.totalFrames)
        #expect(moved == FrameRange(start: 0, count: 500))
    }

    @Test("a body drag clamps as a whole at the end of the file")
    func moveClampsAtTheEnd() {
        let range = FrameRange(start: 1000, count: 500)
        let moved = TimelineHandles.moved(
            range, toStart: Self.totalFrames, totalFrames: Self.totalFrames)
        #expect(moved == FrameRange(start: Self.totalFrames - 500, count: 500))
    }

    /// Nothing in the app can make one, but a hand-edited sidecar can, and a
    /// region longer than the file has no legal position at all.
    @Test("a region longer than the file is clamped to the file rather than moved")
    func moveOfAnOversizedRegionClampsToTheFile() {
        let range = FrameRange(start: 0, count: Self.totalFrames + 10_000)
        let moved = TimelineHandles.moved(range, toStart: 500, totalFrames: Self.totalFrames)
        #expect(moved == FrameRange(start: 0, count: Self.totalFrames))
    }

    // MARK: - Reach by input device

    /// Reported from an iPhone: missing a loop edge "by just a tiny bit" started
    /// something else instead of moving the edge. 9 pt either side is a 20 pt
    /// target — fine for a pointer, half the 44 pt a fingertip needs.
    private func handle(atX x: Double, y: Double, reach: HandleReach) -> TimelineHandle? {
        TimelineHandles.handle(
            at: CGPoint(x: x, y: y), laneHeight: Self.laneHeight, loop: loop(),
            viewport: viewport(), reach: reach)
    }

    @Test("a finger catches a loop edge 20 points away")
    func aFingerCatchesAnEdgeTwentyPointsAway() {
        let reach = ControlMetrics.handleReach(on: .phone)
        #expect(handle(atX: 620, y: Self.laneHeight / 2, reach: reach) == .loopEnd)
        #expect(handle(atX: 180, y: Self.laneHeight / 2, reach: reach) == .loopStart)
    }

    @Test("a pointer does not, at the same distance")
    func thePointerDoesNot() {
        let reach = ControlMetrics.handleReach(on: .desktop)
        #expect(handle(atX: 620, y: Self.laneHeight / 2, reach: reach) == nil)
    }

    @Test("a finger's loop-body band is deeper than a pointer's")
    func touchBodyBandIsDeeper() {
        #expect(handle(atX: 400, y: 20, reach: ControlMetrics.handleReach(on: .phone)) == .loopBody)
        #expect(handle(atX: 400, y: 20, reach: ControlMetrics.handleReach(on: .desktop)) == nil)
    }

    @Test("touch reach is a 44 pt target; the Mac keeps its 20 pt one")
    func reachValues() {
        #expect(ControlMetrics.handleReach(on: .phone) == HandleReach(edge: 22, bodyBand: 22))
        #expect(
            ControlMetrics.handleReach(on: .tabletWithDrop) == HandleReach(edge: 22, bodyBand: 22))
        #expect(ControlMetrics.handleReach(on: .desktop) == HandleReach(edge: 9, bodyBand: 14))
    }
}
