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
printf '<string name="app_name">Firefox</string>\n<string name="hello">Welcome to Firefox. Firefox is fast.</string>\n' \
  > "$WORK/src/firefox-0.0.1/mobile/android/fenix/app/strings.xml"
printf 'old icon\n' > "$WORK/src/firefox-0.0.1/mobile/android/fenix/app/icon.txt"
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
export SAHARA_REPLACE_DIR="$WORK/replace" SAHARA_TRANSFORMS_DIR="$WORK/transforms"
mkdir -p "$WORK/overlay/mobile/android/sahara" "$WORK/patches" "$WORK/replace" "$WORK/transforms"
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


# --- replace/ and transforms/ ------------------------------------------------------------
# The previous test left a deliberately wrong checksum in the pin; restore the real one.
sed -i "s/^SAHARA_UPSTREAM_SHA256=.*/SAHARA_UPSTREAM_SHA256=$SHA/" "$WORK/PIN"
rm -rf "$WORK/build"
"$FETCH" >"$WORK/out" 2>&1 || { cat "$WORK/out"; fail "fetch after restoring the pin"; }
mkdir -p "$WORK/replace/mobile/android/fenix/app"
printf 'new icon\n' > "$WORK/replace/mobile/android/fenix/app/icon.txt"
printf 'docs\n' > "$WORK/replace/README.md"
cat > "$WORK/transforms/10-brand.py" <<'PY'
import pathlib, sys
f = pathlib.Path(sys.argv[1]) / "mobile/android/fenix/app/strings.xml"
text = f.read_text(encoding="utf-8")
n = text.count("Firefox")
if n != 3:
    sys.exit("brand: expected 3 occurrences of Firefox, found %d" % n)
f.write_text(text.replace("Firefox", "Sahara"), encoding="utf-8")
print("brand: %d replacements" % n)
PY
"$APPLY" --reapply >"$WORK/out" 2>&1 || { cat "$WORK/out"; fail "apply with replace and transforms"; }
[[ "$(cat "$TREE/mobile/android/fenix/app/icon.txt")" == "new icon" ]] || fail "replace/ did not overwrite the file"
[[ ! -e "$TREE/README.md" ]] || fail "replace/README.md must not be copied"
grep -q 'Welcome to Sahara. Sahara is fast.' "$TREE/mobile/android/fenix/app/strings.xml" || fail "transform did not run"
ok "replace/ overwrites existing files and transforms/ run after patches"

printf 'x\n' > "$WORK/replace/mobile/android/fenix/app/not-upstream.txt"
expect_fail "replace/ target that does not exist upstream is rejected" "$APPLY" --reapply
grep -q "does not exist upstream" "$WORK/out" || { cat "$WORK/out"; fail "message should say the target is missing"; }
rm "$WORK/replace/mobile/android/fenix/app/not-upstream.txt"

printf 'Firefox changed\n' >> "$WORK/src/firefox-0.0.1/mobile/android/fenix/app/strings.xml"
tar --create --xz --file "$WORK/firefox-0.0.1.source.tar.xz" --directory "$WORK/src" firefox-0.0.1
sed -i "s/^SAHARA_UPSTREAM_SHA256=.*/SAHARA_UPSTREAM_SHA256=$(sha256sum "$WORK/firefox-0.0.1.source.tar.xz" | cut -d' ' -f1)/" "$WORK/PIN"
rm -rf "$WORK/build/cache"
expect_fail "a transform whose expectation no longer holds fails the apply" "$APPLY" --reapply
grep -q "expected 3 occurrences" "$WORK/out" || { cat "$WORK/out"; fail "the transform's own message should be shown"; }

# --- make-patch.sh -----------------------------------------------------------------------
rm -rf "$WORK/scratch" && mkdir -p "$WORK/scratch/mobile/android" "$WORK/pristine/mobile/android"
cp -r "$WORK/src/firefox-0.0.1/mobile/android/fenix" "$WORK/pristine/mobile/android/fenix"
cp -r "$WORK/pristine/mobile/android/fenix" "$WORK/scratch/mobile/android/fenix"
sed -i 's/org.mozilla.fenix/app.sahara.browser/' "$WORK/scratch/mobile/android/fenix/app/build.gradle"
printf 'brand new\n' > "$WORK/scratch/mobile/android/fenix/app/added.txt"
"$ROOT/scripts/make-patch.sh" "$WORK/pristine" "$WORK/scratch" mobile/android/fenix > "$WORK/made.patch" || fail "make-patch.sh"
grep -q '^--- a/mobile/android/fenix/app/build.gradle$' "$WORK/made.patch" || { cat "$WORK/made.patch"; fail "patch header should use a/ and b/ paths without timestamps"; }
cp -r "$WORK/pristine" "$WORK/applied" && patch -p1 -d "$WORK/applied" < "$WORK/made.patch" >/dev/null || fail "generated patch does not apply"
diff -r "$WORK/applied/mobile/android/fenix" "$WORK/scratch/mobile/android/fenix" >/dev/null || fail "applying the generated patch does not reproduce the scratch tree"
ok "make-patch.sh produces a patch that reproduces the edits (including a new file)"
printf 'PNG\0\0data\0' > "$WORK/scratch/mobile/android/fenix/app/blob.bin"
expect_fail "make-patch.sh refuses binary differences" "$ROOT/scripts/make-patch.sh" "$WORK/pristine" "$WORK/scratch" mobile/android/fenix

echo "all $pass checks passed"
