#!/usr/bin/env bash
# Download the pinned Firefox source tarball, verify its SHA-256, extract it to build/upstream.
#
# Usage: scripts/fetch-upstream.sh [--force]
#   --force   re-extract even if the pinned version is already in build/upstream
#
# Env overrides (used by scripts/test.sh): SAHARA_PIN_FILE, SAHARA_BUILD_DIR
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../upstream/PIN
source "${SAHARA_PIN_FILE:-$ROOT/upstream/PIN}"

BUILD_DIR="${SAHARA_BUILD_DIR:-$ROOT/build}"
CACHE_DIR="$BUILD_DIR/cache"
TREE_DIR="$BUILD_DIR/upstream"
MARKER="$TREE_DIR/.sahara-upstream"
TARBALL="$CACHE_DIR/$(basename "$SAHARA_UPSTREAM_URL")"

die() { echo "fetch-upstream: $*" >&2; exit 1; }

force=0
case "${1:-}" in
  "") ;;
  --force) force=1 ;;
  *) die "unknown argument: $1" ;;
esac

if [[ $force -eq 0 && -f "$MARKER" && "$(cat "$MARKER")" == "$SAHARA_UPSTREAM_SHA256" ]]; then
  echo "upstream $SAHARA_UPSTREAM_VERSION already extracted at $TREE_DIR"
  exit 0
fi

checksum_ok() { echo "$SAHARA_UPSTREAM_SHA256  $TARBALL" | sha256sum --check --status; }

mkdir -p "$CACHE_DIR"
if [[ ! -f "$TARBALL" ]] || ! checksum_ok; then
  echo "downloading $SAHARA_UPSTREAM_URL"
  # --continue-at - resumes a partial download. If that is impossible (the cached file is
  # corrupt, e.g. longer than the original), throw it away and start over.
  if ! curl --fail --location --retry 3 --continue-at - --output "$TARBALL" "$SAHARA_UPSTREAM_URL"; then
    echo "resume failed; restarting the download from scratch"
    rm -f "$TARBALL"
    curl --fail --location --retry 3 --output "$TARBALL" "$SAHARA_UPSTREAM_URL"
  fi
fi
checksum_ok || die "SHA-256 mismatch for $TARBALL (delete it and retry; if it persists, re-check upstream/PIN)"
echo "checksum ok"

rm -rf "$TREE_DIR"
mkdir -p "$TREE_DIR"
echo "extracting to $TREE_DIR"
tar --extract --xz --file "$TARBALL" --directory "$TREE_DIR" --strip-components=1
echo "$SAHARA_UPSTREAM_SHA256" > "$MARKER"
echo "done: Firefox for Android $SAHARA_UPSTREAM_VERSION ($SAHARA_UPSTREAM_TAG)"
