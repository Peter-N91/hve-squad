---
bump: patch
type: Fixed
---

- **Initial releases can bootstrap without historical benchmark tooling through v0.18.1.** The release gate warns and preserves the missing-baseline report when no previous stable baseline or trusted comparator exists. The exception expires after v0.18.1 and does not bypass stale evidence, candidate gaps, regressions, or operational failures (`.github/workflows/tier2-benchmark.yml`).
