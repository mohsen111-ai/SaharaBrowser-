#!/usr/bin/env bash
# Point upstream/PIN at a Firefox for Android release (default: newest final release).
#
# Usage: scripts/bump-upstream.sh [VERSION]      e.g. scripts/bump-upstream.sh 158.0
#
# Looks the release tag up on Mozilla's Mercurial server, takes the tarball URL from
# archive.mozilla.org and the checksum from Mozilla's published SHA256SUMS, then rewrites
# upstream/PIN. Beta tags (158.0b1) are never picked. Review the diff before committing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="${SAHARA_PIN_FILE:-$ROOT/upstream/PIN}"
HG="https://hg-edge.mozilla.org/releases/mozilla-release"
ARCHIVE="https://archive.mozilla.org/pub/firefox/releases"

die() { echo "bump-upstream: $*" >&2; exit 1; }

read -r version tag node < <(
  curl --fail --silent --show-error --location "$HG/json-tags" |
  python3 -I -c '
import json, re, sys
want = sys.argv[1]
pat = re.compile(r"^FIREFOX-ANDROID_(\d+)_(\d+)(?:_(\d+))?_RELEASE$")
found = {}
for t in json.load(sys.stdin)["tags"]:
    m = pat.match(t["tag"])
    if not m:
        continue
    major, minor, patch = int(m[1]), int(m[2]), m[3]
    ver = "%d.%d" % (major, minor) + (".%s" % patch if patch is not None else "")
    found[ver] = ((major, minor, int(patch or 0)), t["tag"], t["node"])
if not found:
    sys.exit("no final FIREFOX-ANDROID_*_RELEASE tags found")
ver = want or max(found, key=lambda v: found[v][0])
if ver not in found:
    sys.exit("no release tag for version %s" % ver)
print(ver, found[ver][1], found[ver][2])
' "${1:-}"
) || die "could not resolve a release tag"

[[ -n "${version:-}" && -n "${tag:-}" && -n "${node:-}" ]] || die "could not resolve a release tag"

url="$ARCHIVE/$version/source/firefox-$version.source.tar.xz"
sha="$(curl --fail --silent --show-error --location "$ARCHIVE/$version/SHA256SUMS" \
  | awk -v f="source/firefox-$version.source.tar.xz" '$2 == f { print $1 }')"
[[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "no SHA-256 published for firefox-$version.source.tar.xz"

cat > "$PIN_FILE" <<EOF
# Upstream Firefox for Android that Sahara is built on.
# Sourced by scripts/*.sh. Update with scripts/bump-upstream.sh, never by hand.
#
# Resolved $(date -u +%Y-%m-%d):
#   - tag and changeset from $HG/json-tags
#   - tarball SHA-256 from Mozilla's published SHA256SUMS
SAHARA_UPSTREAM_VERSION=$version
SAHARA_UPSTREAM_TAG=$tag
SAHARA_UPSTREAM_HG_NODE=$node
SAHARA_UPSTREAM_URL=$url
SAHARA_UPSTREAM_SHA256=$sha
EOF
echo "pinned Firefox for Android $version ($tag)"
