# Architecture

## The overlay model

Sahara = **pinned upstream Firefox for Android** + **`overlay/`** (new files) + **`patches/`** (edits to existing files).

```
upstream/PIN ──► fetch-upstream.sh ──► build/upstream (pristine)
                                             │
              overlay/  ──► apply-overlay.sh ┤  new files copied in
              patches/  ──►                  ┘  patch -p1, in order
                                             ▼
                                   build/upstream (Sahara)  ──► build ──► APK
```

Why: the Firefox tree is gigabytes, Mozilla ships a new version roughly every four weeks, and this
browser parses untrusted web content, so staying current is a security requirement, not a nicety. Small
patches plus new files make each upgrade a short, mechanical job: bump the pin, `--reapply`, repair
whichever patch fails.

**Rules of thumb**

- New behavior lives in new files (overlay). Existing files get the smallest possible hook (patch).
- Prefer new packages in existing Gradle modules over new modules; no build-system edits needed.
- Never edit generated or vendored upstream files.

## Upstream pin

Firefox for Android **157.0.1** (`FIREFOX-ANDROID_157_0_1_RELEASE`, changeset `737ec77d7987`), built from
Mozilla's official source tarball. Mozilla's Mercurial server rejected a `.tar.gz` archive request
("Archive type not allowed"), so the tarball comes from `archive.mozilla.org` instead. The SHA-256 in `upstream/PIN` matches Mozilla's published `SHA256SUMS`
and a full streamed download. Fenix, Android Components and GeckoView all live under `mobile/android/`.

Move the pin with `scripts/bump-upstream.sh`.

## Upstream code we hook into

All paths are inside the Firefox tree. **Verified 2026-10-09** against `mozilla-central` tip and the
157.0.1 tarball listing unless marked otherwise.

| Area | Path / API | What it is, and why we care |
|---|---|---|
| Downloads | `mobile/android/android-components/components/feature/downloads/.../AbstractFetchDownloadService.kt` | Foreground service. `performDownload(state, useHttpClient = false)` is where a segmented download plugs in. Resume uses `Range: bytes=N-`. Copies in 32 KB chunks; progress throttled to 750 ms. |
| Downloads | `.../feature/downloads/filewriter/DefaultDownloadFileWriter.kt` | `useFileStream(download, append, scopedStorage, ...)` gives a **sequential** `OutputStream` (MediaStore `IS_PENDING` row or SAF document; legacy `FileOutputStream`). Segmented downloads need a positional writer next to it. |
| Downloads | `.../feature/downloads/` (`ContentRange.kt`, `DownloadEstimator.kt`, `DownloadStorage.kt`, `db/`) | Reusable range parsing, ETA and persistence. |
| Downloads | `mobile/android/fenix/app/src/main/java/org/mozilla/fenix/downloads/DownloadService.kt` | Fenix's subclass; `httpClient = components.core.client`. |
| Downloads UI | `mobile/android/fenix/app/src/main/java/org/mozilla/fenix/downloads/listscreen/` | Compose list screen: the Caravan screen replaces or wraps it. |
| Extensions | `.../concept/engine/webextension/WebExtensionRuntime.kt` | `installBuiltInWebExtension(id, url, onSuccess, onError)` ("takes a resource path or a local `.xpi` resource URL"), `setAllowedInPrivateBrowsing(...)`, `enableWebExtension(...)`. |
| Engine | `.../concept/engine/Engine.kt` | `speculativeConnect(url)` opens a speculative connection to the URL's host. Has **no** generic "set a Gecko pref" method. |
| Gecko prefs | `mobile/android/app/geckoview-prefs.js` | Preprocessed file of `pref("name", value);` lines. This is where GeckoView-specific pref defaults go. Already sets `network.http.max-persistent-connections-per-proxy` (20); sets no `browser.cache.*`. |
| Docs | `mobile/android/docs/fenix.md`, `mobile/android/docs/geckoview/` | Upstream's own notes (the Fenix README still describes the old standalone-repo workflow; do not follow it). |

**Not yet verified** (confirm in the phase that needs it; each is noted in the feature plan):
`Core.client` is `GeckoViewFetchClient`; where Fenix registers its own built-in extensions; Fenix's
`minSdk`; how to build and sign the tree (see [BUILD.md](BUILD.md)).

## Planned code layout (inside the overlay)

```
overlay/mobile/android/
  android-components/components/feature/downloads/src/main/java/mozilla/components/feature/downloads/segmented/
      SegmentPlanner, SegmentedFileWriter, SegmentedDownloader        (Caravan engine)
  fenix/app/src/main/java/app/sahara/
      theme/        Sahara palette and typography on top of Fenix's theme
      shield/       Dune Shield: install, settings, bridge to uBlock Origin, sheet UI
      caravan/      downloads screen: speed meter and lanes
      home/         3-page home, wallpaper host
      wallpapers/   renderer and the 61 scenes
  fenix/app/src/main/res/ ...   sahara_-prefixed resources: icon, Rimal, fonts
  fenix/app/src/main/assets/extensions/ublock/                        (bundled uBlock Origin)
```

Patches will be limited to: app id and name, theme hook-up, the `performDownload` hand-off, built-in
extension registration, the pref lines, and the home/toolbar swaps.
