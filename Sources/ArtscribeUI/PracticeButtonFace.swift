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

    /// The face for this ramp.
    ///
    /// `compact` is the phone's: the header there holds a back button, the
    /// wordmark, the file name, this, the `⋯` menu and Open… across one
    /// landscape row, and "Rep 3 of 8 · 75%" is the thing that can give way.
    /// The numbers stay; only the word goes.
    public static func face(for ramp: SpeedRamp, compact: Bool) -> PracticeButtonFace {
        let speed = Readout.percent(ramp.currentRatio)
        switch ramp.phase {
        case .idle:
            return PracticeButtonFace(
                style: .invitation, title: "Practice", progress: nil, stopSymbol: nil,
                accessibilityLabel: "Practice", stopAccessibilityLabel: nil)
        case .running:
            let count =
                compact
                ? "\(ramp.repetition)/\(ramp.total)"
                : "Rep \(ramp.repetition) of \(ramp.total)"
            return PracticeButtonFace(
                style: .progress, title: "\(count) · \(speed)", progress: ramp.progress,
                stopSymbol: "stop.fill",
                accessibilityLabel:
                    "Practice: repetition \(ramp.repetition) of \(ramp.total), at \(speed)",
                stopAccessibilityLabel: "Stop ramp")
        case .complete:
            return PracticeButtonFace(
                style: .progress, title: "\(compact ? "Done" : "Ramp done") · \(speed)",
                progress: 1, stopSymbol: "xmark",
                accessibilityLabel: "Practice: ramp complete, holding \(speed)",
                stopAccessibilityLabel: "Dismiss finished ramp")
        }
    }
}
