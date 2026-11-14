/// Whether pressing down in the waveform lanes should move the playhead before
/// anyone knows what the gesture is going to be.
///
/// **With a pointer, yes — where the press may draw a loop.** A mouse-down *is*
/// a click until it turns out to be a drag, the playhead following it is
/// instant feedback, and it has behaved that way since the first version. Not
/// on the loop's inside, nor beside a loop, where the press may move the loop
/// or pan the view (`LanePan`): there the click seeks on release.
///
/// **With a finger, no.** A press is the opening of a gesture whose meaning is
/// not yet decided — and the most common thing it opens is a selection, since
/// dragging one out is the first thing anybody does to a waveform. Seeking on
/// touch-down means that reaching for a passage *while the track is playing*
/// interrupts what you are listening to, at the exact moment you were trying to
/// mark it. Reported from an iPhone, and reproduced on a simulator: a
/// press-hold-drag left the playhead at the drag's start point.
///
/// A tap still seeks. It goes through `dragEnded`'s click path, which runs when
/// the finger comes up having gone nowhere — so nothing is lost, the decision is
/// only deferred until the gesture has said what it is.
///
/// Pure, and keyed on the surface rather than an `#if`, for the reason
/// `EmptyStatePrompt` records: this way both answers are checkable in one
/// `make check` instead of one per platform build.
public enum LaneDragPolicy {

    /// Whether a press on a loop **edge** that never moves is a **tap** — seek
    /// there, and a double tap plays — rather than a grab that did nothing.
    ///
    /// Edges only. An unmoved press on the loop's *body* is a click on every
    /// device, because the body is the whole inside of the loop (2026-11) and
    /// a click there has always meant the playhead (`laneDragEnded`).
    ///
    /// **With a finger, yes.** A finger's reach is 22 pt either side of an edge
    /// (`ControlMetrics.handleReach`), so over a short loop almost every tap
    /// lands on a handle; treating those as grabs swallowed the tap.
    ///
    /// **With a pointer, no**, as Task 23 decided: its reach is 9 pt, the
    /// cursor has already turned into the resize arrows to say "this is an
    /// edge", and a click there is someone aiming at the edge.
    public static func edgeTapIsAClick(on surface: EmptyStatePrompt.Surface) -> Bool {
        switch surface {
        case .desktop: return false
        case .tabletWithDrop, .phone: return true
        }
    }

    /// How far a press in the lanes may travel and still be a **tap**, in
    /// points — before it pans (`LanePan`), before it draws a loop, and between
    /// the two taps of a double tap.
    ///
    /// **With a pointer, the click slop** (`ViewerModel.clickSlopPoints`, 3),
    /// what a click has always been allowed here.
    ///
    /// **With a finger, 10.** A fingertip's contact point wanders by more than
    /// 3 pt in an ordinary tap, and a tap that crossed the slop drew a sliver
    /// of a loop — over the one that was there, until 2026-11-14, and since
    /// then where there was none, which a drag could no longer replace. Ten is
    /// under a quarter of the 44 pt touch target, so a deliberate drag still
    /// starts at once.
    public static func tapSlop(on surface: EmptyStatePrompt.Surface) -> Double {
        switch surface {
        case .desktop: return ViewerModel.clickSlopPoints
        case .tabletWithDrop, .phone: return 10
        }
    }

    public static func seeksOnPress(on surface: EmptyStatePrompt.Surface) -> Bool {
        switch surface {
        case .desktop: return true
        case .tabletWithDrop, .phone: return false
        }
    }
}
