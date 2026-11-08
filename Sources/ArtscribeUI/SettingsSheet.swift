#if !os(macOS)
import SwiftUI

/// **Settings, on iPad.** The macOS window's two tabs, in a sheet.
///
/// Deliberately the *same* `SettingsView` the Mac shows rather than a parallel
/// iPad layout. Two implementations of one settings screen is two places to add
/// every future preference to, and the one that gets forgotten is always the
/// platform the author is not using that week — the reason this screen was
/// missing on iPad in the first place.
///
/// What differs is only the frame around it: a `NavigationStack` for a title and
/// a **close** button, because a sheet needs a way out that does not depend on
/// knowing you can swipe it down.
struct SettingsSheet: View {
    let model: ViewerModel
    let theme: ThemeController
    let settings: SettingsWindowController
    let welcome: WelcomeState
    let recents: RecentFiles

    var body: some View {
        NavigationStack {
            SettingsView(model: model, theme: theme, welcome: welcome, recents: recents)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Close, leading, not Done, trailing: every setting here
                    // applies as it changes, so there is nothing to confirm,
                    // and Apple's sheet guidance (March 2026) is that a lone
                    // Done *"implies that completing the task is the only way
                    // to exit"*. The same ✕ as the other sheets, and without
                    // the toolbar's glass behind it — the system's glass ✕ is
                    // what 1.4 first shipped and replaced (`SheetCloseButton`).
                    ToolbarItem(placement: .cancellationAction) {
                        // Closes through the controller, not `dismiss`: the
                        // sheet's presentation *is* `AuxiliaryWindow.isPresented`,
                        // and dismissing without putting that back would leave
                        // the next ⌘, toggling it "closed" and appearing dead.
                        // The same defect the shortcut and Practice sheets had.
                        // The button ends editing first, so a half-typed nudge
                        // is kept, and takes Esc.
                        SheetCloseButton { settings.windowState.isPresented = false }
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
        }
    }
}
#endif
