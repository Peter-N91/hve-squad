---
bump: patch
type: Fixed
---

- **Tier 0 failures no longer wait for one long serial job, and releases no longer repeat the complete suite.** Corrected two obsolete wording assertions without changing routing behavior, partitioned CI into isolated shards with the existing required check and downloadable results, and split release validation into repository checks before tagging and installed-package checks afterward. All existing cases and published self-reference checks remain covered; older hotfix runners retain their full-suite fallback. See `tests/tier0/Invoke-Tier0Tests.ps1` and `.github/workflows/{tier0-conformance,release}.yml`.
