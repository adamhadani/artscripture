import CoreGraphics

/// The grip tab drawn on each loop edge: a small rounded tab with two grip
/// lines, centred on the edge — the "you can take hold of this" that Mac trim
/// handles draw (QuickTime Player's, for one). Asked for after 1.2's
/// TestFlight: the edges were draggable, and nothing said so.
///
/// Pure geometry, sized from the same `HandleReach` that decides where a press
/// takes hold, so the drawn tab can never promise a grab the hit test does not
/// honour: it is at most as wide as the reach either side of the edge.
public enum LoopGrip {

    /// The tab on the edge at `x`, centred halfway down lanes of `laneHeight`.
    ///
    /// A pointer gets 10 × 30 pt, a finger 14 × 40 — a finger is coarser, and it
    /// has no hover cursor to say "this is an edge" instead. Never more than a
    /// third of the lanes' height, so a small window keeps its waveform.
    public static func tab(atX x: Double, laneHeight: Double, reach: HandleReach) -> CGRect {
        let isTouch = reach.edge > HandleReach.pointer.edge
        let width = Swift.min(isTouch ? 14.0 : 10.0, 2 * reach.edge)
        let height = Swift.max(0, Swift.min(isTouch ? 40.0 : 30.0, laneHeight / 3))
        return CGRect(
            x: x - width / 2, y: laneHeight / 2 - height / 2, width: width, height: height)
    }

    /// Two 1 pt vertical grip lines, either side of the tab's centre, over the
    /// middle half of its height.
    public static func gripLines(in tab: CGRect) -> [CGRect] {
        let gap = Swift.min(3.0, tab.width / 4)
        let height = tab.height / 2
        let top = tab.midY - height / 2
        return [tab.midX - gap / 2, tab.midX + gap / 2].map { centre in
            CGRect(x: centre - 0.5, y: top, width: 1, height: height)
        }
    }

    /// Corner radius for the tab: fully rounded ends, like a capsule.
    public static func cornerRadius(of tab: CGRect) -> Double { tab.width / 2 }
}
