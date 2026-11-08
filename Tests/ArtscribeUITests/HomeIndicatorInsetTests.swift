import CoreGraphics
import Testing

@testable import ArtscribeUI

/// The status bar's balancing inset: the home indicator, never the keyboard.
///
/// What stopped the build-185 freeze is structural — `DocumentView` measures a
/// frame its content cannot resize — and is a fact about layout, checked by
/// logging the inset through a keyboard appearance on a simulator (one pass,
/// where there had been thirty). This is the rule for which readings the bar
/// takes; see `HomeIndicatorInset` for why it is not the loop's guard.
@Suite("Home indicator inset")
struct HomeIndicatorInsetTests {

    @Test("a home indicator's inset is taken as measured")
    func aHomeIndicatorIsTaken() {
        #expect(HomeIndicatorInset.next(current: 0, measured: 20) == 20)
        #expect(HomeIndicatorInset.next(current: 0, measured: 21) == 21)
        #expect(HomeIndicatorInset.next(current: 20, measured: 34) == 34)
        #expect(HomeIndicatorInset.next(current: 0, measured: 20.5) == 20.5)
        // A Mac, or an iPad window clear of the bottom edge.
        #expect(HomeIndicatorInset.next(current: 20, measured: 0) == 0)
    }

    /// 194.8 is what a landscape iPhone 17 Pro simulator measured with the
    /// keyboard up over Practice. Balancing against it would lift the bar's
    /// labels by half a keyboard — in plain view around an iPad form sheet.
    @Test("a keyboard-sized reading leaves the inset as it was")
    func theKeyboardIsNotAHomeIndicator() {
        #expect(HomeIndicatorInset.next(current: 20, measured: 194.8) == 20)
        #expect(HomeIndicatorInset.next(current: 20, measured: 34.5) == 20)
        #expect(HomeIndicatorInset.next(current: 0, measured: 400) == 0)
    }

    @Test("when the keyboard goes, the home indicator comes straight back")
    func theKeyboardLeavingRestoresIt() {
        var inset: CGFloat = 0
        for measured: CGFloat in [20, 194.8, 194.8, 20] {
            inset = HomeIndicatorInset.next(current: inset, measured: measured)
            #expect(inset == 20, "after \(measured)")
        }
    }
}
