import ArtscribeKit

/// **What the header's Practice button says**, as a function of the ramp.
///
/// The button is the way into the Practice hub on every platform, and while a
/// ramp runs it doubles as its readout: which repetition, at what speed, and how
/// far through. Everything it shows is decided here, so the view decides
/// nothing — the same split as `TransportControl` and `PracticeReadout`.
///
/// ## Why the button changes shape at all
///
/// A ramp is something you start and then stop watching the window for: your
/// hands are on the instrument. The Practice panel is a sheet on iPad and
/// iPhone, which covers the waveform, so it gets put away while the ramp plays
/// — and until this existed nothing on the main screen said a ramp was running,
/// other than the speed readout changing on its own. The header now says so,
/// and offers the stop without reopening the panel.
public struct PracticeButtonFace: Equatable, Sendable {

    /// How the button is drawn.
    public enum Style: Equatable, Sendable {
        /// The resting invitation: the header's one filled, accent-coloured
        /// control — Apple's "one primary action per toolbar".
        case invitation
        /// A ramp is running or has finished: a bordered readout with a
        /// progress wash behind it, and a stop segment beside it.
        case progress
    }

    public let style: Style
    public let title: String
    /// The widest `title` this ramp can show, in either of its phases. The
    /// button reserves this width, so the header does not shift as
    /// "Rep 9 of 10 · 95%" becomes "Rep 10 of 10 · 100%" — a readout is
    /// supposed to be the thing you can stop looking at.
    public let reservedTitle: String
    /// 0…1 for the wash behind the readout. `nil` when there is nothing to
    /// measure — the resting button has no progress, not zero progress.
    public let progress: Double?
    /// The second segment's SF Symbol, or `nil` when there is no second
    /// segment. A ramp in progress offers **stop**; a finished one, holding its
    /// last speed, offers to put the readout away (`xmark`) — what `stopRamp()`
    /// does from `.complete`.
    public let stopSymbol: String?
    public let accessibilityLabel: String
    public let stopAccessibilityLabel: String?

    /// Whether the header has room for the long wording.
    ///
    /// A phone never does. Neither does an iPad window in a compact width —
    /// Split View, Slide Over, a narrow Stage Manager window — which is why this
    /// is not just a question about the device. The Mac's window has a minimum
    /// width the transport bar already sets far above this.
    public static func prefersCompact(
        surface: EmptyStatePrompt.Surface, horizontallyCompact: Bool
    ) -> Bool {
        surface == .phone || horizontallyCompact
    }

    /// The face for this ramp.
    ///
    /// `speed` is what is **playing** — the model's speed, not the schedule's.
    /// They agree on every wrap, but `1`–`4` or `Q`/`W` mid-repetition change
    /// what you hear until the next one, and a readout that says "the speed you
    /// are hearing" has to say that.
    ///
    /// `compact` (see `prefersCompact`): "Rep 3 of 8 · 75%" is the thing in a
    /// crowded header that can give way. The numbers stay; only the words go.
    public static func face(
        for ramp: SpeedRamp, speed ratio: Double, compact: Bool
    ) -> PracticeButtonFace {
        let speed = Readout.percent(ratio)
        let count = { (repetition: Int) in
            compact ? "\(repetition)/\(ramp.total)" : "Rep \(repetition) of \(ramp.total)"
        }
        let done = compact ? "Done" : "Ramp done"
        // Four characters is the widest a whole-percent speed gets (`100%`;
        // the clamp stops short of four digits), and the readout font is
        // monospaced, so this is the widest either phase can draw.
        let widest =
            [count(ramp.total), done].map { "\($0) · 100%" }
            .max { $0.count < $1.count } ?? ""
        switch ramp.phase {
        case .idle:
            return PracticeButtonFace(
                style: .invitation, title: "Practice", reservedTitle: "Practice",
                progress: nil, stopSymbol: nil,
                accessibilityLabel: "Practice", stopAccessibilityLabel: nil)
        case .running:
            return PracticeButtonFace(
                style: .progress, title: "\(count(ramp.repetition)) · \(speed)",
                reservedTitle: widest, progress: ramp.progress, stopSymbol: "stop.fill",
                accessibilityLabel:
                    "Practice: repetition \(ramp.repetition) of \(ramp.total), at \(speed)",
                stopAccessibilityLabel: "Stop ramp")
        case .complete:
            return PracticeButtonFace(
                style: .progress, title: "\(done) · \(speed)", reservedTitle: widest,
                progress: 1, stopSymbol: "xmark",
                accessibilityLabel: "Practice: ramp complete, holding \(speed)",
                stopAccessibilityLabel: "Dismiss finished ramp")
        }
    }
}
