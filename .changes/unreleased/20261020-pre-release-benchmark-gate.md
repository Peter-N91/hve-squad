---
bump: patch
type: Changed
---

- **Recorded benchmark regressions block publication before release writes.** The Release workflow compares a frozen candidate against its latest stable release ancestor; unavailable or incompatible evidence fails closed. Manual dispatch exposes `run_benchmark`, enabled by default, with an explicit audited bypass that leaves other release checks intact (`.github/workflows/release.yml`, `.github/workflows/tier2-benchmark.yml`).
