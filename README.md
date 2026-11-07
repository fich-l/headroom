<p align="center">
  <img src="docs/icon.png" width="160" alt="Headroom icon">
</p>

<h1 align="center">Headroom</h1>

<p align="center">
  <b>Your MacBook Pro has more light than macOS lets you use. Headroom unlocks it.</b><br>
  Up to 1.75× brighter, everywhere. Free and open source: a free alternative to Vivid.
</p>

<p align="center">
  <a href="#install">Install in one line</a> ·
  <a href="#compatibility">Compatibility</a> ·
  <a href="#faq">FAQ</a>
</p>

---

The XDR displays in MacBook Pros and the Pro Display XDR can get much brighter than macOS allows for
everyday use. The extra range (the display's EDR *headroom*) is reserved for HDR video and photos.
**Headroom** puts it to use for everything on screen: text, apps, the desktop.

It started as a fork of [BrightXDR](https://github.com/starkdmi/BrightXDR) and fixes its best-known
problem: **the screen turning white when you switch Spaces or open Mission Control.**

> [!IMPORTANT]
> Headroom uses public macOS APIs only and macOS stays in control of the display, so it shouldn't
> harm your hardware. Higher brightness means more heat and battery use, and macOS may dim the panel
> when it gets warm. There is no warranty (see [LICENSE](LICENSE)).

## Why you'll want it

- ☀️ **Readable in sunlight.** On a terrace, by a window, on the train: the extra brightness makes
  the difference between squinting and working.
- ⌨️ **Nothing new to learn.** Your brightness keys and the Control Center slider work as before;
  Headroom simply lifts the whole range.
- 🎨 **Looks right.** Every pixel is scaled evenly, so colours and contrast stay true. It isn't a
  washed-out filter.
- 🆓 **Free, for good.** No trial, no licence key, no subscription, and the source is open.

## Features

- **Five levels:** Off · Low 1.19× · Medium 1.38× · **High 1.56× (default)** · Maximum 1.75×.
- **No white flash** on Space switches, swipes between desktops or Mission Control, and the boost
  stays on during the animations.
- **Starts boosted.** Launching Headroom, from the Dock too, turns the boost on at your last level.
- **Launch at Login** from the menu.
- **Nothing left behind.** Quitting (or a crash) instantly returns the display to normal.
- Native and tiny: Apple silicon and Intel binary, no background services, no network access.

## Compatibility

| Mac / display | Status |
|---|---|
| MacBook Pro 14"/16" **M4** (2024) | ✅ Tested (Mac16,1, macOS 15.7) |
| MacBook Pro 14"/16" M1 Pro/Max (2021), M2 Pro/Max (2023), M3 (2023) | ✅ Should work (same panel type, untested) |
| MacBook Pro 14" **M5** (2025) | ⚠️ Untested |
| MacBook Pro **M5 Pro / M5 Max** | ❌ Reportedly not working: macOS ignores gamma tables on these models ([details](https://github.com/fackelmeyer/illuminate#readme)) |
| Pro Display XDR | ✅ Should work (untested) |
| Studio Display XDR | ⚠️ Untested |
| MacBook Air, 13" MacBook Pro, non-XDR displays | ❌ No XDR headroom; Headroom shows "No XDR display detected" |

**macOS 13 Ventura or later.** If you try it on a Mac that isn't listed as tested, please
[open an issue](../../issues) and say whether it worked.

**Find your model:**  → About This Mac. For the model identifier, hold ⌥ and choose
 → System Information.

## Install

### Option 1: one command (easiest)

Open **Terminal** (⌘ Space, type "Terminal"), paste this line and press Return:

```bash
curl -fsSL https://github.com/fich-l/headroom/releases/latest/download/Headroom.zip -o /tmp/Headroom.zip && ditto -x -k /tmp/Headroom.zip /Applications && open /Applications/Headroom.app
```

It downloads the latest release, puts **Headroom** in your Applications folder and starts it. A sun
icon appears in the menu bar, and the screen gets brighter.

### Option 2: download manually

1. Download **Headroom.zip** from [Releases](../../releases/latest) and double-click it.
2. Drag **Headroom** into your **Applications** folder.
3. Double-click Headroom. macOS will say it can't check the app for malware, because Headroom isn't
   notarized by Apple (that needs a paid developer account). To open it anyway:
   - **macOS 15 Sequoia and later:** click **Done**, open **System Settings → Privacy & Security**,
     scroll down to "Headroom was blocked…" and click **Open Anyway**.
   - **macOS 13–14:** right-click Headroom → **Open** → **Open**.

   You only have to do this once.

### Optional: keep it in the Dock

Drag Headroom from Applications into the Dock. A click starts it, and while it's running a click
opens its menu.

## Use

Click the **sun** in the menu bar:

| Menu | |
|---|---|
| Off · Low · Medium · High · Maximum | brightness level (keys 0–4 while the menu is open) |
| Launch at Login | start Headroom with your Mac |
| Quit Headroom | display back to normal immediately |

Your normal brightness keys and slider keep working; Headroom multiplies whatever brightness macOS
is set to.

> [!TIP]
> The menu-bar icon can be hidden behind the camera notch when the menu bar is full. Quit a menu-bar
> app you don't need, or hold ⌘ and drag Headroom's sun further right.

## Uninstall

Quit Headroom from its menu and drag it from Applications to the Trash. Turn off Launch at Login
first if you enabled it.

## Known limitations

- **f.lux** and other apps that change the display's gamma table conflict with Headroom. Night Shift
  and True Tone are fine.
- **HDR videos and photos** are limited to the boosted range while Headroom is on, so their
  brightest highlights are clipped. Switch Headroom off for HDR viewing.
- Screenshots and screen recordings don't show the boost (it's applied after the screen image is
  made).

## How it works

1. A **1×1-pixel EDR window** (the top-left pixel, hidden by the rounded display corner) tells macOS
   that EDR content is on screen, so the panel opens its extra brightness range.
2. Headroom multiplies the display's **gamma (transfer) table** by the chosen level. Values above
   1.0 land in that extra range.

The gamma table is applied after macOS has drawn all windows. That's why nothing can drop the boost
during animations, which is exactly what went wrong with the overlay approach.

### Why BrightXDR turned white

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

<details>
<summary>Developer tools: A/B lab, flash test, pixel test</summary>

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
</details>

## Headroom vs. Vivid

[Vivid](https://www.getvivid.app/) is a polished commercial app that does the same job. If you want
support, a team licence or an M5 Pro/Max Mac, it's a good choice. If you'd rather not pay:

| | Headroom | Vivid |
|---|---|---|
| Price | **Free** | One-time purchase (from about €10) |
| Source code | Open (MIT) | Closed |
| Brightness keys keep working | ✅ | ✅ |
| M5 Pro / M5 Max | ❌ | ✅ |
| Install | One Terminal line or download | Mac App Store, Setapp |

Other open-source options: [BrightIntosh](https://github.com/niklasr22/BrightIntosh) (also in the
Mac App Store), [Illuminate](https://github.com/fackelmeyer/illuminate),
[xdr-lift](https://github.com/Justaboringname/xdr-lift). Also worth a look:
[Lunar](https://lunar.fyi), [BetterDisplay](https://github.com/waydabber/BetterDisplay).

## FAQ

**Is it safe for my display?**
Headroom only asks macOS for brightness the panel is built for: these XDR panels are specified for
1,000 nits sustained full-screen. It uses public APIs, and macOS stays in charge; if the display gets
too warm, macOS dims it on its own.

**Does it cost battery?**
More light needs more power, as with any brighter screen. Headroom itself does almost nothing: it
sets a table and redraws one pixel a few times a second. Use a lower level or Off when you're on
battery and don't need it.

**Why is Maximum 1.75× and not 2×?**
The levels were tuned side by side against the original BrightXDR: 1.75× is already brighter than
BrightXDR's 2× setting looked, and High (1.56×) is the default sweet spot.

**Will it survive a restart?**
Turn on *Launch at Login* in the menu, and Headroom comes back at your last level.

**Is it really free? What's the catch?**
No catch. It's a hobby project built on other people's open-source work (see Credits), so it's
shared the same way.

## Credits

- [BrightXDR](https://github.com/starkdmi/BrightXDR) by Dmitry Starkov: the starting point and the
  reference Headroom was compared against.
- [xdr-lift](https://github.com/Justaboringname/xdr-lift) by Yihan Zhu and
  [Illuminate](https://github.com/fackelmeyer/illuminate) by Jonas Fackelmeyer: the gamma-table
  technique.
- [BrightIntosh](https://github.com/niklasr22/BrightIntosh): read as a reference.
- Written with **Claude Code** (Anthropic's AI coding assistant), directed and tested by the project
  owner.

Everything in detail, including what was copied from where and under which license:
**[NOTICE.md](NOTICE.md)**.

## License

Headroom's own code: **MIT** ([LICENSE](LICENSE)). The folders `Original/`, `Compare/` and
`Tests/PixelEquivalence/` contain or reproduce BrightXDR code and are **GPL-3.0**. The Headroom app
itself contains no GPL code.

Not affiliated with Apple. Apple, Mac, MacBook Pro and Pro Display XDR are trademarks of Apple Inc.
