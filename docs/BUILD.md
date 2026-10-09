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

**Status (2026-10-09): in progress. No APK yet.** What a real run in the cloud sandbox has established so
far, and what is still open.

### Approach that works so far: no Gecko compile at all

Upstream's `mobile/android/fenix/README.md` describes the old standalone-repo workflow and is not usable.
The current in-tree recipe is `./mach gradle fenix:assembleDebug` (from `mobile/android/docs/fenix.md`).
Rather than compiling Gecko or using artifact-mode `./mach build` (which finds prebuilt Gecko through VCS
history, and a source tarball has none), Fenix is built against **Mozilla's published release GeckoView**:
`org.mozilla.geckoview:geckoview-omni-arm64-v8a:157.0.20261005135250` on `maven.mozilla.org`, which is the
157.0.1 release build. Android Components resolves it by itself when no `:geckoview` source project exists
(`patches/0001-use-published-geckoview.patch`). It needs `ac_add_options --enable-update-channel=release`
and `MOZILLA_OFFICIAL=1` in the mozconfig (so the artifact name has no channel suffix and the version no
`-SNAPSHOT`), and `MOZ_BUILD_DATE=<buildid>` set to the build ID in that version. See
[`build-config/mozconfig`](../build-config/mozconfig).

### Steps verified to work (in order)

1. `scripts/fetch-upstream.sh`: download, SHA-256 check, extract (tested on the real 811 MB tarball).
2. `./mach bootstrap --application-choice=mobile_android_artifact_mode --no-system-changes --exclude nimbus-fml`
   installs the JDK 17, Node and helper tools. `nimbus-fml` must be excluded: Mozilla's prebuilt copy is
   looked up by a hash of source files and is not found for the tarball.
3. Build `nimbus-fml` from the tree's own crate (about 70 s with the preinstalled Rust ≥ 1.90):
   copy `.cargo/config.toml.in` to `.cargo/config.toml`, then
   `cargo build --release --locked --offline -p toolchain-nimbus-fml`. Point configure at it with
   `NIMBUS_FML=/path/to/nimbus-fml`.
4. `--no-system-changes` skips the Android SDK. Install only what Gradle needs (SDK platform 37.1,
   build-tools 37.0.0, platform-tools) with mozboot's own helpers, **without** the emulator or system images
   (the bootstrap's default AVD download is about 7 GB).
5. Copy `build-config/mozconfig` to `build/upstream/mozconfig`, apply `patches/0001-*.patch`, then
   `./mach configure`.
6. Write `objdir-sahara/buildid.h` containing `#define MOZ_BUILDID <buildid>` (a full Gecko build normally
   generates it; Gradle refuses to start without it).
7. `MOZ_BUILD_DATE=<buildid> ./mach gradle fenix:assembleDebug`. In the sandbox about 675 Gradle tasks
   (most of Android Components) compile in roughly 7 minutes on 4 cores.

### Behind a TLS-intercepting proxy (the cloud sandbox only)

`source scripts/proxy-env.sh` first. It passes the proxy and CA settings to Gradle through `GRADLE_FLAGS`
(`mach gradle` overwrites `JAVA_TOOL_OPTIONS`) and lists Google's Maven Central mirror before Maven Central,
which rate-limits shared IPs with HTTP 429. Not needed on a normal machine or GitHub Actions.

### Still open

- A finished debug APK, then the release variant (`fenix:assembleRelease`). Upstream's Gradle build does not
  sign release APKs ("official builds are signed by a separate service"), so we sign with our own key.
- Which output APK to install (ABI splits are enabled; we want `arm64-v8a`).
- Wrapping steps 1–7 in scripts (`bootstrap`, `build`) and re-running them from a pristine tree.
- **Runner disk.** Standard GitHub-hosted runners have limited disk. The tree alone is 4.8 GB extracted; the
  build directory here is about 7 GB before the APK. Measure in CI, don't assume.

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
