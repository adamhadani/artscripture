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
/// playhead. So a press on the grip decides nothing until it has moved past
/// the click slop: mostly sideways is a scrub, mostly up or down is the zoom,
/// anchored where it began exactly as before. Off the grip a drag zooms at
/// once, as it always did.
///
/// ## What a scrub does to the engine
///
/// It pauses (once the drag is a drag, so a tap on the grip changes nothing)
/// and moves the model's playhead, which the lanes, the readout and the video
/// picture all follow — the picture is driven from the playhead on every tick,
/// paused too. The engine is told **once**, on release (`seek(to:)`), and plays
/// again if it was playing. A seek per finger event would reset the stretcher
/// sixty times a second for nothing anyone could hear.
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

    /// What a drag on the grip turns out to be, once it has moved `slop`:
    /// `true` for a scrub, `false` for the zoom, `nil` while it is still a tap.
    static func isScrub(dx: Double, dy: Double, slop: Double) -> Bool? {
        guard Swift.max(abs(dx), abs(dy)) >= slop else { return nil }
        return abs(dx) >= abs(dy)
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

    var startX: Double {
        switch self {
        case .zoom(let x): return x
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
