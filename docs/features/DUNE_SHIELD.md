# Dune Shield (uBlock Origin)

**Status: plan only, nothing implemented.** Goal: the full uBlock Origin is built in, on from the first
launch, strict by default, and tuned so that sites keep working.

Firefox still supports Manifest V2 extensions, so the real uBlock Origin (not "Lite") runs on Gecko.

## Install and lifecycle

- Bundle uBlock Origin's Firefox build (an official release, or built from source) inside the app assets.
- Install on first run with `WebExtensionRuntime.installBuiltInWebExtension(id, url, onSuccess, onError)`
  (verified signature; it takes a resource path or a local `.xpi` resource URL, anything else errors).
  Built-ins can't be removed from the add-ons screen and don't auto-update; **updates ship with app
  releases**. *To confirm:* where Fenix registers its own built-in extensions, and the exact resource URL form.
- Call `setAllowedInPrivateBrowsing(extension, true)` so private tabs are protected too.
- **Hold the first navigation until the extension reports ready**, otherwise the very first page loads
  unprotected. The package ships a snapshot of the filter lists, so blocking works offline on day one;
  lists update over the network afterwards.
- Configuration: do **not** rely on desktop policies / managed storage (`adminSettings`). I could not
  confirm that GeckoView honors them. Instead, patch the defaults in the bundled copy (default-enabled
  lists, seeded dynamic rules). That makes it a **modified GPL-3.0 build**: keep its license and notices
  ([NOTICE.md](../../NOTICE.md)).

## "Strict, but doesn't break sites"

Two modes, **Strict (tuned) is the default**:

| Layer | Balanced | Strict (tuned) |
|---|---|---|
| uBO standard lists (filters, privacy, badware, unbreak), EasyList, EasyPrivacy, annoyances / cookie notices | on | on |
| Cosmetic filtering ("hide ad spaces") | on | on |
| Block **third-party scripts** | no | yes, except the curated allow-list |
| Block third-party frames | no | **no** by default (they carry sign-in, payment, video and map embeds) |

**Allow-list** (ships with the app, updatable): infrastructure that sites genuinely depend on: public
script CDNs, font and static-asset hosts, captcha and bot-check services, sign-in providers, payment
providers. Expressed as uBlock dynamic-filtering rules, e.g. `* * 3p-script block` plus
`* <host> * allow` per entry. *Rule syntax to confirm against the bundled version.*

**Safety net**

- Per-site control becomes **Strict → Balanced → Off**, remembered per site.
- "Report broken page" drops the current site to Balanced immediately (and keeps a local note; no network
  reporting).
- Allow-list grows from test results (below), not guesses.

Some sites will still break occasionally. The goal is that fixing one takes a single tap.

## Bridge to the app UI

The Shield sheet needs per-page counts (ads, trackers, third-party scripts), the per-site switch and the
mode, and all of that lives inside uBlock Origin. Plan: a thin addition to the patched uBO that talks to
the app over native messaging (`WebExtension.MessageDelegate`) for: per-tab counts → app, and
set-site-mode / set-global-mode ← app. The uBO popup stays reachable from "uBlock Origin panel".

## Testing breakage

Run the **same patched uBO build in desktop Firefox** with Playwright over a list of a few hundred popular
sites in both modes; flag failures (blank page, missing key elements, console errors, failed sign-in
forms) and feed them into the allow-list. Then spot-check on the phone.

## Honest limits

"Zero ads" cannot be promised: server-side inserted ads and anti-adblock walls defeat any blocker, and
filter lists need continuous updates. The claim to stand behind is "blocks ads and trackers by default,
with a one-tap way out when a site breaks."
