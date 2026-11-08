import CoreGraphics

/// **What the status bar balances against**: the home-indicator strip, and
/// nothing else `DocumentView` happens to measure.
///
/// `StatusBarView` adds half the bottom safe-area inset above its labels (see
/// `StatusBarView.bottomInset`), and `DocumentView` measures that inset.
///
/// ## The freeze (1.4, build 185)
///
/// Tapping a number field in Practice on an iPhone froze the app: no keyboard,
/// no swipe, no buttons, and a `0x8BADF00D` scene-update watchdog kill when it
/// was sent to the background. All four crash logs had the main thread inside
/// `UISheetPresentationController _keyboardAboutToShow:` → a layout pass →
/// `DocumentView.body`, each stopped in a different view body: a loop.
///
/// The inset used to be measured from the document's own stack, whose height
/// includes the status bar's padding. When the keyboard rises over a sheet,
/// UIKit re-lays out the presenter in what is left — about 207 pt of a
/// landscape iPhone, less than the document's fixed rows need — and the
/// document overhangs. The "inset" it measured was then how far it overhung,
/// which the padding changed: 20 → 194.8 → 151.1 → 162.1 → 159.3 → … on an
/// iPhone 17 Pro simulator, every step a full re-render, about thirty before it
/// settled. On the device it never settled. `ignoresSafeArea(.keyboard)`
/// changed nothing at any placement: it is the sheet controller resizing the
/// presenter, not SwiftUI's keyboard region.
///
/// ## Two halves, and which one stops the loop
///
/// **The loop is removed in `DocumentView`**, structurally: on iOS the inset is
/// read from a frame of exactly the space offered (`minHeight: 0, maxHeight:
/// .infinity`), which the content can overhang but never resize. Padding can no
/// longer change the measurement, so any value settles in one pass. A filter on
/// the values could not promise that — a response that flips between two
/// readings both under any ceiling loops just the same, as review pointed out —
/// which is why this type is not the guard.
///
/// **This rule is about what the bar should look like.** With the keyboard up,
/// the honest measurement is the keyboard's height, and balancing the bar
/// against it would push the labels up by half a keyboard — under a sheet on an
/// iPhone, but in plain view around a form sheet on an iPad. The tallest
/// home-indicator strip on any device this runs on is an iPhone's in portrait,
/// 34 pt (20 on iPad and on a landscape iPhone), so a larger reading is not one,
/// and the bar keeps the value it has.
enum HomeIndicatorInset {

    /// The tallest home-indicator inset on any supported device: 34 pt, an
    /// iPhone in portrait.
    static let ceiling: CGFloat = 34

    /// The inset the status bar should balance against next, given the one it
    /// has and the one just measured.
    static func next(current: CGFloat, measured: CGFloat) -> CGFloat {
        guard measured <= ceiling else { return current }
        return max(measured, 0)
    }
}
