# overlay/

**New files only.** Everything under this directory is copied into the upstream tree by
`scripts/apply-overlay.sh`, at the same relative path. This README is not copied.

- The path mirrors the upstream tree, e.g. `overlay/mobile/android/fenix/app/src/main/java/app/sahara/...`
  lands at `build/upstream/mobile/android/fenix/app/src/main/java/app/sahara/...`.
- If a file already exists upstream the script stops with an error. Changing an existing upstream file
  is a job for [`patches/`](../patches/README.md), which keeps monthly upstream updates small.
- Put new code in new packages inside existing Gradle modules (for example `app.sahara.*` in the Fenix app
  module, and a new `segmented` package inside `feature-downloads`). That needs no build-system changes;
  the existing code only needs a small patch at each call site.
- Resources need unique names (prefix them `sahara_`) so they never collide with upstream resources.
