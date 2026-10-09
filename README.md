# Sahara

A fast, quiet, desert-themed Android browser for personal use, built as a fork of Firefox for Android
(Fenix on GeckoView). Mascot: **Rimal the camel**.

> **Status: planning and build scaffolding.** There is no browser code yet. The pinned upstream, the
> fetch/patch tooling and the plans below are in place and tested; the first milestone is building the
> unmodified upstream into an APK (see [docs/BUILD.md](docs/BUILD.md)).

## What makes it Sahara

| | |
|---|---|
| **Caravan downloads** | Every download is split across 4, 6, 8, 10, 12 or 16 parallel connections (default 8). [Plan](docs/features/DOWNLOADS.md) |
| **Dune Shield** | The full uBlock Origin is built in and strict by default, tuned so sites keep working. [Plan](docs/features/DUNE_SHIELD.md) |
| **Speed** | GeckoView network, prefetch and cache settings tuned against a benchmark, not folklore. [Plan](docs/features/PERFORMANCE.md) |
| **Desert design** | Dune Gold / Oasis Teal / Sahara palette, Sora + Figtree, the cream-sun icon, and 61 wallpapers (31 still, 30 live). [Spec](docs/DESIGN.md), [wallpapers](docs/features/WALLPAPERS.md) |

The design is the source of truth: <https://claude.ai/artifact/3o53n4Rr9KXD6zxo77jJNg>

## How this repo works

Firefox for Android is part of the Firefox source tree and is far too large to copy here. Instead this repo
holds **only Sahara's own changes** and a script that fetches a pinned upstream release and applies them:

```
upstream/PIN          the exact Firefox for Android release we build on (tag, changeset, URL, SHA-256)
overlay/              NEW files, copied into the upstream tree (never overwrites an upstream file)
patches/              changes to EXISTING upstream files, applied in filename order
scripts/              fetch-upstream.sh, apply-overlay.sh, bump-upstream.sh, test.sh
design/tokens.json    palette, type and icon values from the design
docs/                 architecture, design spec, roadmap, one plan per feature
build/                (git-ignored) downloaded tarball and the patched tree
```

Keeping changes as small patches plus new files is what makes monthly upstream updates cheap.

```sh
scripts/fetch-upstream.sh    # download (~0.8 GB), verify SHA-256, extract to build/upstream
scripts/apply-overlay.sh     # add overlay files, apply patches
scripts/test.sh              # self-test of the tooling (offline, uses a fake tarball)
scripts/bump-upstream.sh     # move the pin to the newest final release (review the diff)
```

## Docs

- [Architecture](docs/ARCHITECTURE.md): the overlay model and the upstream code we hook into
- [Design spec](docs/DESIGN.md): tokens, screens, icon
- [Roadmap](docs/ROADMAP.md): phases and decisions made so far
- [Build and install](docs/BUILD.md): signing, CI, updating
- Features: [downloads](docs/features/DOWNLOADS.md), [Dune Shield](docs/features/DUNE_SHIELD.md),
  [speed](docs/features/PERFORMANCE.md), [wallpapers](docs/features/WALLPAPERS.md)

See [NOTICE.md](NOTICE.md) for licensing and trademarks.
