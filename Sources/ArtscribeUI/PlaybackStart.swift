import ArtscribeKit

/// Where `⇧Space` aims — one rule, decided here rather than left to the engine.
///
/// **The bug this first existed to kill.** `returnToStart` used to aim at the
/// selection or at 0 and never mentioned the loop, while `PlaybackEngine` pulled
/// playback into an active loop — so `⇧Space` looked as if it followed two
/// competing rules. Since Task 24 the loop captures on arrival only, so aiming
/// correctly matters more, not less: nothing downstream corrects a bad target.
///
/// **The rule, since the one-range change (2026-11):** the range's start, else
/// the start of the track. There is no separate selection any more — the loop is
/// the range — so the old precedence (selection, then an *active* loop, then 0)
/// collapses into one line. Looping off no longer hides the range from this rule:
/// a range with looping off is exactly what a selection used to be, and its start
/// is what `⇧Space` aimed at then. A zero-length range — one press of `A` with no
/// `S` yet — has no start worth playing from, and falls through to 0.
public enum PlaybackStart {

    /// - Returns: the frame `⇧Space` should seek to. Unclamped; `ViewerModel.seek`
    ///   clamps to the file, and every input here is already a frame within it.
    ///
    /// **Since the one-range change (2026-11):** the loop is the only range, so
    /// its start is the aim point whether or not looping is on — exactly what
    /// the selection's start was, which this rule used to check first. Only a
    /// range with no frames in it falls through to the file start.
    public static func target(loop: LoopRegion) -> FrameIndex {
        loop.range.isEmpty ? 0 : loop.range.start
    }
}
