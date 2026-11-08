import ArtscribeKit

/// What `A` and `S` do to the loop region.
///
/// The whole of the interesting behaviour is what happens when the two edges
/// cross, which a transcriber hits constantly: set the out point, then decide the
/// passage should start earlier and press `A` past it. Collapsing the region
/// there would present as "the key did nothing", so instead the *other* edge is
/// pushed to the nearest file boundary and the loop stays real.
///
/// With no loop yet, either key makes one, and a new loop loops
/// (`ViewerModel.enterLoopIfOutside`); on an existing loop they are edits and
/// leave looping as it was. `S` from nothing loops the start of the file up to
/// the playhead, which is then at the loop's end — so playback goes back to
/// the start, or it would run straight on past.
public enum LoopEditing {

    /// `A` — set the in point, keeping the out point where it is when it still
    /// makes a region, and running to the end of the file when it does not.
    public static func settingIn(
        at frame: FrameIndex, in loop: LoopRegion, totalFrames: FrameIndex
    ) -> LoopRegion {
        let start = clamp(frame, totalFrames)
        let end = loop.range.end > start ? loop.range.end : totalFrames
        return LoopRegion(
            range: FrameRange(start: start, count: Swift.max(0, end - start)),
            isEnabled: loop.isEnabled || loop.range.isEmpty)
    }

    /// `S` — set the out point, pulling the in point back to the start of the
    /// file when the existing one is no longer before it.
    public static func settingOut(
        at frame: FrameIndex, in loop: LoopRegion, totalFrames: FrameIndex
    ) -> LoopRegion {
        let end = clamp(frame, totalFrames)
        let start = loop.range.start < end ? loop.range.start : 0
        return LoopRegion(
            range: FrameRange(start: start, count: Swift.max(0, end - start)),
            isEnabled: loop.isEnabled || loop.range.isEmpty)
    }

    private static func clamp(_ frame: FrameIndex, _ totalFrames: FrameIndex) -> FrameIndex {
        Swift.max(0, Swift.min(frame, totalFrames))
    }
}
