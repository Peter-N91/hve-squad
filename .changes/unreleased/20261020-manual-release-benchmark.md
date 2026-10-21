---
bump: patch
type: Changed
---

- **Benchmark reports no longer run on every pull request.** `tier2-benchmark.yml` supports manual comparisons and published stable releases, selects a previous stable release on the same ancestry, and also handles releases published by the existing release workflow without making paid model calls.
