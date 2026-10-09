# Design spec

Source of truth: the design canvas, <https://claude.ai/artifact/3o53n4Rr9KXD6zxo77jJNg> (14 boards).
Machine-readable values are in [`design/tokens.json`](../design/tokens.json). This file records what the
design says and where we deliberately differ.

## Brand

- **Name:** Sahara (lowercase wordmark in Sora 600). **Tagline:** "A quiet, fast browser for the open dunes."
- **Mascot:** Rimal the camel: standing, walking, and caravan (three walking). Appears in the icon, splash,
  loading states and empty tabs. Gold when active, Sunbleached when quiet.
- **Palette:** Dune Gold `#D97706` (primary) · Oasis Teal `#0D9488` (accent: protection, success, links) ·
  Sahara `#1C1917` (background) · Sandstone `#292524` (surfaces) · Sunbleached `#FAFAF9` (text).
  The design adds tints (`#fbbf24`, `#2dd4bf`, `#fde68a`, greys); see the tokens file.
- **Type:** Sora (titles, wordmark) and Figtree (interface), bundled in the app.
- **Shape:** icon corner 22.5%; cards 20–24 dp; pills 28–36 dp; touch targets at least 44 dp.

## App icon: option 5, "Cream sun"

Background `#1C1917`, sun `#fde68a`, ground `#D97706`, camel `#1C1917`. Softer and less orange than the
primary teal variant, so the in-app logo (Home header, splash) uses it too.

To do for Android: refit the art to the adaptive-icon safe zone (the circle mask would clip the full-bleed
square), add a **monochrome** layer for Android 13 themed icons, and a legacy fallback. Source geometry:
`Icon.dc.html` in the canvas (SVG, 640-unit square, horizon-clipped sun disc, ground silhouette, camel).

## Screens

| Screen | Contents (from the design) |
|---|---|
| **Splash** | 7 s loop: sunrise over dunes, three camels crossing, wordmark letters rising, thin gold progress bar. Honors reduced motion. Android's system splash can only animate an icon, so this is an in-app screen right after it. |
| **Home** (3 pages) | Wallpaper background. Header: icon, wordmark, Dune Shield status button, next-wallpaper button. Greeting by time of day. **Page 1:** search pill, 8 shortcuts, "Dune Shield is on" card. **Page 2:** recent pages. **Page 3:** live Caravan downloads. Page dots; wallpaper chip (name + Still/Live). Bottom bar: address pill, tab count, menu. |
| **Tabs** | Segments: Tabs · Private · Camps. Stacked cards, active tab expanded with a gold ring; "Close all"; gold "New tab" button (teal in Private). Empty states with Rimal. "Camps" = grouped tabs. |
| **Browsing + Dune Shield sheet** | Shield button in the toolbar opens a sheet: total blocked on this page, breakdown (ads, trackers, third-party scripts), per-site switch, "uBlock Origin panel", "Report broken page". |
| **Settings** | *Caravan downloads:* connections per download (4/6/8/10/12/16, default 8, with a hint per value), ask where to save (off), resume after network changes (on). *Dune Shield:* blocking level, hide ad spaces (on), block cookie notices and popups (on), filter lists, allowed sites. *Speed:* preload likely pages (on), look up links early (on), cache size 512 MB. *Wallpapers:* Still/Live/Both; change on enter / on leave / on each new home page (all on); pause live on battery saver (on). *Appearance:* Sahara (dark) / Sunbleached (light) / System. |
| **Caravan downloads** | Aggregate speed meter with live bars and "N connections active". Per download: file, size, speed, **lanes** (one progress segment per connection), percent, ETA, pause/resume. "Pause all / Resume all", "Clear finished". |
| **Wallpapers** | 61 scenes in two sets. See [features/WALLPAPERS.md](features/WALLPAPERS.md). |
| **Motion** | "Unhurried, never idle." Duration tokens: **Quick** 150 ms (taps, toggles, presses), **Standard** 280 ms (sheets, tabs, lists), **Calm** 900 ms (wallpaper crossfade), **Ambient** 5–70 s (live wallpapers, loaders). Easing `cubic-bezier(.4, 0, .2, 1)`; new-tab card uses an overshoot `cubic-bezier(.2, .9, .3, 1.25)` (grows from 80%, plus button turns a quarter). Caravan lanes: each connection fills its own lane at its own pace (4 s loop in the demo). **Rimal loader** (5 s loop) is shown while a page loads and on pull-to-refresh, and **replaces the spinner**. |

## Where we differ from the design (decisions)

- **Dune Shield default.** The design shows **Balanced** as the default. The decision is **Strict, tuned so
  sites keep working**, with Balanced one tap away. The Settings and Shield-sheet boards should be updated
  to match; the per-site control becomes three-state (Strict / Balanced / Off). See
  [features/DUNE_SHIELD.md](features/DUNE_SHIELD.md).
- **Icon.** Option 5 replaces the teal-ground primary shown on the brand board.
- **Camps.** Maps onto whatever tab-grouping the pinned Fenix provides; to be confirmed when the tabs
  screen is built.
