#!/usr/bin/env bash
# Turn edits made in a scratch copy of part of the Firefox tree into a patch for patches/.
#
# Usage: scripts/make-patch.sh PRISTINE_TREE SCRATCH_TREE REL_DIR [REL_DIR...] > patches/NNNN-name.patch
#
#   PRISTINE_TREE   the untouched tree (normally build/upstream)
#   SCRATCH_TREE    a directory laid out like the tree (for example a copy of mobile/android/fenix kept at
#                   <scratch>/mobile/android/fenix) in which you made your edits
#   REL_DIR         directories to compare, relative to the tree root, e.g. mobile/android/fenix
#
# The result is a unified diff with a/ and b/ prefixes, ready for `patch -p1` from the tree root. Added and
# deleted text files are included. Build output directories are ignored. If any file differs in binary form
# the script stops: binary assets belong in replace/ (or overlay/ if new), not in a patch.
#
# Start the patch file with a comment saying what it does and why (patch ignores text before the first
# "---" line), then append this script's output.
set -euo pipefail

die() { echo "make-patch: $*" >&2; exit 2; }

[[ $# -ge 3 ]] || die "usage: make-patch.sh PRISTINE_TREE SCRATCH_TREE REL_DIR [REL_DIR...]"
pristine="$(cd "$1" && pwd)"; scratch="$(cd "$2" && pwd)"; shift 2

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
ln -s "$pristine" "$work/a"
ln -s "$scratch" "$work/b"

out="$work/patch.diff"
: > "$out"
for rel in "$@"; do
  [[ -d "$pristine/$rel" ]] || die "not a directory in the pristine tree: $rel"
  [[ -d "$scratch/$rel" ]] || die "not a directory in the scratch tree: $rel"
  # diff exits 1 when it finds differences, which is the normal case here.
  (cd "$work" && diff -ruN -x build -x .gradle -x .cxx -x '*.orig' -x '*.rej' "a/$rel" "b/$rel") >> "$out" || [[ $? -eq 1 ]] \
    || die "diff failed for $rel"
done

if grep -q '^Binary files ' "$out"; then
  grep '^Binary files ' "$out" >&2
  die "binary files differ (put them in replace/ or overlay/)"
fi
[[ -s "$out" ]] || die "no differences"

# Drop the timestamps diff appends to the ---/+++ lines; they only make patches noisy to review.
sed -E 's/^((---|\+\+\+) [^\t]+)\t.*$/\1/' "$out"
