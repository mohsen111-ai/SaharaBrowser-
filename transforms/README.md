# transforms/

**Rule-based edits** run by `scripts/apply-overlay.sh` after patches, in filename order, as
`python3 -I <script> <tree-root>` (`<tree-root>` is the extracted Firefox source root).

Why they exist: some changes are fragile as patches because their context changes every month, for example
renaming "Firefox" to "Sahara" in the app's string resources. A rule ("replace this word in these files,
except in these places") keeps working when upstream adds a hundred new strings; a patch would not.

## Rules for writing one

- Name them `NN-short-description.py`. Plain Python 3 standard library only (they run with `-I`).
- Start with a comment saying **what and why**.
- **Count what you change and fail if the count is wrong.** Each transform must `sys.exit(1)` with a clear
  message when a rule matches nothing (or far fewer places than expected). That is how an upstream refactor
  gets noticed instead of silently producing an unbranded or half-edited build.
- Be idempotent-safe: running on a pristine tree is the only supported case, but never corrupt a file if a
  pattern is not found.
- Read and write files as UTF-8 and preserve everything you do not mean to change (including line endings).
- Print one summary line, for example `branding: 412 replacements in 3 files`.
- This README is not run.
