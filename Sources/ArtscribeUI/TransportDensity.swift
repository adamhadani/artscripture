import SwiftUI

/// How tightly the transport bar has to pack itself to fit the width it has.
///
/// ## Why this is arithmetic and not `ViewThatFits`
///
/// It *was* `ViewThatFits`, with four candidate rows laid out widest-first. That
/// is the idiomatic answer and it produced the right pixels — and it cost too
/// much to keep. Every candidate is a whole transport bar: fourteen buttons,
/// each with a `GeometryReader` publishing its frame into the model for the
/// acceptance harness. Four candidates is **fifty-six** geometry readers writing
/// into `@Observable` state on every layout pass, each write inviting the next
/// pass.
///
/// It showed up as a *playback* failure, which is the part worth remembering:
/// `the playhead tracks real time at 1.0x` went from 0.608 s of travel per 0.6 s
/// of wall clock to 0.757 s — the audio was fine, the main thread was not, and
/// the harness's wall-clock sampling drifted 26%. Two runs on this branch failed
/// it and two at the merge-base passed, which is what separated a regression
/// from the environmental flake it first looked like.
///
/// So the row is built once and the width is *computed*. One row, fourteen
/// readers, and the decision is a pure function that a test can drive at any
/// width without a window.
struct TransportDensity: Equatable {

    /// What each button is drawn at.
    let buttonWidth: CGFloat

    /// Whether the speed readout, the pitch slider and the pitch label drop to
    /// their floors. Only the tightest density does this.
    let readoutsAtFloor: Bool

    /// The fixed costs of a row, which every candidate pays whatever the buttons
    /// are doing. Passed in rather than reached for, so the formula below is a
    /// function of its arguments and nothing else.
    struct Row: Equatable {
        let buttons: Int
        let groups: Int
        /// Gaps *within* groups — one fewer than the buttons in each, summed.
        let gaps: Int
        let speedPreferred: CGFloat
        let speedFloor: CGFloat
        let sliderPreferred: CGFloat
        let sliderFloor: CGFloat
        let labelPreferred: CGFloat
        let labelFloor: CGFloat
        /// The gap between the pitch slider and its readout.
        let pitchGap: CGFloat
        /// The minimum trailing spacer.
        let slack: CGFloat
    }

    /// What a row of this shape occupies. **This is the layout's own
    /// arithmetic**, so it is the one place to correct if the bar gains a
    /// control — and the reason `TransportBarView` reads its widths from here
    /// rather than keeping a second copy.
    static func width(
        buttonWidth: CGFloat, readoutsAtFloor: Bool, row: Row, metrics: ControlMetrics
    ) -> CGFloat {
        let readouts =
            readoutsAtFloor
            ? row.speedFloor + row.sliderFloor + row.labelFloor
            : row.speedPreferred + row.sliderPreferred + row.labelPreferred
        return CGFloat(row.buttons) * buttonWidth
            + CGFloat(row.gaps) * metrics.spacing
            + CGFloat(row.groups) * 2 * metrics.groupPadding
            // One rule between each pair of groups, and one before the pitch
            // control — which is `groups` of them, not `groups - 1`.
            + CGFloat(row.groups)
            + readouts
            + row.pitchGap
            + 2 * metrics.barInset
            + row.slack
    }

    /// The roomiest packing that fits `available`, or the tightest one if none
    /// does.
    ///
    /// **Between the preferred width and the floor, the widest that fits** —
    /// not the next of a few fixed steps. With steps (55, 44, 30) a landscape
    /// phone could not reach 44 and fell all the way to 30, leaving about
    /// 110 pt of the row empty beside a column of narrow, tall buttons; the
    /// user asked for the buttons to *"stretch out horizontally a bit so
    /// doesn't look weird and fills up the space more naturally"*. A row that
    /// fits its preferred width (an iPad, a Mac) is unchanged.
    ///
    /// Falling back to the tightest rather than to nothing is deliberate: a bar
    /// that overflows a little is recoverable, and `available` is zero on the
    /// very first layout pass, before any geometry has been measured. Starting
    /// tight and widening on the next pass is the direction to be wrong in —
    /// the other way round draws a row out under the notch for one frame.
    static func fitting(available: CGFloat, row: Row, metrics: ControlMetrics) -> TransportDensity {
        let preferred = TransportDensity(buttonWidth: metrics.buttonWidth, readoutsAtFloor: false)
        let full = width(
            buttonWidth: preferred.buttonWidth, readoutsAtFloor: false, row: row, metrics: metrics)
        if full <= available { return preferred }
        // Everything but the buttons, then what is left shared between them —
        // rounded down, so the row never ends up a fraction of a point too wide.
        let rest = width(buttonWidth: 0, readoutsAtFloor: false, row: row, metrics: metrics)
        let stretched = ((available - rest) / CGFloat(Swift.max(1, row.buttons))).rounded(.down)
        if stretched >= metrics.compactWidth {
            return TransportDensity(
                buttonWidth: Swift.min(stretched, metrics.buttonWidth), readoutsAtFloor: false)
        }
        return TransportDensity(buttonWidth: metrics.compactWidth, readoutsAtFloor: true)
    }

    /// The glyph for a button `width` wide: the metric's own size, or smaller
    /// where the button is too narrow to hold it. A ⏪ runs about 1.4× its
    /// point size across, so 0.62 of the width leaves it a margin either side.
    static func glyph(forWidth width: CGFloat, metrics: ControlMetrics) -> CGFloat {
        Swift.min(metrics.buttonGlyph, (width * 0.62).rounded(.down))
    }
}
