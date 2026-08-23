---
bump: patch
type: Fixed
---

- **`Publish Plugin`'s blank-`ref` fallback resolved the wrong tag.** Left blank, the workflow ran
  `git describe --tags --abbrev=0`, which only walks commit ancestors of `main`'s tip. This repo's
  release automation tags each release on a "chore(release): pin squad self-references to vX.Y.Z"
  commit one step past `main` that is never merged back (see `release.yml`) — so the actual latest
  release tag is never an ancestor of `main`, and `git describe` silently fell back to an older,
  unrelated tag instead of erroring.

  The blank-`ref` path now resolves the highest `vX.Y.Z` tag by version sort (`sort -V`), which does
  not depend on ancestry at all. An explicit `ref` input is unaffected — it was already validated
  directly against the tag rather than resolved through `git describe`.
