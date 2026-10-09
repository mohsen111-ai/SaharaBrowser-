# Install the Android SDK packages the build needs (platform, build-tools, platform-tools, and the
# `emulator` binary, which `mach configure` insists on finding even though a build never runs it),
# reusing mozboot's own helpers so the versions come from the pinned tree.
#
# Run with the tree's Python:  (cd build/upstream && ./mach python ../../scripts/install-android-sdk.py)
# `mach bootstrap --no-system-changes` skips the SDK entirely, and its default path also downloads
# an Android Virtual Device (about 7 GB) that a build does not need; that is what we leave out.
from mozboot import android

android.ensure_android_sdk("linux", android.get_os_tag_for_android("linux"))
android.ensure_bundletool()
packages = android.get_android_packages(android.AndroidPackageList.ALL)
android.ensure_android_packages(
    "linux", "x86_64", packages=packages, avd_manifest=None, no_interactive=True
)
print("SDK at", android.get_sdk_path("linux"))
