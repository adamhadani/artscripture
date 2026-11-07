import SwiftUI

/// What the header's overflow menu can open.
///
/// A value rather than a closure per surface on `TitleBarView`, so adding one
/// is one field here and one line in the menu rather than a change to the
/// view's shape and to every call site.
///
/// Practice is not here. It was, until it got a button of its own in the
/// header (`PracticeButton`): it is the feature, not a destination beside About.
struct AuxiliaryMenuActions {
    let settings: () -> Void
    let shortcuts: () -> Void
    let about: () -> Void
}

/// The header: wordmark, the loaded file, the decode progress bar, and the
/// Practice button.
struct TitleBarView: View {
    let model: ViewerModel
    let onOpen: () -> Void
    /// Opens Practice — a window on the Mac, a sheet on iPad and iPhone. The
    /// button shows only while a track is open, on every platform.
    ///
    /// **Required, with no default**, like `restoreFocus` below: a closure that
    /// may be `nil` is a wire that may not be connected (CLAUDE.md), and a call
    /// site that forgot this would hide the app's main feature without a word.
    ///
    /// `DocumentView` passes `practice.show()`, not the menu's `toggle()`: a
    /// button labelled Practice should never be the thing that closes it. On
    /// the Mac a click here has already made the document key, so the two would
    /// agree anyway; on iPad the sheet covers the button.
    let onPractice: () -> Void
    /// Hands the keyboard back to the document after a press. See
    /// `TransportBarView` for why this is not optional in a keyboard-first app.
    let restoreFocus: () -> Void
    /// **The only route to the auxiliary surfaces on a touch-only device.**
    ///
    /// iPadOS has a menu bar, but reaching it needs a hardware keyboard — so on
    /// a phone, or an iPad without one, `⌘,` and `⌘/` reach nothing at all.
    /// Settings and About had been given buttons; the shortcut reference never
    /// was, and so simply did not exist on those devices.
    ///
    /// One menu rather than a button each: the header is already tight on a
    /// phone, and this is the shape iOS uses for exactly this — a set of
    /// destinations that are not the primary action. macOS passes nil; it has
    /// the menu bar.
    var auxiliary: AuxiliaryMenuActions?
    /// Puts the track away, returning to the resting screen and its recents.
    ///
    /// A **leading** control, which is where every Apple document app puts the
    /// way back to its library — Pages, Numbers and GarageBand all do this. On
    /// macOS it is nil: the File menu and ⇧⌘W carry it, and a Mac window does
    /// not have a "back".
    var onClose: (() -> Void)?
    @Environment(\.palette) private var palette
    #if !os(macOS)
    /// Split View, Slide Over and a narrow Stage Manager window are compact
    /// on an iPad; see `PracticeButtonFace.prefersCompact`.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    /// Follows the user's text-size setting. A plain `CGFloat` scaled by the
    /// body text style, used as a *factor* rather than as a size, because the
    /// base value depends on the surface and `@ScaledMetric` takes a literal.
    /// See `ControlMetrics.scaled(by:)` for why it is clamped.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    private var metrics: ControlMetrics { ControlMetrics.current.scaled(by: typeScale) }
    /// The decode progress bar. Fixed, so the header does not reflow as
    /// the phase label changes length underneath it.
    private static let progressWidth: CGFloat = 130
    #if os(macOS)
    /// Computed, not stored: a stored `private` property would make the
    /// synthesised memberwise initialiser private too, and `DocumentView`
    /// constructs this. Reading `.leading` inside `body` is what registers the
    /// observation, so this still follows a full-screen transition.
    private var trafficLights: TrafficLightInset { .shared }
    #endif

    var body: some View {
        HStack(spacing: Metrics.gutter) {
            if let onClose, model.hasTrack {
                Button(action: onClose) {
                    // Chevron plus a word: the glyph alone reads as "undo" or
                    // "previous track" on something with a transport bar.
                    Label("Close", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .font(Typography.readoutSmall)
                        .foregroundStyle(palette.accent.color())
                        // The words are 10 pt tall; the region that answers a
                        // thumb is not. `contentShape` after the frame is what
                        // makes the padding tappable rather than merely empty.
                        .hitRegion(target: metrics.target, drawn: metrics.chromeHeight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close track")
            }

            Text("ARTSCRIPTURE")
                .font(Typography.eyebrow)
                .tracking(2.2)
                .foregroundStyle(palette.accent.color(opacity: 0.85))

            Rectangle()
                .fill(palette.rule.color())
                .frame(width: Metrics.hairline, height: 14)

            Text(model.fileName ?? "No file open")
                .font(Typography.fileName)
                .foregroundStyle(
                    model.fileName == nil
                        ? palette.dimmed.color() : palette.text.color()
                )
                .lineLimit(1)
                .truncationMode(.middle)

            // The session-fallback banner, put away (`ViewerModel+FallbackNotice`).
            // Still on screen, because the condition it describes still holds.
            if model.showsFallbackBadge {
                Button(action: model.expandFallbackNotice) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: metrics.glyph * 0.8))
                        .foregroundStyle(palette.emphasis.color())
                        .hitRegion(target: metrics.target, drawn: metrics.chromeHeight)
                }
                .buttonStyle(.plain)
                .help("This track's session is stored in Application Support. Show why.")
                .accessibilityLabel("Session stored away from the track. Show details")
            }

            // The read-only sidecar fallback used to be indicated here, then in
            // the inspector's chrome. It is now an inline banner beside the
            // decode and device notices — see `SessionFallbackBanner`.

            Spacer(minLength: Metrics.xl)

            if model.isLoading {
                HStack(spacing: Metrics.md) {
                    Text(model.loadPhase?.label ?? "Loading…")
                        .font(Typography.readoutSmall)
                        .foregroundStyle(palette.dimmed.color())
                    ProgressView(value: model.progress)
                        .progressViewStyle(.linear)
                        .tint(palette.accent.color())
                        .frame(width: Self.progressWidth)
                    Text("\(Int((model.progress * 100).rounded()))%")
                        .font(Typography.readoutSmall)
                        .foregroundStyle(palette.dimmed.color())
                        .monospacedDigit()
                }
            }

            if model.hasTrack {
                PracticeButton(
                    face: PracticeButtonFace.face(
                        for: model.ramp, speed: model.speed.ratio, compact: compactPractice),
                    metrics: metrics,
                    onOpen: {
                        // Focus first, *then* the window or sheet: restoring it
                        // afterwards would point the keyboard back at the
                        // document behind a Practice surface that has just
                        // taken it. Done before, the document is the one that
                        // has it when Practice is put away again.
                        restoreFocus()
                        onPractice()
                    },
                    onStop: {
                        model.stopRamp()
                        restoreFocus()
                    })
            }

            // `⋯` and Open… sit closer to each other than to Practice: two
            // groups, the primary action and the utilities, which is how Apple's
            // toolbar guidance asks related items to be gathered.
            HStack(spacing: Metrics.sm) {
                auxiliaryMenu
                openButton
            }
        }
        .padding(.horizontal, Metrics.gutter)
        // Clear of the window's traffic lights, which macOS draws on top of this
        // header — the wordmark used to read `A ● ● ● IBE`. Measured rather than
        // assumed so that full screen, where the buttons are removed, gets no
        // gap. See `TrafficLightInset`.
        #if os(macOS)
        .padding(.leading, trafficLights.leading)
        #endif
        .padding(.vertical, metrics.barPadding)
        .background(palette.background.color())
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.rule.color()).frame(height: Metrics.hairline)
        }
    }

    private var compactPractice: Bool {
        #if os(macOS)
        let horizontallyCompact = false
        #else
        let horizontallyCompact = horizontalSizeClass == .compact
        #endif
        return PracticeButtonFace.prefersCompact(
            surface: EmptyStatePrompt.current, horizontallyCompact: horizontallyCompact)
    }

    @ViewBuilder private var auxiliaryMenu: some View {
        if let auxiliary {
            Menu {
                Button("Settings…", systemImage: "gearshape", action: auxiliary.settings)
                Button(
                    "Keyboard Shortcuts", systemImage: "keyboard",
                    action: auxiliary.shortcuts)
                // Only for a video file, like the transport's Video button:
                // without a hardware keyboard there is no View menu.
                if model.hasVideo {
                    Toggle(
                        isOn: Binding(
                            get: { model.prefs.video.shown },
                            set: { _ in model.toggleVideo() })
                    ) {
                        Label("Video", systemImage: "film")
                    }
                }
                Divider()
                // A phone has no menu bar, so this and the Loop button's
                // long press are its only ways to remove a loop.
                Button("Clear Loop", systemImage: "xmark.circle", role: .destructive) {
                    model.clearLoop()
                }
                .disabled(model.loop.range.isEmpty)
                Divider()
                Button(
                    "About Artscripture", systemImage: "info.circle", action: auxiliary.about)
            } label: {
                // **The control this whole file was reopened for.** It was a
                // bare 15 pt glyph: a 15 × 15 pt target, on the one route to
                // Settings, Shortcuts and About that a device without a
                // hardware keyboard has. Then it was `ellipsis.circle` — a ring
                // drawn smaller than the buttons either side of it, which is
                // most of why the header's trailing end looked like three
                // unrelated shapes. It is now a square in Open…'s own chrome.
                Image(systemName: "ellipsis")
                    .font(.system(size: metrics.glyph * 0.85, weight: .semibold))
                    .foregroundStyle(palette.text.color())
                    .frame(width: metrics.chromeHeight, height: metrics.chromeHeight)
                    .controlChrome(
                        metrics, fill: palette.panel.color(), stroke: palette.rule.color()
                    )
                    .hitRegion(target: metrics.target, drawn: metrics.chromeHeight)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
    }

    private var openButton: some View {
        Button("Open…", action: onOpen)
            .buttonStyle(.plain)
            .font(Typography.readout)
            .foregroundStyle(palette.text.color())
            .padding(.horizontal, metrics.groupPadding * 1.4)
            .frame(minHeight: metrics.chromeHeight)
            .controlChrome(metrics, fill: palette.panel.color(), stroke: palette.rule.color())
            .fixedSize()
            .hitRegion(target: metrics.target, drawn: metrics.chromeHeight)
    }
}

/// A decode failure, shown in place rather than as a modal. The previously
/// loaded track is still on screen behind it (spec §8).
struct ErrorBannerView: View {
    @Environment(\.palette) private var palette
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.danger.color())
                .font(.system(size: 12))
            Text(message)
                .font(Typography.bannerBody)
                .foregroundStyle(palette.text.color())
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Metrics.md)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .font(Typography.readoutSmall)
                .foregroundStyle(palette.dimmed.color())
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.lg)
        .background(palette.danger.color(opacity: 0.12))
        .overlay(alignment: .leading) {
            Rectangle().fill(palette.danger.color()).frame(width: Metrics.accentBar)
        }
    }
}

/// **Spec §8: the read-only-sidecar fallback**, standing in the banner stack.
///
/// The track's folder could not be written to, so its session went into
/// Application Support instead of next to the music. Spec §7 forbids loop
/// points being silently lost because a directory was read-only, and this is
/// the "not silently" half.
///
/// Two things it is not, both deliberate. It does not **vanish** when dismissed:
/// the four banners above it announce events, and this announces a *condition*,
/// so Dismiss collapses it to a badge by the file name (1.2), which brings it
/// back — something on screen always says where your session went. And it is not
/// the `danger` red: nothing failed, the fallback worked. `emphasis` is this
/// palette's "you should know about this" colour, and it is the same amber the
/// status bar uses for a speed that is not 100%.
///
/// Task 19 parked it in the title bar for want of anywhere better; Task 20 moved
/// it into the inspector's chrome, following §8's wording; Task 25 removed the
/// inspector and it landed here, where this window already keeps everything it
/// has to say.
struct SessionFallbackBanner: View {
    let model: ViewerModel
    @Environment(\.palette) private var palette

    var body: some View {
        if model.showsFallbackBanner {
            HStack(alignment: .top, spacing: Metrics.lg) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(palette.emphasis.color())
                    .font(.system(size: 12))
                Text(ViewerModel.fallbackNotice(reason: model.sessionFallbackReason))
                    .font(Typography.bannerBody)
                    .foregroundStyle(palette.text.color())
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Metrics.md)
                // Collapses to the title bar's badge rather than vanishing: the
                // condition holds, so something has to keep saying so.
                Button("Dismiss", action: model.collapseFallbackNotice)
                    .buttonStyle(.plain)
                    .font(Typography.readoutSmall)
                    .foregroundStyle(palette.dimmed.color())
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, Metrics.lg)
            .background(palette.emphasis.color(opacity: 0.12))
            .overlay(alignment: .leading) {
                Rectangle().fill(palette.emphasis.color()).frame(width: Metrics.accentBar)
            }
        }
    }
}
