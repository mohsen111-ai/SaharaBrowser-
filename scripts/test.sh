#!/usr/bin/env bash
# Self-test for fetch-upstream.sh and apply-overlay.sh against a tiny fake "Firefox" tarball.
# Needs no network and downloads nothing from Mozilla.   Usage: scripts/test.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail() { echo "FAIL: $*" >&2; exit 1; }
ok()   { pass=$((pass + 1)); echo "ok - $*"; }
# expect_fail "<description>" <command...>: the command must exit non-zero.
expect_fail() { local d="$1"; shift; if "$@" >"$WORK/out" 2>&1; then fail "$d (expected failure)"; else ok "$d"; fi; }

# --- fixture: fake upstream tarball ------------------------------------------------------
mkdir -p "$WORK/src/firefox-0.0.1/mobile/android/fenix/app"
printf 'applicationId "org.mozilla.fenix"\n' > "$WORK/src/firefox-0.0.1/mobile/android/fenix/app/build.gradle"
tar --create --xz --file "$WORK/firefox-0.0.1.source.tar.xz" --directory "$WORK/src" firefox-0.0.1
SHA="$(sha256sum "$WORK/firefox-0.0.1.source.tar.xz" | cut -d' ' -f1)"

cat > "$WORK/PIN" <<EOF
SAHARA_UPSTREAM_VERSION=0.0.1
SAHARA_UPSTREAM_TAG=TEST
SAHARA_UPSTREAM_HG_NODE=0
SAHARA_UPSTREAM_URL=file://$WORK/firefox-0.0.1.source.tar.xz
SAHARA_UPSTREAM_SHA256=$SHA
EOF
export SAHARA_PIN_FILE="$WORK/PIN" SAHARA_BUILD_DIR="$WORK/build"
export SAHARA_OVERLAY_DIR="$WORK/overlay" SAHARA_PATCHES_DIR="$WORK/patches"
mkdir -p "$WORK/overlay/mobile/android/sahara" "$WORK/patches"
printf 'docs, not shipped\n' > "$WORK/overlay/README.md"
printf 'new file\n' > "$WORK/overlay/mobile/android/sahara/hello.txt"

FETCH="$ROOT/scripts/fetch-upstream.sh"
APPLY="$ROOT/scripts/apply-overlay.sh"
TREE="$WORK/build/upstream"

# --- fetch -------------------------------------------------------------------------------
"$FETCH" >"$WORK/out" 2>&1 || { cat "$WORK/out"; fail "fetch"; }
[[ -f "$TREE/mobile/android/fenix/app/build.gradle" ]] || fail "fetch did not extract the tree"
ok "fetch downloads, verifies and extracts"

"$FETCH" 2>&1 | grep -q "already extracted" || fail "second fetch should be a no-op"
ok "second fetch is a no-op"

# --- apply: patch + overlay --------------------------------------------------------------
cat > "$WORK/patches/0001-app-id.patch" <<'EOF'
--- a/mobile/android/fenix/app/build.gradle
+++ b/mobile/android/fenix/app/build.gradle
@@ -1 +1 @@
-applicationId "org.mozilla.fenix"
+applicationId "app.sahara.browser"
EOF
"$APPLY" >"$WORK/out" 2>&1 || { cat "$WORK/out"; fail "apply"; }
grep -q 'app.sahara.browser' "$TREE/mobile/android/fenix/app/build.gradle" || fail "patch not applied"
[[ -f "$TREE/mobile/android/sahara/hello.txt" ]] || fail "overlay file not copied"
[[ ! -e "$TREE/README.md" ]] || fail "overlay README.md must not be copied"
ok "apply copies overlay files and applies patches"

expect_fail "apply refuses to run twice" "$APPLY"

# --- reapply restores pristine upstream first --------------------------------------------
"$APPLY" --reapply >"$WORK/out" 2>&1 || { cat "$WORK/out"; fail "reapply"; }
[[ "$(grep -c 'app.sahara.browser' "$TREE/mobile/android/fenix/app/build.gradle")" == 1 ]] || fail "reapply double-applied"
ok "reapply starts from pristine upstream"

# --- safety checks -----------------------------------------------------------------------
mkdir -p "$WORK/overlay/mobile/android/fenix/app"
printf 'x\n' > "$WORK/overlay/mobile/android/fenix/app/build.gradle"
expect_fail "overlay file colliding with upstream is rejected" "$APPLY" --reapply
rm -rf "$WORK/overlay/mobile/android/fenix"

printf 'garbage\n' > "$WORK/patches/0002-broken.patch"
expect_fail "a patch that does not apply is rejected" "$APPLY" --reapply
rm "$WORK/patches/0002-broken.patch"

# A corrupted cached tarball is discarded and downloaded again.
printf 'tampered' >> "$WORK/build/cache/firefox-0.0.1.source.tar.xz"
"$FETCH" --force >"$WORK/out" 2>&1 || { cat "$WORK/out"; fail "corrupted cache should self-heal"; }
sha256sum --check --status <<<"$SHA  $WORK/build/cache/firefox-0.0.1.source.tar.xz" || fail "cache not repaired"
ok "corrupted cached tarball is re-downloaded"

# A pin whose checksum does not match what the server delivers must fail, naming the checksum.
sed -i "s/^SAHARA_UPSTREAM_SHA256=.*/SAHARA_UPSTREAM_SHA256=$(printf '0%.0s' {1..64})/" "$WORK/PIN"
rm -rf "$WORK/build"
if "$FETCH" >"$WORK/out" 2>&1; then fail "wrong pinned checksum must fail"; fi
grep -q "SHA-256 mismatch" "$WORK/out" || { cat "$WORK/out"; fail "failure should mention the checksum"; }
ok "wrong pinned checksum fails with a checksum error"

echo "all $pass checks passed"
