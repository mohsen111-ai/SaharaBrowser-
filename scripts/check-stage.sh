#!/usr/bin/env bash
# Dry-run a staged set of Sahara changes against a throw-away copy of the pristine mobile/ tree.
#
# Usage: scripts/check-stage.sh STAGE_DIR [--keep]
#
# STAGE_DIR holds any of overlay/ replace/ patches/ transforms/ (the same layout as the repository).
# They are applied with the real scripts/apply-overlay.sh, in the real order, onto a copy of the
# pristine upstream mobile/ directory. Then every changed or new XML file is checked for well-formedness
# and every changed resource file is compiled with aapt2 (which catches bad resource names, bad value
# types and malformed resource XML). Prints a summary of what changed. Exit status is non-zero on any
# problem. --keep leaves the patched copy on disk and prints its path (for looking at the result).
#
# This does NOT compile Kotlin or Java; the full Gradle build does that.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../upstream/PIN
source "$ROOT/upstream/PIN"
BUILD_DIR="${SAHARA_BUILD_DIR:-$ROOT/build}"
PRISTINE="$BUILD_DIR/pristine"            # extracted once from the pinned tarball: only mobile/
TARBALL="$BUILD_DIR/cache/$(basename "$SAHARA_UPSTREAM_URL")"
AAPT2="$(ls -d "${MOZBUILD_STATE_PATH:-$HOME/.mozbuild}"/android-sdk-linux/build-tools/*/aapt2 2>/dev/null | sort -V | tail -n 1 || true)"

die() { echo "check-stage: $*" >&2; exit 2; }

stage="${1:-}"; keep=0
[[ -n "$stage" && -d "$stage" ]] || die "usage: check-stage.sh STAGE_DIR [--keep]"
stage="$(cd "$stage" && pwd)"
[[ "${2:-}" == "--keep" ]] && keep=1

if [[ ! -f "$PRISTINE/.complete" ]]; then
  [[ -f "$TARBALL" ]] || die "pinned tarball not found at $TARBALL; run scripts/fetch-upstream.sh first"
  echo "extracting pristine mobile/ from the pinned tarball (once)..." >&2
  rm -rf "$PRISTINE"; mkdir -p "$PRISTINE"
  tar --extract --xz --file "$TARBALL" --directory "$PRISTINE" --strip-components=1 \
    "firefox-$SAHARA_UPSTREAM_VERSION/mobile"
  touch "$PRISTINE/.complete"
fi

work="$(mktemp -d)"
cleanup() { [[ $keep -eq 1 ]] || rm -rf "$work"; }
trap cleanup EXIT

mkdir -p "$work/upstream"
cp -a "$PRISTINE/mobile" "$work/upstream/mobile"
touch "$work/upstream/.sahara-upstream"

echo "== apply" >&2
SAHARA_BUILD_DIR="$work" \
SAHARA_OVERLAY_DIR="$stage/overlay" SAHARA_REPLACE_DIR="$stage/replace" \
SAHARA_PATCHES_DIR="$stage/patches" SAHARA_TRANSFORMS_DIR="$stage/transforms" \
  "$ROOT/scripts/apply-overlay.sh" >&2 || die "applying the staged changes failed (see above)"

echo "== changed files" >&2
changed="$work/changed.txt"
# Compare file by file so deleted, added and modified are all visible.
python3 -I - "$PRISTINE" "$work/upstream" "$changed" <<'PY'
import filecmp, os, sys
old, new, out = sys.argv[1:4]
rows = []
def walk(base):
    for root, dirs, files in os.walk(os.path.join(base, "mobile")):
        dirs[:] = [d for d in dirs if d not in ("build", ".gradle", ".cxx")]
        for f in files:
            yield os.path.relpath(os.path.join(root, f), base)
o, n = set(walk(old)), set(walk(new))
for p in sorted(n - o): rows.append(("A", p))
for p in sorted(o - n): rows.append(("D", p))
for p in sorted(o & n):
    if not filecmp.cmp(os.path.join(old, p), os.path.join(new, p), shallow=False):
        rows.append(("M", p))
open(out, "w").write("\n".join("%s %s" % r for r in rows) + ("\n" if rows else ""))
print("added %d, modified %d, deleted %d" % tuple(sum(1 for r in rows if r[0] == k) for k in "AMD"))
PY
cat "$changed" | head -n 60 >&2
[[ $(wc -l < "$changed") -le 60 ]] || echo "... ($(wc -l < "$changed") files in total)" >&2

echo "== xml well-formedness and aapt2" >&2
problems=0
while read -r status path; do
  [[ "$status" == "D" ]] && continue
  file="$work/upstream/$path"
  case "$path" in
    *.xml)
      if ! python3 -I -c 'import sys, xml.etree.ElementTree as E; E.parse(sys.argv[1])' "$file" 2>"$work/err"; then
        echo "NOT WELL-FORMED: $path: $(cat "$work/err")" >&2; problems=$((problems + 1)); continue
      fi
      ;;
  esac
  case "$path" in
    */res/*/*.xml|*/res/*/*.png|*/res/*/*.webp)
      if [[ -n "$AAPT2" ]]; then
        if ! "$AAPT2" compile "$file" -o "$work/aapt-out" >"$work/err" 2>&1; then
          echo "AAPT2 REJECTED: $path: $(head -c 400 "$work/err")" >&2; problems=$((problems + 1))
        fi
      fi
      ;;
  esac
done < "$changed"
[[ -n "$AAPT2" ]] || echo "(aapt2 not found: resource compile check skipped)" >&2

[[ $keep -eq 1 ]] && echo "kept: $work/upstream" >&2
if [[ $problems -gt 0 ]]; then die "$problems problem(s) found"; fi
echo "OK" >&2
