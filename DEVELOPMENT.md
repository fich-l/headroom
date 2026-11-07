# Headroom — developer notes

Technical background, build instructions and test tools. For users: see [README.md](README.md).

## How it works

1. A **1×1-pixel EDR window** (the top-left pixel, hidden by the rounded display corner) tells macOS
   that EDR content is on screen, so the panel opens its extra brightness range.
2. Headroom multiplies the display's **gamma (transfer) table** by the chosen level. Values above
   1.0 land in that extra range.

The gamma table is applied after macOS has drawn all windows. That's why nothing can drop the boost
during animations, which is exactly what went wrong with the overlay approach.

## Why not an overlay (BrightXDR's white screen)

BrightXDR draws a full-screen window filled with an EDR value of 2.0 and multiply-blends it over
everything. During Space switches and Mission Control, macOS turns every window into a flat SDR
snapshot (values clamped to 0…1, no blend modes), so that window becomes plain white for the whole
animation.

This was **measured, not guessed**: `FlashTest/` records the display in HDR with ScreenCaptureKit
while it switches Spaces and opens Mission Control.

| Approach | Result |
|---|---|
| Original BrightXDR | White for the whole switch animation (≈55 of 58 frames per switch) |
| 38 overlay variants (all window levels, Space behaviours, content types, blend modes) | Same white flash |
| Overlay with negative alpha | No white, but the boost vanishes during the animation |
| **Gamma table (Headroom)** | **0 white frames** |

The look was then compared with the original BrightXDR side by side in the A/B app (below).

## Build from source

Only the free **Xcode Command Line Tools** are needed (`xcode-select --install`):

```bash
git clone https://github.com/fich-l/headroom.git
cd headroom
./build.sh            # → build/Headroom.app
./make_release.sh     # → build/Headroom.zip (release asset)
```

## Developer tools: A/B lab, flash test, pixel test

```bash
./build_original.sh      # build/BrightXDR Original.app: untouched upstream BrightXDR
./build_compare.sh       # build/Headroom Lab.app: A/B toggle and lab (GPL-3)
./build_flashtest.sh     # FlashTest/XDR Flash Test.app
./test.sh                # pixel-equivalence test of the lab overlay vs. BrightXDR
```

**Headroom Lab** toggles between the untouched original BrightXDR (it starts and quits the real app)
and Headroom at a chosen level:
- ⌃⌥⌘B: Original ⇄ Headroom
- ⌃⌥⌘N: Off
- ⌃⌥⌘M: Mission Control

**Flash test** needs Screen Recording and Accessibility once. Build it once: rebuilding changes its
signature and drops the permissions. The lab must be running.

```bash
open -W "FlashTest/XDR Flash Test.app" --args --modes "OFF|ORIGINAL|GAMMA:p1:1.5625" --out "$PWD/build/ft"
python3 FlashTest/analyze.py build/ft/frames.csv
```

`Support/` works around a damaged Command Line Tools SDK (missing `CarbonCore/Script.h`) and is only
used when needed.

## Known limitations

- Apps that also change the display's gamma table (for example f.lux) conflict with Headroom.
- HDR content is limited to the boosted range while Headroom is on.
- Screenshots and screen recordings don't include the gamma table, so they don't show the boost.
- macOS ignores gamma tables on M5 Pro / M5 Max, so Headroom can't work there.
