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
GECKOVIEW_MAVEN="https://maven.mozilla.org/maven2/org/mozilla/geckoview"

die() { echo "bump-upstream: $*" >&2; exit 1; }

read -r version tag node tag_epoch < <(
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
    found[ver] = ((major, minor, int(patch or 0)), t["tag"], t["node"], int(t["date"][0]))
if not found:
    sys.exit("no final FIREFOX-ANDROID_*_RELEASE tags found")
ver = want or max(found, key=lambda v: found[v][0])
if ver not in found:
    sys.exit("no release tag for version %s" % ver)
print(ver, found[ver][1], found[ver][2], found[ver][3])
' "${1:-}"
) || die "could not resolve a release tag"

[[ -n "${version:-}" && -n "${tag:-}" && -n "${node:-}" && -n "${tag_epoch:-}" ]] || die "could not resolve a release tag"

# Mozilla's published GeckoView for this release is org.mozilla.geckoview:geckoview-omni-arm64-v8a:<major>.<minor>.<buildid>.
# The build ID is a UTC timestamp taken a few minutes after the release tag, so pick the first one in that window.
gv_buildid="$(
  curl --fail --silent --show-error --location "$GECKOVIEW_MAVEN/geckoview-omni-arm64-v8a/maven-metadata.xml" |
  python3 -I -c '
import calendar, re, sys, time
major_minor, tag_epoch = sys.argv[1], int(sys.argv[2])
major_minor = ".".join(major_minor.split(".")[:2])
best = None
for v in re.findall(r"<version>([^<]+)</version>", sys.stdin.read()):
    m = re.fullmatch(re.escape(major_minor) + r"\.(\d{14})", v)
    if not m:
        continue
    epoch = calendar.timegm(time.strptime(m[1], "%Y%m%d%H%M%S"))
    if tag_epoch - 60 <= epoch <= tag_epoch + 3600 and (best is None or epoch < best[0]):
        best = (epoch, m[1])
if best is None:
    sys.exit("no published GeckoView build within an hour after the release tag")
print(best[1])
' "$version" "$tag_epoch"
)" || die "could not find Mozilla's published GeckoView build for $version"
[[ "$gv_buildid" =~ ^[0-9]{14}$ ]] || die "could not find Mozilla's published GeckoView build for $version"
gv_version="$(cut -d. -f1,2 <<<"$version").$gv_buildid"
curl --fail --silent --location --head --output /dev/null \
  "$GECKOVIEW_MAVEN/geckoview-omni-arm64-v8a/$gv_version/geckoview-omni-arm64-v8a-$gv_version.pom" \
  || die "GeckoView $gv_buildid is listed but its files are not downloadable"

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
#   - GeckoView build ID from maven.mozilla.org (org.mozilla.geckoview:geckoview-omni-arm64-v8a:<major>.<minor>.<id>)
SAHARA_UPSTREAM_VERSION=$version
SAHARA_UPSTREAM_TAG=$tag
SAHARA_UPSTREAM_HG_NODE=$node
SAHARA_UPSTREAM_URL=$url
SAHARA_UPSTREAM_SHA256=$sha
SAHARA_GECKOVIEW_BUILDID=$gv_buildid
EOF
echo "pinned Firefox for Android $version ($tag)"
