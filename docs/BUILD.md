# Build and install

Sahara is for one phone, so there is no store, no listing and no policy review. The package id is just a
label: **`app.sahara.browser`**. What matters instead: a signing key you keep, and a way to rebuild every
time Mozilla ships a fix.

## Where builds run

This repo is edited from a cloud session, whose disk is limited and ephemeral, and the Firefox tree plus
toolchains are large (about 20 GB of disk, 10 GB of RAM at peak). So the intended route is **GitHub
Actions**: [`.github/workflows/build.yml`](../.github/workflows/build.yml) builds, signs and uploads the
APK. A local Linux machine works too, with the same scripts.

## Phase 0: an unmodified Firefox for Android, built by our scripts

**Status (2026-10-09): the scripts work end to end in the cloud sandbox, from a pristine tree, and produce
a signed arm64 release APK. It has not been run on a phone, and the GitHub Actions workflow has not been
run yet.** The APK is still *Firefox* (`org.mozilla.firefox`, label "Firefox"); rebranding is Phase 1.

```sh
scripts/fetch-upstream.sh        # download, verify SHA-256, extract (about 5 GB)
scripts/bootstrap-android.sh     # once per machine: JDK, Node, Android SDK, nimbus-fml
scripts/build.sh release         # apply patches, configure, Gradle -> unsigned arm64 APK
SAHARA_KEYSTORE=... SAHARA_KEYSTORE_PASS=... scripts/sign-apk.sh <unsigned.apk> sahara.apk
```

Rough timings in the sandbox (4 CPUs, 16 GB), once toolchains and Gradle's dependency cache exist: the
Gradle build is on the order of 15 to 25 minutes from a pristine tree (a debug build is somewhat shorter,
a repackaging-only rerun is a few minutes). The very first run also downloads about 2 GB of dependencies.

### How it works: no Gecko compile at all

Upstream's `mobile/android/fenix/README.md` describes the old standalone-repo workflow and is not usable.
The current in-tree recipe is `./mach gradle fenix:assembleDebug` (from `mobile/android/docs/fenix.md`).
Rather than compiling Gecko, or using artifact-mode `./mach build` (which finds prebuilt Gecko through VCS
history, and a source tarball has none), Fenix is built against **Mozilla's published release GeckoView**:
`org.mozilla.geckoview:geckoview-omni-arm64-v8a:157.0.<buildid>` on `maven.mozilla.org`, which is the exact
157.0.1 release build (`upstream/PIN` records the build ID; `bump-upstream.sh` resolves it). Android
Components picks it up by itself when no `:geckoview` source project exists
([`patches/0001-use-published-geckoview.patch`](../patches/0001-use-published-geckoview.patch)). The mozconfig
([`build-config/mozconfig`](../build-config/mozconfig)) selects the release channel and `MOZILLA_OFFICIAL=1`
(so the artifact name has no channel suffix and the version no `-SNAPSHOT`), and the build sets
`MOZ_BUILD_DATE=<buildid>`.

Consequence: Sahara can change everything above the engine (UI, downloads, extensions, prefs). Changing C++
(for example the deep network patch in the downloads plan) would need a full Gecko build, which this route
deliberately avoids.

### Things that were needed, and why (so the scripts are not mysterious)

- **`nimbus-fml` is built from the tree's own Rust crate.** `mach bootstrap` fetches Mozilla's prebuilt copy
  by a hash of source files, which does not match a source tarball, so bootstrap runs with
  `--exclude nimbus-fml` and `bootstrap-android.sh` builds it (about 70 s, Rust 1.90 or newer).
- **Android SDK.** `--no-system-changes` skips it. `install-android-sdk.py` installs it with mozboot's own
  helpers: platform 37.1, build-tools 37.0.0, platform-tools and the `emulator` package (configure requires
  that binary to exist) but **not** the 7 GB Android Virtual Device image that bootstrap downloads by default.
- **`buildid.h` and generated sources.** A full Gecko build writes `objdir/buildid.h` and a few
  Kotlin/Java/JS files (`CrashReport.kt` for the crash library, 500 WebCompat add-on files). Gradle does not.
  `build.sh` writes `buildid.h` and runs `make mobile/android/pre-export` on the object directory.
- **Release builds are signed with Android's public debug key by default.** `build.sh release` passes
  `-PdisableDebugSigning` so the output is `...-release-unsigned.apk` and `sign-apk.sh` is the only signer.
- **Memory.** The tree gives the Gradle JVM a 7 GB heap and by default the Kotlin compiler runs in a second
  JVM with another 7 GB, which gets the build OOM-killed on a 16 GB machine (especially with stale daemons
  from earlier builds). `build.sh` compiles Kotlin inside the Gradle JVM
  (`-Pkotlin.compiler.execution.strategy=in-process`) and stops the daemon when done.

### Behind a TLS-intercepting proxy (the cloud sandbox only)

`. scripts/proxy-env.sh` before building. `mach gradle` overwrites `JAVA_TOOL_OPTIONS`, so Gradle's JVM loses
the environment's proxy and CA settings; the script passes them through `GRADLE_FLAGS`
(`~/.gradle/gradle.properties` cannot be used: mozboot rewrites that file and lowercases every key). It also
lists Google's Maven Central mirror ahead of Maven Central, which rate-limits shared IPs with HTTP 429 (and
Gradle does not fall through to the next repository on that error). Not needed on a normal machine or on
GitHub Actions.

### Still open

- **Never run on a device.** The sandbox is x86 and cannot run an arm64 app, so no APK has been launched.
  First real test: install it on your phone.
- **GitHub Actions has not run.** Open questions there: free-disk headroom on the runner, total time, and
  whether pushing a workflow file is allowed from this session.
- Upgrade path: on a new Firefox release `bump-upstream.sh` moves the pin and the GeckoView build ID;
  patches must be re-checked with `apply-overlay.sh --reapply`.

## Signing key

Generate **one** keystore and keep it forever: Android only installs an update over an app signed with the
same key, so losing it means uninstalling (and losing app data) to move to a new one.

- Create it with `scripts/make-keystore.sh` on a trusted machine; back it up somewhere safe.
- Store it in CI as encrypted repository secrets: `SAHARA_KEYSTORE_BASE64`, `SAHARA_KEYSTORE_PASS`,
  `SAHARA_KEY_ALIAS` (the script prints exactly what to paste). Without them the workflow signs with a
  one-off temporary key so a first test build can still be installed; such a build cannot be updated in
  place by a later build signed with the permanent key.
- It is git-ignored (`*.keystore`, `*.jks`, `keystore.properties`); never commit it.

## Installing

The repository is **public**, so anything published from it is downloadable by anyone. The workflow's
"publish" option (a GitHub release) is off by default for that reason; the normal route is the build's
artifact (a zip, 14 days, requires a GitHub login), or make the repository private. Download the APK on the
phone (or `adb install -r`), allow "install unknown apps" for the app you
opened it from, and install. Updates install over the top as long as the key and package id are unchanged.

## Staying current

1. `scripts/bump-upstream.sh` (newest final release), review the `upstream/PIN` diff.
2. `scripts/apply-overlay.sh --reapply`; fix any patch that no longer applies.
3. CI build, install, smoke-test (open a few sites, a download, Dune Shield on).

Do this for every Firefox release and every dot release: roughly monthly. A browser that falls behind on
security fixes is a risk even if only you use it.
