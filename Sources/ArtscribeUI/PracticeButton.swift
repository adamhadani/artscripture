import SwiftUI

/// **The header's way into Practice**, shown whenever a track is open.
///
/// Practice used to be reachable only from View ▸ Practice and ⌘P on the Mac,
/// and from the `⋯` menu on iPad and iPhone — a first-class feature filed with
/// About. This puts it in the header beside Open…, as the one filled control
/// there: Apple's toolbar guidance is a single primary action, on the trailing
/// side, and it is the action this app exists for once a track is loaded.
///
/// What it says comes from `PracticeButtonFace`; nothing is decided here.
///
/// ## One shape family with its neighbours
///
/// It is drawn in `controlChrome` at `chromeHeight`, exactly like Open… and the
/// `⋯` button beside it, so the header's trailing cluster reads as one set of
/// controls that differ in emphasis rather than as three shapes that happen to
/// sit together — a pill, a ring and a rounded rectangle was the first draft's
/// problem. The transport bar below is drawn in the same chrome.
///
/// ## Focus
///
/// `.focusable(false)` and `restoreFocus` after every press, for the reason
/// `TransportBarView` spells out: a clicked button that keeps the keyboard turns
/// Space into "press whatever was clicked last".
struct PracticeButton: View {
    let face: PracticeButtonFace
    let metrics: ControlMetrics
    let onOpen: () -> Void
    let onStop: () -> Void
    @Environment(\.palette) private var palette

    /// The running dot — small enough to read as a status light, not a control.
    private static let dot: CGFloat = 6
    /// Strong enough to read as filled at a glance, weak enough that the
    /// readout's text keeps its contrast over it.
    private static let washOpacity: Double = 0.22

    private var isInvitation: Bool { face.style == .invitation }
    private var radius: CGFloat { metrics.cornerRadius }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) { readout }
                .buttonStyle(.plain)
                .help(isInvitation ? "Ramp the loop up to tempo  (⌘P)" : "Show Practice  (⌘P)")
                .accessibilityLabel(face.accessibilityLabel)

            if let symbol = face.stopSymbol {
                Rectangle()
                    .fill(palette.accent.color(opacity: 0.45))
                    .frame(width: Metrics.hairline, height: metrics.chromeHeight)
                Button(action: onStop) {
                    Image(systemName: symbol)
                        .font(.system(size: metrics.glyph * 0.6, weight: .semibold))
                        .foregroundStyle(palette.text.color())
                        // `target` wide, not `chromeHeight`: `hitRegion` only
                        // grows a control vertically, and a stop a thumb has to
                        // aim at is the wrong control to be stingy with.
                        .frame(width: metrics.target, height: metrics.chromeHeight)
                        .hitRegion(target: metrics.target, drawn: metrics.chromeHeight)
                }
                .buttonStyle(.plain)
                .help(face.stopAccessibilityLabel ?? "")
                .accessibilityLabel(face.stopAccessibilityLabel ?? "")
            }
        }
        .controlChrome(
            metrics,
            fill: isInvitation ? palette.accent.color() : palette.panel.color(),
            stroke: isInvitation ? .clear : palette.accent.color()
        )
        // Never truncated: the file name to its left is what gives way.
        .fixedSize()
        .focusable(false)
    }

    private var readout: some View {
        HStack(spacing: Metrics.sm) {
            if isInvitation {
                Image(systemName: "metronome")
                    .font(.system(size: metrics.glyph * 0.85, weight: .semibold))
            } else {
                Circle()
                    .fill(palette.accent.color())
                    .frame(width: Self.dot, height: Self.dot)
            }
            // The reserved width, drawn invisibly underneath: see
            // `PracticeButtonFace.reservedTitle`.
            ZStack(alignment: .leading) {
                Text(face.reservedTitle).hidden()
                Text(face.title)
            }
            .font(Typography.readout.weight(.semibold))
            .monospacedDigit()
        }
        // `background` on the filled button, not `text`: the accent is light
        // in the dark palette and dark in the light one, and the window's
        // background colour is the opposite of it in both.
        .foregroundStyle(isInvitation ? palette.background.color() : palette.text.color())
        .padding(.horizontal, metrics.groupPadding * 1.4)
        .frame(minHeight: metrics.chromeHeight)
        .background(alignment: .leading) { wash }
        .hitRegion(target: metrics.target, drawn: metrics.chromeHeight)
    }

    /// The ramp's progress, filling the readout segment from the leading edge.
    @ViewBuilder private var wash: some View {
        if let progress = face.progress {
            GeometryReader { proxy in
                Rectangle()
                    .fill(palette.accent.color(opacity: Self.washOpacity))
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: radius, bottomLeadingRadius: radius,
                    bottomTrailingRadius: 0, topTrailingRadius: 0))
        }
    }
}
