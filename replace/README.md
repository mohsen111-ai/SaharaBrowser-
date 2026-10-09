# replace/

**Whole-file replacements of existing upstream files.** Files here overwrite the file at the same relative
path in the upstream tree (step 2 of `scripts/apply-overlay.sh`, after `overlay/` and before `patches/`).

Use it for things a text patch cannot express: icons, images and other binary assets. For text files prefer a
patch (small, reviewable, rebases cleanly) or a transform (rule-based).

- The target **must exist** upstream. If a new upstream release moves or deletes it, applying fails loudly
  instead of silently shipping the old asset.
- Keep replacements few. Each one has to be re-checked when upstream changes the file.
- This README is not copied.
