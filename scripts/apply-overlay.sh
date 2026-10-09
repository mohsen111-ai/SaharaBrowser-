#!/usr/bin/env bash
# Apply Sahara's changes to the extracted upstream tree in build/upstream:
#   1. overlay/  - NEW files, copied in. A file that already exists upstream is an error.
#   2. patches/  - changes to EXISTING upstream files, applied in filename order with patch -p1.
#
# Usage: scripts/apply-overlay.sh [--reapply]
#   --reapply   re-extract pristine upstream first, then apply again
#
# Env overrides (used by scripts/test.sh): SAHARA_PIN_FILE, SAHARA_BUILD_DIR,
# SAHARA_OVERLAY_DIR, SAHARA_PATCHES_DIR
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SAHARA_BUILD_DIR:-$ROOT/build}"
TREE_DIR="$BUILD_DIR/upstream"
OVERLAY_DIR="${SAHARA_OVERLAY_DIR:-$ROOT/overlay}"
PATCHES_DIR="${SAHARA_PATCHES_DIR:-$ROOT/patches}"
APPLIED="$TREE_DIR/.sahara-applied"

die() { echo "apply-overlay: $*" >&2; exit 1; }

case "${1:-}" in
  "") ;;
  --reapply) "$ROOT/scripts/fetch-upstream.sh" --force ;;
  *) die "unknown argument: $1" ;;
esac

[[ -f "$TREE_DIR/.sahara-upstream" ]] || die "no upstream tree; run scripts/fetch-upstream.sh first"
[[ ! -f "$APPLIED" ]] || die "changes already applied; run with --reapply to start from pristine upstream"

# 1. Overlay: new files only. Changing an existing file belongs in a patch, which keeps rebases small.
shopt -s nullglob
count_overlay=0
if [[ -d "$OVERLAY_DIR" ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$OVERLAY_DIR"/}"
    [[ "$rel" == "README.md" ]] && continue   # documentation for this directory, not shipped
    dest="$TREE_DIR/$rel"
    [[ ! -e "$dest" ]] || die "overlay file collides with an upstream file: $rel (use a patch to change existing files)"
    mkdir -p "$(dirname "$dest")"
    cp -p "$src" "$dest"
    count_overlay=$((count_overlay + 1))
  done < <(find "$OVERLAY_DIR" -type f -print0 | sort -z)
fi
echo "overlay: $count_overlay file(s) added"

# 2. Patches, in order. Stop at the first failure so the tree is never half-understood.
count_patches=0
for p in "$PATCHES_DIR"/*.patch; do
  echo "patch: $(basename "$p")"
  patch --strip=1 --forward --no-backup-if-mismatch --directory="$TREE_DIR" --input="$p" \
    || die "$(basename "$p") failed to apply to the pinned upstream; fix the patch, then retry with --reapply"
  count_patches=$((count_patches + 1))
done
echo "patches: $count_patches applied"

date -u +%Y-%m-%dT%H:%M:%SZ > "$APPLIED"
echo "done: $TREE_DIR is ready to build"
