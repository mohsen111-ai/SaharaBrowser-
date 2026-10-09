# Build and install

Sahara is for one phone, so there is no store, no listing and no policy review. The package id is just a
label: **`app.sahara.browser`**. What matters instead: a signing key you keep, and a way to rebuild every
time Mozilla ships a fix.

## Where builds will run

This repo is edited from a cloud session, whose disk is limited and ephemeral, and the Firefox tree plus
toolchains are large. So the plan is **GitHub Actions** builds that publish a signed APK as a downloadable
artifact; you install it on the phone. A local machine works too, using the same scripts.

## Phase 0: the first milestone

Before any Sahara feature: **build the unmodified pinned upstream into an installable arm64 APK.**
Everything after depends on knowing the exact commands and that CI can hold the build.

Open questions to settle with a real run (none of these are guessed here):

- The exact `mach` / Gradle commands and JDK/SDK/NDK versions for this release. Upstream's
  `mobile/android/fenix/README.md` still describes the old standalone-repo workflow; the current pointers
  are `mobile/android/docs/fenix.md`, the Firefox Source Docs ("Setup", and Fenix → "Substituting Local
  GeckoView"), and `mach bootstrap` for the Android artifact-mode build.
- **Artifact builds** (download prebuilt Gecko instead of compiling it) cover everything except C++
  patches. Compiling Gecko is only needed if the download plan's deep network patch is ever approved.
- **arm64-v8a only**: one ABI is enough for a modern phone and makes the build smaller and faster.
- **Runner disk.** Standard GitHub-hosted runners have limited disk. The extracted tree, Android SDK/NDK and
  Gradle caches are large, so the workflow may need a clean-up step or a larger runner. Measure, don't assume.
- Whether the build uses `build/upstream` produced by `scripts/fetch-upstream.sh` directly (expected).

When that works, add `.github/workflows/build.yml` (manual trigger only, so it never burns CI minutes by
accident) that runs: fetch → apply → build → sign → upload APK.

## Signing key

Generate **one** keystore and keep it forever: Android only installs an update over an app signed with the
same key, so losing it means uninstalling (and losing app data) to move to a new one.

- Create it with `keytool` on a trusted machine; back it up somewhere safe.
- Store it in CI as encrypted repository secrets (base64 keystore, alias, passwords).
- It is git-ignored (`*.keystore`, `*.jks`, `keystore.properties`); never commit it.

## Installing

Download the APK artifact on the phone (or `adb install -r`), allow "install unknown apps" for the app you
opened it from, and install. Updates install over the top as long as the key and package id are unchanged.

## Staying current

1. `scripts/bump-upstream.sh` (newest final release), review the `upstream/PIN` diff.
2. `scripts/apply-overlay.sh --reapply`; fix any patch that no longer applies.
3. CI build, install, smoke-test (open a few sites, a download, Dune Shield on).

Do this for every Firefox release and every dot release: roughly monthly. A browser that falls behind on
security fixes is a risk even if only you use it.
