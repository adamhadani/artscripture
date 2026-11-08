#if !os(macOS)
import SwiftUI
import UIKit

/// **The way out of a sheet on iPhone and iPad**: the system's Close button, at
/// the sheet's top leading corner.
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
/// Settings, inside a `NavigationStack`, puts the same role in its toolbar
/// instead and gets the same glass ✕ from the system. The others draw their
/// own header rows, which a navigation bar would sit on top of and duplicate,
/// so they carry this view at the leading end of the row they already have.
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

    /// The toolbar's own ✕ glyph weight, measured off Settings' button.
    private static let glyph: CGFloat = 17

    /// Resigns whatever text field has the keyboard, which is what makes a
    /// `TextField(value:format:)` write its edit back. Settings' toolbar Close
    /// calls it too.
    @MainActor
    static func endEditing() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// **Drawn at the full target, unlike the app's other chrome** — the one
    /// exception to "44 is a hit region, not a drawn size", and on purpose.
    /// Settings gets its ✕ from the system toolbar, which draws a 44 pt glass
    /// circle; `.buttonStyle(.glass)` outside a toolbar drew 30 pt, so the same
    /// button was two sizes depending on which sheet you opened, and the
    /// smaller one was under Apple's 44 pt minimum. This is the button people
    /// already know from Apple's own sheets, so it is drawn at Apple's size.
    /// Scaled with Dynamic Type like the rest of the chrome, so it grows with
    /// the header text beside it.
    private var side: CGFloat { ControlMetrics.current.scaled(by: typeScale).target }

    var body: some View {
        // The glyph is spelled out. In a toolbar the role alone draws the ✕;
        // anywhere else it draws the word "Close".
        Button(role: .close) {
            Self.endEditing()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: Self.glyph * typeScale, weight: .medium))
                .frame(width: side, height: side)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .keyboardShortcut(escapeCloses ? .cancelAction : nil)
        .accessibilityLabel("Close")
        .help(escapeCloses ? "Close  (Esc)" : "Close")
    }
}
#endif
