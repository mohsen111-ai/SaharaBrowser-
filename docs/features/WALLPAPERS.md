# Wallpapers

**Status: plan only, nothing implemented.** Goal: all **61** wallpapers (31 still, 30 live) from the design,
on the home screen and new-tab page.

## What the design contains

The wallpapers are **drawn in code, not images or videos**, which is why shipping all of them is cheap in
app size.

| IDs | Set | Kind | Source in the design canvas |
|---|---|---|---|
| 1–16 | one | still | `Wall.dc.html`, `n` = 1–31 |
| 17–31 | one | live | same component |
| 32–46 | two | still | `Wall2.dc.html`, `n` = 1–30 (ID = n + 31) |
| 47–61 | two | live | same component |

- **Set one** is data-driven: a table of scene specs (sky gradient, sun or moon, stars, four dune layers,
  camel, dust, highlights) feeding one renderer; 19 named CSS animations (twinkle, rise, sway, walk, drift,
  aurora, shooting stars, ripples, ...).
- **Set two** is procedural: each scene is a small program with a seeded random generator
  (`seed = n * 7919 + 101; seed = seed * 16807 % 2147483647`), 24 named animations, one blur filter and one
  clip path. Patterns, arches, maps, aerial views, star trails, an hourglass, an astrolabe, and so on.
- Names are listed in the design (`Wallpapers.dc.html`); keep them as the display names.
- The rotation order on Home interleaves the sets: for k = 0..14 → `1+k, 32+k, 17+k, 47+k`, then `16`
  (61 entries). Settings filter it: Still / Live / Both.

## Behavior (from the design)

- Change when entering the app, when leaving it (next one queued), and on each new home page. Each toggle in
  Settings. Crossfade **900 ms** ("Calm"): two layers swap opacity and the old scene stays until the new one
  is fully in.
- Live wallpapers pause on battery saver and show a still frame instead; also when the system animation
  scale is 0 (reduced motion).
- Shown on the home screen and new-tab page only, never behind a web page.

## Porting plan (Jetpack Compose `Canvas`)

- One shared **frame clock**, capped at **30 fps**, for all live scenes; scenes are pure functions
  `draw(scope, timeSeconds)`. A still is the same function at a fixed time, which doubles as the
  battery-saver frame.
- **Set one:** export the spec table to JSON/Kotlin once and build one renderer. **Set two:** port the 30
  programs one by one, reusing the same random generator so the scenes come out identical.
- Gradients map directly; SVG paths map to `Path`; CSS keyframes become time functions. The one blur effect
  uses `RenderEffect` blur on Android 12+ with a gradient approximation on older devices (Fenix's `minSdk` to
  be confirmed).
- No per-frame allocations; stop the clock when the surface isn't visible, the app is backgrounded, or a
  page is showing. During a crossfade, freeze the outgoing scene at its current frame.

## Checking fidelity

Render each design scene to PNG at t = 0 (and one fixed time for live ones) using headless Chromium on the
design HTML, render the Android scene at the same sizes, and compare. The golden images double as
regression tests. Test the live set on a low-end phone for heat and battery.

## Order of work

1. Renderer + set one stills (16)  2. set one live (15)  3. set two stills (15)  4. set two live (15),
checking battery after each live batch.
