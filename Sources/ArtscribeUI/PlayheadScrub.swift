import CoreGraphics

/// **Scrubbing: dragging the playhead by its grip on the time ruler.**
///
/// Asked for from an iPhone, with a video open (2026-11): *"dragging the
/// playhead with my finger would be good to quickly move through audio/frames
/// … I can see the frames scroll by quickly as I drag my finger"*, and once a
/// drag inside the loop moves the loop (PR #86) there was no other gesture
/// left for it. The user's own suggestion: give the playhead *"that
/// 'draggable handles' ui"* the loop's edges have, and scrub when that is
/// dragged.
///
/// ## Why on the ruler, not in the lanes
///
/// The lanes are where every loop gesture lives — edges, body, a new passage,
/// a click — and the playhead sits inside the loop most of the time. A grip
/// there would take some of those presses for itself, which is the regression
/// the request was explicit about not wanting. The ruler has one gesture, the
/// drag-to-zoom, and dragging in a ruler to move the playhead is the DAW
/// convention besides. So the grip is drawn on the ruler, in the loop grips'
/// shape (`PlayheadGrip`), and the lanes are untouched.
///
/// ## Sideways scrubs, up and down still zooms
///
/// The ruler's vertical drag is the app's only modifier-free zoom, and the
/// natural place to start a zoom is where you are looking — often the
/// playhead. So a press on the grip decides nothing until it has travelled
/// `decisionDistance`, and then only a **clearly** sideways drag is a scrub
/// (more than twice as far across as down); anything else, ties included, is
/// the zoom, anchored where it began exactly as before. A finger's first few
/// points wobble, so on touch it waits longer (10 pt, against the pointer's
/// 3). Off the grip a drag zooms at once, as it always did.
///
/// ## What a scrub does to the engine
///
/// It pauses (once the drag is a drag, so a tap on the grip changes nothing)
/// and moves the model's playhead, which the lanes, the readout and the video
/// picture all follow — the picture is driven from the playhead on every tick,
/// paused too. The engine is told **once**, on release (`seek(to:)`), and plays
/// again if it was playing. A seek per finger event would reset the stretcher
/// sixty times a second for nothing anyone could hear.
///
/// ## When it does not end normally
///
/// - **Cancelled** (a call, an app switch, another recogniser): landed with
///   the seek and *without* playing again — the gesture is noticed through
///   the ruler's gesture state, which resets on cancel as on end.
/// - **Play pressed mid-scrub** (Space, headphones, the lock screen): `play()`
///   lands the scrub first, so playback starts from where the finger is, and
///   the rest of that drag is spent.
/// - **The track closes or changes**: dropped, like a lane gesture.
/// - A scrub still pending when a later ruler drag starts is landed with the
///   seek alone — never by starting playback from an unrelated gesture.
struct PlayheadScrub: Equatable {
    /// Where the press began, in ruler points: the gesture's identity.
    let startX: Double
    /// Pointer minus playhead at the press, kept for the whole drag, so the
    /// playhead does not jump to the middle of the finger.
    let grabOffset: Double
    /// Whether to play again on release. `nil` until the drag has moved far
    /// enough sideways to be a scrub — which is when it pauses.
    var resumes: Bool?

    /// The scrub a press at `x` could become, or `nil` when it is not on the
    /// grip — including when the playhead is off the page and has no grip.
    static func grabbed(
        atX x: Double, playheadX: Double, reach: HandleReach, width: Double
    ) -> PlayheadScrub? {
        guard playheadX >= 0, playheadX <= width, abs(x - playheadX) <= reach.edge else {
            return nil
        }
        return PlayheadScrub(startX: x, grabOffset: x - playheadX)
    }

    /// What a drag on the grip turns out to be, once it has moved `distance`:
    /// `true` for a scrub — clearly sideways — `false` for the zoom, ties
    /// included, and `nil` while it is still a tap.
    static func isScrub(dx: Double, dy: Double, distance: Double) -> Bool? {
        guard Swift.max(abs(dx), abs(dy)) >= distance else { return nil }
        return abs(dx) > 2 * abs(dy)
    }

    /// How far a press on the grip travels before it is decided: the click
    /// slop with a pointer, more under a finger, whose first points wobble.
    static func decisionDistance(reach: HandleReach) -> Double {
        reach.edge > HandleReach.pointer.edge ? 10 : 3
    }

    /// Where the playhead goes with the pointer at `x`: at its grab offset,
    /// and held to the visible page.
    func playheadX(forPointerAt x: Double, width: Double) -> Double {
        Swift.min(Swift.max(x - grabOffset, 0), width)
    }
}

/// What the drag in flight on the ruler is, latched at the press.
enum RulerDrag: Equatable {
    case zoom(startX: Double)
    case scrub(PlayheadScrub)
    /// A scrub that playback took over (`landScrubForPlayback`): the rest of
    /// the gesture is ignored.
    case spent(startX: Double)

    var startX: Double {
        switch self {
        case .zoom(let x), .spent(let x): return x
        case .scrub(let scrub): return scrub.startX
        }
    }
}

/// The playhead's grip on the ruler: the loop grips' shape and width
/// (`LoopGrip`), in the playhead's colour, nearly the ruler's height.
enum PlayheadGrip {
    static func tab(atX x: Double, rulerHeight: Double, reach: HandleReach) -> CGRect {
        let isTouch = reach.edge > HandleReach.pointer.edge
        let width = Swift.min(isTouch ? 14.0 : 10.0, 2 * reach.edge)
        let height = Swift.max(0, rulerHeight - 10)
        return CGRect(x: x - width / 2, y: (rulerHeight - height) / 2, width: width, height: height)
    }
}
