import ArtscribeKit
import SwiftUI

/// The bottom readout, which doubles as the transport bar (spec §8: degraded
/// state is indicated here). Every value is monospaced and every field keeps its
/// slot, so nothing shifts sideways while you zoom or while the playhead runs.
struct StatusBarView: View {
    let model: ViewerModel
    /// How much of the screen below this bar belongs to the system — the home
    /// indicator on iOS, zero on a Mac.
    ///
    /// **Without it the bar reads as top-aligned**, and correctly so: the
    /// content stops at the safe area while the background carries on to the
    /// bottom of the screen, so 8 pt of padding sits above the labels and 8 + 20
    /// below them. Nothing is misaligned; the eye simply sees the painted band,
    /// not the safe area, and judges the balance against that.
    ///
    /// Half the inset is added on top, which centres the content in what is
    /// actually visible while still leaving it clear of the indicator. Measured
    /// from `DocumentView`'s own geometry rather than read off a UIKit
    /// singleton, which would be a nonisolated `UIDevice`-style trap and
    /// untestable besides.
    ///
    /// **Only ever the home indicator.** The padding this adds used to change
    /// the height of the view the inset was measured from, and a keyboard over
    /// a sheet turned that into a layout loop that froze the app (1.4, build
    /// 185). `HomeIndicatorInset` explains the fix and the rule.
    var bottomInset: CGFloat = 0
    @Environment(\.palette) private var palette

    var body: some View {
        // Widest arrangement first: `ViewThatFits` takes the first child whose
        // ideal width fits what it is offered, so the order of
        // `StatusBarFields.candidates` *is* the priority. The last candidate is
        // the essential three, which always fits anything worth calling a
        // window.
        //
        // A `ForEach`, never literal indices: those named five arrangements
        // over a list whose length follows `dropOrder`, and when the Selection
        // field went (2026-11) the bar trapped "Index out of range" on launch.
        //
        // **One line, not two** (2026-11): a label beside each value rather
        // than above it, so the bar is a single row of text and the transport
        // above it — what you actually press — gets the height. The user chose
        // it from four layouts rendered on a phone. The last arrangement gives
        // up LOADED IN, which a phone has no room for beside the essential
        // three; DEGRADED is not droppable and keeps its slot in every one.
        ViewThatFits(in: .horizontal) {
            ForEach(StatusBarFields.candidates.indices, id: \.self) { index in
                row(StatusBarFields.candidates[index], showsLoadTime: true)
            }
            row(StatusBarFields.essential, showsLoadTime: false)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, Metrics.sm + bottomInset / 2)
        .padding(.bottom, Metrics.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.panel.color())
        .overlay(alignment: .top) {
            Rectangle().fill(palette.rule.color()).frame(height: Metrics.hairline)
        }
    }

    /// One arrangement of the bar. Fixed column widths, not intrinsic ones: the
    /// zoom readout swings from "19822 f/px" to "1.28 f/px" as you zoom, and a
    /// shifting column drags every field to its right along with it. The
    /// position readout is the worst offender of all, changing sixty times a
    /// second.
    ///
    /// Each field is a label and a value, and only the *value* has the fixed
    /// width — the labels are constant, and the two that change reserve the
    /// longer word (`steadyLabel`), so the whole row is a fixed width too.
    private func row(_ fields: [StatusBarFields.Field], showsLoadTime: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.gutter) {
            ForEach(fields, id: \.self) { field in
                view(for: field)
            }
            Spacer(minLength: Metrics.md)
            // Outside the droppable set on purpose. DEGRADED is spec §8 — a
            // stall the user is not told about is the whole thing that rule
            // exists to prevent — so it must survive every width. LOADED IN
            // shares the slot because the two are never both interesting.
            trailing(showsLoadTime: showsLoadTime)
        }
    }

    @ViewBuilder
    private func view(for field: StatusBarFields.Field) -> some View {
        switch field {
        case .position:
            transport
        case .volume:
            // Beside the transport, not buried in a menu: the level is something
            // you reach for constantly while transcribing.
            VolumeSliderView(model: model)
        case .speed:
            // A speed that is not 100% is the one piece of state you can forget
            // you left on, and it changes what you are hearing, so it is the one
            // readout that shouts.
            self.field(
                "SPEED", speedText, width: StatusBarFields.width(of: .speed),
                emphasised: SpeedStepping.isAltered(model.speed.ratio))
        case .loop:
            // An engaged loop is a mode, and it changes what you are hearing
            // just as much as an altered speed does — so it gets the speed
            // readout's treatment: bold, and in a colour.
            //
            // The colour is the loop's own violet rather than the emphasis
            // amber. Both are "you changed something" hues in this palette, but
            // the loop already wears violet on the lanes and in the overview
            // strip, and two modes that are on at once must not be told apart
            // only by which word is bold. Contrast against the panel is 4.9
            // (dark) and 6.8 (light) — see `Palette`.
            self.field(
                "LOOP", loopText, width: StatusBarFields.width(of: .loop),
                emphasised: model.loop.isActive,
                tint: model.loop.isActive ? palette.loop.color() : nil)
        case .zoom:
            self.field("ZOOM", zoom, width: StatusBarFields.width(of: .zoom))
        case .format:
            self.field("FORMAT", format, width: StatusBarFields.width(of: .format))
        }
    }

    @ViewBuilder
    private func trailing(showsLoadTime: Bool) -> some View {
        if let warning {
            field("DEGRADED", warning, tint: palette.danger.color())
        } else if showsLoadTime, let seconds = model.lastLoadSeconds {
            field("LOADED IN", String(format: "%.2f s", seconds))
        }
    }

    /// Position and play state together, because they are read together: the
    /// triangle says whether the number is moving.
    private var transport: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
            Eyebrow.steady(model.isPlaying ? "▶ PLAYING" : "■ POSITION", widest: "■ POSITION")
            Text(positionText)
                .font(Typography.readout)
                .monospacedDigit()
                .foregroundStyle(
                    model.isPlaying ? palette.accent.color() : palette.text.color()
                )
                .frame(width: StatusBarFields.width(of: .position), alignment: .leading)
        }
    }

    /// `emphasised` bolds and colours the *value* only; the eyebrow keeps its own
    /// dimmed style, so the field still reads as one of a row rather than
    /// becoming a second heading.
    ///
    /// `tint` overrides the colour, and has to be applied *here* rather than by
    /// the caller: this `foregroundStyle` sits nearer the `Text` and would win
    /// over anything wrapped around the field. That is exactly how the spec §8
    /// DEGRADED warning had been rendering in the ordinary text colour, visually
    /// identical to the readout beside it.
    ///
    /// `width` is the value's fixed column; `nil` for the trailing slot, the
    /// one field without one, as before.
    private func field(
        _ label: String, _ value: String, width: CGFloat? = nil, emphasised: Bool = false,
        tint: Color? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
            Eyebrow(label)
            Text(value)
                .font(emphasised ? Typography.readoutEmphasis : Typography.readout)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .foregroundStyle(tint ?? (emphasised ? palette.emphasis.color() : palette.text.color()))
    }

    /// Position over length, the way every transport reads it — the length on its
    /// own (which is what this field used to show) is the less useful half.
    private var positionText: String {
        guard let audio = model.audio else { return "—" }
        let position = TimeCode.precise(frames: model.playhead, sampleRate: audio.sampleRate)
        return "\(position) / \(TimeCode.coarse(seconds: audio.duration))"
    }

    /// Speed and engine, and the fact that the graph is resampling if it is —
    /// not a failure, but the user is entitled to know it is happening.
    private var speedText: String {
        var text = "\(SpeedStepping.percentLabel(model.speed.ratio)) · \(engineLabel)"
        if model.isResampling { text += " · SRC" }
        return text
    }

    private var engineLabel: String { model.speed.engine.shortName }

    private var loopText: String {
        let range = model.loop.range
        guard model.hasTrack, !range.isEmpty else { return "none" }
        let span = TimeCode.precise(
            seconds: TimeCode.seconds(frames: range.count, sampleRate: model.sampleRate))
        let start = TimeCode.coarse(frames: range.start, sampleRate: model.sampleRate)
        return "\(model.loop.isEnabled ? "on" : "off") · \(span) @ \(start)"
    }

    private var format: String {
        guard model.hasTrack else { return "—" }
        let rate = (model.sampleRate / 1000).rounded(.toNearestOrEven)
        let layout = model.channels == 2 ? "stereo" : "\(model.channels) ch"
        return "\(Int(rate)) kHz · \(layout)"
    }

    private var zoom: String {
        guard model.hasTrack else { return "—" }
        let fpp = model.framesPerPixel
        let factor = model.zoomFactor
        let fppText = fpp < 10 ? String(format: "%.2f", fpp) : String(format: "%.0f", fpp)
        return "\(fppText) f/px · \(String(format: "%.1f", factor))x"
    }

    /// The render-thread counters. Stays on screen once it has appeared: these
    /// are monotonic, and a stall that has happened does not un-happen.
    private var warning: String? { model.degradation.summary }
}
