---
bump: patch
type: Added
---

- **Contributor pull requests conflicted on `apm.yml` and `CHANGELOG.md` every time two landed together.** Version and changelog are now release outputs assembled on `main` from per-pull-request fragments under `.changes/unreleased/`, so nothing in a pull request touches shared release state (`scripts/New-ChangeFragment.ps1`, `scripts/Invoke-ReleasePrep.ps1`, `.github/workflows/pr-validation.yml`, `.github/workflows/release-prep.yml`).
