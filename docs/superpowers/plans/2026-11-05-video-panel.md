# Video Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the picture of a video file beside the timeline, frame-locked to the audible
position, with a movable/resizable split, a transport toggle, and a Mac mini player.

**Architecture:** A new `Video` module decodes frames with `AVAssetReader` into a bounded cache,
steered by a pure frame plan derived from the playhead, speed and loop. A `@MainActor` presenter
picks the frame for the audible position on every `PlayheadClock` tick and pushes it to video
surfaces (`AVSampleBufferDisplayLayer`). `ArtscribeUI` adds a placement-generic split, the panel,
two actions, a transport button, settings, and (macOS) a non-activating floating panel.

**Tech Stack:** Swift 6, SwiftUI + AppKit/UIKit, AVFoundation, CoreMedia, CoreVideo, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-05-video-panel-design.md`

## Global Constraints

- Platforms stay `.macOS(.v26), .iOS(.v26)`. `Video` builds for **both**; it imports AVFoundation,
  CoreMedia, CoreVideo, QuartzCore and `ArtscribeKit` only. Never `Playback`, never UI.
- No change to `PlaybackEngine.render`, `AudioOutput`'s render block or `CommandRing`.
- Swift Testing only. A new regression test must be seen failing against its defect.
- Fixtures are produced by `Tests/Fixtures/generate.sh` and stay under 100 KB each.
- `make check` green before every commit, with explicit `git add` paths (never `-A`).
  Branch: `feat/video-panel`. Check `git branch --show-current` before each commit.
- Launch the app with `ARTSCRIPTURE_SILENT=1` when verifying by eye.
- Audio-only files: no panel, no transport button, both actions disabled.
- Copy: menu titles **"Video"** and **"Picture in Picture"**; settings **"Video position"**
  (Right / Top) and **"Float video when switching apps"**; undecodable picture:
  **"This video's picture can't be shown."** followed by the reason.

## Review Focus

1. **B-frames:** YouTube H.264 has frames in decode order ≠ presentation order. The lookup must
   still return the right frame → `decodedFramesFollowPresentationOrder` in Task 3.
2. **Picture shorter than the sound or starting late:** positions past the last frame hold the
   last frame, and positions before the first frame show the first → `positionsOutsideThePictureClamp`
   in Task 3.
3. **Opening a new file while frames are decoding:** no frame of the old file may reach a
   surface of the new one → `aClosedPresenterShowsNothingMore` in Task 4.
4. **Scrubbing while paused:** twenty quick seeks must end on the *last* position's frame, not
   replay a queue → `rapidSeeksEndOnTheLatest` in Task 3.
5. **Panel hidden:** no decoding happens while nothing shows the video →
   `aPresenterWithNoSurfaceDoesNotDecode` in Task 4.

---

### Task 1: The `Video` module, the fixture, and the probe

**Files:**
- Create: `Sources/Video/VideoTrackInfo.swift`, `Tests/VideoTests/VideoTrackInfoTests.swift`,
  `Tests/VideoTests/FixtureFrames.swift` (fixture URL + luma → index helper)
- Modify: `Package.swift` (library product `Video`, target `Video` deps `["ArtscribeKit"]`,
  test target `VideoTests` with `Tests/Fixtures` resources the way `AudioDecodeTests` does;
  `ArtscribeUI` gains `"Video"`), `project.yml` (`ArtscribePortableTests` gains
  `Tests/VideoTests` and product `Video`), `Tests/Fixtures/generate.sh`
- Fixtures: `Tests/Fixtures/frame_index.mp4`, `Tests/Fixtures/frame_index_rotated.mov`

**Interfaces — Produces:**
```swift
public struct VideoTrackInfo: Equatable, Sendable {
    public let naturalSize: CGSize        // coded size
    public let transform: CGAffineTransform
    public let displaySize: CGSize        // naturalSize after transform, positive
    public let frameRate: Double          // nominal, > 0 (fallback 30)
    public let start: Double              // track timeRange.start, seconds
    public let duration: Double           // track timeRange.duration, seconds
    public var frameInterval: Double { 1 / frameRate }
    public var isRotated: Bool { transform != .identity }
    public static func probe(url: URL) async throws -> VideoTrackInfo?  // nil: no *enabled* video track
}
```

- [ ] **Step 1: Add fixtures to `generate.sh`.** Each frame's luma encodes its index in video
  range: `nullsrc=s=48x32:r=10:d=3,geq=lum='16+7*N':cb=128:cr=128`, `libx264 -g 10` (B-frames
  left at the x264 default), 440 Hz `aac -b:a 32k`, `-shortest` → `frame_index.mp4` (~16 KB).
  `ffmpeg -display_rotation 90 -i frame_index.mp4 -c copy frame_index_rotated.mov`. Run it; check
  `ffprobe` shows `has_b_frames=2`, 30 frames, rotation 90 on the `.mov`.
- [ ] **Step 2: Write failing tests** (`VideoTrackInfoTests`):
  - `probesTheFrameIndexClip`: `naturalSize == 48×32`, `displaySize == 48×32`, `frameRate ≈ 10`
    (±0.01), `duration ≈ 3.0` (±0.05), `isRotated == false`.
  - `aRotatedClipReportsItsUprightSize`: `displaySize == 32×48`, `isRotated == true`.
  - `anAudioFileHasNoVideo`: `probe(sine.m4a) == nil`.
  - `aSilentVideoStillHasAPicture`: `silent_video.mp4` probes non-nil (it is 16×16).
- [ ] **Step 3: Run** `swift test --filter VideoTests` → FAIL (no module).
- [ ] **Step 4: Implement.** `AVURLAsset.loadTracks(withMediaType: .video)`, the first track whose
  `load(.isEnabled)` is true (same rule as the audio decoder), `load(.naturalSize,
  .preferredTransform, .nominalFrameRate, .timeRange)`.
- [ ] **Step 5: Run** the filter → PASS. Then `make check`, `make ios-check`.
- [ ] **Step 6: Commit** `Video: module, frame-index fixtures, track probe`.

### Task 2: The frame plan (pure)

**Files:** Create `Sources/Video/FramePlan.swift`, `Tests/VideoTests/FramePlanTests.swift`

**Interfaces — Produces:**
```swift
public struct PlaybackSnapshot: Equatable, Sendable {
    public var position: Double          // audible, seconds
    public var isPlaying: Bool
    public var speed: Double             // speed ratio, 0.5 = half speed
    public var loop: Range<Double>?      // only when the loop is *active*
}
public struct FramePlan: Equatable, Sendable {
    public var main: [Range<Double>]     // 1 window, or 2 when it crosses the loop end
    public var loopHead: Range<Double>?  // pinned while looping
    public var all: [Range<Double>]      // main + loopHead, merged where they overlap
    public static let aheadWallSeconds = 0.25
    public static let loopHeadWallSeconds = 0.25
    public static func make(_ s: PlaybackSnapshot, info: VideoTrackInfo) -> FramePlan
}
```

Rules (each one a test): media spans are wall seconds × `speed`. Every window is clipped to
`info.start ..< info.start + info.duration`. **Paused:** `main == [position ..< position +
frameInterval]`. **Playing:** `main` starts at `position − frameInterval` and runs
`aheadWallSeconds × speed` past `position`. If that crosses `loop.upperBound`, it is cut there
and the remainder continues from `loop.lowerBound` (capped at the loop's length). **Loop active**
(playing or not): `loopHead == loop.lowerBound ..< min(loop.upperBound, lowerBound +
loopHeadWallSeconds × speed)`.

- [ ] **Step 1: Failing tests:** `pausedPlansOneFrame`, `playingLooksAheadInWallTime` (speed
  0.5 → ahead span 0.125 s), `aWindowThatCrossesTheLoopEndContinuesAtItsStart`,
  `aLoopShorterThanTheHorizonIsCapped`, `theLoopHeadIsPinnedEvenFarFromTheWrap`,
  `noLoopNoHead`, `windowsAreClippedToThePicture`, `overlappingWindowsMergeInAll`. Use a
  10 fps, 3 s `VideoTrackInfo` literal (add an internal memberwise init for tests).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Mutation check:** delete the loop-head clause and watch
  `theLoopHeadIsPinnedEvenFarFromTheWrap` fail, then restore.
- [ ] **Step 6: Commit** `Video: the frame plan`.

### Task 3: Frame cache and the decoding source

**Files:** Create `Sources/Video/FrameCache.swift`, `Sources/Video/VideoFrameSource.swift`,
`Tests/VideoTests/FrameCacheTests.swift`, `Tests/VideoTests/VideoFrameSourceTests.swift`

**Interfaces — Produces:**
```swift
public struct DecodedFrame: @unchecked Sendable {   // CVPixelBuffer is immutable once decoded
    public let pts: Double; public let duration: Double; public let pixelBuffer: CVPixelBuffer
}
struct FrameCache<Payload> {                        // generic so tests run without pixel buffers
    mutating func insert(pts: Double, duration: Double, _ payload: Payload)  // replaces same pts
    func entry(at t: Double) -> (pts: Double, payload: Payload)?            // pts ≤ t < pts+duration
    func covers(_ window: Range<Double>) -> Bool
    mutating func evict(outside windows: [Range<Double>])
    var count: Int { get }
}
public final class VideoFrameSource: @unchecked Sendable {
    public init(url: URL, info: VideoTrackInfo, frameBudget: Int = 48)
    public func request(_ plan: FramePlan)          // non-blocking; latest wins
    public func frame(at t: Double) -> DecodedFrame?
    public func idle() async                        // test hook: resolves when the queue is drained
    public private(set) var failure: String?        // decoder's reason, for the panel
    public func close()                             // cancels; later requests are ignored
}
```

Source behaviour: one serial queue and two readers, **main** and **head**. The head reader is
created at `loopHead.lowerBound`, pulls until it passes `loopHead.upperBound`, then **parks**.
The main reader keeps pulling until it passes the end of its window. When the main window jumps
to where the parked head reader's cursor already is (the loop wrap), the head reader **becomes**
the main reader and a fresh head reader is primed. Any other jump makes a new reader at the
window start. Frames go into the cache under a lock (`Synchronization.Mutex`). Frames outside
`plan.all` are evicted; the total never exceeds `frameBudget`. Output is
`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`, IOSurface-backed. **Rotated tracks** decode
through `AVAssetReaderVideoCompositionOutput` with `AVVideoComposition(propertiesOf:)`, so the
frames come out upright. `info.start ..< end` clamps every lookup.

- [ ] **Step 1: Failing cache tests:** `lookupFindsTheFrameCoveringATime` (span edges inclusive
  start, exclusive end), `aGapIsAMissNotAStaleFrame`, `evictionKeepsOnlyPlannedWindows`,
  `insertingTheSamePtsReplaces`, `decodedFramesFollowPresentationOrder` (insert out of order →
  lookups are still right).
- [ ] **Step 2: Failing source tests** against `frame_index.mp4` (index = `round((Y − 16) / 7)`
  from the centre luma, via `FixtureFrames`):
  - `theFrameAtATimeIsThatFrame`: paused plan at 1.05 s → index 10, at 2.95 → 29.
  - `positionsOutsideThePictureClamp`: −1 s → 0, 9 s → 29.
  - `theLoopHeadIsReadyBeforeTheWrap`: loop 1.0..<2.0, playing at 1.5 → after `idle()`, frames
    10, 11, 12 are cached *and* frames 15–17 are.
  - `theWrapHandsOffWithoutANewReader`: playing at 1.9 → then at 1.0 → the frame at 1.0 is
    available with no `idle()` between, and `readersCreated` (internal counter) rises by one
    (the re-primed head), not two.
  - `rapidSeeksEndOnTheLatest`: twenty paused requests from 0.1 to 2.0 → after `idle()` the
    frame at 2.0 is index 20, and `framesDecoded < 20 × 10`.
  - `aRotatedClipDecodesUpright`: pixel buffer is 32 wide × 48 high.
  - `budgetIsRespected`: speed 2.0, frameBudget 8 → `count ≤ 8` after `idle()`.
- [ ] **Step 3: Run** `swift test --filter VideoTests` → FAIL. **Step 4: Implement.**
  **Step 5: Run** → PASS.
- [ ] **Step 6: Mutation check:** make the wrap always create a new reader. `theWrapHandsOff…`
  must fail. Restore.
- [ ] **Step 7:** `make check`, `make ios-check`. **Commit** `Video: frame cache and decoding source`.

### Task 4: Presenter and video surface

**Files:** Create `Sources/Video/VideoPresenter.swift`, `Sources/Video/VideoSurfaceView.swift`,
`Tests/VideoTests/VideoPresenterTests.swift`

**Interfaces — Produces:**
```swift
@MainActor public protocol VideoSurface: AnyObject { func show(_ frame: DecodedFrame) }
@MainActor public final class VideoPresenter {
    public init(source: VideoFrameSource, info: VideoTrackInfo)
    public let info: VideoTrackInfo
    public func update(_ snapshot: PlaybackSnapshot)   // called every clock tick
    public func attach(_ surface: VideoSurface)        // gets the current frame at once
    public func detach(_ surface: VideoSurface)
    public func close()                                // closes the source; surfaces get nothing more
    public var failure: String? { get }
    public private(set) var shownPTS: Double?          // for tests and the harness
}
/// NSView (macOS) / UIView (iOS) whose backing layer is an AVSampleBufferDisplayLayer,
/// `.resizeAspect`, black background. Enqueues with kCMSampleAttachmentKey_DisplayImmediately.
public final class VideoSurfaceView: PlatformView, VideoSurface { … }
```

`update` does nothing when no surface is attached (no plan, no decode). Otherwise it asks the
source for `FramePlan.make`, looks up the frame for `position`, and sends it to every surface
only if its pts differs from `shownPTS`. A miss keeps the previous frame.

- [ ] **Step 1: Failing tests** with a recording fake `VideoSurface`:
  `aPresenterWithNoSurfaceDoesNotDecode` (source `framesDecoded == 0` after updates + `idle()`),
  `theSameFrameIsNotSentTwice`, `aNewSurfaceGetsTheCurrentFrame`,
  `aClosedPresenterShowsNothingMore` (update after `close()` → no new `show`).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** (the view: `makeBackingLayer` on macOS,
  `layerClass` on iOS — the spike showed a *sublayer* breaks PiP scaling). **Step 4: Run** → PASS.
- [ ] **Step 5:** `make check`, `make ios-check`. **Commit** `Video: presenter and surface`.

### Task 5: The model owns the video

**Files:** Create `Sources/ArtscribeUI/ViewerModel+Video.swift`,
`Tests/ArtscribeUITests/ViewerModelVideoTests.swift`.
Modify `ViewerModel.swift` (state), `ViewerModel+Loading.swift` (`adopt`, `closeTrack`),
`ViewerModel+Playback.swift` (`tickPlayback`: the presenter is driven on **every** tick,
paused too, after `playhead` is final).

**Interfaces — Produces:**
```swift
@Observable public final class VideoState {          // child observable, like CueMarkers
    public let info: VideoTrackInfo
    public internal(set) var failure: String?
}
extension ViewerModel {
    public internal(set) var video: VideoState?                  // stored on the model
    @ObservationIgnored public internal(set) var videoPresenter: VideoPresenter?
    public var hasVideo: Bool { video != nil }
    var videoSnapshot: PlaybackSnapshot { get }  // playhead/sampleRate, isPlaying, speed.ratio,
                                                 // loop only if loop.isActive, in seconds
}
```

Probe after `adopt` under the same `loadToken` (a stale probe is dropped), inside the security
scope that `scopedURL` already holds. `closeTrack` and a new `adopt` close the presenter first.

- [ ] **Step 1: Failing tests:** `snapshotConvertsFramesToSeconds` (48 kHz, playhead 72 000 →
  1.5 s; inactive loop → `nil`; active loop 48 000..<96 000 → 1.0..<2.0),
  `openingAVideoFileExposesItsPicture` (open `frame_index.mp4` via `open(url:)`, await load →
  `hasVideo`, `displaySize` 48×32), `anAudioFileHasNoVideo` (`sine.m4a`),
  `closingTheTrackClosesThePresenter`.
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Commit** `Model: probe, own and drive the video`.

### Task 6: Placement, split, panel and settings

**Files:** Create `Sources/ArtscribeUI/VideoPlacement.swift` (enum + `VideoSplitPolicy`),
`Sources/ArtscribeUI/VideoSplitView.swift` (generic container + divider),
`Sources/ArtscribeUI/VideoPanelView.swift` (surface representable + overlays),
`Sources/ArtscribeUI/VideoSettings.swift` (UserDefaults store), and tests
`Tests/ArtscribeUITests/VideoSplitPolicyTests.swift`, `VideoSettingsTests.swift`.
Modify `Preferences.swift`, `DocumentView.swift`, `SettingsView.swift`,
`Sources/ArtscribeApp/ArtscribeAppMain.swift` and `AcceptanceMain.swift` (adopt the store).

**Interfaces — Produces:**
```swift
public enum VideoPlacement: String, CaseIterable, Sendable { case trailing, top
    public var axis: Axis { get } ; public var title: String { get } }  // "Right", "Top"
enum VideoSplitPolicy {
    static let minimumVideo: CGFloat = 160
    static func minimumTimeline(on: EmptyStatePrompt.Surface) -> CGFloat   // 320; phone 200
    static func defaultFraction(for: VideoPlacement) -> Double             // 0.35 / 0.40
    static func videoExtent(fraction: Double, available: CGFloat,
                            surface: EmptyStatePrompt.Surface) -> CGFloat
    static func fraction(dragTo extent: CGFloat, available: CGFloat,
                         surface: EmptyStatePrompt.Surface) -> Double      // clamped, round-trips
}
// Preferences
public internal(set) var videoShown = true
public internal(set) var videoPlacement = VideoPlacement.trailing
public internal(set) var floatVideoWhenInactive = true
public func videoFraction(for: VideoPlacement) -> Double
public func setVideoShown(_:), setVideoPlacement(_:), setVideoFraction(_:for:),
            setFloatVideoWhenInactive(_:)
public func adopt(video settings: VideoSettings)
```

Extent rules: `clamp(fraction × available, minimumVideo, available − minimumTimeline)`, and when
`available − minimumTimeline < minimumVideo` the timeline wins (`max(0, available −
minimumTimeline)`). The container lays the timeline column (ruler, cue lane, lanes) and the
panel along `placement.axis`, video after the timeline for `.trailing` and before it for
`.top`. The overview strip stays outside, full width. Divider: drawn 1 pt (`palette.rule`), hit
region 8 pt on desktop and 44 pt on touch (`hitRegion(target:drawn:)`), `.pointerStyle
(.frameResize(position: …))` on macOS, double-click restores the default. The fraction is saved
on drag *end* only. Settings gets a **Video** section: a Picker "Video position" and a Toggle
"Float video when switching apps" (macOS only for now). Keys: `video.shown`, `video.placement`,
`video.fraction.<placement>`, `video.floatWhenInactive`. Defaults are stored by *removing* the
key, as `InteractionSettings` does.

- [ ] **Step 1: Failing tests:** `extentFollowsTheFraction`, `extentNeverBelowTheVideoMinimum`,
  `theTimelineKeepsItsFloor`, `aTinyWindowGivesTheTimelineEverything`,
  `phoneHasALowerTimelineFloor`, `dragFractionRoundTrips`, `placementAxes`
  (`.trailing → .horizontal`, `.top → .vertical`); settings: `defaultsWhenNothingStored`,
  `aSavedPlacementLoads`, `restoringADefaultRemovesTheKey`.
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Look at the pixels.** `make app` or `swift run -c release ArtscribeApp` with
  `ARTSCRIPTURE_SILENT=1`, open a real 16:9 clip and a 9:16 clip, and `screencapture -o -x -l <id>` at
  both placements and after a divider drag. Check: an audio file looks exactly as before.
- [ ] **Step 6:** `make check`, `make ios-check`. **Commit** `Video panel: movable split, settings`.

### Task 7: Actions, menu, and the transport button

**Files:** Modify `ActionID.swift` (`viewVideoToggle = "view.video.toggle"`,
`viewVideoPictureInPicture = "view.video.pictureInPicture"`), `ActionCatalog.swift`
(`ActionEnablement.trackVideo`), `ActionCatalogEntries.swift` (`V`, `⇧V`, `.view`, toggle for
the first), `ActionMenuItem.swift` (`trackVideo` = ready && `model.hasVideo`; the PiP item also
requires `MiniPlayerSupport.isAvailable`, which is `false` on iOS until the iOS pass),
`ActionInvoker.swift` (`isOn` for the toggle = `prefs.videoShown`), `ActionInvokerTable.swift`,
`MenuPlan.swift` (after Track Marks), `TransportControls.swift` (case `.video`, face `V`
"Video" `film`, group `[.video]` last, `TransportState.hasVideo`/`videoIsShown`,
`static func visibleGroups(in: TransportState)`), `TransportBarView.swift` (uses visible groups
for layout and `TransportDensity.Row`), `AcceptanceTransportChecks.swift` (count the *visible*
controls), `docs/superpowers/specs/2026-07-27-artscribe-design.md` §6.2, `README.md`.
Tests: extend `ActionCatalogTests`, `TransportControlTests`, `KeyBindingsTests` as they already
do for `viewTrackMarksToggle`.

- [ ] **Step 1: Failing tests:** `videoActionsAreBoundToV` (read from `ActionCatalog`, not a
  literal), `videoActionsAreDisabledForAnAudioFile`, `theVideoButtonOnlyShowsForVideo`
  (`visibleGroups` without `hasVideo` == today's five groups), `videoToggleFlipsThePreference`.
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5:** `swift run -c release ArtscribeAcceptance --acceptance <audio> --only
  transport,menu` (via `make acceptance AUDIO=… ARGS='--only transport,menu'`) → unchanged.
- [ ] **Step 6: Commit** `Video: V toggles the panel; transport button; spec §6.2`.

### Task 8: The Mac mini player

**Files:** Create `Sources/ArtscribeUI/MiniPlayerPolicy.swift`,
`Sources/ArtscribeUI/MiniPlayerController.swift` (`#if os(macOS)`),
`Sources/ArtscribeUI/MiniPlayerView.swift`, `Tests/ArtscribeUITests/MiniPlayerPolicyTests.swift`,
`MiniPlayerControllerTests.swift`. Modify `ArtscribeAppMain.swift` (build and hold one
controller in `start()`), `ActionInvokerTable.swift` (`⇧V` → `controller.toggleByUser()`
through `MenuContext.miniPlayer`), `ActionInvoker.swift` (`MenuContext` gains `miniPlayer`).

**Interfaces — Produces:**
```swift
public struct MiniPlayerState: Equatable, Sendable {
    var isShowing, openedByUser, hasVideo, isPlaying, floatsWhenInactive: Bool
}
public enum MiniPlayerEvent: Sendable { case appResigned, appActivated, userToggled, closed }
public enum MiniPlayerPolicy {
    /// The new (isShowing, openedByUser).
    public static func next(_ s: MiniPlayerState, on: MiniPlayerEvent) -> (Bool, Bool)
}
@MainActor public final class MiniPlayerController {
    public init(model: ViewerModel)              // required: the transport it drives
    public private(set) var isShowing: Bool
    public func handle(_ event: MiniPlayerEvent)
    public func toggleByUser()
    func playPause()                             // → model.togglePlayPause()
}
```

Policy table (one test each): resigned + video + playing + setting on → show (not by user);
resigned while paused → stay hidden; resigned with the setting off → hidden; activated →
hide *unless* opened by user; user toggle → flip, marked by user; closed → hidden; no video →
always hidden. The panel: `NSPanel` with `[.nonactivatingPanel, .titled, .closable,
.resizable, .fullSizeContentView]`, `level = .floating`, `collectionBehavior =
[.canJoinAllSpaces, .fullScreenAuxiliary]`, `hidesOnDeactivate = false`,
`isMovableByWindowBackground = true`, `contentAspectRatio = info.displaySize`,
`setFrameAutosaveName("MiniPlayer")`, default width 360 at the screen's top-right. Content: a
`VideoSurfaceView` attached to the presenter, hover overlay with play/pause and "Show
Artscripture" (`NSApp.activate()`). The main panel gains its corner button
(`pip.enter`, shown on hover) for the same `toggleByUser()`. While the mini player is
showing, the main panel shows "Playing in the mini player" instead of the picture. The controller observes `NSApplication.didResignActive` /
`didBecomeActive` and the track changing (closing the track closes the window).

- [ ] **Step 1: Failing tests:** the seven policy rows above, plus
  `theControllerTheAppBuildsDrivesTheModel` (`playPause()` on a controller built around a model
  with no session sets the "no audio output" notice, which proves it reached `play()`).
- [ ] **Step 2–4:** Run → FAIL, implement, run → PASS.
- [ ] **Step 5: Verify for real.** Launch with `ARTSCRIPTURE_SILENT=1` and a clip, play, activate
  Finder (`osascript -e 'tell application "Finder" to activate'`): the window appears, the
  frames advance, play/pause works without Artscripture coming forward (check `NSApp.isActive`
  stays false via the log), and reactivating the app hides it. Screenshot it.
- [ ] **Step 6: Commit** `Mac mini player: a floating window when the app is not in front`.

### Task 9: Finish

- [ ] **Step 1:** `CLAUDE.md`: a short **Video** section (position-driven presentation, why not
  `AVPlayer`, the PiP spike result, the surface must be the *backing* layer for iOS PiP).
- [ ] **Step 2:** `make check`, `make ios-check`, `make ios-test`.
- [ ] **Step 3:** The full acceptance run, `make acceptance AUDIO=<the usual FLAC>` → exit 0.
- [ ] **Step 4:** Screenshots of the Mac window at both placements (16:9 and 9:16 clips) and of
  the mini player, for the user's review.
- [ ] **Step 5: Commit** and hand over for dogfooding on the Mac. The iOS half (system PiP, iPad
  and iPhone layout check) is the next plan, after that feedback.
