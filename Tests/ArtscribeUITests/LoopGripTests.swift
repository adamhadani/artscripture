import CoreGraphics
import Testing

@testable import ArtscribeUI

/// The grip tab on each loop edge — the "you can take hold of this" that Mac
/// trim handles draw (QuickTime Player's, for one). Asked for after 1.2's
/// TestFlight: the edges were draggable, but nothing said so.
@Suite("Loop grip tabs")
struct LoopGripTests {

    private static let pointer = ControlMetrics.handleReach(on: .desktop)
    private static let finger = ControlMetrics.handleReach(on: .phone)

    @Test("a tab sits centred on its edge, halfway down the lanes")
    func centredOnTheEdge() {
        let tab = LoopGrip.tab(atX: 400, laneHeight: 300, reach: Self.pointer)
        #expect(tab.midX == 400)
        #expect(tab.midY == 150)
        #expect(tab.width > 0 && tab.height > tab.width)
    }

    /// The drawn tab is a promise about where a press takes hold. One wider than
    /// the reach would invite a grab at a point that starts a new range instead.
    @Test("a tab is never drawn wider than the reach that grabs it")
    func neverWiderThanItsReach() {
        for reach in [Self.pointer, Self.finger] {
            let tab = LoopGrip.tab(atX: 400, laneHeight: 300, reach: reach)
            #expect(tab.width / 2 <= reach.edge, "\(reach): tab \(tab.width) pt wide")
        }
    }

    @Test("a finger gets a bigger tab than a pointer")
    func touchTabsAreBigger() {
        let small = LoopGrip.tab(atX: 0, laneHeight: 300, reach: Self.pointer)
        let big = LoopGrip.tab(atX: 0, laneHeight: 300, reach: Self.finger)
        #expect(big.width > small.width)
        #expect(big.height > small.height)
    }

    /// A small window's lanes can be short; the tab must not swallow them.
    @Test("in a short lane the tab takes at most a third of its height")
    func shortLanesClampTheTab() {
        let tab = LoopGrip.tab(atX: 100, laneHeight: 45, reach: Self.finger)
        #expect(tab.height <= 15)
        #expect(tab.midY == 22.5)
    }

    @Test("two grip lines, inside the tab and either side of its centre")
    func gripLines() {
        let tab = LoopGrip.tab(atX: 400, laneHeight: 300, reach: Self.finger)
        let lines = LoopGrip.gripLines(in: tab)
        #expect(lines.count == 2)
        for line in lines { #expect(tab.contains(line)) }
        #expect(lines[0].midX < tab.midX && lines[1].midX > tab.midX)
        #expect(abs((tab.midX - lines[0].midX) - (lines[1].midX - tab.midX)) < 0.001)
    }
}
