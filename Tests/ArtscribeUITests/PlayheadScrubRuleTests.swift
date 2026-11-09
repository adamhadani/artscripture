import CoreGraphics
import Testing

@testable import ArtscribeUI

/// Scrubbing from the playhead's grip, halfway down the lanes — see
/// `PlayheadScrub`.
@Suite("Playhead scrub: the rules")
struct PlayheadScrubRuleTests {

    private func grab(
        _ x: Double, _ y: Double = 150, playhead: Double = 400, edges: [Double] = [],
        reach: HandleReach = .pointer, laneHeight: Double = 300, width: Double = 1000
    ) -> PlayheadScrub? {
        PlayheadScrub.grabbed(
            at: CGPoint(x: x, y: y), playheadX: playhead,
            lanes: CGSize(width: width, height: laneHeight), reach: reach, loopEdges: edges)
    }

    @Test("the grip is the playhead's x within the edges' reach, halfway down the lanes")
    func theGripIsWhereItIsDrawn() {
        #expect(grab(400)?.grabOffset == 0)
        #expect(grab(409)?.grabOffset == 9)
        #expect(grab(391)?.grabOffset == -9)
        #expect(grab(410) == nil)
        // A pointer's tab is 30 pt tall, centred on 150.
        #expect(grab(400, 135) != nil)
        #expect(grab(400, 165) != nil)
        #expect(grab(400, 134) == nil, "above the tab is the lane's")
        #expect(grab(400, 166) == nil, "below the tab is the lane's")
        #expect(grab(400, playhead: -5) == nil, "a playhead off the page has no grip")
    }

    @Test("a finger gets 22 pt either side and 44 pt of height")
    func aFingersTarget() {
        let touch = HandleReach(edge: 22)
        #expect(grab(422, reach: touch) != nil)
        #expect(grab(423, reach: touch) == nil)
        #expect(grab(400, 128, reach: touch) != nil)
        #expect(grab(400, 127, reach: touch) == nil)
        let target = PlayheadGrip.target(atX: 400, laneHeight: 300, reach: touch)
        #expect(target.height == 44)
        #expect(PlayheadGrip.target(atX: 400, laneHeight: 30, reach: touch).height == 30)
    }

    @Test("it is drawn exactly where the loop's grips are, in their shape")
    func drawnInLineWithTheLoopGrips() {
        for reach in [HandleReach.pointer, HandleReach(edge: 22)] {
            #expect(
                PlayheadGrip.tab(atX: 400, laneHeight: 300, reach: reach)
                    == LoopGrip.tab(atX: 400, laneHeight: 300, reach: reach))
        }
    }

    /// The playhead parked on a loop's start, where a new loop puts it: a press
    /// there resizes the loop, as it always did.
    @Test("a loop edge as near as the playhead wins; a nearer playhead wins")
    func theNearerWinsAndTiesGoToTheEdge() {
        #expect(grab(400, edges: [400]) == nil, "a tie went to the playhead")
        // Edge at 408: its tab (10 pt with a pointer) is 403…413.
        #expect(grab(401, edges: [408]) != nil, "the playhead is nearer, off the edge's tab")
        #expect(grab(406, edges: [408]) == nil, "the edge is nearer")
        // An edge out of its own reach takes nothing.
        #expect(grab(408, edges: [418]) != nil)
    }

    /// Review finding: "nearer wins" alone let the playhead take a press on
    /// the loop's tab — drawn on top — whenever it was nearer, which on a
    /// playing loop it is for a moment every repetition: the same press then
    /// resized the loop or paused and scrubbed, depending on when it landed.
    @Test("a press on a loop edge's drawn tab always takes the edge")
    func theLoopsTabIsTheLoops() {
        // Overlapping tabs, the playhead nearer: 403…405 is both, and the
        // loop's is on top.
        #expect(grab(404, edges: [408]) == nil)
        #expect(grab(403, edges: [408]) == nil)
        // Touch: the loop's end at 500 has a 14 pt tab, 493…507; the playhead
        // passing at 494 is nearer to a press at 496 — and loses it.
        let touch = HandleReach(edge: 22)
        #expect(grab(496, playhead: 494, edges: [500], reach: touch) == nil)
        #expect(grab(492, playhead: 494, edges: [500], reach: touch) != nil)
    }

    /// Sideways only: a vertical wobble on the grip while playing became a
    /// "scrub" — pause, seek to the same spot, play — an audible hiccup
    /// (review finding).
    @Test("a press is a scrub once it has travelled sideways")
    func sidewaysIsADrag() {
        #expect(!PlayheadScrub.isADrag(dx: 2, dy: 2, distance: 3))
        #expect(PlayheadScrub.isADrag(dx: 3, dy: 0, distance: 3))
        #expect(PlayheadScrub.isADrag(dx: -3, dy: 40, distance: 3))
        #expect(!PlayheadScrub.isADrag(dx: 0, dy: -30, distance: 3))
        #expect(PlayheadScrub.decisionDistance(reach: .pointer) == 3)
        #expect(PlayheadScrub.decisionDistance(reach: HandleReach(edge: 22)) == 10)
    }

    @Test("the modifiers beat the grip, and the grip beats a handle")
    func thePrecedence() {
        #expect(LaneDragMode(option: true, shift: false, onPlayheadGrip: true) == .zoom)
        #expect(
            LaneDragMode(option: false, shift: true, onPlayheadGrip: true)
                == .range(extending: true))
        #expect(
            LaneDragMode(option: false, shift: false, handle: .loopBody, onPlayheadGrip: true)
                == .scrub)
        #expect(
            LaneDragMode(option: false, shift: false, handle: .loopBody) == .edge(.loopBody))
    }

    @Test("the Mac's cursor says sideways over the grip and while scrubbing; the ruler zooms")
    func theCursor() {
        #expect(
            PointerAffordance.over(
                .waveformLanes, optionHeld: false, laneDrag: nil, onPlayheadGrip: true)
                == .scrubPlayhead)
        #expect(
            PointerAffordance.over(
                .waveformLanes, optionHeld: true, laneDrag: nil, onPlayheadGrip: true) == .zoom)
        #expect(
            PointerAffordance.over(
                .waveformLanes, optionHeld: false, shiftHeld: true, laneDrag: nil,
                onPlayheadGrip: true) == .selectRange)
        #expect(
            PointerAffordance.over(.waveformLanes, optionHeld: false, laneDrag: .scrub)
                == .scrubPlayhead)
        #expect(
            PointerAffordance.over(
                .timeRuler, optionHeld: false, laneDrag: nil, onPlayheadGrip: true)
                == .verticalDrag)
    }
}
