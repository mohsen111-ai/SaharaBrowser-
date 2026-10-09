#!/usr/bin/env bash
# Apply Sahara's changes to the extracted upstream tree in build/upstream, in this order:
#   1. overlay/     NEW files, copied in. A file that already exists upstream is an error.
#   2. replace/     whole-file REPLACEMENTS (icons and other binary assets that a text patch cannot express).
#                   The target must already exist upstream; a missing target is an error, which is how an
#                   upstream change that moved or removed it gets noticed.
#   3. patches/     edits to existing text files, applied in filename order with patch -p1.
#   4. transforms/  rule-based edits: executable-by-python scripts run in filename order as
#                   `python3 -I <script> <tree-root>`. A transform must exit non-zero if the rules it expects
#                   to apply do not match anything (see transforms/README.md). Used for edits that are
#                   fragile as patches, such as renaming a word across many string resources.
#
# Usage: scripts/apply-overlay.sh [--reapply]
#   --reapply   re-extract pristine upstream first, then apply again
#
# Env overrides (used by scripts/test.sh): SAHARA_PIN_FILE, SAHARA_BUILD_DIR,
# SAHARA_OVERLAY_DIR, SAHARA_REPLACE_DIR, SAHARA_PATCHES_DIR, SAHARA_TRANSFORMS_DIR
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${SAHARA_BUILD_DIR:-$ROOT/build}"
TREE_DIR="$BUILD_DIR/upstream"
OVERLAY_DIR="${SAHARA_OVERLAY_DIR:-$ROOT/overlay}"
REPLACE_DIR="${SAHARA_REPLACE_DIR:-$ROOT/replace}"
PATCHES_DIR="${SAHARA_PATCHES_DIR:-$ROOT/patches}"
TRANSFORMS_DIR="${SAHARA_TRANSFORMS_DIR:-$ROOT/transforms}"
APPLIED="$TREE_DIR/.sahara-applied"

die() { echo "apply-overlay: $*" >&2; exit 1; }

case "${1:-}" in
  "") ;;
  --reapply) "$ROOT/scripts/fetch-upstream.sh" --force ;;
  *) die "unknown argument: $1" ;;
esac

[[ -f "$TREE_DIR/.sahara-upstream" ]] || die "no upstream tree; run scripts/fetch-upstream.sh first"
[[ ! -f "$APPLIED" ]] || die "changes already applied; run with --reapply to start from pristine upstream"

shopt -s nullglob

# 1. Overlay: new files only. Changing an existing file belongs in a patch, which keeps rebases small.
count_overlay=0
if [[ -d "$OVERLAY_DIR" ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$OVERLAY_DIR"/}"
    [[ "$rel" == "README.md" ]] && continue   # documentation for this directory, not shipped
    dest="$TREE_DIR/$rel"
    [[ ! -e "$dest" ]] || die "overlay file collides with an upstream file: $rel (use replace/ or a patch to change existing files)"
    mkdir -p "$(dirname "$dest")"
    cp -p "$src" "$dest"
    count_overlay=$((count_overlay + 1))
  done < <(find "$OVERLAY_DIR" -type f -print0 | sort -z)
fi
echo "overlay: $count_overlay file(s) added"

# 2. Replacements: the target has to exist, so that an upstream rename is an error and not a silent no-op.
count_replace=0
if [[ -d "$REPLACE_DIR" ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$REPLACE_DIR"/}"
    [[ "$rel" == "README.md" ]] && continue
    dest="$TREE_DIR/$rel"
    [[ -f "$dest" ]] || die "replace/ target does not exist upstream: $rel (upstream moved or removed it?)"
    cp -p "$src" "$dest"
    count_replace=$((count_replace + 1))
  done < <(find "$REPLACE_DIR" -type f -print0 | sort -z)
fi
echo "replace: $count_replace file(s) replaced"

# 3. Patches, in order. Stop at the first failure so the tree is never half-understood.
count_patches=0
for p in "$PATCHES_DIR"/*.patch; do
  echo "patch: $(basename "$p")"
  patch --strip=1 --forward --no-backup-if-mismatch --directory="$TREE_DIR" --input="$p" \
    || die "$(basename "$p") failed to apply to the pinned upstream; fix the patch, then retry with --reapply"
  count_patches=$((count_patches + 1))
done
echo "patches: $count_patches applied"

# 4. Transforms, in order.
count_transforms=0
for t in "$TRANSFORMS_DIR"/*.py; do
  echo "transform: $(basename "$t")"
  python3 -I "$t" "$TREE_DIR" \
    || die "$(basename "$t") failed; upstream probably changed what it expects to find (retry with --reapply after fixing it)"
  count_transforms=$((count_transforms + 1))
done
echo "transforms: $count_transforms run"

date -u +%Y-%m-%dT%H:%M:%SZ > "$APPLIED"
echo "done: $TREE_DIR is ready to build"
