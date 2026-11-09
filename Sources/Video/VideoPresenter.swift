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
    /// The last of the source's answers this presenter fell back on, so one is
    /// never shown twice — not even after an exact frame replaced it.
    private var fallenBackOn = 0

    /// No decoding while set: iOS in the background with no Picture in
    /// Picture, where nobody can see the picture and the audio background
    /// mode would otherwise keep the decoder running on battery.
    public var isSuspended = false {
        didSet {
            guard isSuspended, !oldValue else { return }
            lastPlan = nil
            source.release()
        }
    }

    public init(source: VideoFrameSource) {
        self.source = source
        self.info = source.info
    }

    /// Why the picture cannot be shown, when it cannot.
    public var failure: String? { source.failure }

    /// Resolves once the decoder has caught up with every request so far.
    public func idle() async { await source.idle() }

    public func update(_ snapshot: PlaybackSnapshot) {
        surfaces.removeAll { $0.surface == nil }
        // Nothing is showing the picture, so nothing is decoded: a hidden panel
        // costs no CPU.
        guard !isClosed, !isSuspended, !surfaces.isEmpty else { return }
        let plan = FramePlan.make(snapshot, info: info)
        if plan != lastPlan {
            lastPlan = plan
            source.request(plan)
        }
        // A miss keeps the frame already on screen: holding the last picture
        // for a tick while a seek decodes beats a black flash. Paused — a
        // scrub, a click, a nudge — it shows the decoder's newest answer
        // instead, if there is one it has not shown: during a drag that is the
        // picture of where the finger just was, so the frames change while the
        // finger moves rather than only when it stops (`VideoFrameSource`).
        guard let frame = source.frame(at: snapshot.position) ?? newAnswer(snapshot),
            frame.pts != shownPTS
        else { return }
        current = frame
        shownPTS = frame.pts
        for entry in surfaces { entry.surface?.show(frame) }
    }

    /// The source's latest answer, once, when paused. Playing, a miss is a
    /// seek or a wrap catching up and the frame on screen holds: an answer
    /// can be for a position the sound has already left.
    private func newAnswer(_ snapshot: PlaybackSnapshot) -> DecodedFrame? {
        guard !snapshot.isPlaying, let answer = source.latestAnswer,
            answer.serial != fallenBackOn
        else { return nil }
        fallenBackOn = answer.serial
        return answer.frame
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
        // The last one gone: nothing shows the picture, so nothing need be
        // held for it. The next surface starts the plan afresh.
        if surfaces.isEmpty {
            lastPlan = nil
            source.release()
        }
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
