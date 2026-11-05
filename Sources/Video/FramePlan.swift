/// Where the sound is, in the picture's terms: the one input the video takes.
///
/// Everything is seconds on the file's timeline. `position` is the **audible**
/// position — the playhead the UI already draws, compensated for the stretcher
/// and the output buffer — so a picture chosen from it is the picture of what
/// is being heard. There is no second clock to drift.
public struct PlaybackSnapshot: Equatable, Sendable {
    public var position: Double
    public var isPlaying: Bool
    /// Speed ratio: 0.5 is half speed. Never the stretcher's time ratio.
    public var speed: Double
    /// The loop, only while it is *active*. A drawn range with looping off is
    /// not a loop as far as what plays next is concerned.
    public var loop: Range<Double>?

    public init(position: Double, isPlaying: Bool, speed: Double, loop: Range<Double>?) {
        self.position = position
        self.isPlaying = isPlaying
        self.speed = speed
        self.loop = loop
    }
}

/// Which stretches of the picture must already be decoded.
///
/// Pure, so the rule that keeps the loop wrap seamless is tested without a
/// decoder. The rule is the picture's version of how the stretcher is fed: at
/// a loop's end what comes next is its start, so the frames there are decoded
/// *before* the wrap arrives — and stay decoded (`loopHead`) for as long as the
/// loop is on, because re-reading them at the wrap is a seek into a GOP that
/// can be seconds long, and a stall at every repetition.
public struct FramePlan: Equatable, Sendable {
    /// The window around the position, in playing order: one range, or two
    /// when it runs past the loop's end and carries on from its start.
    public var main: [Range<Double>]
    /// The loop's first stretch, pinned while a loop is active.
    public var loopHead: Range<Double>?

    /// How far ahead to have decoded while playing, in *wall* seconds.
    public static let aheadWallSeconds = 0.25
    /// How much of the loop's start to keep decoded, in wall seconds.
    public static let loopHeadWallSeconds = 0.25

    /// `main` and `loopHead` together, sorted, with overlapping ranges merged —
    /// what the cache must hold, and how many readers it takes to fill it.
    public var all: [Range<Double>] {
        let sorted = (main + [loopHead].compactMap { $0 }).sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<Double>] = []
        for range in sorted {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    public static func make(_ snapshot: PlaybackSnapshot, info: VideoTrackInfo) -> FramePlan {
        let picture = info.start..<info.end
        // The sound can run past the picture, or start before it. Clamped, the
        // picture holds its first or last frame; unclamped, it would plan
        // nothing at all and the panel would keep whatever it last showed.
        var snapshot = snapshot
        snapshot.position = min(
            max(snapshot.position, info.start), info.end - info.frameInterval / 2)
        let loop = snapshot.loop.flatMap { $0.isEmpty ? nil : $0 }
        let head = loop.map {
            $0.lowerBound..<min($0.upperBound, $0.lowerBound + loopHeadWallSeconds * snapshot.speed)
        }
        let main: [Range<Double>]
        if snapshot.isPlaying {
            main = ahead(of: snapshot, loop: loop)
        } else {
            main = [snapshot.position..<(snapshot.position + info.frameInterval)]
        }
        return FramePlan(
            main: main.compactMap { clip($0, to: picture) },
            loopHead: head.flatMap { clip($0, to: picture) })
    }

    /// From the position to `aheadWallSeconds` ahead, cut at the loop's end
    /// and continued from its start.
    ///
    /// **Not one frame behind.** The frame on screen already intersects a
    /// window that starts at the position, so it is kept without a margin —
    /// and a margin would, just after a wrap, reach back *before the loop*,
    /// which nothing has decoded, and turn every repetition into a seek.
    private static func ahead(
        of snapshot: PlaybackSnapshot, loop: Range<Double>?
    ) -> [Range<Double>] {
        let start = snapshot.position
        let end = snapshot.position + aheadWallSeconds * snapshot.speed
        guard let loop, snapshot.position < loop.upperBound, end > loop.upperBound else {
            return [start..<end]
        }
        let carried = min(end - loop.upperBound, loop.upperBound - loop.lowerBound)
        return [start..<loop.upperBound, loop.lowerBound..<(loop.lowerBound + carried)]
    }

    private static func clip(_ range: Range<Double>, to picture: Range<Double>) -> Range<Double>? {
        let lower = max(range.lowerBound, picture.lowerBound)
        let upper = min(range.upperBound, picture.upperBound)
        return lower < upper ? lower..<upper : nil
    }
}
