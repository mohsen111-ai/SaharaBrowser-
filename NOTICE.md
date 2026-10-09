# Notice

Sahara is a **personal-use** browser. It is not published to any store and is not distributed to anyone.
The notes below matter only if that ever changes.

## What Sahara is built from

| Component | License | Notes |
|---|---|---|
| Firefox for Android (Fenix), Android Components, GeckoView, Gecko | MPL-2.0 | Fetched at build time from Mozilla's official source tarball; never copied into this repo. |
| uBlock Origin (bundled as "Dune Shield") | GPL-3.0 | Author: Raymond Hill. If we modify its defaults, the modified source and license stay with the build. |
| Sora, Figtree (fonts) | SIL OFL 1.1 | Bundled with the app, not loaded from Google Fonts at runtime. |

## Trademarks

"Firefox", "Mozilla" and their logos are Mozilla trademarks. Sahara does not use them: the app has its own
name, icon and branding, and must not ship Mozilla's official branding.

## Sahara's own files

The license for the files in `overlay/`, `patches/` and `scripts/` has not been chosen yet. Because they
live inside an MPL-2.0 tree, MPL-2.0 is the natural choice if the project is ever shared.

## If Sahara is ever shared

Anyone receiving a build must also be able to get the corresponding source for the MPL-2.0 files and for
the (modified) GPL-3.0 uBlock Origin, with all license notices intact, and the Mozilla branding must
already be removed. Decide this before the first build leaves your own phone.
