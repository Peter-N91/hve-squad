---
bump: patch
type: Fixed
---

- **Tier 0 hot-file budgets preserve the aggregate performance envelope without
  blocking unrelated pull requests.** Documented per-file overrides redistribute
  the existing budget, pull requests cannot increase inherited budget debt, and
  pushes to `main` now report absolute budget health.
