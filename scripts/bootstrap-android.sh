#!/usr/bin/env bash
# One-time setup (per machine) of the toolchains needed to build Fenix from build/upstream.
# Run scripts/fetch-upstream.sh first. Safe to re-run; finished steps are skipped.
#
# What it installs, all under ~/.mozbuild (or $MOZBUILD_STATE_PATH):
#   - JDK 17, Node, uniffi-bindgen and friends        via `mach bootstrap`
#   - Android SDK (no virtual device image)           via mozboot's own helpers
#   - nimbus-fml                                       built from the tree's own Rust crate
#
# Why nimbus-fml is built here: `mach bootstrap` looks Mozilla's prebuilt copy up in their CI index by a
# hash of source files, and that lookup does not match a source tarball. Building it takes about a minute.
# Needs a Rust toolchain (cargo) of at least 1.90.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SAHARA_BUILD_DIR:-$ROOT/build}"
TREE="$BUILD_DIR/upstream"
MOZBUILD="${MOZBUILD_STATE_PATH:-$HOME/.mozbuild}"
NIMBUS_FML_BIN="$MOZBUILD/nimbus-fml/nimbus-fml"

die() { echo "bootstrap-android: $*" >&2; exit 1; }

[[ -f "$TREE/.sahara-upstream" ]] || die "no upstream tree; run scripts/fetch-upstream.sh first"
command -v cargo >/dev/null || die "cargo not found; install Rust (https://rustup.rs) first"

echo "== mach bootstrap"
(cd "$TREE" && ./mach bootstrap --application-choice=mobile_android_artifact_mode \
  --no-system-changes --exclude nimbus-fml)
# bootstrap also fetches an Android Virtual Device image the build does not use (about 7 GB).
rm -rf "$MOZBUILD/android-device"

echo "== Android SDK"
if [[ -d "$MOZBUILD/android-sdk-linux/platforms" ]]; then
  echo "already installed"
else
  (cd "$TREE" && ./mach python "$ROOT/scripts/install-android-sdk.py")
fi

echo "== nimbus-fml"
if [[ -x "$NIMBUS_FML_BIN" ]]; then
  echo "already built: $NIMBUS_FML_BIN"
else
  # The vendoring template is valid as-is for cargo (see the comment at the end of the file).
  cp -n "$TREE/.cargo/config.toml.in" "$TREE/.cargo/config.toml"
  (cd "$TREE" && cargo build --release --locked --offline -p toolchain-nimbus-fml \
    --target-dir "$BUILD_DIR/nimbus-fml-target")
  mkdir -p "$(dirname "$NIMBUS_FML_BIN")"
  cp "$BUILD_DIR/nimbus-fml-target/release/nimbus-fml" "$NIMBUS_FML_BIN"
fi

echo "done"
