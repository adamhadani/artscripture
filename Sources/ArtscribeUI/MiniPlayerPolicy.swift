/// The facts the mini player's decision depends on, read fresh at each event.
public struct MiniPlayerState: Equatable, Sendable {
    public var isShowing = false
    /// Opened with View ▸ Picture in Picture rather than by leaving the app:
    /// it then stays until closed, instead of going when the app comes back.
    public var openedByUser = false
    public var hasVideo = false
    /// The picture is showing in the window. Hidden there means the user does
    /// not want it, and it does not reappear in a floating window instead.
    public var isPanelShown = true
    /// The transport's answer, never the audio graph's: the graph runs for
    /// every open document, paused or not (`CLAUDE.md`, "was playing").
    public var isPlaying = false
    /// Settings ▸ Video ▸ Float video when switching apps.
    public var floatsWhenInactive = true

    public init(
        isShowing: Bool = false, openedByUser: Bool = false, hasVideo: Bool = false,
        isPanelShown: Bool = true, isPlaying: Bool = false, floatsWhenInactive: Bool = true
    ) {
        self.isShowing = isShowing
        self.openedByUser = openedByUser
        self.hasVideo = hasVideo
        self.isPanelShown = isPanelShown
        self.isPlaying = isPlaying
        self.floatsWhenInactive = floatsWhenInactive
    }
}

public enum MiniPlayerEvent: Sendable {
    /// The app stopped being frontmost.
    case appResigned
    /// The app came back to the front.
    case appActivated
    /// View ▸ Picture in Picture, `⇧I`, or the panel's corner button.
    case userToggled
    /// The window's own close button, or the system dismissing it.
    case closed
    /// A different file — or none — is now open.
    case trackChanged
}

/// When the picture floats in its own small window.
///
/// Pure, so the rule is tested without a window, and one table serves the
/// Mac's floating panel and iOS's Picture in Picture alike — like
/// `AudioSessionPolicy`, the platform code only translates events into this
/// vocabulary.
public enum MiniPlayerPolicy {
    /// The new `(isShowing, openedByUser)`.
    public static func next(
        _ state: MiniPlayerState, on event: MiniPlayerEvent
    ) -> (isShowing: Bool, openedByUser: Bool) {
        guard state.hasVideo else { return (false, false) }
        let unchanged = (state.isShowing, state.openedByUser)
        switch event {
        case .appResigned:
            guard !state.isShowing else { return unchanged }
            // Playing, because a window appearing every time you click away
            // from a paused track would be noise; iOS asks the same.
            let floats = state.isPlaying && state.isPanelShown && state.floatsWhenInactive
            return floats ? (true, false) : unchanged
        case .appActivated:
            return state.openedByUser ? unchanged : (false, false)
        case .userToggled:
            return state.isShowing ? (false, false) : (true, true)
        case .closed:
            return (false, false)
        case .trackChanged:
            return unchanged
        }
    }
}

/// What iOS's Picture in Picture asks of the app, answered without AVKit so it
/// is tested in `make check`. The AVKit delegate only forwards to these.
public enum PictureInPictureBridge {
    /// The window's play button says which state it wants. A request that is
    /// already true changes nothing: the system repeats itself, and passing a
    /// repeat on as a toggle would undo it.
    public static func shouldToggle(requestedPlaying: Bool, isPlaying: Bool) -> Bool {
        requestedPlaying != isPlaying
    }

    /// Whether the system may float the picture by itself when the app goes
    /// to the background — the Mac's rule, less "playing", which the system
    /// checks for itself.
    public static func startsAutomatically(_ state: MiniPlayerState) -> Bool {
        state.hasVideo && state.isPanelShown && state.floatsWhenInactive
    }

    /// The window's ± skip, in frames for the model's seek.
    public static func frames(forSkip seconds: Double, sampleRate: Double) -> Int64 {
        guard sampleRate > 0 else { return 0 }
        return Int64((seconds * sampleRate).rounded())
    }
}
