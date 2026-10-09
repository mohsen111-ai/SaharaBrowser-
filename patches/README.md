# patches/

Changes to **existing** upstream files, applied in filename order with `patch -p1` against the pinned tree
(after the overlay is copied in).

## Rules

- Name them `NNNN-short-description.patch` (`0001-app-id-and-name.patch`). Order is the filename order.
- **One concern per patch**, as small as possible. A patch that touches an upstream file should change
  only the lines it must, usually a call into code that lives in `overlay/`.
- Make them against the pristine pinned tree, with `a/` and `b/` prefixes (`diff -u`, or `git diff` /
  `git format-patch` from a scratch checkout). Paths are relative to the root of the Firefox tree.
- Start each patch with a header comment saying **why** it exists and which upstream function it hooks, so
  a failed patch after an upstream bump is quick to repair.
- When `scripts/bump-upstream.sh` moves the pin, run `scripts/apply-overlay.sh --reapply`; the first patch
  that fails to apply tells you what upstream changed.

There are no patches yet. The first ones will be the app identity (package name, app name) and the theme
palette; see [docs/ROADMAP.md](../docs/ROADMAP.md).
