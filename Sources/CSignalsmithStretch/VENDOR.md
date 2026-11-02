# Vendored: Signalsmith Stretch

Third-party source, copied in verbatim. **Do not edit these files.** A local fix
would be silently reverted by the next update and would not exist upstream; if
something needs changing, change `signalsmith_stretch_shim.cpp` or report it
upstream.

## What is here, and where it came from

| Path | Upstream | Version | Licence |
|---|---|---|---|
| `vendor/signalsmith-stretch/` | [Signalsmith-Audio/signalsmith-stretch](https://github.com/Signalsmith-Audio/signalsmith-stretch) | 1.4.0 (header unchanged on `main` through `88061fd`, Oct 2026) | MIT |
| `vendor/signalsmith-linear/` | [Signalsmith-Audio/linear](https://github.com/Signalsmith-Audio/linear) | 0.6.6 | MIT |

The stretch header was copied in January 2026 from `main`, and was labelled 1.3.2
here. It is byte-identical to the later 1.4.0 tag: every upstream commit since has
touched only the CMake pin on `linear` and the `cmd/` tool, never the header.

Licence texts are in `LICENSES/` at the repository root and are reproduced in
`NOTICE`, which is what ships.

**These are two repositories, not one.** `signalsmith-stretch.h` opens with

```cpp
#include "signalsmith-linear/stft.h" // https://github.com/Signalsmith-Audio/linear
```

and the stretch tarball does not contain it — upstream's CMake pulls it with
`FetchContent` at build time, pinned to tag 0.6.6 on `main` (1.4.0 itself pins
0.6.4). That is the version above. Updating one library means checking the other,
and the pin in upstream's `CMakeLists.txt` is where to look for which pairing is
intended.

Only the headers actually reached are copied: `stft.h`, `fft.h`, and
`platform/fft-accelerate.h`. Since 0.6, `fft.h` can also include
`platform/fft-cmsisdsp.h` and `platform/fft-linear.h`, but only under
`SIGNALSMITH_USE_CMSISDSP` / `SIGNALSMITH_USE_XSIMD`, which nothing here defines,
so those are not vendored either. `linear.h` is **not** here, deliberately — nothing
includes it, and its Accelerate backend has an `#include <iostream>` that logs to
stderr when an expression is unoptimised, which is not something to have anywhere
near a render thread.

## Refreshing

```sh
curl -sL https://github.com/Signalsmith-Audio/signalsmith-stretch/archive/refs/heads/main.tar.gz | tar xz
curl -sL https://github.com/Signalsmith-Audio/linear/archive/refs/tags/<tag>.tar.gz | tar xz
```

then copy the four headers into place and re-run the suites. `git diff` on this
directory is the upstream changelog you actually care about, which is the reason
the files are byte-identical to upstream and the reason the pre-commit
whitespace hooks exclude this directory.

The suites say whether the update is *acceptable*; they do not say whether it
*changed anything*. For that, render a fixed, seeded input through the stretcher
before and after, in release, at both presets and at time ratios 0.5, 1 and 2, and
compare the raw output byte for byte — except the standard preset at time ratio 2,
which is random (see below). The 0.3.1 → 0.6.6 update was done that way: every deterministic
configuration bit-identical, start delays and pitch identical, CPU within 1%.

## Findings from reading the source, worth not rediscovering

**No allocation on the render path, but only just.** `process()` calls
`tmpProcessBuffer.resize(length)` on every block; that is safe *because*
`configure()` already sized it to `blockSamples + intervalSamples` and `length`
can never exceed that, so `std::vector` keeps its capacity. It is a property of
the sizes, not a guarantee in the code. A future upstream change to either could
turn a resize into a reallocation on the audio thread without looking like it
changed anything.

**One theoretical exception.** `findPeaks()` does `peaks.emplace_back` into a
vector reserved at `bands/2` in `configure()`. Each peak consumes at least two
bands, so `bands/2` is exactly the bound when `bands` is even — which it is for
the packed spectrum this uses. An odd `bands` would make the worst case
`ceil(bands/2)` and could reallocate. Not reachable today; worth re-checking if
`stft.h`'s `_fftBins` calculation ever changes. (Re-checked for 0.6.6: `configure`
gained an `fftMinSize` argument, but the stretch header never passes it, so it
defaults to `blockSamples` and the FFT size and bin count come out as before.)

**Above a stretch factor of 2, the output is random — on purpose, and differently
every run.** Past `maxCleanStretch` (2), the stretcher randomises per-bin time
factors to avoid phasiness, drawing from an engine the default constructor seeds
with `std::random_device`. The shim uses that constructor. So two renders of the
same input at the standard preset and 0.5× speed (time ratio 2.0) are *not*
bit-identical — 99.9% of samples differ, by up to half the signal RMS, between two
runs of the same build. The cheaper preset was bit-identical run to run at the same
time ratio, in the same measurement. Two consequences: comparing outputs across an
update only means anything below that threshold, and a differential test that
compares two separately constructed stretchers is only valid there too — which is
why `signalsmithLoopingIsIndistinguishableFromAContiguousRender` runs at ratio 1.0.
`SignalsmithStretch(long seed)` exists if a test ever needs to go further.

**`splitComputation` matters more to us than to upstream.** The library defaults
it *off* for `presetDefault`, which is right for offline work. Off means one call
per interval does an entire FFT block while its neighbours do almost none — a
periodic spike against a hard deadline. `SignalsmithStretcher` turns it on
always; see the comment there.

**Accelerate is available but not enabled.** Defining `SIGNALSMITH_USE_ACCELERATE`
makes `fft.h` pull in `platform/fft-accelerate.h` (vDSP), and that header is
already vendored so the switch is one `.define` plus `.linkedFramework`. It is
off for now because the backend landed with the plain C++ FFT and every number
recorded — pitch, length, latency, loop seam — was measured against that. Turn it
on as its own change, with its own before/after CPU measurement, so a regression
has one candidate cause rather than two.
