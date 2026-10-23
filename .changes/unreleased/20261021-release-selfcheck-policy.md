---
bump: patch
type: Fixed
---

- **Release benchmark self-checks distinguish configurable manual defaults from mandatory safety rules.** Tests honor the declared boolean default and Release Prep inheritance while retaining automatic-release enforcement, failure blocking and frozen-candidate checks; operator documentation reflects the current default-off manual policy (`tests/tier2/live-benchmark/BenchmarkResults.Tests.ps1`, `benchmarks/efficiency/README.md`).
