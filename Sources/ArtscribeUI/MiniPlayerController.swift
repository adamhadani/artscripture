import Observation
import SwiftUI

#if os(macOS)
import AppKit
#else
import AVKit
import UIKit
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
/// **On iOS it is the system's**, the only way to float over another app; see
/// `MiniPlayerController+iOS`.
@MainActor
public final class MiniPlayerController {
    let model: ViewerModel
    var state = MiniPlayerState()
    /// `false` only in unit tests, where a real floating window would cross
    /// every Space on the developer's screen for each run of `make check`.
    private let showsWindows: Bool

    #if os(macOS)
    private var panel: MiniPlayerPanel?
    private var observers: [NSObjectProtocol] = []
    #else
    var pip: AVPictureInPictureController?
    var pipDelegate: PictureInPictureDelegate?
    weak var pipSurface: VideoSurfaceView?
    var observers: [NSObjectProtocol] = []
    var isInBackground = false
    #endif

    public init(model: ViewerModel, showsWindows: Bool = true) {
        self.model = model
        self.showsWindows = showsWindows
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
        #else
        // Only coming back: going away is the system's to act on, through
        // `canStartPictureInPictureAutomaticallyFromInline`.
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.handle(.appActivated) } },
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.setInBackground(true) } },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in MainActor.assumeIsolated { self?.setInBackground(false) } }
        ]
        observePlaying()
        #endif
        observeTrack()
    }

    /// The main panel's surface, which iOS's Picture in Picture takes its
    /// picture from. A no-op on the Mac, whose mini player has its own.
    public func adopt(surface: VideoSurfaceView) {
        #if !os(macOS)
        adoptPictureInPictureSource(surface)
        #endif
    }

    public func release(surface: VideoSurfaceView) {
        #if !os(macOS)
        releasePictureInPictureSource(surface)
        #endif
    }

    public var isShowing: Bool { state.isShowing }

    /// View ▸ Picture in Picture, `⇧I`, and the panel's corner button.
    public func toggleByUser() { handle(.userToggled) }

    public func handle(_ event: MiniPlayerEvent) {
        refreshFacts()
        let (showing, byUser) = MiniPlayerPolicy.next(state, on: event)
        state.openedByUser = byUser
        #if !os(macOS)
        updateAutomaticStart()
        #endif
        guard showing != state.isShowing else { return }
        state.isShowing = showing
        model.video?.isFloating = showing
        guard showsWindows else { return }
        if showing { present() } else { dismiss() }
    }

    /// The play button: the same call as `Space`, so preroll, loops and Now
    /// Playing behave exactly as they do from the keyboard.
    func playPause() { model.togglePlayPause() }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func refreshFacts() {
        // A picture that could not be opened has nothing to float: the panel
        // shows its reason, and a mini player would be an empty black window.
        state.hasVideo = model.videoPresenter != nil
        state.isPlaying = model.isPlaying
        state.isPanelShown = model.prefs.video.shown
        state.floatsWhenInactive = model.prefs.video.floatsWhenInactive
    }

    /// A new file, or none: the window follows the picture or goes with it.
    private func observeTrack() {
        withObservationTracking {
            _ = model.video
            _ = model.prefs.video
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
    /// A first-time window's distance from the screen's top-right corner.
    private static let screenMargin: CGFloat = 20

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(
            contentRect: NSRect(
                x: 0, y: 0, width: Self.defaultLongSide, height: Self.defaultLongSide * 9 / 16),
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
        if let aspect, aspect.width > 0, aspect.height > 0 { contentAspectRatio = aspect }
        // Where the user left it, then the shape of *this* clip — in that
        // order, or a landscape clip's saved frame squashes a portrait one.
        if !setFrameUsingName(Self.autosaveName) { placeAtTopRight() }
        setFrameAutosaveName(Self.autosaveName)
        fit(to: aspect)
        orderFrontRegardless()
    }

    /// Keeps the window the shape of the picture.
    func fit(to aspect: CGSize?) {
        guard let aspect, aspect.width > 0, aspect.height > 0 else { return }
        contentAspectRatio = aspect
        setFrame(Self.reshaped(frame, to: aspect), display: true)
    }

    /// `frame` given `aspect`, keeping its area and its top-left corner — so
    /// a window moves neither its position nor its overall size when a clip
    /// of another shape arrives.
    static func reshaped(_ frame: NSRect, to aspect: CGSize) -> NSRect {
        let area = frame.width * frame.height
        let width = (area * aspect.width / aspect.height).squareRoot()
        let height = width * aspect.height / aspect.width
        return NSRect(x: frame.minX, y: frame.maxY - height, width: width, height: height)
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
        setFrame(
            NSRect(
                x: screen.maxX - width - Self.screenMargin,
                y: screen.maxY - height - Self.screenMargin,
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
