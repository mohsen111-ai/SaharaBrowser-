# Source this (". scripts/proxy-env.sh") before building behind a TLS-intercepting HTTPS proxy,
# such as the Claude Code cloud sandbox. It is NOT needed on a normal machine or on GitHub Actions.
#
# Why it exists:
#  - `mach gradle` replaces JAVA_TOOL_OPTIONS, so Gradle's JVM loses the proxy and CA settings that
#    the environment provides. We pass them on Gradle's command line (GRADLE_FLAGS) instead.
#    ~/.gradle/gradle.properties is not usable for this: mozboot rewrites that file and lowercases
#    every key, which silently disables `systemProp.*` entries.
#  - Maven Central rate-limits shared egress IPs (HTTP 429) and Gradle does not fall through to the next
#    repository on that error. Google's public Maven Central mirror and the Gradle Plugin Portal (for
#    plugin markers) are therefore listed before Central itself. This only takes effect at
#    `mach configure` time, because the repository list is baked into the objdir.
#
# TLS verification stays on: the JVM is pointed at a trust store that contains the proxy's CA.

if [ -n "${JAVA_TOOL_OPTIONS:-}" ]; then
  GRADLE_FLAGS="$(python3 -I - <<'PY'
import os, re, shlex
keep = ("javax.net.ssl.", "https.proxy", "http.proxy", "http.nonProxyHosts", "jdk.http.auth.")
out = []
for opt in shlex.split(os.environ["JAVA_TOOL_OPTIONS"]):
    m = re.match(r"-D([^=]+)=(.*)$", opt, re.S)
    if m and m.group(1).startswith(keep):
        out.append(shlex.quote("-D%s=%s" % (m.group(1), m.group(2))))
print(" ".join(out))
PY
)"
  export GRADLE_FLAGS
fi

export GRADLE_MAVEN_REPOSITORIES="https://maven.mozilla.org/maven2/,https://maven.google.com/,https://maven-central.storage-download.googleapis.com/maven2/,https://plugins.gradle.org/m2/,https://repo.maven.apache.org/maven2/"
