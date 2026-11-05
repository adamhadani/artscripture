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
