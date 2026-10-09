# Roadmap

Nothing below is implemented yet except where ticked.

## Decisions made

| Topic | Decision |
|---|---|
| Name / mascot | Sahara / Rimal the camel |
| Audience | Personal use only; sideloaded; no store. Package id `app.sahara.browser`; own signing key |
| Upstream | Firefox for Android 157.0.1 from Mozilla's official tarball; bump monthly |
| Repo shape | Overlay (new files) + patches (edits); no copy of Firefox in the repo |
| App icon | Option 5, "Cream sun" |
| Dune Shield default | **Strict, tuned so sites keep working**; Balanced available; per-site Strict / Balanced / Off |
| Downloads | Easy way first (segmented downloads on the existing network layer), benchmark, and only then decide on a deep engine patch |
| Wallpapers | All 61 (31 still, 30 live), drawn in code |
| `max-persistent-connections-per-server` | Not raised globally until measured (it only affects HTTP/1.1 and also affects page loads) |

## Phases

### Phase 0: scaffolding and first build
- [x] Pinned upstream, verified (tag, changeset, tarball SHA-256, contents)
- [x] `fetch-upstream.sh`, `apply-overlay.sh`, `bump-upstream.sh`, offline self-test (`scripts/test.sh`)
- [x] Architecture, design spec, per-feature plans
- [ ] Unmodified pinned upstream builds into an arm64 APK ([BUILD.md](BUILD.md))
- [ ] CI workflow (manual trigger) that builds, signs and uploads the APK
- [ ] Signing key created and stored as CI secrets

### Phase 1: identity and theme
- [ ] App id `app.sahara.browser`, name "Sahara", Mozilla branding removed
- [ ] Cream-sun adaptive icon (+ monochrome layer), Rimal vector, Sora/Figtree bundled
- [ ] Sahara palette applied through Fenix's theme; Sunbleached (light) theme
- [ ] Strip telemetry, sponsored content, Pocket, experiments
- [ ] In-app animated splash

### Phase 2: Dune Shield
- [ ] uBlock Origin bundled and installed on first run, allowed in private tabs
- [ ] Strict (tuned) defaults + allow-list; Balanced mode
- [ ] Bridge: per-page counts and per-site mode; Shield sheet and Settings
- [ ] Breakage test run over a site list (desktop Firefox + same uBO build)

### Phase 3: Caravan downloads
- [ ] Segment planner (pure, unit-tested) and positional file writer
- [ ] Hand-off from `performDownload`, with fallback to the stock single stream
- [ ] Resume across restarts; connection setting (4–16, default 8)
- [ ] Caravan screen: speed meter and lanes
- [ ] Benchmark → **decision gate** on the deep network patch

### Phase 4: speed
- [ ] Benchmark harness and baseline (stock 157.0.1)
- [ ] Pref changes in `geckoview-prefs.js`, one group at a time, kept only if the numbers improve
- [ ] `speculativeConnect` on suggestions, tab switch and link touch-down
- [ ] Settings toggles wired to the real prefs

### Phase 5: home, tabs and wallpapers
- [ ] 3-page home and wallpaper host; tabs screen with Private and Camps
- [ ] Wallpaper renderer; set one stills, set one live, set two stills, set two live
- [ ] Battery-saver / reduced-motion behavior; golden-image checks against the design

### Phase 6: keep it healthy
- [ ] Monthly bump routine; patch-repair notes
