#!/usr/bin/env bash
# Align and sign a release APK with Sahara's key.
#
# Usage: SAHARA_KEYSTORE=sahara.keystore SAHARA_KEYSTORE_PASS=... scripts/sign-apk.sh unsigned.apk signed.apk
#
# Env:   SAHARA_KEYSTORE        path to the keystore (see scripts/make-keystore.sh)
#        SAHARA_KEYSTORE_PASS   its password (also used for the key unless SAHARA_KEY_PASS is set)
#        SAHARA_KEY_ALIAS       key alias, default "sahara"
#        SAHARA_KEY_PASS        key password, default = keystore password
#
# Passwords are read by apksigner from the environment, so they never appear in the process list.
set -euo pipefail

die() { echo "sign-apk: $*" >&2; exit 1; }

[[ $# -eq 2 ]] || die "usage: sign-apk.sh <unsigned.apk> <signed.apk>"
in="$1"; out="$2"
[[ -f "$in" ]] || die "no such file: $in"
[[ -n "${SAHARA_KEYSTORE:-}" && -f "$SAHARA_KEYSTORE" ]] || die "set SAHARA_KEYSTORE to an existing keystore file"
[[ -n "${SAHARA_KEYSTORE_PASS:-}" ]] || die "set SAHARA_KEYSTORE_PASS"
export SAHARA_KEY_PASS="${SAHARA_KEY_PASS:-$SAHARA_KEYSTORE_PASS}"
alias_name="${SAHARA_KEY_ALIAS:-sahara}"

# Find build-tools in the SDK that the build installed, falling back to ANDROID_HOME. ANDROID_HOME is tried
# last because it can point at a directory that no longer exists (the CI job deletes the runner's own SDK).
MOZBUILD="${MOZBUILD_STATE_PATH:-$HOME/.mozbuild}"
bt=""
for sdk in "$MOZBUILD/android-sdk-linux" "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}"; do
  [[ -n "$sdk" && -d "$sdk/build-tools" ]] || continue
  bt="$(ls -d "$sdk"/build-tools/*/ 2>/dev/null | sort -V | tail -n 1)" || bt=""
  bt="${bt%/}"
  [[ -n "$bt" && -x "$bt/apksigner" ]] && break
  bt=""
done
[[ -n "$bt" ]] || die "no Android build-tools with apksigner under $MOZBUILD/android-sdk-linux, \$ANDROID_HOME or \$ANDROID_SDK_ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# zipalign must run BEFORE signing (signing invalidates alignment). -P 16 keeps native libraries
# page-aligned for devices with 16 KB pages; it also covers the 4-byte alignment everything else needs.
"$bt/zipalign" -f -P 16 4 "$in" "$tmp/aligned.apk"
"$bt/apksigner" sign \
  --ks "$SAHARA_KEYSTORE" --ks-key-alias "$alias_name" \
  --ks-pass env:SAHARA_KEYSTORE_PASS --key-pass env:SAHARA_KEY_PASS \
  --out "$out" "$tmp/aligned.apk"

"$bt/zipalign" -c -P 16 4 "$out" || die "output is not aligned"
"$bt/apksigner" verify "$out" >/dev/null || die "signature verification failed for $out"
# Show which key signed it (the label differs between signature schemes, so this is best-effort).
"$bt/apksigner" verify --print-certs "$out" | grep -E "certificate (DN|SHA-256)" || true
echo "signed: $out"
