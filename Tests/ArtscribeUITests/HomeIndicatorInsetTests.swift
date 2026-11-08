import CoreGraphics
import Testing

@testable import ArtscribeUI

/// The status bar's balancing inset, and the feedback loop that froze Practice
/// on an iPhone when the keyboard rose over it (1.4, build 185).
@Suite("Home indicator inset")
struct HomeIndicatorInsetTests {

    /// Plays `DocumentView`'s loop: each pass measures the document, the rule
    /// turns that into the status bar's inset, and the inset changes the next
    /// measurement. Returns the inset after every pass, stopping once a pass
    /// changes nothing — which is the only way SwiftUI's update ends.
    private static func passes(
        from start: CGFloat,
        response: (CGFloat) -> CGFloat,
        rule: (CGFloat, CGFloat) -> CGFloat,
        limit: Int = 200
    ) -> [CGFloat] {
        var inset = start
        var trail: [CGFloat] = []
        for _ in 0..<limit {
            let next = rule(inset, response(inset))
            trail.append(next)
            if next == inset { break }
            inset = next
        }
        return trail
    }

    /// What `DocumentView` did before: take whatever was measured.
    private static func acceptEverything(_: CGFloat, measured: CGFloat) -> CGFloat { measured }

    /// The document overhanging a keyboard-shortened space on an iPhone 17 Pro
    /// simulator, fitted to the logged pairs: inset 20 measured 194.8, 194.8
    /// measured 151.1, 151.1 measured 162.1.
    private static func recorded(_ inset: CGFloat) -> CGFloat { 199.8 - 0.25 * inset }

    @Test("a home indicator's inset is taken, in whole points")
    func aHomeIndicatorIsTaken() {
        #expect(HomeIndicatorInset.next(current: 0, measured: 20) == 20)
        #expect(HomeIndicatorInset.next(current: 0, measured: 21) == 21)
        #expect(HomeIndicatorInset.next(current: 20, measured: 34) == 34)
        #expect(HomeIndicatorInset.next(current: 0, measured: 20.4) == 20)
        // A Mac, or an iPad window clear of the bottom edge.
        #expect(HomeIndicatorInset.next(current: 20, measured: 0) == 0)
    }

    @Test("anything taller than a home indicator leaves the inset as it was")
    func theKeyboardIsNotAHomeIndicator() {
        #expect(HomeIndicatorInset.next(current: 20, measured: 194.8) == 20)
        #expect(HomeIndicatorInset.next(current: 20, measured: 34.5) == 20)
        #expect(HomeIndicatorInset.next(current: 0, measured: 400) == 0)
    }

    /// The model is checked against the log first, so the test is about the
    /// loop that happened rather than one invented for it.
    @Test("the recorded loop: thirty-odd re-renders before, one after")
    func theRecordedLoopSettlesAtOnce() {
        let before = Self.passes(from: 20, response: Self.recorded, rule: Self.acceptEverything)
        #expect(abs(before[0] - 194.8) < 0.1)
        #expect(abs(before[1] - 151.1) < 0.1)
        #expect(abs(before[2] - 162.1) < 0.1)
        #expect(before.count > 10, "\(before.count) passes")

        let after = Self.passes(from: 20, response: Self.recorded, rule: HomeIndicatorInset.next)
        #expect(after == [20])
    }

    /// On the phone the loop never ended. Any response whose swing does not
    /// shrink does that — here, one that flips between two layouts.
    @Test("a loop that never settles by itself settles under the rule")
    func aLoopThatNeverSettlesDoes() {
        let flip: (CGFloat) -> CGFloat = { 214.8 - $0 }
        let before = Self.passes(from: 20, response: flip, rule: Self.acceptEverything)
        #expect(before.count == 200, "the unguarded loop ran out the limit")

        let after = Self.passes(from: 20, response: flip, rule: HomeIndicatorInset.next)
        #expect(after == [20])
    }

    /// Below the ceiling an overhang can still move the reading. Whole points
    /// and the ceiling bound how long that can go on.
    @Test("an overhang below the ceiling still ends within a handful of passes")
    func anOverhangBelowTheCeilingEnds() {
        let nudge: (CGFloat) -> CGFloat = { 20 + 0.5 * $0 }
        let after = Self.passes(from: 20, response: nudge, rule: HomeIndicatorInset.next)
        #expect(after.count <= 10, "\(after)")
        #expect(after.allSatisfy { $0 <= HomeIndicatorInset.ceiling })
    }
}
