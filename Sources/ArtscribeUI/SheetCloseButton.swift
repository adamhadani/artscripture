#if !os(macOS)
import SwiftUI
import UIKit

/// **The way out of a sheet on iPhone and iPad**: a plain ✕ at the sheet's top
/// leading corner.
///
/// Practice, the shortcut reference and About used to have no button at all —
/// a swipe down was the only way back, and on a landscape iPhone, where a sheet
/// covers the whole screen and nothing of the document shows behind it, a
/// tester could not tell that it was a sheet rather than a new screen.
///
/// Apple's guidance, as of the sheet button-placement update (March 2026):
/// *"Always give people an obvious way to dismiss a modal view"*, the Close
/// button *"dismisses a sheet without saving any changes"*, and in a
/// single-view sheet it *"belongs on the leading edge of the top toolbar"*.
/// `ButtonRole.close` is the role for exactly this — *"unlike a cancel
/// operation, a close operation doesn't lose progress"* — which is true of
/// every one of these sheets: each applies its settings as they change, so
/// there is nothing to confirm and nothing to lose.
///
/// ## Why a bare glyph, and not the system's glass ✕
///
/// The first version (1.4, build 186) was the system's own Close: a 44 pt glass
/// circle. It worked and it looked bolted on — the only round, glassy, full-size
/// shape in sheets whose headers are a 9 pt monospaced eyebrow over a hairline
/// rule. Four alternatives were rendered on a phone side by side (a teal
/// "⌄ Close" link, the ✕ in the header's square chrome, a "Close" pill, and
/// this); the user chose this one as *"minimalistic and clear"*. The ✕ itself
/// is what makes it clear — nobody needs it explained — so it needs no frame.
///
/// Drawn in `dimmed`, the colour of the eyebrow beside it: a control, not a
/// heading, but no louder than the heading. `dimmed` clears WCAG's 3:1 for
/// non-text controls on both themes: 4.1 dark and 4.8 light against the
/// sheets' `background` (see `Palette`).
///
/// **The ✕ is 11 pt across; what answers a finger is 44 × 44.** The same rule as
/// the rest of the chrome (`hitRegion`), applied on both axes because a glyph
/// is narrower than the target as well as shorter. The layout keeps the
/// glyph's own width, so the ✕ lines up with the sheet's content edge.
///
/// Settings, inside a `NavigationStack`, puts this same view in its toolbar
/// with the toolbar's glass turned off, so all four sheets close the same way.
/// The others draw their own header rows, which a navigation bar would sit on
/// top of and duplicate, so they carry it at the leading end of the row they
/// already have.
///
/// **Esc closes it** with a hardware keyboard on iPad. That does not fight the
/// document's own `Esc` (Clear Loop): while any sheet is up the menu's
/// key equivalents are disabled (`SheetFocus`), so the key reaches the sheet.
/// `escapeCloses: false` hands the key back where it means something nearer:
/// the shortcut filter's first Esc clears the filter, as on the Mac, and About
/// stands down while a licence is open over it so one Esc closes one sheet.
///
/// **A half-typed number is committed, not dropped.** Practice's and Settings'
/// fields are `TextField(value:format:)`, which write back on Return or on
/// losing focus; the sheet going away is not reliably either. So the button
/// ends editing first (`endEditing()`), and the edit lands before the close.
///
/// The action is required, not optional — a close button wired to nothing is
/// exactly the shape of defect `TransportLink` was made non-optional to stop.
/// It sets the controller's `isPresented` rather than calling `dismiss`, for
/// the reason `SettingsSheet` gives: a sheet dismissed behind its controller's
/// back leaves the next ⌘P toggling a sheet it thinks is still up.
struct SheetCloseButton: View {
    var escapeCloses = true
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    /// Read here rather than taking `\.palette`: Settings is a system form and
    /// never sets one, and the environment's default palette is the dark one.
    @Environment(\.colorScheme) private var colorScheme

    /// The glyph against the touch chrome's `glyph` (18 pt): an ✕ is all
    /// diagonals and reads larger than its point size, and at full size it
    /// outweighed the eyebrow beside it.
    private static let glyphScale: CGFloat = 0.8

    /// Resigns whatever text field has the keyboard, which is what makes a
    /// `TextField(value:format:)` write its edit back.
    @MainActor
    static func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    var body: some View {
        // Scaled with Dynamic Type like the rest of the chrome, so the ✕
        // grows with the header text beside it.
        let metrics = ControlMetrics.current.scaled(by: typeScale)
        let glyph = metrics.glyph * Self.glyphScale
        let palette = Palette.of(colorScheme == .dark ? .dark : .light)
        let across = max(0, (metrics.target - glyph) / 2)
        let down = max(0, (metrics.target - metrics.chromeHeight) / 2)
        Button(role: .close) {
            Self.endEditing()
            action()
        } label: {
            // An explicit glyph: `role: .close` draws the ✕ only inside a
            // toolbar, and anywhere else it draws the word "Close".
            Image(systemName: "xmark")
                .font(.system(size: glyph, weight: .medium))
                // Pinned: a toolbar draws its symbols a scale up, which made
                // Settings' ✕ 14 pt across where the others are 11 — measured
                // off the screenshots, not visible in the code.
                .imageScale(.medium)
                .foregroundStyle(palette.dimmed.color())
                .frame(height: metrics.chromeHeight)
                // `hitRegion`'s pad out, claim it, pad back in — on both axes
                // at once, since a glyph is narrower than the target as well
                // as shorter. One shape: two nested ones would leave which
                // wins up to SwiftUI.
                .padding(.horizontal, across)
                .padding(.vertical, down)
                .contentShape(.rect)
                .padding(.horizontal, -across)
                .padding(.vertical, -down)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(escapeCloses ? .cancelAction : nil)
        .accessibilityLabel("Close")
        .help(escapeCloses ? "Close  (Esc)" : "Close")
    }
}
#endif
