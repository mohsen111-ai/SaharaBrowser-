# Speed (page loading)

**Status: plan only, nothing implemented.** Goal: match or beat Chrome's page-load feel on mobile, proven
by measurement. Some of the gap is engine-level and prefs won't close it; the rest we can.

## Where changes go (verified)

- `mobile/android/app/geckoview-prefs.js`: preprocessed `pref("name", value);` lines, roughly alphabetical,
  each with a comment. The `Engine` interface has **no generic "set pref" method**, so tuned defaults go in
  this file via a patch. Defaults for any other pref live in Gecko's static prefs; **read the pinned tree's
  value before changing anything.**
- Already there: `network.http.max-persistent-connections-per-proxy` = 20 (proxy, not server);
  `dom.ipc.processPrelaunch.enabled` = true; no `browser.cache.*` entries.

## Candidate prefs: all UNMEASURED

Keep a pref only if the benchmark shows a win. Groups map to the Settings toggles:

| Group (setting) | Prefs to evaluate |
|---|---|
| **Preload likely pages** | `network.prefetch-next`, `network.predictor.enabled`, `network.http.speculative-parallel-limit`, `network.early-hints.enabled`, `network.early-hints.preconnect.enabled` |
| **Look up links early** | `network.dns.disablePrefetch`, `network.dns.disablePrefetchFromHTTPS`, `network.dnsCacheEntries`, `network.dnsCacheExpiration` |
| **Transport** | HTTP/3 enabled, 0-RTT, `network.ssl_tokens_cache_enabled` |
| **Cache size (512 MB in the design)** | `browser.cache.disk.capacity`, `browser.cache.disk.smart_size.enabled`, memory cache capacity |

Do **not** copy "speed tweak" lists from the internet: many are placebo, obsolete, or make things worse.

## Chrome-style speculative connections

`Engine.speculativeConnect(url)` (verified) opens a connection to a URL's host ahead of time. Call it:
on the top address-bar suggestion, on tab switch, and on link touch-down (via a small content script that
messages the app). This is the single most Chrome-like behavior available without engine changes.

## The biggest lever is probably content blocking

Ads and trackers are a large share of requests on typical pages. Measure with and without Dune Shield before
crediting any pref.

## Benchmark method

1. Fixed site list (popular news, shopping, social, search results, a few heavy pages).
2. Fixed network profiles (unthrottled Wi-Fi, ~Fast-3G, ~4G with latency) via a controllable proxy.
3. Same phone: **stock Firefox 157.0.1**, Sahara, and Chrome. Metrics: time to first contentful paint, largest
   contentful paint, load complete. Median of at least 5 runs per cell, cold start and warm.
4. Record results in `docs/benchmarks/`, and change one pref group at a time.

"Beat Chrome" needs a concrete target, e.g. *median LCP across the site list at the 4G profile*; pick it
once the baseline exists.
