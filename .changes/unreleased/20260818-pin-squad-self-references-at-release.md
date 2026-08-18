---
bump: patch
type: Fixed
---

- **Every release tag served squad files from `main` instead of from the tag.** The 47
  `Peter-N91/hve-squad` entries in `apm.yml` ship as bare paths, and APM resolves a bare path against
  the default branch — so a tag froze the dependency list but not its contents. Measured by installing
  `#v0.14.0` and getting `main`'s coordinator back, while the hve-core entries in the same manifest
  resolved correctly because they carry `#<sha>`. `release.yml` now pins the self-references to the tag
  it is cutting and pushes that commit straight to `refs/tags/`, so a release installs the files it was
  built from (`.github/workflows/release.yml`, `scripts/Set-SquadSelfRefPin.ps1`). `main` keeps the
  unpinned manifest, so development installs still track `main`. Tags before v0.15.2 remain unpinned.
