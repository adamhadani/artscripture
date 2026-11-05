# Video panel — design

**Date:** 2026-11-05 · **Status:** for approval · **Extends:** spec §6.2 (two actions), §8
(one notice), and the "video files open for their soundtrack" rule in `CLAUDE.md`.

## Why

Artscripture already opens MP4, MOV and M4V files, but only plays their soundtrack. The
clips people open are usually from YouTube or Instagram, and often show a **pianist's hands**.
Being able to see the hands answers what the ear can't, such as which voicing, which octave,
which finger, or which hand takes the inner line. The video is meant as a second view of the
same moment as the waveform, not as a separate player.

Prior art: Transcribe! is the one desktop transcription tool that shows synced, slowed-down
video, and users report it as fragile. Anytune and Amazing Slow Downer only extract the audio
from a video. Video practice apps (Loop Loop, Practy) offer mirroring and zoom, which are
built for guitar and dance footage and are not needed here.

## Decisions taken with the user (2026-11-05)

1. **A side panel on the right**, beside the timeline (option A of three mockups).
2. **Placement must be easy to change**, through a clean positioning abstraction rather than
   a layout written for one side, and ideally **user-configurable in Settings**.
3. **A draggable divider** resizes the video between sensible minimum and maximum sizes. The
   motivating case: once a loop is set, you need less waveform and more video.
4. **A toggle in the transport bar** shows or hides the video.
5. **A mini player when the app is not in front.** It keeps the video visible, with
   play/pause, while something else is in front.
6. **The picture follows the sound**: it slows down with the speed control, jumps back at
   every loop wrap, and matches the playhead.
7. **Dogfood on macOS first**, then iPad on TestFlight. iPhone if it works out.

## What it must be

- **Picture always matches what you hear.** The frame shown is a function of the *audible*
  position that the playhead already displays (`ViewerModel.playhead`, polled from the
  engine and already compensated for latency). No separate video clock exists, so there is
  nothing to drift.
- **The paused picture is the frame at the playhead.** A click, nudge or loop-edge move while
  paused shows that exact frame, so you can step through a fast run and read each hand shape.
  *(Agreed as a guess during the conversation.)*
- **No hitch at the loop wrap.** A stall at every repetition would be the visual version of
  the click this project refuses to allow at the loop boundary (see "Looping" in `CLAUDE.md`).
  The frames at the loop start are decoded *before* the wrap arrives.
- **Audio-only files are unchanged.** No panel, no transport button, and the menu items are
  disabled. Everything an audio file does today, it still does with nothing new on screen.
- **The video never touches audio.** No change to `PlaybackEngine.render`, the render thread or
  `CommandRing`. Video decoding happens on its own queue and only reads the polled playhead.

### Anti-goals

- A picture that drifts from the sound, or lags it visibly at slow speeds.
- A visible stall, black flash or stale frame at the loop wrap.
- A video file whose picture cannot be decoded failing silently, or failing to *open*. Its
  audio must still play, and the panel says why it is empty (spec §8: never silent).
- Memory that grows with the length or resolution of the video.

## Layout

```
┌ title bar ─────────────────────────────────────────────────────┐
├ banners ───────────────────────────────────────────────────────┤
├ overview strip  (full width — maps the whole track)            ┤
├──────────────────────────────────────────────┬─┬───────────────┤
│ time ruler                                   │ │               │
│ cue-mark lane (when present)                 │▐│     video     │
│ waveform lanes                               │ │  (aspect fit) │
├──────────────────────────────────────────────┴─┴───────────────┤
├ transport bar  … [▣ video]                                     ┤
└ status bar ────────────────────────────────────────────────────┘
```

- The video sits beside the **timeline column**: the ruler, the cue lane and the waveform
  lanes. These three share one x-mapping, so they move together. The overview strip stays full
  width because it maps the whole track to its own width and is independent.
- **Placement is a value, not a layout.** `VideoPlacement` is `.trailing` or `.top` (`.leading`
  and `.bottom` can be added later). One generic split container takes the placement, the
  timeline and the video, and draws a draggable divider along the placement's axis. Nothing
  else knows which side the video is on. With `.top`, the video sits between the overview and
  the ruler (option B of the mockups).
- **Settings ▸ Video position: Right / Top.** Right is the default.
- **The divider** shows a resize cursor on the Mac and has a 44 pt touch region on iPad and
  iPhone (`ControlMetrics`, drawn thinner than it responds, per "44 × 44 is a hit *region*").
  - The size is **remembered as a fraction** of the space available, so the video grows with
    the window, and is clamped in points at layout time. The minimum video size is about
    160 pt. The timeline keeps at least about 320 pt (Mac/iPad) or 200 pt (iPhone). The clamp
    is a pure function and is unit-tested. Exact numbers are left to the builder and tuned by
    eye.
  - Double-clicking or double-tapping the divider restores the default size. Default: 35% for
    `.trailing` and 40% for `.top`. *My call.*
- **The picture is aspect-fit** inside the panel on black, and is drawn upright: phone-shot
  clips carry a `preferredTransform`, and frames from `AVAssetReader` arrive unrotated.
- **Panel visibility and size are app-wide preferences**, not per-document. If you hide the
  video, it stays hidden for the next clip. A video file opens with the panel shown by default.
  *My call.*

## Controls

Spec §6.2 is the source of truth for actions, so both are added there:

| Action | Title | Key | Menu | Enablement |
|---|---|---|---|---|
| `view.video.toggle` | Video | `V` | View (toggle, ✓) | track **with video** |
| `view.video.pictureInPicture` | Picture in Picture | `⇧V` | View | track with video, panel shown |

- `V` is unbound on every layer today. This needs a new enablement case, `trackVideo`, next to
  `track`, so that audio files show both items disabled rather than as dead keys.
- **Transport bar:** a toggle button with the video glyph, at the trailing end, **present only
  when the track has video**. It takes part in `TransportDensity` packing like any other
  button.
- **The panel's own chrome:** a Picture-in-Picture button in a corner. It appears on hover on
  the Mac and is always visible on touch.

## The mini player

**When it appears** is one pure function shared by both platforms, `MiniPlayerPolicy`,
tested like `AudioSessionPolicy`. It floats when the app stops being frontmost, if the panel is
shown, the track is **playing**, and **Settings ▸ Float video when switching apps** is on
(the default). It goes away when the app comes back. Requiring "playing" matches what iOS
does for every video app, and avoids a window appearing every time you click away from a
paused track. *My call; easy to change.* **View ▸ Picture in Picture** (`⇧V`) opens it by
hand. One opened that way stays until it is closed, rather than going away when the app
comes back.

**Its controls call the transport the app already has.** Play/pause calls
`ViewerModel.play()`/`pause()`, the same path as `Space`, so preroll, loops and Now Playing
behave identically. "Is paused" reads the transport (`TransportLatch`), never the graph (see
the interruption rules in `CLAUDE.md`). **The wiring is a required `init` parameter, not an
optional closure** ("a closure that may be `nil` is a wire that may not be connected"). The
object the app actually builds is the one the tests drive.

### Mac: our own floating panel. The system's PiP was tried and does not scale.

Spiked on this machine (macOS 27.2) with `AVPictureInPictureController` and a sample-buffer
content source, decoding a 720p clip and starting PiP:

- With the display layer as a **sublayer**, the PiP window showed a zoomed-in corner of the
  frame. This is the bug reported on the developer forums for macOS 26.4, and it is still
  present.
- With the display layer as the view's **backing layer**, it improves but is still wrong. A
  bordered test frame showed only its left and bottom edges. PiP draws the layer at the
  layer's own size (`render size 888x500`) into an 831 × 448 window, anchored bottom-left,
  so the top and right are cut off.

So the Mac mini player is **a floating `NSPanel` of our own**:

- **Non-activating** (`.nonactivatingPanel`), so pressing its play button does not bring
  Artscripture to the front. Without this, the press would make the app frontmost, and the
  policy would then close the window that was just used.
- **Floating level**, joins all Spaces and full-screen apps, and **`hidesOnDeactivate =
  false`** (a panel hides on deactivate by default, which is exactly the moment this one
  exists for).
- Locked to the video's aspect ratio and resizable. Its frame is remembered
  (`setFrameAutosaveName`).
- On hover it shows play/pause, and a button that brings the app back.

The panel is SwiftUI in an `NSHostingView`, showing the same video surface as the main panel.

### iPad / iPhone: the system's Picture in Picture

`AVPictureInPictureController` with the sample-buffer content source is the only way to float
over another app on iOS, and is what YouTube uses there. Turning on
`canStartPictureInPictureAutomaticallyFromInline` while the panel is shown lets the system
start it when the app goes to the background. This needs the `audio` background mode, which
`Info.plist` already has. `AVPictureInPictureSampleBufferPlaybackDelegate`'s `setPlaying`
calls the transport as above, and skip ± calls the existing seek.

**Not yet verified on a device or simulator.** Check it at the start of the iPad pass. The
scaling bug above was reported for macOS only.

## How the picture is produced

**Position-driven presentation, not a second player.** An `AVPlayer` slaved to the engine was
considered and rejected. It has its own clock that has to be continually corrected against
ours. Each loop wrap is a seek, and a seek in long-GOP YouTube H.264 decodes forward from the
last keyframe, so it stalls at every repetition. And its PiP controls drive the `AVPlayer`
rather than our transport.

Instead, in a new **`Video` module** (macOS + iOS, sitting beside `AudioDecode`; it imports
AVFoundation and nothing from `Playback` or the UI):

1. **Probe**: does the file have an *enabled* video track? If so: natural size and transform
   → display size, nominal frame rate, duration. The same "first enabled track" rule as the
   audio decoder.
2. **Decode** with `AVAssetReader` (hardware decoding through VideoToolbox) on a dedicated
   serial queue, into IOSurface-backed pixel buffers. A reader starts at a time; frames come
   out in order.
3. **A frame cache** holds decoded frames keyed by presentation time. A lookup returns the
   frame whose span covers a time.
4. **A frame plan**, a pure function, says which media-time windows must be resident, given
   the position, whether it is playing, the speed, the loop region and the duration. Playing:
   a window ahead of the position, sized in *wall* time so 0.5× needs half the media span. If
   that window crosses the loop end, a **second window at the loop start** is included. This
   is what makes the wrap seamless: the same idea as the stretcher being fed continuously
   across the boundary. Paused: just the frame at the position. The cache evicts anything
   outside the plan, which keeps memory bounded (decoded size capped, frame count capped).
5. **Presentation:** on every `PlayheadClock` tick, which already runs while paused,
   `ViewerModel` hands the presenter a snapshot (audible position in seconds, playing, speed,
   loop). The presenter updates the plan, looks up the frame for the position, and if it
   differs from the frame on screen, enqueues it for immediate display to every attached
   **video surface**. A surface is a view whose *backing* layer is an
   `AVSampleBufferDisplayLayer`; the main panel and the Mac mini player are one each, and a
   surface that attaches is given the current frame at once. When the position jumps (seek, click, nudge) the frame is decoded from
   a fresh reader, and the last frame stays on screen until the new one arrives. Rapid
   scrubs coalesce: the latest request wins.
6. The presenter is `@ObservationIgnored` on the model and **passed to the panel view
   separately** (the `recents` lesson). It is driven imperatively from the tick, **never
   through a SwiftUI `body`**, so it adds nothing to SwiftUI's per-tick work (the
   `TransportDensity` lesson).

Loading: the probe runs after the audio is adopted, under the same `loadToken` and the same
security scope as the audio. A probe that finds no video leaves everything exactly as today.
A track whose video cannot be *decoded* still plays its audio, and the panel says "This
video's picture can't be shown" with the reason.

## Testing

- **Pure, on both platforms** (`VideoTests` joins the iOS portable bundle; the CI test-count
  assertion moves with it): the frame plan (wrap window present only when it is needed, scales
  with speed, paused plan is a single frame), the cache lookup (span edges, before the first
  frame, after the last), the split clamp, the placement → axis mapping, `trackVideo`
  enablement, and `MiniPlayerPolicy`.
- **Integration**: a generated fixture in `Tests/Fixtures/generate.sh` whose frames *encode
  their own index* (a flat luma of `8 × n`, about 3 s at 10 fps, a short GOP, a 440 Hz
  soundtrack, under 100 KB). Asserts that the frame shown at a time is the right index,
  including immediately after a loop wrap and after a seek, and that a rotated variant comes
  out upright.
- Each regression test is checked against its defect before it is trusted (for example: drop
  the wrap window and watch the wrap test fail).
- **Pixels, on each platform.** Screenshot the Mac window and an iPad simulator with a real
  clip, at both placements, before calling it done.
- `make check` green, `make ios-check`, and the full acceptance run before the commit. The
  harness drives an audio file, so it must show no change. Adding a `video` acceptance group
  is left to the builder.

## Non-goals (for now)

- Zooming into part of the frame (the keyboard strip). It is the most likely next step.
- Mirroring, video export, subtitles, picking among several video tracks.
- Stepping by video frame (the nudge tiers cover this for now).
- Keyboard resizing of the panel.
- iPhone portrait. iPhone gets the same panel in landscape, with the smaller timeline floor.

## Left to the builder

The exact min/max/default numbers, the decode size cap and cache bounds, whether the iOS
PiP progress bar is driven by a `controlTimebase` on the layer or the content is presented as
live, the transport glyph, the mini player's hover chrome, and whether a `video` acceptance
group is worth adding in this pass.

## Order of work

Mac first, so it can be dogfooded: the `Video` module and its tests, then the panel, split and
controls, then the Mac mini player. The iOS half (system PiP, the iPad layout check, the iPhone
floor) comes after the user has used it on the Mac and before TestFlight.
