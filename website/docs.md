---
layout: page
permalink: /docs/
title: Documentation
nav: docs
standfirst: >-
  Everything Artscripture does, and the key that does it. The shortcut tables here
  are the same catalog the application's menus and its ⌘/ window are generated
  from.
description: >-
  Artscripture documentation: getting started, keyboard shortcuts, loading files,
  marking a passage and looping, speed and pitch, practice mode, and session files.
---

<nav class="toc" aria-label="Contents">
  <p>Contents</p>
  <ul>
    <li><a href="#getting-started">Getting started</a></li>
    <li><a href="#opening-a-track">Opening a track</a></li>
    <li><a href="#transport-and-preroll">Transport and preroll</a></li>
    <li><a href="#marking-a-passage">Marking a passage</a></li>
    <li><a href="#looping">Looping</a></li>
    <li><a href="#speed-and-pitch">Speed and pitch</a></li>
    <li><a href="#volume">Volume</a></li>
    <li><a href="#navigating-and-zooming">Navigating and zooming</a></li>
    <li><a href="#track-marks">Track marks</a></li>
    <li><a href="#practice-mode">Practice mode</a></li>
    <li><a href="#sessions">Sessions</a></li>
    <li><a href="#settings">Settings</a></li>
    <li><a href="#the-shortcut-window">The shortcut window</a></li>
    <li><a href="#every-shortcut">Every shortcut</a></li>
  </ul>
</nav>

## Getting started

Artscripture is one uninterrupted waveform and a set of keys. There are no palettes
to arrange and no modes to be in. The working loop is:

1. Open a track — <kbd>⌘O</kbd>, or drop a file on the window.
2. Find the passage. Drag in the waveform to mark it, or set the loop's edges
   at the playhead with <kbd>A</kbd> and <kbd>S</kbd>.
3. It loops straight away — <kbd>D</kbd> switches looping off, and on again.
4. Slow it down with <kbd>Q</kbd>, or jump straight to half speed with
   <kbd>3</kbd>.
5. Play with <kbd>Space</kbd>, and leave it running while you work it out.
6. Save where you got to with <kbd>⌘S</kbd>.

That is the whole product. Everything below is detail on one of those six steps.

**Requirements.** macOS 26 on Apple Silicon for the Mac download; iOS or iPadOS 26
for the [App Store]({{ site.app_store_url }}) app on iPhone and iPad.

## Opening a track

Three routes in:

- <kbd>⌘O</kbd> opens a file panel.
- **Drop a file on the window.**
- **Pick one from the recent list on the resting screen** — the eight most
  recent, each named by file *and* folder so two rips of the same track are told
  apart.

Recents survive a relaunch on every platform. On iPhone and iPad that list is the only
route to recents, since there is no menu bar to hang Open Recent from.

### Formats

MP3, AAC, M4A/MP4, ALAC, FLAC (including 24-bit), WAV, AIFF, CAF, Ogg Vorbis and
Opus — all decoded by the operating system. There is no bundled ffmpeg and there
are no bundled codecs. **Video files open for their soundtrack:** MP4, MOV and M4V,
so a lesson filmed on your phone loops and slows down like any other track.

**Ogg Vorbis is macOS only.** iOS and iPadOS cannot decode it, so their file picker
does not offer it rather than offering a file it would then refuse to open. Opus
is a different codec and works on both.

## Transport and preroll

| Key | Action |
|---|---|
| <kbd>Space</kbd> | Play / pause — a resume rolls back by the preroll |
| <kbd>⇧Space</kbd> | Play from start — of the marked passage (looping or not), else of the file |
| <kbd>H</kbd> | Preroll on / off |

**Preroll.** You stop on a note; to hear it in context you have to start slightly
before it. <kbd>Space</kbd> therefore resumes from *position − preroll* rather
than from exactly where it stopped. Two seconds by default, editable in
**Settings ▸ Playback**, and **0 turns it off** — that is an allowed value, not a
rejected one.

It clamps at the start of the file, and when a loop is active and the playhead is
inside it, at the loop's in point — so a resume never steps outside the passage
you set. Pausing and resuming twice rolls back twice: each press is a fresh
resume, which is how you inch back through a phrase.

<kbd>⇧Space</kbd> never prerolls; it already has an explicit target.

<kbd>H</kbd> is not the same as setting the amount to 0. Zero is a permanent
"resume exactly where I stopped"; the toggle is the mode you flip while working,
and it remembers your seconds. It is also a **Playback** menu item and a
transport-bar button, both of which show the current state.

**Stop** exists as a menu item and has no key, deliberately —
<kbd>Space</kbd> is play/pause and a separate Stop key would be a third way to
say the same thing.

## Marking a passage

Drag across the waveform lanes to mark a passage — **that passage is the loop**,
and it starts looping straight away, because marking a passage only to hear the
music run on past it is never what was meant. Press <kbd>D</kbd> or the **Loop**
button to stop it repeating, and again to bring it back.

**Drag inside the loop to move it**, keeping its length — if it is looping, playback
stays inside it. A drag that starts *outside* the loop marks a new passage
in its place. Drag a loop edge — its grip tab marks it — to adjust it; on iPhone
and iPad an edge takes hold from a fingertip's width away. Shift-drag extends the
passage. A click places the
playhead and leaves the passage alone; a double-click places it and plays from
there.

| Key | Action |
|---|---|
| <kbd>⌘A</kbd> | The whole file becomes the passage |
| <kbd>Esc</kbd> | Clear the loop |
| <kbd>⇧←</kbd> <kbd>⇧→</kbd> | Extend the passage left / right — or start one at the playhead |
| <kbd>C</kbd> <kbd>V</kbd> | Move the whole loop left / right (250 ms); <kbd>⇧C</kbd> <kbd>⇧V</kbd> too |
| <kbd>⌥C</kbd> <kbd>⌥V</kbd> | Move it further (2 s) |

Both move amounts are configurable in Settings. On iPhone and iPad, **Clear Loop**
is in the <kbd>⋯</kbd> menu and on a long press of the Loop button.

## Looping

This is what Artscripture is for, so it is worth knowing what it does. The time
stretcher is **never reset at a loop boundary** — audio is fed continuously
across the seam. A reset would flush the stretcher's overlap state and click on
every repetition; feeding through it means a repeat is inaudible. That is
verified rather than assumed: a looped render is compared against a file with the
same passage already laid out end to end, and the measured difference around
every wrap is exactly zero.

| Key | Action |
|---|---|
| <kbd>A</kbd> | Set loop in at the playhead |
| <kbd>S</kbd> | Set loop out at the playhead |
| <kbd>D</kbd> | Loop on / off |
| <kbd>F</kbd> | Restart the loop |

Every way of making a new loop — a drag, <kbd>A</kbd> and <kbd>S</kbd>,
<kbd>⌘A</kbd>, <kbd>⇧←</kbd> <kbd>⇧→</kbd> — starts it with looping on;
<kbd>D</kbd> is there to switch it off. A loop region that exists but is switched
off is still drawn, visibly inert —
having set it is worth remembering. **Clear Loop** is <kbd>Esc</kbd>, and in the
**Loop** menu.

### Moving the loop

<kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd> <kbd>F</kbd> is the loop row and reads
left to right. Adding <kbd>⇧</kbd> turns "set this edge at the playhead" into
"nudge it from where it is"; adding <kbd>⌥</kbd> on top makes the step bigger.

| Key | Action |
|---|---|
| <kbd>⇧A</kbd> <kbd>⇧S</kbd> | Move the loop's **in** point left / right |
| <kbd>⌥⇧A</kbd> <kbd>⌥⇧S</kbd> | …further |
| <kbd>⇧D</kbd> <kbd>⇧F</kbd> | Move the loop's **out** point left / right |
| <kbd>⌥⇧D</kbd> <kbd>⌥⇧F</kbd> | …further |
| <kbd>⇧C</kbd> <kbd>⇧V</kbd> | Move the whole loop, keeping its length |
| <kbd>⌥⇧C</kbd> <kbd>⌥⇧V</kbd> | …further |

## Speed and pitch

Speed and pitch are independent. Slowing a passage down does not transpose it,
and transposing it does not change the tempo.

| Key | Action |
|---|---|
| <kbd>Q</kbd> <kbd>W</kbd> | Slower / faster, in 5% steps |
| <kbd>⇧Q</kbd> <kbd>⇧W</kbd> | Slower / faster, in 1% steps |
| <kbd>1</kbd> <kbd>2</kbd> <kbd>3</kbd> <kbd>4</kbd> | 100% · 75% · 50% · 33% |
| <kbd>[</kbd> <kbd>]</kbd> | Pitch down / up, one semitone |
| <kbd>⇧[</kbd> <kbd>⇧]</kbd> | Pitch down / up, one cent |
| <kbd>⌥]</kbd> | Reset pitch to the original key |

Speed runs from **10% to 200%**.

Pitch is deliberately *not* on the <kbd>Q</kbd> <kbd>W</kbd> cluster: the two
being independent is the feature, and putting them on adjacent keys of the same
row would invite exactly the confusion the separation exists to avoid.
<kbd>[</kbd> and <kbd>]</kbd> read as down and up by shape.

### How good is the slowdown?

On macOS, Artscripture uses Rubber Band 4.0's **R3 “Finer”** engine — a
multiresolution, phase-locked spectral stretcher. Pitch error, measured as an FFT
peak against a reference tone:

<div class="table-scroll" markdown="1">

| Engine | Mode | At 50% speed | At 200% speed |
|---|---|---|---|
| Rubber Band R3 | Studio (default) | ~0.00 cents | a fraction of a cent |
| Signalsmith Stretch | either preset | within 0.05 cents | within 0.05 cents |
| Rubber Band R2 | Fast | up to ~26 cents | up to −108 cents |

</div>

Studio is the default and earns it. The R2 "Fast" row is why the engine is not a
user-facing choice — it exists for low-CPU scrubbing and is not a pitch
reference. iPhone and iPad use Signalsmith Stretch, which measures in the same class as
R3; Rubber Band has no iOS build.

## Volume

| Key | Action |
|---|---|
| <kbd>↑</kbd> <kbd>↓</kbd> | Volume up / down |
| <kbd>⇧↑</kbd> <kbd>⇧↓</kbd> | …in finer steps |
| <kbd>M</kbd> | Mute |

The output device is chosen from the **Playback** menu on macOS. On iPhone and iPad
routing belongs to the system, via Control Centre.

## Navigating and zooming

| Key | Action |
|---|---|
| <kbd>Z</kbd> <kbd>X</kbd> | Nudge the playhead back / forward (2 s) — <kbd>←</kbd> <kbd>→</kbd> do the same |
| <kbd>⇧Z</kbd> <kbd>⇧X</kbd> | Nudge finely (50 ms) |
| <kbd>⌥Z</kbd> <kbd>⌥X</kbd> | Rewind / skip (10 s) — <kbd>⌥←</kbd> <kbd>⌥→</kbd> do the same |
| <kbd>R</kbd> <kbd>E</kbd> | Zoom in / out, anchored on the playhead |
| <kbd>⌘9</kbd> | Zoom to the loop |
| <kbd>⌘0</kbd> | Fit the whole file |

All three nudge amounts are configurable in **Settings ▸ Playback**.

With the pointer: pinch to zoom, two-finger scroll to pan, and drag the overview
strip to move the visible window — or click (or tap) it to move the playhead there. **Drag down on the time ruler** — or ⌥-drag in
the waveform — to zoom in smoothly. **Settings ▸ Playback ▸ Invert zoom
direction** reverses that and the scroll wheel together.

**Scrub** by dragging the handle on the playhead in the time ruler sideways. The
playhead follows your pointer or finger; if the track was playing it pauses while
you drag and carries on from where you let go, and with a video open the picture
follows frame by frame. Dragging up or down from the handle still zooms, and
because the handle lives on the ruler, every loop gesture in the waveform works
exactly as before.

**Scroll Left** and **Scroll Right** are View menu items with no key: <kbd>Z</kbd>
and <kbd>X</kbd> are the nudge keys and a nudge brings the view with it, so
moving the view alone is left to the menu, the trackpad and the overview strip.

## Track marks

A single FLAC of a whole album is a wall with no landmarks. If a `.cue` sheet is
sitting beside the audio file, Artscripture parses it and draws a lane showing where
each track begins.

| Key | Action |
|---|---|
| <kbd>T</kbd> | Show / hide the track-mark lane |

The cue sheet is found by name next to the audio. Its own `FILE` line is
deliberately *not* consulted — rippers routinely write the name of a `.wav` that
was then encoded to FLAC and deleted, so matching on it would find nothing for
most real albums.

## Practice mode

Press **Practice** in the header — it is there whenever a track is open, on the
Mac, iPad and iPhone alike — or <kbd>⌘P</kbd>, or **View ▸ Practice**. It plays
your loop over and over while the speed climbs, so you can take a passage from
slow to tempo without touching anything. On the Mac it opens in its own window;
on iPad and iPhone, as a sheet.

| Key | Action |
|---|---|
| <kbd>⌘P</kbd> | Show / hide Practice — the **Practice** button in the header opens it too |
| <kbd>⌥P</kbd> | Start / stop the ramp — stopping it pauses playback too |

Give it three numbers and it works out the rest:

- **Start speed**, **end speed** and **number of repetitions.** The default is
  50% → 100% over ten passes, and the per-repetition step is computed and shown
  under the fields. Both endpoints are played, so ten repetitions from 50% to
  100% is nine steps of 5.6%, not ten.
- **An end speed below the start speed ramps down**, which is a real way to
  practise: take something you can just about play at tempo and slow it down to
  hear what your fingers are actually doing.
- **Start speed equal to end speed** drills one tempo for a set number of passes.

While it runs, the window shows which repetition you are on, the speed you are
hearing, and how many are left. **It advances when the loop comes round, not on a
timer** — a timer would drift the moment the loop length or the speed changed
underneath it, and the ramp changes the speed on purpose.

The header button follows along: while a ramp runs it reads *Rep 3 of 10 · 61%*,
filling from the left as the passes go by, with a stop button beside it. Put the
panel away and the main screen still tells you where you are; tap the readout to
bring the panel back. When the ramp finishes it reads *Ramp done · 100%*, and its
✕ returns it to the plain button.

**Stopping a ramp stops the music.** The stop button beside the readout, **Stop**
in the panel, the menu item and <kbd>⌥P</kbd> all end the ramp *and* pause
playback where it is. Dismissing a finished ramp with its ✕ does not: by then the
ramp is holding the speed you were working towards, and the music carries on.

When the last repetition finishes the ramp **holds the final speed and keeps
playing**, and the window says *Ramp complete — holding 100%*. A ramp is a speed
automation, not a transport: the end of one is the moment you have arrived at the
passage, at tempo, in the loop, which is what the exercise was for.

A ramp needs a loop. With none set, the window says so and names the keys that
fix it. Starting a ramp switches looping on for you if the region is set but
disabled.

## Sessions

| Key | Action |
|---|---|
| <kbd>⌘S</kbd> | Save the session |
| <kbd>⇧⌘S</kbd> | Save it elsewhere |

A session is a small JSON file recording the loop region, the speed, the pitch,
the playhead, the visible viewport and whether the track-mark lane is showing. It
identifies the track it belongs to, and it contains no audio.

It is written next to your audio file, with `.artscripture` **appended to the whole
filename** — `Blackbird.flac` becomes `Blackbird.flac.artscripture`. Replacing the
extension would read better, but a transcriber routinely keeps a lossless master
and a smaller copy of the same song in one folder, and a single
`Blackbird.artscripture` between them would mean whichever you opened last silently
overwrote the other's loop points.

If the folder cannot be written to — a read-only volume, say — the session goes
to `~/Library/Application Support/Artscripture/Sessions/` instead, and the app tells
you so rather than failing quietly. **Dismiss** puts that notice away to a small drive
badge beside the file name, remembered for the track; tap the badge to read it again.

Every field is optional, so a hand-edited or truncated file is repaired field by
field with a named explanation rather than being thrown away. You are invited to
read and edit these files.

## Settings

<kbd>⌘,</kbd> opens Settings:

- **Preroll** — the resume rollback, in seconds with fractions; 0 turns it off.
- **Navigation amounts** — the fine, normal and coarse nudge steps.
- **Loop movement** — the gentle and aggressive move steps.
- **Zoom** — invert the drag and scroll direction.
- **Theme** — system, light or dark. *System* follows the appearance macOS is set
  to and changes with it.

Each section can be restored to its shipped defaults.

## The shortcut window

Press <kbd>⌘/</kbd> — or **View ▸ Keyboard Shortcuts** — for a separate window
with the whole keymap drawn on a keyboard and a searchable list beside it.

- **The keyboard shows one modifier layer at a time, and follows the modifiers
  you hold.** Hold <kbd>⇧</kbd> and <kbd>A</kbd> <kbd>S</kbd> <kbd>D</kbd>
  <kbd>F</kbd> change from setting the loop's edges to moving them; add
  <kbd>⌥</kbd> and they move further. Six actions live on the <kbd>A</kbd> and
  <kbd>Z</kbd> caps alone, which is why a picture that stacked them all would
  teach nothing.
- **A layer can also be pinned** from the picker, for anyone who cannot hold two
  modifiers at once. Holding wins while you hold; the pin is what you come back
  to.
- **One filter narrows both surfaces.** Type "loop" and the list shows the loop
  actions while every key that is not one goes quiet. It matches the action's
  name, its group, its note, and the chord both written (`⌥⇧A`) and spoken
  ("option shift").
- Keys are tinted by category, and unbound keys are dimmed. Actions with no
  shortcut at all still appear in the list.

Drag the divider to resplit it; it stays where you left it between launches.

It is generated from the same action catalog the menus and this page are built
from, so it cannot fall out of step with what the keys actually do.

## Every shortcut

Sixty-five actions. Every shortcut also appears beside its item in the menus —
Select All in **Edit**, looping in **Loop**, transport, speed, pitch, volume and
output device in **Playback**.

<div class="table-scroll" markdown="1">

| Key | Action | Menu |
|---|---|---|
| <kbd>Space</kbd> | Play / pause | Playback |
| <kbd>⇧Space</kbd> | Play from start | Playback |
| <kbd>H</kbd> | Preroll on / off | Playback |
| — | Stop | Playback |
| <kbd>Z</kbd> <kbd>←</kbd> | Nudge back | Playback |
| <kbd>X</kbd> <kbd>→</kbd> | Nudge forward | Playback |
| <kbd>⇧Z</kbd> | Nudge back (fine) | Playback |
| <kbd>⇧X</kbd> | Nudge forward (fine) | Playback |
| <kbd>⌥Z</kbd> <kbd>⌥←</kbd> | Rewind | Playback |
| <kbd>⌥X</kbd> <kbd>⌥→</kbd> | Skip | Playback |
| <kbd>Q</kbd> | Slower | Playback |
| <kbd>W</kbd> | Faster | Playback |
| <kbd>⇧Q</kbd> | Slower (fine) | Playback |
| <kbd>⇧W</kbd> | Faster (fine) | Playback |
| <kbd>1</kbd> | 100% speed | Playback |
| <kbd>2</kbd> | 75% speed | Playback |
| <kbd>3</kbd> | 50% speed | Playback |
| <kbd>4</kbd> | 33% speed | Playback |
| <kbd>]</kbd> | Pitch up (one semitone) | Playback |
| <kbd>[</kbd> | Pitch down (one semitone) | Playback |
| <kbd>⇧]</kbd> | Pitch up (one cent) | Playback |
| <kbd>⇧[</kbd> | Pitch down (one cent) | Playback |
| <kbd>⌥]</kbd> | Reset pitch | Playback |
| <kbd>↑</kbd> | Volume up | Playback |
| <kbd>↓</kbd> | Volume down | Playback |
| <kbd>⇧↑</kbd> | Volume up (fine) | Playback |
| <kbd>⇧↓</kbd> | Volume down (fine) | Playback |
| <kbd>M</kbd> | Mute | Playback |
| <kbd>A</kbd> | Set loop in | Loop |
| <kbd>S</kbd> | Set loop out | Loop |
| <kbd>D</kbd> | Loop on / off | Loop |
| <kbd>F</kbd> | Restart loop | Loop |
| <kbd>Esc</kbd> | Clear loop | Loop |
| <kbd>⇧←</kbd> | Extend loop left | Loop |
| <kbd>⇧→</kbd> | Extend loop right | Loop |
| <kbd>⇧A</kbd> | Move loop in left | Loop |
| <kbd>⇧S</kbd> | Move loop in right | Loop |
| <kbd>⌥⇧A</kbd> | Move loop in left (far) | Loop |
| <kbd>⌥⇧S</kbd> | Move loop in right (far) | Loop |
| <kbd>⇧D</kbd> | Move loop out left | Loop |
| <kbd>⇧F</kbd> | Move loop out right | Loop |
| <kbd>⌥⇧D</kbd> | Move loop out left (far) | Loop |
| <kbd>⌥⇧F</kbd> | Move loop out right (far) | Loop |
| <kbd>C</kbd> or <kbd>⇧C</kbd> | Move loop left | Loop |
| <kbd>V</kbd> or <kbd>⇧V</kbd> | Move loop right | Loop |
| <kbd>⌥C</kbd> or <kbd>⌥⇧C</kbd> | Move loop left (far) | Loop |
| <kbd>⌥V</kbd> or <kbd>⌥⇧V</kbd> | Move loop right (far) | Loop |
| <kbd>⌥P</kbd> | Speed ramp on / off | Loop |
| <kbd>⌘A</kbd> | Select all (the whole file becomes the loop's passage) | Edit |
| <kbd>⌘X</kbd> <kbd>⌘C</kbd> <kbd>⌘V</kbd> | Cut / copy / paste — in text fields | Edit |
| <kbd>⌘0</kbd> | Fit whole file | View |
| <kbd>⌘9</kbd> | Zoom to loop | View |
| <kbd>R</kbd> | Zoom in | View |
| <kbd>E</kbd> | Zoom out | View |
| — | Scroll left / right | View |
| <kbd>T</kbd> | Track marks | View |
| <kbd>⌘/</kbd> | Keyboard shortcuts | View |
| <kbd>⌘P</kbd> | Practice | View |
| <kbd>⌘O</kbd> | Open… | File |
| <kbd>⌘S</kbd> | Save | File |
| <kbd>⇧⌘S</kbd> | Save As… | File |
| <kbd>⌘,</kbd> | Settings… | Artscripture |

</div>

Rebinding is not available yet. The bindings live in a single catalog and the app
is built so a user-editable table can replace it, but the editor has not been
written.

---

Something here wrong, or missing? [Open an issue]({{ site.new_issue_url }}) — see
the [support page]({{ '/support/' | relative_url }}).
