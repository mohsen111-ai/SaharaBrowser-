#!/usr/bin/env bash
# Create the signing key for Sahara. Do this ONCE and keep the file and password safe forever:
# Android only installs an update over an app signed with the same key, so losing it means
# uninstalling Sahara (and losing its data) to switch to a new key.
#
# Usage: SAHARA_KEYSTORE_PASS='choose-a-long-password' scripts/make-keystore.sh [output.keystore]
#
# The key is RSA 4096, valid for 100 years, stored as PKCS12 with alias "sahara". The output file is
# git-ignored (*.keystore). Never commit it and never paste the password into logs or chat.
set -euo pipefail

out="${1:-sahara.keystore}"
alias_name="${SAHARA_KEY_ALIAS:-sahara}"

die() { echo "make-keystore: $*" >&2; exit 1; }

[[ -n "${SAHARA_KEYSTORE_PASS:-}" ]] || die "set SAHARA_KEYSTORE_PASS to the password you want"
[[ ${#SAHARA_KEYSTORE_PASS} -ge 12 ]] || die "use a password of at least 12 characters"
[[ ! -e "$out" ]] || die "$out already exists; refusing to overwrite a signing key"
command -v keytool >/dev/null || die "keytool not found (it ships with the JDK; try ~/.mozbuild/jdk/*/bin)"

keytool -genkeypair -storetype PKCS12 -keystore "$out" -alias "$alias_name" \
  -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=Sahara, O=Personal" \
  -storepass:env SAHARA_KEYSTORE_PASS -keypass:env SAHARA_KEYSTORE_PASS

chmod 600 "$out"
echo
echo "created $out (alias: $alias_name)"
echo "certificate fingerprint (write this down; every future build must show the same one):"
keytool -list -keystore "$out" -alias "$alias_name" -storepass:env SAHARA_KEYSTORE_PASS | grep -i "fingerprint"
echo
echo "For GitHub Actions, add these repository secrets (Settings > Secrets and variables > Actions):"
echo "  SAHARA_KEYSTORE_BASE64  = output of: base64 -w0 $out"
echo "  SAHARA_KEYSTORE_PASS    = the password you chose"
echo "  SAHARA_KEY_ALIAS        = $alias_name"
