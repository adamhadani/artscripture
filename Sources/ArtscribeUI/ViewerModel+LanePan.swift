import ArtscribeKit
import CoreGraphics

/// A drag in open lane while there is a loop: it carries the view.
///
/// **Why it exists (2026-11-14).** Until then a drag anywhere outside the loop
/// drew a new range and threw the loop away. On a phone that is what a tap
/// does when the fingertip wobbles past the 3 pt click slop, and what a reach
/// to pan or the first finger of a pinch does — so a loop set with care went
/// at the slightest touch outside it. Reported by the user: "very destructive
/// and frustrating". A loop now changes only by being taken hold of — its
/// edges, or its inside, which moves it — or by being cleared (`Esc`, a long
/// press on Loop). With **no** loop a drag still draws one, or there would be
/// no way to make the first.
///
/// **The frame under the press stays under the finger.** That is the whole
/// rule, and it is held against the current viewport on every event rather
/// than by summing deltas: a sum drifts once the view stops at either end of
/// the file, and this cannot.
///
/// Every platform, by the user's choice: one rule for the loop everywhere, as
/// with its other gestures. On a Mac a click there still moves the playhead —
/// on release rather than on press, as a click on the loop's inside already
/// does, because a press that becomes a pan must not have moved what you are
/// listening to.
struct LanePan: Equatable, Sendable {
    /// The frame under the press, held under the finger for the whole drag.
    let anchorFrame: FrameIndex
    /// Past the tap slop. From then on the drag pans and its release is not a
    /// tap, even if the finger wanders back to where it started.
    var hasMoved = false
}

extension ViewerModel {

    /// One event of a pan. Nothing moves until the finger has travelled the
    /// tap slop — in any direction, so a vertical swipe is not read as a tap
    /// either — and from then on the view follows it.
    func panChanged(_ pan: LanePan, start: CGPoint, current: CGPoint) {
        var pan = pan
        if !pan.hasMoved {
            let travel = hypot(current.x - start.x, current.y - start.y)
            guard travel >= prefs.panSlop else { return }
            pan.hasMoved = true
            // Written once per gesture, on this transition: the mode is
            // observed (the cursor reads it), so not on every event.
            laneDragMode = .pan(pan)
        }
        let drift = viewport.pixel(forFrame: pan.anchorFrame) - Double(current.x)
        guard drift.isFinite, abs(drift) < Double(Int.max) else { return }
        scroll(byPoints: Int(drift.rounded()))
    }

    /// The end of a pan. One that never moved was a tap: it seeks, and a
    /// second in quick succession plays — exactly as a tap anywhere else in
    /// the lanes does.
    func panEnded(_ pan: LanePan, end: CGPoint, now: Double) {
        guard pan.hasMoved else {
            click(atPixel: end.x, now: now)
            return
        }
        // A pan is not the first half of a double-click.
        lastClick = nil
    }
}
