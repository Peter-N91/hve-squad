---
bump: patch
type: Fixed
---

- **Comparator self-checks no longer lose their historical fixtures in CI.** The Tier 2 selfcheck checkout fetches full Git history so existing recorded-evidence tests can read pinned revisions without weakening validation or rerunning paid benchmarks (`.github/workflows/tier2-semantic.yml`).
