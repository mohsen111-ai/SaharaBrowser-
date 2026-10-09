#!/usr/bin/env bash
# Smoke-test an APK on a running Android emulator or device (adb must see exactly one).
#
# Usage: scripts/emulator-smoke-test.sh APK OUTDIR
# Env (all optional):
#   EXPECT_PACKAGE   the application id the APK must have, e.g. app.sahara.browser
#   EXPECT_LABEL     the launcher label it must have, e.g. Sahara
#
# What it does: installs the APK, launches it, takes screenshots, loads a page from a small web server on
# the host (the emulator reaches the host at 10.0.2.2), and proves from that server's own log that the page
# was fetched and its JavaScript ran (Gecko's page content is not visible to Android's UI tools, so the log
# is the reliable evidence). It also watches logcat for crashes, ANRs and native crashes.
#
# Everything it collects is written to OUTDIR: report.md, screenshots, logcat.txt, ui dumps, server log.
# Exit status 1 if any check failed. It keeps going after a failure so that as much evidence as possible
# is gathered.
set -uo pipefail

APK="${1:?usage: emulator-smoke-test.sh APK OUTDIR}"
OUT="${2:?usage: emulator-smoke-test.sh APK OUTDIR}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT"
REPORT="$OUT/report.md"
: > "$REPORT"
failures=0

say()  { echo "$*" | tee -a "$REPORT"; }
pass() { say "- PASS: $*"; }
fail() { say "- **FAIL**: $*"; failures=$((failures + 1)); }
info() { say "- info: $*"; }

adb_() { adb "$@" 2>&1 | tr -d '\r'; }

shot() {  # shot NAME: screenshot to OUT/NAME.png
  adb exec-out screencap -p > "$OUT/$1.png" 2>/dev/null || true
}

ui_texts() {  # ui_texts NAME: dump the view hierarchy and print the visible texts / content descriptions
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
  adb pull /sdcard/ui.xml "$OUT/$1.xml" >/dev/null 2>&1 || true
  python3 - "$OUT/$1.xml" <<'PY' 2>/dev/null || true
import re, sys
try:
    data = open(sys.argv[1], encoding="utf-8", errors="replace").read()
except OSError:
    sys.exit()
seen = []
for m in re.finditer(r'(?:text|content-desc)="([^"]+)"', data):
    t = m.group(1).strip()
    if t and t not in seen:
        seen.append(t)
print(" | ".join(seen[:60]))
PY
}

find_aapt2() {
  local sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/.mozbuild/android-sdk-linux}}"
  ls -d "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -n 1
}

say "# Emulator smoke test"
say ""
say "APK: \`$(basename "$APK")\` ($(du -h "$APK" | cut -f1))"
say ""

# ---- 0. what are we testing -----------------------------------------------------------------
AAPT2="$(find_aapt2)"
PKG=""; LABEL=""
if [[ -n "$AAPT2" ]]; then
  badging="$("$AAPT2" dump badging "$APK" 2>/dev/null)"
  PKG="$(sed -n "s/^package: name='\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)"
  LABEL="$(sed -n "s/^application-label:'\(.*\)'$/\1/p" <<<"$badging" | head -n1)"
  VERSION="$(sed -n "s/.*versionName='\([^']*\)'.*/\1/p" <<<"$badging" | head -n1)"
fi
[[ -n "$PKG" ]] || { fail "could not read the package name from the APK (aapt2 missing?)"; exit 1; }
info "package \`$PKG\`, launcher label \"$LABEL\", version ${VERSION:-?}"
[[ -z "${EXPECT_PACKAGE:-}" || "$PKG" == "$EXPECT_PACKAGE" ]] && pass "package id is $PKG" || fail "package id is $PKG, expected $EXPECT_PACKAGE"
[[ -z "${EXPECT_LABEL:-}" || "$LABEL" == "$EXPECT_LABEL" ]] && pass "launcher label is \"$LABEL\"" || fail "launcher label is \"$LABEL\", expected \"$EXPECT_LABEL\""

# ---- 1. device ready, install ------------------------------------------------------------------
adb wait-for-device
for _ in $(seq 1 60); do
  [[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == "1" ]] && break
  sleep 2
done
info "device: $(adb shell getprop ro.product.model | tr -d '\r'), Android $(adb shell getprop ro.build.version.release | tr -d '\r') (API $(adb shell getprop ro.build.version.sdk | tr -d '\r')), ABI $(adb shell getprop ro.product.cpu.abi | tr -d '\r')"

adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell wm dismiss-keyguard >/dev/null 2>&1 || true

install_out="$(adb_ install -r -g "$APK")"
if grep -q '^Success' <<<"$install_out"; then pass "installed"; else fail "install failed: $install_out"; exit 1; fi

# ---- 2. host web server for the page-load check ----------------------------------------------------
SITE="$HERE/emulator-test-site"
SERVER_LOG="$OUT/server.log"
python3 -m http.server 8000 --bind 0.0.0.0 --directory "$SITE" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
sleep 1

# ---- 3. cold start ------------------------------------------------------------------------------------
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
alive=0
for _ in $(seq 1 45); do
  if [[ -n "$(adb shell pidof "$PKG" | tr -d '\r')" ]]; then alive=1; break; fi
  sleep 1
done
[[ $alive -eq 1 ]] && pass "process started" || fail "process did not start"
sleep 20   # first run: let Gecko start and the first screen settle
shot 01-launch
info "visible after launch: $(ui_texts 01-launch)"
[[ -n "$(adb shell pidof "$PKG" | tr -d '\r')" ]] && pass "still running 20 s after launch" || fail "process died within 20 s of launch"

# ---- 4. load a page from the host -------------------------------------------------------------------------
adb shell am start -a android.intent.action.VIEW -d "http://10.0.2.2:8000/test.html" -p "$PKG" >/dev/null 2>&1
fetched=0; js=0
for _ in $(seq 1 60); do
  grep -q 'GET /test.html' "$SERVER_LOG" && fetched=1
  grep -q 'GET /beacon?js=ok' "$SERVER_LOG" && js=1
  [[ $js -eq 1 ]] && break
  sleep 1
done
sleep 3
shot 02-page
info "visible with the page open: $(ui_texts 02-page)"
[[ $fetched -eq 1 ]] && pass "the browser fetched the test page" || fail "the browser never requested the test page (see server.log)"
[[ $js -eq 1 ]] && pass "JavaScript on the page ran" || fail "page JavaScript did not run (no beacon request)"
ua="$(grep -o 'GET /beacon[^ ]*' "$SERVER_LOG" | head -n1 | sed 's/.*ua=//' | python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))' 2>/dev/null)"
[[ -n "$ua" ]] && info "user agent: $ua"

# ---- 5. pixel checks (best effort; need Pillow) -----------------------------------------------------------
python3 - "$OUT" <<'PY' 2>&1 | tee -a "$REPORT"
import os, sys
try:
    from PIL import Image
except ImportError:
    print("- info: Pillow not installed, pixel checks skipped"); sys.exit()
out = sys.argv[1]
def px(name, fx, fy):
    p = os.path.join(out, name + ".png")
    if not os.path.exists(p) or os.path.getsize(p) == 0: return None
    im = Image.open(p).convert("RGB"); w, h = im.size
    return im.getpixel((int(w * fx), int(h * fy)))
def dist(a, b): return sum(abs(x - y) for x, y in zip(a, b))
page = px("02-page", 0.5, 0.55)
if page is None: print("- **FAIL**: no screenshot of the page")
elif dist(page, (255, 0, 255)) < 60: print("- PASS: the page is visibly rendered (magenta at the centre: #%02x%02x%02x)" % page)
else: print("- info: centre of the page screenshot is #%02x%02x%02x (not the magenta test colour; the page may be behind another screen)" % page)
launch = px("01-launch", 0.5, 0.5)
if launch: print("- info: centre pixel after launch: #%02x%02x%02x" % launch)
PY

# ---- 6. crash / ANR scan ---------------------------------------------------------------------------------------
adb logcat -d > "$OUT/logcat.txt" 2>&1
crashes="$(grep -E 'FATAL EXCEPTION|ANR in |Process '"$PKG"' .*has died|\*\*\* \*\*\* \*\*\* \*\*\*|Fatal signal' "$OUT/logcat.txt" | head -n 5)"
if [[ -z "$crashes" ]]; then pass "no crash, ANR or native crash in logcat"; else fail "crash signs in logcat: $(tr '\n' ' ' <<<"$crashes" | cut -c1-400)"; fi
[[ -n "$(adb shell pidof "$PKG" | tr -d '\r')" ]] && pass "still running at the end" || fail "process is not running at the end"

say ""
if [[ $failures -eq 0 ]]; then say "**Result: all checks passed.**"; else say "**Result: $failures check(s) failed.**"; fi
[[ $failures -eq 0 ]]
