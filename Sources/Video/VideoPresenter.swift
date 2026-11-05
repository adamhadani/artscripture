/// Something that puts a decoded frame on screen: the panel, the mini player.
@MainActor
public protocol VideoSurface: AnyObject {
    func show(_ frame: DecodedFrame)
}

/// Chooses the picture for where the sound is, and shows it.
///
/// Driven from the playhead clock on **every** tick, paused as well as
/// playing, so a click, a nudge or a loop edge moved while paused shows that
/// frame. It is a pure function of the audible position — there is no video
/// clock — so the picture cannot drift from the sound; at worst it is a tick
/// late, or holds the previous frame while a seek decodes.
///
/// Called imperatively, never from a SwiftUI `body`: the tick is 60 Hz, and a
/// view that re-rendered with it would put the picture's cost into every
/// layout pass of the window.
@MainActor
public final class VideoPresenter {
    public let info: VideoTrackInfo
    private let source: VideoFrameSource
    private var surfaces: [WeakSurface] = []
    private var current: DecodedFrame?
    private var lastPlan: FramePlan?
    private var isClosed = false

    /// The presentation time of the frame on screen, for tests and the harness.
    public private(set) var shownPTS: Double?

    public init(source: VideoFrameSource) {
        self.source = source
        self.info = source.info
    }

    /// Why the picture cannot be shown, when it cannot.
    public var failure: String? { source.failure }

    public func update(_ snapshot: PlaybackSnapshot) {
        surfaces.removeAll { $0.surface == nil }
        // Nothing is showing the picture, so nothing is decoded: a hidden panel
        // costs no CPU.
        guard !isClosed, !surfaces.isEmpty else { return }
        let plan = FramePlan.make(snapshot, info: info)
        if plan != lastPlan {
            lastPlan = plan
            source.request(plan)
        }
        // A miss keeps the frame already on screen: holding the last picture
        // for a tick while a seek decodes beats a black flash.
        guard let frame = source.frame(at: snapshot.position), frame.pts != shownPTS else {
            return
        }
        current = frame
        shownPTS = frame.pts
        for entry in surfaces { entry.surface?.show(frame) }
    }

    /// Adds a surface and gives it the current frame at once — paused, the
    /// next change of frame might never come.
    public func attach(_ surface: VideoSurface) {
        guard !isClosed, !surfaces.contains(where: { $0.surface === surface }) else { return }
        surfaces.append(WeakSurface(surface: surface))
        if let current { surface.show(current) }
    }

    public func detach(_ surface: VideoSurface) {
        surfaces.removeAll { $0.surface == nil || $0.surface === surface }
    }

    /// For good: the decoder stops and no surface is shown anything more, so a
    /// frame of this file can never land on the next file's panel.
    public func close() {
        isClosed = true
        surfaces.removeAll()
        current = nil
        source.close()
    }
}

/// The presenter does not own what it draws into: a closed panel takes its
/// surface with it.
@MainActor
private struct WeakSurface {
    weak var surface: VideoSurface?
}
