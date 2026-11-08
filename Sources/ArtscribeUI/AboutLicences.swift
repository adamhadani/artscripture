import SwiftUI

/// One licence: the component, its terms, and why it is in this build — and a
/// button that opens the licence itself.
///
/// **The row is the button**, chevron and all, rather than a "View licence" link
/// beside it: there are six of them, and six identical links would be noise. The
/// vertical padding is the touch target. A row draws about 34 pt tall and a
/// fingertip wants 44, so each row pads itself by `Metrics.sm` inside its own hit
/// area, and the list puts no gap between rows that nothing could tap.
struct AboutLicenceRow: View {
    let licence: AboutLicence
    let open: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: Metrics.md) {
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.md) {
                        Text(licence.component)
                            .font(Typography.readoutEmphasis)
                            .foregroundStyle(palette.text.color())
                            .underline(hovering)
                        Text(licence.terms)
                            .font(Typography.readoutSmall)
                            .foregroundStyle(palette.accent.color())
                    }
                    Text(licence.detail)
                        .font(Typography.readoutSmall)
                        .foregroundStyle(palette.dimmed.color())
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: Metrics.md)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.dimmed.color())
            }
            .padding(.vertical, Metrics.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        #if os(macOS)
        .pointerStyle(.link)
        #endif
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the full licence text")
    }
}

/// One licence in full: what a row of the list opens.
///
/// Monospaced, because licence texts are laid out for it — the GPL centres its
/// title with spaces, and the Apache and CC0 texts indent their clauses — and
/// selectable, because the one thing anyone does with a licence beyond reading it
/// is quote it. The palette is passed in rather than read from the environment:
/// what a sheet inherits from its presenter has varied between OS releases, and a
/// licence drawn in the system's colours over this app's background would be the
/// one screen that looked unlike the rest.
struct LicenceTextSheet: View {
    let licence: AboutLicence
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    #if os(macOS)
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    private var metrics: ControlMetrics { ControlMetrics.current.scaled(by: typeScale) }
    /// Done is text, so it sits on the titles' baseline.
    private static let headerAlignment = VerticalAlignment.firstTextBaseline

    /// **The sheet is exactly as wide as the window it hangs from, and no wider.**
    /// The longest line in any of these texts is 78 columns, which at 11 pt
    /// monospace is 530 pt; with the standard gutter either side that is 558, just
    /// inside the About window's 560-pt minimum. So no licence line rewraps and the
    /// sheet never overhangs its parent — which the first width tried, 620, did.
    private static let inset = EdgeInsets(
        top: 20, leading: Metrics.gutter, bottom: 20, trailing: Metrics.gutter)
    private static let minimumWidth = CGFloat(AboutWindow.minimumWidth)
    private static let minimumHeight: CGFloat = 480
    #else
    /// The system sizes a sheet here, so the margin is free to be generous.
    private static let inset = EdgeInsets(top: 20, leading: 24, bottom: 20, trailing: 24)
    /// The ✕ is a 44 pt circle, so it is centred on the titles rather than
    /// hung from their baseline, which left them riding above its middle.
    private static let headerAlignment = VerticalAlignment.center
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: Self.headerAlignment, spacing: Metrics.md) {
                // `dismiss` is right here, unlike in the top-level sheets: this
                // one is presented from `readingLicence`, which the dismissal
                // puts back to `nil` itself.
                #if !os(macOS)
                SheetCloseButton { dismiss() }
                #endif
                HStack(alignment: .firstTextBaseline, spacing: Metrics.md) {
                    Text(licence.component)
                        .font(Typography.readoutEmphasis)
                        .foregroundStyle(palette.text.color())
                    Text(licence.terms)
                        .font(Typography.readoutSmall)
                        .foregroundStyle(palette.accent.color())
                }
                Spacer(minLength: Metrics.md)
                // The Mac keeps Done at the trailing end, where a Mac sheet's
                // button goes; iOS has the Close button at the leading end.
                #if os(macOS)
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent.color())
                    .hitRegion(target: metrics.target, drawn: metrics.chromeHeight)
                    .keyboardShortcut(.defaultAction)
                #endif
            }
            .padding(Self.inset)
            Rectangle().fill(palette.rule.color()).frame(height: Metrics.hairline)
            ScrollView {
                Text(licence.fullText ?? "This build is missing its copy of this licence.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.text.color())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Self.inset)
            }
        }
        .background(palette.background.color())
        .environment(\.palette, palette)
        #if os(macOS)
        .frame(minWidth: Self.minimumWidth, minHeight: Self.minimumHeight)
        #else
        .presentationDetents([.large])
        #endif
    }
}
