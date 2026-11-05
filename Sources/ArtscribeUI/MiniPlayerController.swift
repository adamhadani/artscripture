import Observation
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// The picture in a small window of its own, floating over other apps.
///
/// One per app, built with the model it drives — a required `init` argument,
/// so there is no version of this object that is connected to nothing (the
/// interruption callbacks' lesson in `CLAUDE.md`). When it appears is
/// `MiniPlayerPolicy`'s decision; this class only translates the platform's
/// events into that vocabulary and draws the result.
///
/// **On the Mac it is our own panel**, not the system's Picture in Picture: a
/// spike on macOS 27.2 found sample-buffer PiP still draws the layer at its own
/// size into a smaller window, cutting off the top and right of the frame.
@MainActor
public final class MiniPlayerController {
    private let model: ViewerModel
    private var state = MiniPlayerState()

    #if os(macOS)
    private var panel: MiniPlayerPanel?
    private var observers: [NSObjectProtocol] = []
    #endif

    public init(model: ViewerModel) {
        self.model = model
        #if os(macOS)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.handle(.appResigned) } },
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.handle(.appActivated) } }
        ]
        #endif
        observeTrack()
    }

    public var isShowing: Bool { state.isShowing }

    /// View ▸ Picture in Picture, `⇧I`, and the panel's corner button.
    public func toggleByUser() { handle(.userToggled) }

    public func handle(_ event: MiniPlayerEvent) {
        refreshFacts()
        let (showing, byUser) = MiniPlayerPolicy.next(state, on: event)
        state.openedByUser = byUser
        guard showing != state.isShowing else { return }
        state.isShowing = showing
        model.video?.isFloating = showing
        if showing { present() } else { dismiss() }
    }

    /// The play button: the same call as `Space`, so preroll, loops and Now
    /// Playing behave exactly as they do from the keyboard.
    func playPause() { model.togglePlayPause() }

    private func refreshFacts() {
        state.hasVideo = model.hasVideo
        state.isPlaying = model.isPlaying
        state.isPanelShown = model.prefs.video.shown
        state.floatsWhenInactive = model.prefs.video.floatsWhenInactive
    }

    /// A new file, or none: the window follows the picture or goes with it.
    private func observeTrack() {
        withObservationTracking {
            _ = model.video
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handle(.trackChanged)
                if self.state.isShowing {
                    self.model.video?.isFloating = true
                    #if os(macOS)
                    self.panel?.fit(to: self.model.video?.info.displaySize)
                    #endif
                }
                self.observeTrack()
            }
        }
    }

    #if os(macOS)
    private func present() {
        let panel = self.panel ?? MiniPlayerPanel(onClose: { [weak self] in self?.handle(.closed) })
        self.panel = panel
        panel.show(
            MiniPlayerView(model: model, playPause: { [weak self] in self?.playPause() }),
            aspect: model.video?.info.displaySize)
    }

    private func dismiss() {
        panel?.hide()
    }
    #else
    // iOS: the system's Picture in Picture arrives in the iOS pass; until then
    // `MiniPlayerSupport.isAvailable` keeps the menu item disabled there.
    private func present() {}
    private func dismiss() {}
    #endif
}

#if os(macOS)
/// A floating, non-activating panel.
///
/// **Non-activating** so its play button does not bring Artscripture to the
/// front — which would make the policy close the very window just used.
/// **`hidesOnDeactivate = false`** because a panel hides when its app
/// deactivates by default, and that is exactly when this one is for.
final class MiniPlayerPanel: NSPanel {
    private let onClose: () -> Void
    private static let autosaveName = "MiniPlayer"
    /// The long side of a first-time window, before the user resizes it.
    private static let defaultLongSide: CGFloat = 400

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 225),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        backgroundColor = .black
        title = "Video"
    }

    // A non-activating panel still has to take clicks for its buttons.
    override var canBecomeKey: Bool { true }

    func show(_ content: some View, aspect: CGSize?) {
        contentView = FirstMouseHostingView(rootView: AnyView(content))
        fit(to: aspect)
        if !setFrameUsingName(Self.autosaveName) { placeAtTopRight() }
        setFrameAutosaveName(Self.autosaveName)
        orderFrontRegardless()
    }

    /// Keeps the window the shape of the picture.
    func fit(to aspect: CGSize?) {
        guard let aspect, aspect.width > 0, aspect.height > 0 else { return }
        contentAspectRatio = aspect
        var frame = self.frame
        frame.size.height = frame.width * aspect.height / aspect.width
        setFrame(frame, display: true)
    }

    func hide() {
        orderOut(nil)
        // Dropping the content detaches its surface from the presenter, so a
        // hidden window costs nothing per frame.
        contentView = nil
    }

    override func close() {
        hide()
        onClose()
    }

    private func placeAtTopRight() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let aspect = contentAspectRatio
        let landscape = aspect.width >= aspect.height
        let width =
            landscape ? Self.defaultLongSide : Self.defaultLongSide * aspect.width / aspect.height
        let height = width * aspect.height / max(aspect.width, 1)
        let margin: CGFloat = 20
        setFrame(
            NSRect(
                x: screen.maxX - width - margin, y: screen.maxY - height - margin,
                width: width, height: height),
            display: true)
    }
}

/// A click on an inactive floating window should press the button under it,
/// not merely bring the window forward.
private final class FirstMouseHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
#endif
