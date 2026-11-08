import CoreGraphics

/// **What the status bar balances against**: the home-indicator strip, and
/// nothing else `DocumentView` happens to measure.
///
/// `StatusBarView` adds half the bottom safe-area inset above its labels (see
/// `StatusBarView.bottomInset`). That inset is measured from the document's own
/// geometry, and the document's height includes the status bar's padding — so
/// the measurement feeds back into the thing it measures. While the document
/// fills exactly the space it is given, the loop is closed after one pass: the
/// inset is the system's, and padding cannot change it.
///
/// ## The freeze it caused (1.4, build 185)
///
/// Tapping a number field in Practice on an iPhone froze the app: no keyboard,
/// no swipe, no buttons, and a `0x8BADF00D` scene-update watchdog kill when it
/// was sent to the background. All four crash logs had the main thread inside
/// `UISheetPresentationController _keyboardAboutToShow:` → a layout pass →
/// `DocumentView.body`, over and over.
///
/// When the keyboard rises over a sheet, UIKit re-lays out the presenting view
/// in what is left — about 207 pt of a landscape iPhone, less than the
/// document's fixed rows need. The document then overhangs its space, and the
/// "inset" it measures is how far it overhangs: 20 → 194.8 → 151.1 → 162.1 →
/// 159.3 → … on an iPhone 17 Pro simulator, every step a full re-render, about
/// thirty of them before it settled. On a device at 3× it never settled.
///
/// `ignoresSafeArea(.keyboard)` does not help, at any placement in
/// `DocumentView`: it is the sheet controller resizing the presenter, not
/// SwiftUI's keyboard region, and the numbers were identical with and without
/// it. So the fix is here, where the value is accepted.
///
/// ## The rule
///
/// - **Nothing taller than a home indicator is one.** The tallest strip on any
///   device this runs on is an iPhone's in portrait, 34 pt (20 on iPad and on a
///   landscape iPhone). A larger reading is the keyboard, or an overhang, and
///   the bar keeps the value it has — so nothing is written and nothing loops.
/// - **Whole points.** Below the ceiling an overhang can still nudge the
///   reading; rounding means a sub-pixel back-and-forth cannot keep the layout
///   alive at 3×, and the ceiling means there are only so many whole points to
///   walk through.
enum HomeIndicatorInset {

    /// The tallest home-indicator inset on any supported device: 34 pt, an
    /// iPhone in portrait.
    static let ceiling: CGFloat = 34

    /// The inset the status bar should balance against next, given the one it
    /// has and the one just measured.
    static func next(current: CGFloat, measured: CGFloat) -> CGFloat {
        guard measured <= ceiling else { return current }
        return max(measured, 0).rounded()
    }
}
